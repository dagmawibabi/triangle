import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../ai/data/ai.dart';
import '../../assistant/notifications.dart';
import '../../assistant/watch_engine.dart';
import '../../auth/data/auth_controller.dart';
import '../../settings/data/settings.dart';
import '../../settings/presentation/model_picker_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../data/chat_controller.dart';
import '../domain/chat_models.dart';
import '../../voice/dictation.dart';
import '../../voice/player_sheet.dart';
import '../../voice/voice_mode_screen.dart';
import '../../voice/voice_note_recorder.dart';
import '../../media/audio_player_ui.dart';
import '../../../app/app.dart' show appRouteObserver;
import '../../telegram/presentation/attach_sheet.dart';
import 'history_drawer.dart';
import '../../share/ask_sheet.dart';
import '../../share/share_intake.dart';
import '../../assistant/default_assistant.dart';
import 'widgets/chat_sheets.dart';
import 'widgets/message_view.dart';
import 'widgets/chat_date_divider.dart';
import '../../account/account_switcher.dart';
import '../../account/account_router.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with RouteAware, WidgetsBindingObserver {
  bool _covered = false;

  /// Tells the controller whether a watch's update posted to the open
  /// conversation would be seen right now: the app is in front and no other
  /// screen covers this one.
  void _reportVisibility() {
    final resumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    ref
        .read(chatControllerProvider.notifier)
        .setScreenVisible(resumed && !_covered);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    _covered = true;
    _reportVisibility();
  }

  @override
  void didPopNext() {
    _covered = false;
    _reportVisibility();
  }

  /// Whether the app was closed outright (swiped away or backed out of).
  bool _closed = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _reportVisibility();
    switch (state) {
      case AppLifecycleState.detached:
        // The engine lives on (for watches), but to the person the app was
        // closed: opening it again starts a new chat. Switching to another
        // app and back keeps the chat that was open, however long it took.
        _closed = true;
      case AppLifecycleState.resumed when _closed:
        _closed = false;
        _opened();
      default:
        break;
    }
  }

  /// The app was opened: a new chat or the last one, as Appearance says.
  void _opened() {
    final last = ref.read(settingsProvider).openLastChat;
    unawaited(ref.read(chatControllerProvider.notifier).appOpened());
    if (!last) _input.clear();
  }

  final _input = TextEditingController();
  final _focus = FocusNode();
  // While a reply streams and the person has scrolled up to read, the
  // list holds what they're reading still (see _HoldingScrollController).
  bool _streaming = false;
  late final _scroll = _HoldingScrollController(hold: () => _streaming);
  bool _pinnedToBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // The list is reversed: offset 0 is the newest message.
      final pinned = _scroll.hasClients && _scroll.offset < 80;
      if (pinned != _pinnedToBottom) setState(() => _pinnedToBottom = pinned);
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(modelCatalogProvider.notifier).ensureLoaded(),
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportVisibility());
    // Android says when the app is opened (not just switched back to);
    // the first start counts too.
    const MethodChannel('teleai/app_open').setMethodCallHandler((call) async {
      if (call.method == 'opened' && mounted) _opened();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(settingsProvider).openLastChat) _opened();
    });
    // Signed in from here on: watches may run, and a tapped notification
    // opens the conversation it came from.
    ref.read(watchEngineProvider).start();
    _taps = ref.read(appNotifierProvider).taps.stream.listen((id) {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      // A mention opens the Telegram chat it happened in.
      // "chat:<id>@<account>": a mention or alert from that account, which
      // is switched to first so the chat opens in it.
      final chat = RegExp(r'^chat:(-?\d+)(?:@(.+))?$').firstMatch(id);
      if (chat != null) {
        openChatInAccount(context, int.parse(chat[1]!), hint: chat[2]);
        return;
      }
      ref.read(chatControllerProvider.notifier).open(id);
    });
    ShareIntake.listen(_onShared);
    DefaultAssistant.listen(_onAssist);
  }

  /// Called up as the phone's assistant (long-press home): voice mode or a
  /// fresh chat with the keyboard up, as Settings → Default assistant says.
  Future<void> _onAssist(bool voice) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ref.read(chatControllerProvider.notifier).newChat();
    if (voice || ref.read(assistOpensProvider) == AssistOpens.voice) {
      await VoiceModeScreen.open(context);
    } else {
      _input.clear();
      _focus.requestFocus();
    }
  }

  StreamSubscription<String>? _taps;
  final _composerKey = GlobalKey<_ComposerState>();

  /// Shared from another app: selected text opens Ask Triangle; text and
  /// files go into a new chat's input box, ready for a question.
  Future<void> _onShared(SharedPayload p) async {
    // After the app's own resume handling, which may start a fresh chat.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ref.read(chatControllerProvider.notifier).newChat();
    if (p.selection) {
      final question = await showAskSheet(context, p.text);
      if (question != null && mounted) _send(question);
      return;
    }
    _input.text = p.text;
    final files = [for (final (path, name) in p.files) await ChatController.attach(path, name: name)];
    if (!mounted) return;
    _composerKey.currentState?.addAttachments(files);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _taps?.cancel();
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String value, [List<Attachment> attachments = const []]) {
    value = value.trim();
    if (value.isEmpty && attachments.isEmpty) return;
    final settings = ref.read(settingsProvider);
    if (!settings.hasAnyKey) {
      _openSettings();
      showSnack(context, 'Add an AI provider API key first.');
      return;
    }
    _input.clear();
    ref
        .read(chatControllerProvider.notifier)
        .send(value, attachments: attachments);
    _toBottom();
  }

  void _toBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _openSettings() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  Future<void> _pickModel() async {
    final current = ref.read(settingsProvider).model;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ModelPickerScreen(current: current)),
    );
    if (id != null) await ref.read(settingsProvider.notifier).setModel(id);
  }

  @override
  Widget build(BuildContext context) {
    // A new chat is a clean slate: nothing typed or attached carries over
    // from the one before (the model only ever sees the chat on screen).
    ref.listen(chatControllerProvider.select((s) => s.conversation.id), (before, now) {
      if (before == now || ref.read(chatControllerProvider).conversation.entries.isNotEmpty) return;
      _input.clear();
      _composerKey.currentState?.clearAttachments();
    });
    final chat = ref.watch(chatControllerProvider);
    final settings = ref.watch(settingsProvider);
    final catalog = ref.watch(modelCatalogProvider);
    final model = catalog.byId(settings.model);
    final entries = chat.conversation.entries;

    return Scaffold(
      drawer: HistoryDrawer(onOpenSettings: _openSettings),
      appBar: AppBar(
        leading: lead(Builder(
          builder: (context) => IconButton(
            tooltip: 'Chats',
            icon: Badge(
              isLabelVisible: chat.history.any(
                (h) => h.unread > 0 && h.id != chat.conversation.id,
              ),
              backgroundColor: AppColors.accent,
              smallSize: 9,
              child: const Icon(Icons.menu_rounded),
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        )),
        titleSpacing: 0,
        title: _ModelButton(
          name: model?.name ?? modelLabel(settings.model).split('/').last,
          onTap: _pickModel,
        ),
        actions: [
          // The account the assistant's Telegram tools use by default.
          const AccountSwitcherButton(),
          const ContextMeter(),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.edit_outlined, size: 21),
            onPressed: entries.isEmpty
                ? null
                : () => ref.read(chatControllerProvider.notifier).newChat(),
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const AudioMiniBar(
              margin: EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
            ),
            Expanded(
              child: entries.isEmpty
                  ? _EmptyState(
                      onPick: _send,
                      hasKey: settings.hasAnyKey || !settings.loaded,
                      onSettings: _openSettings,
                      seed: chat.conversation.id.hashCode,
                      telegram: ref.watch(telegramConnectedProvider),
                    )
                  : Stack(
                      children: [
                        _MessageList(
                          scroll: _scroll,
                          conversation: chat.conversation,
                          busy: _streaming = chat.busy,
                        ),
                        if (!_pinnedToBottom)
                          Positioned(
                            bottom: Space.m,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Material(
                                color: AppColors.surface3,
                                shape: CircleBorder(
                                  side: BorderSide(color: AppColors.line),
                                ),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _toBottom,
                                  child: const Padding(
                                    padding: EdgeInsets.all(Space.s),
                                    child: Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const NowReadingBar(),
            if (ref.watch(settingsProvider.select((s) => s.aiChatEnabled)))
              _Composer(
                key: _composerKey,
                controller: _input,
                focus: _focus,
                busy: chat.busy,
                onSend: _send,
                onStop: () => ref.read(chatControllerProvider.notifier).stop(),
              )
            else
              const _ChatOffBar(),
          ],
        ),
      ),
    );
  }
}

/// In place of the input box while AI chat is off in Settings.
class _ChatOffBar extends ConsumerWidget {
  const _ChatOffBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.s),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.xl + 4),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(Icons.pause_circle_outline_rounded, color: AppColors.text3),
          const SizedBox(width: Space.m),
          Expanded(child: Text('AI chat is off in Settings', style: context.text.bodyMedium)),
          TextButton(
            onPressed: () => ref.read(settingsProvider.notifier).setAiChatEnabled(true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    ),
  );
}

class _ModelButton extends StatelessWidget {
  const _ModelButton({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.s),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s,
          vertical: Space.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppColors.text3,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.scroll,
    required this.conversation,
    required this.busy,
  });

  final ScrollController scroll;
  final Conversation conversation;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showDateTime = ref.watch(settingsProvider.select((s) => s.showChatDateTime));
    final entries = conversation.entries;
    // Where a compaction under way will end: just before the last question but one.
    final users = [
      for (final (i, e) in entries.indexed)
        if (e is UserEntry) i,
    ];
    final compactingAt = ref.read(chatControllerProvider.notifier).isCompacting(conversation.id) && users.length >= 3
        ? entries[users[users.length - 2] - 1].id
        : null;
    return ListView.builder(
      controller: scroll,
      reverse: true,
      padding: EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.l),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final index = entries.length - 1 - i;
        final e = entries[index];
        final startsDay = index == 0 ||
            !DateUtils.isSameDay(e.at.toLocal(), entries[index - 1].at.toLocal());
        final child = switch (e) {
          UserEntry() => UserBubble(entry: e, posts: conversation.posts),
          AssistantEntry() => AssistantMessage(
            entry: e,
            posts: conversation.posts,
            streaming: busy && i == 0,
          ),
        };
        final item = Center(
          key: ValueKey(e.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            // Full width, so a reply that is only a loading indicator so far
            // sits on the left rather than shrinking to the middle.
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDateTime && startsDay) ChatDateDivider(date: e.at),
                  child,
                  // Above here the model reads a summary, not the messages.
                  if (e.id == compactingAt)
                    const CompactionDivider(compacting: true)
                  else if (e.id == conversation.summaryUntil)
                    CompactionDivider(
                      compacting: false,
                      onTap: () => showCompactionSheet(context, conversation),
                    ),
                ],
              ),
            ),
          ),
        );
        // The newest message: its growth is what the list makes up for.
        return i == 0 ? _HeightReporter(key: ValueKey('h${e.id}'), id: e.id, child: item) : item;
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onPick,
    required this.hasKey,
    required this.onSettings,
    required this.seed,
    this.telegram = true,
  });
  final ValueChanged<String> onPick;

  /// Telegram is connected: its ideas join the mix.
  final bool telegram;
  final bool hasKey;
  final VoidCallback onSettings;

  /// Picks this chat's suggestions; a new chat gets a new mix.
  final int seed;

  /// Ideas that between them show off what the assistant can do.
  static const _pool = [
    (Icons.forum_outlined, 'How many channels am I part of?'),
    (
      Icons.mark_chat_unread_outlined,
      'Do I have unread DMs? Who are they from?',
    ),
    (Icons.bolt_rounded, 'What\'s new in my channels today?'),
    (Icons.alternate_email_rounded, 'Did anyone mention me recently?'),
    (
      Icons.topic_outlined,
      'What\'s happening in my forum groups? Go topic by topic.',
    ),
    (
      Icons.folder_outlined,
      'Summarise the unread chats in each of my folders.',
    ),
    (Icons.archive_outlined, 'What\'s in my Archive that I might have missed?'),
    (
      Icons.mode_comment_outlined,
      'What are people saying in the comments on my latest post?',
    ),
    (
      Icons.emoji_emotions_outlined,
      'Which of my recent posts got the most reactions?',
    ),
    (
      Icons.push_pin_outlined,
      'Show me the pinned messages in my most active group.',
    ),
    (
      Icons.perm_media_outlined,
      'Find the files and links shared with me this week.',
    ),
    (Icons.search_rounded, 'Search my chats for anything about a meeting.'),
    (Icons.travel_explore_rounded, 'Find public channels about AI news.'),
    (
      Icons.badge_outlined,
      'Who is my most recent DM, and what groups do we share?',
    ),
    (Icons.event_note_outlined, 'Do I have any scheduled messages?'),
    (
      Icons.schedule_send_outlined,
      'Schedule "Good morning!" to my Saved Messages for 8 am tomorrow.',
    ),
    (Icons.reply_rounded, 'Draft a reply to my latest unread DM.'),
    (Icons.visibility_outlined, 'Tell me whenever someone DMs me.'),
    (
      Icons.wb_twilight_rounded,
      'Every morning at 8, summarise what my channels posted overnight.',
    ),
    (
      Icons.bookmark_add_outlined,
      'Remember that I prefer short, bullet-point answers.',
    ),
    (
      Icons.notifications_off_outlined,
      'Which chats are muted? Suggest any I should unmute.',
    ),
    (
      Icons.brush_outlined,
      'Make an image of a cosy reading nook for my channel.',
    ),
    (Icons.insights_outlined, 'Which of my groups were the busiest this week?'),
    (Icons.contacts_outlined, 'Which of my contacts were online recently?'),
    (Icons.wb_sunny_outlined, 'Brief me: what needs my attention right now?'),
    (Icons.dashboard_customize_outlined, 'Organise the last 10 posts from my favourite channel into canvas folders by topic.'),
    (Icons.call_missed_rounded, 'Did I miss any calls this week? Who should I call back?'),
    (Icons.new_releases_outlined, 'Which channels and groups did I join this month?'),
    (Icons.person_add_alt_outlined, 'Which of my contacts recently joined Telegram?'),
    (Icons.admin_panel_settings_outlined, 'List the channels and groups I own or admin, with member counts.'),
    (Icons.smart_toy_outlined, 'Which bots have I made, and what were their last messages?'),
    (Icons.poll_outlined, 'Make a quiz for my channel about this week\'s top post.'),
    (Icons.how_to_vote_outlined, 'Show the results of the latest poll in my groups.'),
    (Icons.translate_rounded, 'Translate the latest post in my busiest foreign-language channel.'),
    (Icons.wallpaper_outlined, 'Give my Saved Messages a dark blue gradient background.'),
    (Icons.gif_box_outlined, 'Find a celebration GIF and send it to my Saved Messages.'),
    (Icons.forward_rounded, 'Forward my last Saved Message to my two most recent DMs.'),
    (Icons.groups_outlined, 'Who are the admins of my biggest group?'),
    (Icons.smart_button_outlined, 'What buttons does the last bot message I got have?'),
    (Icons.record_voice_over_outlined, 'Turn my next voice message into a tidy text reply.'),
    (Icons.trending_up_rounded, 'Which posts in my channels got the most views this week?'),
    (Icons.label_important_outline_rounded, 'Rank my unread chats by how important they look.'),
    (Icons.location_on_outlined, 'Has anyone shared a location with me recently?'),
    (Icons.sticky_note_2_outlined, 'Write a canvas note summarising everything in my Ideas folder.'),
    (Icons.event_available_outlined, 'Find every date or deadline people mentioned to me this week.'),
    (Icons.link_rounded, 'Collect the links shared in my groups today, grouped by site.'),
    (Icons.sentiment_satisfied_alt_outlined, 'What\'s the mood in my group chats today?'),
    // The newer tools: reminders, the web, code, GitHub, account, stories…
    (Icons.alarm_add_rounded, 'Remind me to stretch in 20 minutes.'),
    (Icons.alarm_rounded, 'Every weekday at 9:00, catch me up on my unread channels.'),
    (Icons.language_rounded, 'What are the latest posts on dagmawibabi.com/blog?'),
    (Icons.screenshot_monitor_rounded, 'Take a screenshot of news.ycombinator.com and tell me what\'s trending.'),
    (Icons.public_rounded, 'Open wikipedia.org in the browser and look up today\'s featured article.'),
    (Icons.terminal_rounded, 'Write and run code for the first 20 Fibonacci numbers.'),
    (Icons.bar_chart_rounded, 'Chart how many messages I got per day this week, and send me the image.'),
    (Icons.code_rounded, 'What\'s new in the flutter/flutter GitHub repo\'s latest release?'),
    (Icons.bug_report_outlined, 'Find open GitHub issues about Telegram in tdlib/td.'),
    (Icons.health_and_safety_outlined, 'Run a security check-up on my Telegram account.'),
    (Icons.devices_rounded, 'Which devices are logged in to my account? Any I should worry about?'),
    (Icons.privacy_tip_outlined, 'Who can see my phone number and last seen?'),
    (Icons.amp_stories_outlined, 'Whose stories are active right now? Summarise them.'),
    (Icons.folder_copy_outlined, 'Make a "Work" folder with my work-related groups.'),
    (Icons.manage_search_rounded, 'Find every PDF people sent me last month.'),
    (Icons.favorite_border_rounded, 'Who reacted to my messages lately?'),
    (Icons.star_rounded, 'How many Stars do I have, and where did they go?'),
    (Icons.storage_rounded, 'How much space is Telegram using? What can I clear?'),
    (Icons.data_usage_rounded, 'How much mobile data has Telegram used?'),
    (Icons.link_rounded, 'What is t.me/durov, and what did it post last?'),
    (Icons.gif_rounded, 'Use @gif to find a "thank you" GIF for my latest DM.'),
    (Icons.query_stats_rounded, 'Show my channel\'s statistics: growth, views and best hours.'),
    (Icons.folder_zip_outlined, 'Zip the files I attached and send them to my Saved Messages.'),
    (Icons.menu_book_rounded, 'Find a free copy of Frankenstein and send me the epub.'),
    (Icons.auto_stories_outlined, 'Recommend classic science fiction I can read for free.'),
    (Icons.smart_display_outlined, 'What are the latest videos on the Flutter YouTube channel?'),
    (Icons.ondemand_video_rounded, 'Summarise this YouTube video from its description and chapters.'),
    (Icons.alternate_email_rounded, 'Show me the X profile of @NASA.'),
    (Icons.table_chart_outlined, 'Send my Saved Messages a table comparing the last 3 iPhones.'),
    (Icons.forum_outlined, 'Who has messaged my channel directly? Any unanswered?'),
    (Icons.waving_hand_outlined, 'Set a friendly welcome message for new members of my group.'),
    (Icons.sticky_note_2_outlined, 'Add a private note to my last contact: met at the hackathon.'),
    (Icons.library_music_outlined, 'What songs are on my profile music?'),
    (Icons.stream_rounded, 'Have my bot send me a message, typed out live.'),
    (Icons.label_outline_rounded, 'Tag the admins in my group as "Mod".'),
    (Icons.done_all_rounded, 'Did Liya read my last message? When?'),
    (Icons.circle_notifications_outlined, 'Tell me when my brother comes online.'),
    (Icons.library_music_outlined, 'Play me previews of Tems\' best songs.'),
    (Icons.movie_outlined, 'Tell me about the movie Arrival: cast, runtime, trailer.'),
    (Icons.live_tv_rounded, 'When is the next episode of Severance?'),
  ];

  /// Ideas that need no Telegram: apps, the cloud, code, the phone, the web.
  static const _general = [
    (Icons.mail_outline_rounded, 'Summarise my unread emails and tell me which need a reply.'),
    (Icons.event_available_outlined, 'What\'s on my calendar tomorrow? Find me a free hour.'),
    (Icons.tag_rounded, 'What did I miss in Slack today?'),
    (Icons.sticky_note_2_outlined, 'Find my Notion notes about the launch and summarise them.'),
    (Icons.task_alt_rounded, 'What tasks are due this week in Todoist?'),
    (Icons.code_rounded, 'Which GitHub pull requests are waiting on my review?'),
    (Icons.language_rounded, 'List my Cloudflare sites and their DNS records.'),
    (Icons.inventory_2_outlined, 'What\'s in my R2 bucket? Make a share link for the newest file.'),
    (Icons.terminal_rounded, 'Plot the last 30 days of BTC prices in E2B.'),
    (Icons.sms_outlined, 'What\'s the latest verification code in my texts?'),
    (Icons.account_balance_wallet_outlined, 'Sync my bank texts and show where my money went this month.'),
    (Icons.health_and_safety_outlined, 'How healthy are my finances? Any recurring payments?'),
    (Icons.call_missed_rounded, 'Who called me today that I missed?'),
    (Icons.battery_charging_full_rounded, 'How\'s my battery and storage?'),
    (Icons.flashlight_on_rounded, 'Turn on the flashlight.'),
    (Icons.alarm_add_rounded, 'Set an alarm for 6:30 tomorrow.'),
    (Icons.travel_explore_rounded, 'Search the web for this week\'s tech news and summarise it.'),
    (Icons.menu_book_rounded, 'Find a free copy of Pride and Prejudice.'),
    (Icons.record_voice_over_outlined, 'Read me a good-morning message in Amharic.'),
    (Icons.brush_outlined, 'Make an image of a cosy reading nook at night.'),
    // Money.
    (Icons.pie_chart_outline_rounded, 'What did I spend the most on last month?'),
    (Icons.savings_outlined, 'Set a 5,000 birr monthly budget for eating out.'),
    (Icons.receipt_long_outlined, 'Verify a Telebirr payment by its reference number.'),
    (Icons.payments_outlined, 'Tell me whenever money comes into my bank account.'),
    // Calls, screen time, the network and notifications.
    (Icons.phone_callback_rounded, 'Which missed calls haven\'t I returned this week?'),
    (Icons.call_rounded, 'Who do I talk to most on the phone, and when?'),
    (Icons.hourglass_bottom_rounded, 'How much screen time did I have today? Which apps?'),
    (Icons.lock_open_rounded, 'How many times did I unlock my phone today?'),
    (Icons.speed_rounded, 'Run a speed test on my connection.'),
    (Icons.sim_card_outlined, 'Which SIM am I using for data, and how strong is the signal?'),
    (Icons.data_usage_rounded, 'Which apps used the most mobile data this week?'),
    (Icons.notifications_active_outlined, 'What notifications did I get in the last hour?'),
    // Pictures and QR codes.
    (Icons.auto_fix_high_rounded, 'Remove the background from the photo I attached.'),
    (Icons.photo_size_select_large_rounded, 'Resize my attached photo to 1080 px and compress it.'),
    (Icons.qr_code_2_rounded, 'Make a QR code for my Wi-Fi network.'),
    (Icons.qr_code_scanner_rounded, 'Read the QR code in the picture I attached.'),
    // The Ethiopian calendar and the Bible.
    (Icons.calendar_month_rounded, 'What\'s today\'s date in the Ethiopian calendar?'),
    (Icons.celebration_outlined, 'When is Fasika this year? Is there a fast on now?'),
    (Icons.auto_stories_rounded, 'What\'s the verse of the day?'),
    (Icons.compare_rounded, 'Compare John 3:16 in three translations.'),
    // Books, audiobooks, radio and podcasts.
    (Icons.headphones_rounded, 'Find a free audiobook of Sherlock Holmes and play it.'),
    (Icons.radio_rounded, 'Play a jazz radio station.'),
    (Icons.podcasts_rounded, 'Find a good history podcast and play the latest episode.'),
    // Markets, weather and travel.
    (Icons.currency_bitcoin_rounded, 'What\'s Bitcoin at, and how did it do this week?'),
    (Icons.show_chart_rounded, 'Chart Apple\'s stock over the last month.'),
    (Icons.currency_exchange_rounded, 'Convert 100 US dollars to euros and birr.'),
    (Icons.cloud_outlined, 'What\'s the weather in Addis Ababa this week?'),
    (Icons.flight_rounded, 'Where is flight ET500 right now?'),
    (Icons.beach_access_outlined, 'What are the next public holidays in Kenya?'),
    // News, papers, sports and YouTube.
    (Icons.whatshot_outlined, 'What\'s on the front page of Hacker News?'),
    (Icons.reddit, 'What\'s top on r/FlutterDev this week?'),
    (Icons.science_outlined, 'Find recent papers on small language models.'),
    (Icons.sports_soccer_rounded, 'What are today\'s Premier League scores?'),
    (Icons.leaderboard_outlined, 'Show me the La Liga table.'),
    (Icons.sports_motorsports_outlined, 'Who won the last Formula 1 race?'),
    (Icons.trending_up_rounded, 'What\'s trending on YouTube right now?'),
    (Icons.smart_display_outlined, 'Compare MKBHD and Linus Tech Tips on YouTube.'),
    // Lookups.
    (Icons.inventory_outlined, 'What\'s the latest version of the dio package on pub.dev?'),
    (Icons.dns_outlined, 'Who owns example.com, and when does it expire?'),
    (Icons.sentiment_very_satisfied_outlined, 'Show me a random xkcd.'),
    (Icons.diamond_outlined, 'What does gold cost per gram today?'),
    (Icons.crisis_alert_rounded, 'Were there any big earthquakes today?'),
    (Icons.restaurant_rounded, 'Give me a recipe for shakshuka.'),
    (Icons.local_dining_outlined, 'How many calories are in a Snickers bar?'),
    (Icons.air_rounded, 'How are the air quality and UV in Addis today?'),
    (Icons.spellcheck_rounded, 'Define "serendipity" and use it in a sentence.'),
    (Icons.article_outlined, 'Summarise the Wikipedia article on the Aksumite Empire.'),
    (Icons.flag_outlined, 'Tell me about Ethiopia: capital, population, neighbours.'),
    (Icons.rocket_launch_outlined, 'Show me NASA\'s picture of the day.'),
    (Icons.catching_pokemon_rounded, 'Tell me about Pikachu and how it evolves.'),
    // Routines.
    (
      Icons.playlist_play_rounded,
      'Make a routine: every morning check the weather and my calendar, then send me a brief.',
    ),
  ];

  List<(IconData, String)> get _suggestions {
    final rnd = Random(seed);
    final general = [..._general]..shuffle(rnd);
    if (!telegram) return general.take(6).toList();
    final tg = [..._pool]..shuffle(rnd);
    // Half Telegram, half the rest, so the other tools get noticed too.
    return [...tg.take(3), ...general.take(3)]..shuffle(rnd);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: Space.xxl),
                  const BrandMark(size: 44),
                  const SizedBox(height: Space.xl),
                  Text(
                    'What do you want to know?',
                    style: context.text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.s),
                  Text(
                    telegram
                        ? 'Ask about your chats, channels, email, money, phone, the news and more.'
                        : 'Ask about your email, calendar, money, phone, the news and more. Connect Telegram any time in Settings.',
                    style: context.text.bodyMedium?.copyWith(
                      color: AppColors.text2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.x4),
                  if (!hasKey)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.l),
                      child: OutlinedButton.icon(
                        onPressed: onSettings,
                        icon: const Icon(Icons.key_rounded, size: 18),
                        label: const Text('Add an AI provider API key'),
                      ),
                    ),
                  for (final (icon, text) in _suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s),
                      child: Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(Radii.m),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.m),
                          onTap: () => onPick(text),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.l,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.m),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Row(
                              children: [
                                Icon(icon, size: 18, color: AppColors.text3),
                                const SizedBox(width: Space.m),
                                Expanded(
                                  child: Text(
                                    text,
                                    style: context.text.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: Space.xxl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    super.key,
    required this.controller,
    required this.focus,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final void Function(String text, List<Attachment> attachments) onSend;
  final VoidCallback onStop;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

/// Ideas for the empty input box, one at a time, so it suggests what the
/// assistant can do instead of always saying the same thing.
const _telegramHints = [
  'What did I miss today?',
  'Summarise my unread channels…',
  'Who\'s waiting on my reply?',
  'Draft a reply to my last DM…',
  'Any mentions I haven\'t seen?',
  'What are my groups talking about?',
  'Find that link from last week…',
  'Watch my DMs for anything urgent…',
  'Write my morning brief…',
  'Schedule a message for 9 am…',
  'Which chats can I mute?',
  'Save that post to my canvas…',
];

const _generalHints = [
  'Ask me anything…',
  'Remind me to stretch at 5…',
  'What\'s on my calendar today?',
  'Search the web for…',
  'How\'s my phone\'s battery?',
  'Am I on Wi-Fi or mobile data?',
  'Turn on the flashlight…',
  'Explain this like I\'m five…',
  'Help me plan my week…',
  'Make me an image of…',
  'Anything important in my email?',
  'Translate this into Amharic…',
  'Where did my money go this month?',
  'Verify a payment…',
  'Who should I call back?',
  'How\'s my screen time today?',
  'Run a speed test…',
  'Which apps ate my data?',
  'Remove the background from…',
  'Make a QR code for…',
  'Today in the Ethiopian calendar?',
  'Verse of the day…',
  'Find a free audiobook…',
  'Play some jazz radio…',
  'What\'s Bitcoin at?',
  'Convert 100 dollars to birr…',
  'Weather this week in…',
  'Today\'s football scores…',
  'What\'s on Hacker News?',
  'Find papers about…',
  'A recipe for…',
  'Define a word…',
];

class _ComposerState extends ConsumerState<_Composer> {
  final List<Attachment> _files = [];

  /// The idea shown in the empty box: a random one, and a new one each time
  /// a new chat starts.
  final _random = Random();
  late int _hint = _random.nextInt(1 << 20);

  String _hintText(bool telegram) {
    final ideas = telegram ? [..._telegramHints, ..._generalHints] : _generalHints;
    return ideas[_hint % ideas.length];
  }

  /// A different idea from the one showing.
  void _nextHint() {
    if (mounted) setState(() => _hint += 1 + _random.nextInt(5));
  }

  /// Files shared from another app, added as if picked here.
  void addAttachments(List<Attachment> files) => setState(() => _files.addAll(files));

  /// A new chat starts with nothing attached.
  void clearAttachments() {
    if (_files.isNotEmpty) setState(_files.clear);
  }
  bool _adding = false;
  String _typedBeforeDictation = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    // A new chat (or another one opened) gets a new idea.
    ref.listenManual(chatControllerProvider.select((s) => s.conversation.id), (_, _) => _nextHint());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _submit() {
    if (widget.busy) return;
    final text = widget.controller.text.trim();
    if (text.isEmpty && _files.isEmpty) return;
    final files = [..._files];
    setState(_files.clear);
    widget.onSend(text, files);
  }

  Future<void> _add(Future<List<(String, String?)>> Function() pick) async {
    setState(() => _adding = true);
    try {
      for (final (path, name) in await pick()) {
        final a = await ChatController.attach(path, name: name);
        if (mounted) setState(() => _files.add(a));
      }
    } catch (e) {
      if (mounted)
        showSnack(
          context,
          'Couldn\'t attach: $e',
          icon: Icons.error_outline_rounded,
        );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<List<(String, String?)>> _recordVoice() async {
    final note = await recordVoiceNote(context);
    if (note == null) return const [];
    return [(note.path, 'voice_${note.duration}s.opus')];
  }

  /// The same attach sheet as Telegram chats, with what the assistant can
  /// take: the gallery (camera included) and files.
  void _attachMenu() {
    showAttachSheet(context, telegram: false).then((r) {
      if (r is AttachFiles) _add(() async => [for (final (p, n) in r.files) (p, n)]);
    });
  }

  Future<void> _toggleDictation() async {
    final d = ref.read(dictationProvider);
    if (d.listening) {
      await d.stop();
      return;
    }
    _typedBeforeDictation = widget.controller.text;
    await d.start(onText: (words, done) {
      if (!mounted) return;
      final text = joinDictation(_typedBeforeDictation, words);
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
    if (d.error != null && mounted)
      showSnack(context, d.error!, icon: Icons.mic_off_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final dictation = ref.watch(dictationProvider);
    final canSend =
        widget.controller.text.trim().isNotEmpty || _files.isNotEmpty;
    final listening = dictation.listening;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(Radii.xl + 4),
              border: Border.all(
                color: listening
                    ? AppColors.accent.withValues(alpha: 0.6)
                    : AppColors.line,
              ),
            ),
            padding: const EdgeInsets.all(5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_files.isNotEmpty || _adding)
                  SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                      children: [
                        for (final a in _files)
                          _AttachmentPreview(
                            attachment: a,
                            onRemove: () => setState(() => _files.remove(a)),
                          ),
                        if (_adding)
                          const Padding(
                            padding: EdgeInsets.all(Space.m),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _RoundButton(
                      icon: Icons.add_rounded,
                      tooltip: 'Attach',
                      quiet: true,
                      onTap: widget.busy ? null : _attachMenu,
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter):
                              _submit,
                        },
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focus,
                          minLines: 1,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          style: context.text.bodyLarge?.copyWith(height: 1.35),
                          decoration: InputDecoration(
                            hintText: listening
                                ? 'Listening…'
                                : dictation.transcribing
                                ? 'Transcribing…'
                                : _hintText(ref.watch(telegramConnectedProvider)),
                            // One line, cut short rather than wrapped.
                            hintMaxLines: 1,
                            hintStyle: TextStyle(color: AppColors.text3, overflow: TextOverflow.ellipsis),
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    if (!canSend && !listening && !dictation.transcribing && ref.watch(settingsProvider.select((s) => s.voiceEnabled))) ...[
                      _RoundButton(
                        icon: Icons.graphic_eq_rounded,
                        tooltip: 'Talk to Triangle',
                        quiet: true,
                        onTap: () {
                          if (ref.read(settingsProvider).hasAnyKey) {
                            VoiceModeScreen.open(context);
                          } else {
                            showSnack(context, 'Add an AI provider API key first.');
                          }
                        },
                      ),
                      const SizedBox(width: Space.xs),
                    ],
                    if (!widget.busy && (!canSend || listening) && ref.watch(settingsProvider.select((s) => s.voiceEnabled)))
                      _MicButton(
                        listening: listening,
                        transcribing: dictation.transcribing,
                        level: dictation.level,
                        onTap: dictation.transcribing ? null : _toggleDictation,
                        onLongPress: listening ? null : () => _add(_recordVoice),
                      )
                    else
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: widget.busy
                            ? _RoundButton(
                                key: const ValueKey('stop'),
                                icon: Icons.stop_rounded,
                                tooltip: 'Stop',
                                onTap: widget.onStop,
                              )
                            : _RoundButton(
                                key: const ValueKey('send'),
                                icon: Icons.arrow_upward_rounded,
                                tooltip: 'Send',
                                onTap: canSend ? _submit : null,
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment, required this.onRemove});
  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return Padding(
      padding: const EdgeInsets.only(right: Space.s),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.m),
            child: a.isImage
                ? Image.file(
                    File(a.path),
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 150,
                    height: 54,
                    color: AppColors.surface3,
                    padding: const EdgeInsets.symmetric(horizontal: Space.s),
                    child: Row(
                      children: [
                        Icon(
                          a.isPdf
                              ? Icons.picture_as_pdf_outlined
                              : Icons.description_outlined,
                          size: 20,
                          color: AppColors.text2,
                        ),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: Text(
                            a.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.text,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: AppColors.bg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.transcribing,
    required this.level,
    this.onTap,
    this.onLongPress,
  });
  final bool listening;
  final bool transcribing;
  final double level;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (transcribing) {
      return const SizedBox.square(
        dimension: 36,
        child: Padding(
          padding: EdgeInsets.all(9),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Tooltip(
      message: listening ? 'Stop dictation' : 'Dictate (hold for a voice message)',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: listening
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    blurRadius: 4 + level * 14,
                    spreadRadius: level * 4,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: listening ? AppColors.accent : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox.square(
              dimension: 36,
              child: Icon(
                listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                size: 20,
                color: listening ? AppColors.bg : AppColors.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.quiet = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// A plain icon button rather than a filled circle.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: quiet
            ? Colors.transparent
            : (enabled ? AppColors.text : AppColors.surface3),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(
              icon,
              size: quiet ? 22 : 20,
              color: quiet
                  ? (enabled ? AppColors.text2 : AppColors.text3)
                  : (enabled ? AppColors.bg : AppColors.text3),
            ),
          ),
        ),
      ),
    );
  }
}

/// A scroll controller for the reversed message list that keeps the reader's
/// place while a reply streams in.
///
/// In a reversed list offset 0 is the newest message, so as the reply at the
/// bottom grows every message above it moves up: someone who scrolled up to
/// read would see the text slide away with each new token. When [hold] is
/// true and the list isn't at the bottom, the position moves by however much
/// the content grew, during layout, so nothing on screen moves. At the
/// bottom it follows the reply as usual.
class _HoldingScrollController extends ScrollController {
  _HoldingScrollController({required this.hold});
  final bool Function() hold;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _HoldingScrollPosition(holding: hold, physics: physics, context: context, oldPosition: oldPosition);
}

class _HoldingScrollPosition extends ScrollPositionWithSingleContext {
  _HoldingScrollPosition({required this.holding, required super.physics, required super.context, super.oldPosition});
  final bool Function() holding;

  /// Within this of the newest message counts as "at the bottom".
  static const _bottom = 80.0;

  /// The newest messages seen so far, and growth not yet made up for.
  final Set<Object> _seen = {};
  double _grown = 0;

  /// The newest message grew by [delta] since its last layout. That growth
  /// moves everything above it, so it is what the position makes up for.
  /// The list's own length isn't used: it is an estimate that changes as
  /// older messages are built while scrolling up, and following it threw the
  /// reader past the end, onto a blank screen.
  void grew(double delta) => _grown += delta;

  /// The newest message was laid out for the first time: all of it is new
  /// when it was just added; built again after scrolling back, none is.
  void appeared(Object id, double height) {
    if (_seen.add(id) && _seen.length > 1) _grown += height;
    if (_seen.length > 16) _seen.remove(_seen.first);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final grew = _grown;
    _grown = 0;
    if (grew != 0 && hasPixels && pixels > _bottom && holding()) {
      correctPixels((pixels + grew).clamp(minScrollExtent, maxScrollExtent));
      super.applyContentDimensions(minScrollExtent, maxScrollExtent);
      // Lay out again at the corrected place, so this frame already shows it.
      return false;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// Tells the list's position how tall the newest message is after each
/// layout, so a reply growing below the reader doesn't move what they read.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({super.key, required this.id, required super.child});
  final Object id;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeightReporter(id, Scrollable.maybeOf(context)?.position);

  @override
  void updateRenderObject(BuildContext context, _RenderHeightReporter r) => r
    ..id = id
    ..position = Scrollable.maybeOf(context)?.position;
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.id, this.position);
  Object id;
  ScrollPosition? position;

  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final p = position;
    if (p is _HoldingScrollPosition) {
      final last = _last;
      if (last == null) {
        p.appeared(id, size.height);
      } else if (size.height != last) {
        p.grew(size.height - last);
      }
    }
    _last = size.height;
  }
}
