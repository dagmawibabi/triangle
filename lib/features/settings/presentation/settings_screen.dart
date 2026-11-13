
import '../../../app/start_page.dart';
import '../../telegram/presentation/chat_actions.dart' show confirmAction;
import '../../brief/brief_store.dart';
import '../../canvas/canvas_store.dart';
import '../../chat/data/chat_controller.dart';
import 'system_prompt_screen.dart';
import '../../telegram/presentation/translate_sheet.dart'
    show translateLanguages;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/code_highlight.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../ai/data/ai.dart';
import 'package:omni_ai/omni_ai.dart' show ElevenLabsProvider, showVoicePicker;
import '../../auth/data/auth_controller.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/presentation/tg_avatar.dart';
import '../../voice/player_sheet.dart';
import '../../voice/speaker.dart';
import '../data/settings.dart';
import 'model_picker_screen.dart';
import 'approvals_screen.dart';
import 'permissions_screen.dart';
import 'settings_hub.dart';
import 'decisions_settings.dart';
import '../../assistant/memory.dart';
import '../../assistant/presentation/memory_screen.dart';

/// The pages Settings opens into.
enum SettingsSection {
  ai(
    'AI & models',
    'Chat, images and video, voice, decisions',
    Icons.auto_awesome_outlined,
  ),
  assistant(
    'Assistant',
    'Instructions, memory and tools',
    Icons.psychology_outlined,
  ),
  proactivity(
    'Proactivity & watches',
    'Notifications, background, watches',
    Icons.bolt_rounded,
  ),
  voice('Voice', 'Read aloud and dictation', Icons.graphic_eq_rounded),
  media(
    'Media & downloads',
    'Auto-download and storage',
    Icons.perm_media_outlined,
  ),
  appearance(
    'Appearance',
    'Accent, chat text and code colours',
    Icons.palette_outlined,
  ),
  account(
    'Account & privacy',
    'Your Telegram session and safety',
    Icons.shield_outlined,
  );

  const SettingsSection(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.section});

  /// The page to show; none shows the overview.
  final SettingsSection? section;

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    ModelType kind,
    String current,
    Future<void> Function(String) set,
  ) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ModelPickerScreen(current: current, kind: kind),
      ),
    );
    if (id != null) await set(id);
  }

  /// The model that answers when the chat model fails.
  Widget _fallbackTile(BuildContext context, WidgetRef ref, AppSettings s) {
    final ai = ref.read(aiProvider);
    ref.watch(modelCatalogProvider);
    final chosen = s.fallbackModel.trim();
    final auto = chosen.isEmpty ? fallbackChatModel(ai, s, s.model) : null;
    return ListTile(
      leading: lead(const Icon(Icons.alt_route_rounded)),
      title: const Text('Fallback model'),
      subtitle: Text(
        chosen.isNotEmpty
            ? '${modelLabel(chosen)} · answers when the chat model fails'
            : auto != null
            ? 'Automatic: a free model (now ${modelLabel(auto)})'
            : 'Automatic: no free model with tools for your keys yet',
        style: context.text.bodySmall,
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
      onTap: () async {
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          backgroundColor: AppColors.surface,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Automatic'),
                  subtitle: const Text('A free model from a service you have a key for (OpenRouter :free, LM Studio)'),
                  trailing: chosen.isEmpty ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.of(context).pop(''),
                ),
                ListTile(
                  leading: const Icon(Icons.list_rounded),
                  title: const Text('Choose a model…'),
                  trailing: chosen.isNotEmpty ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.of(context).pop('pick'),
                ),
              ],
            ),
          ),
        );
        if (choice == null || !context.mounted) return;
        final ctl = ref.read(settingsProvider.notifier);
        if (choice == 'pick') {
          await _pick(context, ref, ModelType.text, chosen.isEmpty ? s.model : chosen, ctl.setFallbackModel);
        } else {
          await ctl.setFallbackModel('');
        }
      },
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This ends Triangle\'s session for the Telegram account on screen; your other accounts stay signed in. '
          'Signing out of your only account also removes your conversations from this device. '
          'Nothing in your Telegram account is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = this.section;
    if (section == null) return const SettingsHub();
    // Voice lives in AI & models now, as its third tab.
    if (section == SettingsSection.ai || section == SettingsSection.voice) {
      return DefaultTabController(
        length: AiTab.values.length,
        initialIndex: section == SettingsSection.voice ? AiTab.voice.index : 0,
        child: Scaffold(
          appBar: AppBar(
            title: Text(SettingsSection.ai.title),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in AiTab.values) Tab(text: t.label)],
            ),
          ),
          body: TabBarView(
            children: [for (final t in AiTab.values) _page(context, ref, SettingsSection.ai, tab: t)],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: _page(context, ref, section),
    );
  }

  /// One settings page; [tab] picks the part of AI & models shown.
  Widget _page(BuildContext context, WidgetRef ref, SettingsSection section, {AiTab? tab}) {
    if (tab == AiTab.decisions) return const DecisionsSettingsPage();
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final cat = ref.watch(modelCatalogProvider);
    final store = ref.watch(telegramStoreProvider);
    final me = store.me;
    final limiter = ref.watch(telegramClientProvider).limiter;
    final model = cat.byId(s.model);
    return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.l,
              Space.s,
              Space.l,
              Space.xxl,
            ),
            children: [
              if (tab == AiTab.chat) ...[
                _FeatureSwitch(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'AI chat',
                  on: 'The assistant answers in chat.',
                  off: 'Off: chat is paused and no model is called from it.',
                  value: s.aiChatEnabled,
                  onChanged: ctl.setAiChatEnabled,
                ),
                const _Header('Keys', note: 'Any one is enough'),
                _Card(
                  children: [
                    _KeyTile(
                      title: 'Vercel AI Gateway',
                      subtitle: 'vercel.com → AI Gateway → API keys',
                      value: s.vercelKey,
                      onSave: ctl.setVercelKey,
                      verify: (k) => ref.read(aiProvider).verifyKey('gateway', key: k),
                      help: Uri.parse('https://vercel.com/ai-gateway/models'),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    _KeyTile(
                      title: 'OpenRouter',
                      subtitle: 'openrouter.ai → Keys',
                      value: s.openRouterKey,
                      onSave: ctl.setOpenRouterKey,
                      verify: (k) => ref.read(aiProvider).verifyKey('openrouter', key: k),
                      help: Uri.parse('https://openrouter.ai/keys'),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    _KeyTile(
                      title: 'OpenCode Zen',
                      subtitle: 'opencode.ai → Console → API keys. Pay-as-you-go GPT, Claude, Gemini, GLM, Kimi and more.',
                      value: s.openCodeKey,
                      onSave: ctl.setOpenCodeKey,
                      verify: (k) => ref.read(aiProvider).verifyKey('opencode', key: k),
                      help: Uri.parse('https://opencode.ai/console'),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    _KeyTile(
                      title: 'Google AI Studio Gemini',
                      subtitle: 'AI Studio → API keys. Lists the models available to your key.',
                      value: s.geminiKey,
                      onSave: ctl.setGeminiKey,
                      verify: (k) => ref.read(aiProvider).verifyKey('google', key: k),
                      help: Uri.parse('https://aistudio.google.com/app/apikey'),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    _KeyTile(
                      title: 'LM Studio',
                      subtitle:
                          'Models running on your computer. In LM Studio: Developer → Start server, with "Serve on Local Network" on. Use the address it shows, e.g. 192.168.1.20:1234.',
                      value: s.lmStudioUrl,
                      onSave: ctl.setLmStudioUrl,
                      verify: (url) => ref.read(aiProvider).verifyKey('lmstudio', key: url),
                      help: Uri.parse('https://lmstudio.ai/docs/developer'),
                      secret: false,
                      hint: '192.168.1.20:1234',
                      helpLabel: 'How to',
                    ),
                  ],
                ),
              ],
              if (tab == AiTab.chat) ...[
                const _Header('Model'),
                _Card(
                  children: [
                    _ModelTile(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Chat',
                      model: cat.byId(s.model),
                      id: s.model,
                      onTap: () => _pick(
                        context,
                        ref,
                        ModelType.text,
                        s.model,
                        ctl.setModel,
                      ),
                    ),
                    _fallbackTile(context, ref, s),
                    if (model != null && !model.toolCall)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.l,
                          0,
                          Space.l,
                          Space.m,
                        ),
                        child: Text(
                          'This model can\'t call tools, so answers can\'t use your Telegram.',
                          style: context.text.bodySmall?.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        Space.m,
                        Space.l,
                        Space.l,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Thinking', style: context.text.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            'How much reasoning models think before answering.',
                            style: context.text.bodySmall,
                          ),
                          const SizedBox(height: Space.m),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<Thinking>(
                              showSelectedIcon: false,
                              segments: [
                                for (final t in Thinking.values)
                                  ButtonSegment(value: t, label: Text(t.label)),
                              ],
                              selected: {s.thinking},
                              onSelectionChanged: (v) =>
                                  ctl.setThinking(v.first),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              if (tab == AiTab.media) ...[
                _FeatureSwitch(
                  icon: Icons.brush_outlined,
                  title: 'Images',
                  on: 'The assistant can make pictures and look at them.',
                  off: 'Off: no picture is made or looked at.',
                  value: s.mediaEnabled,
                  onChanged: ctl.setMediaEnabled,
                ),
                const SizedBox(height: Space.s),
                _FeatureSwitch(
                  icon: Icons.movie_creation_outlined,
                  title: 'Video',
                  on: 'The assistant can make short videos when you ask for one.',
                  off: 'Off: no video is made. Videos cost far more than pictures.',
                  value: s.videoEnabled,
                  onChanged: ctl.setVideoEnabled,
                ),
                const _Header('Image model'),
                _Card(
                  children: [
                    _ModelTile(
                      icon: Icons.brush_outlined,
                      title: 'Images',
                      model: cat.byId(s.imageModel),
                      id: s.imageModel,
                      onTap: () => _pick(
                        context,
                        ref,
                        ModelType.image,
                        s.imageModel,
                        ctl.setImageModel,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
                      child: Text(
                        'Used by generate_image. Looking at pictures (view_image) uses your chat model, so it needs one that sees images.',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
                const _Header('Video model'),
                _Card(
                  children: [
                    _ModelTile(
                      icon: Icons.movie_creation_outlined,
                      title: 'Video',
                      model: s.videoModel.isEmpty ? null : cat.byId(s.videoModel),
                      id: s.videoModel.isEmpty ? 'Not chosen' : s.videoModel,
                      onTap: () => _pick(
                        context,
                        ref,
                        ModelType.video,
                        s.videoModel,
                        ctl.setVideoModel,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
                      child: Text(
                        'Used by generate_video, which can also start from a picture in the chat. Priced per second by the provider; a clip takes from seconds to minutes.',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              if (section == SettingsSection.assistant) ...[
                const _Header('Assistant'),
                _Card(
                  children: [
                    ListTile(
                      leading: lead(const Icon(Icons.bookmarks_outlined)),
                      title: const Text('Memory'),
                      subtitle: Text(
                        '${ref.watch(memoryProvider).length} things remembered',
                        style: context.text.bodySmall,
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.text3,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MemoryScreen(),
                        ),
                      ),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    const _InstructionsField(),
                  ],
                ),
                const _Header('System prompt'),
                _Card(
                  children: [
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.description_outlined)),
                      title: const Text('Use the system prompt'),
                      subtitle: Text(systemPromptStatus(s), style: context.text.bodySmall),
                      value: s.systemPromptEnabled,
                      onChanged: ctl.setSystemPromptEnabled,
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: lead(const Icon(Icons.visibility_outlined)),
                      title: const Text('See the exact prompt'),
                      subtitle: Text('Everything a new chat is sent, filled in', style: context.text.bodySmall),
                      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const SystemPromptPreviewScreen()),
                      ),
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: lead(const Icon(Icons.edit_note_rounded)),
                      title: const Text('Edit, clear or reset'),
                      subtitle: Text(
                        s.systemPromptCustom ? 'Edited by you' : 'Built in',
                        style: context.text.bodySmall,
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const SystemPromptEditorScreen()),
                      ),
                    ),
                  ],
                ),
                const _Header('What it may do'),
                _Card(
                  children: [
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.bolt_outlined)),
                      title: const Text('Load tools as needed'),
                      subtitle: Text(
                        s.loadToolsOnDemand
                            ? 'Each message carries only the tools it needs; the assistant loads more when it has to. Cheaper and faster.'
                            : 'Off: every tool that is on goes with every message. Costs much more per message.',
                        style: context.text.bodySmall,
                      ),
                      value: s.loadToolsOnDemand,
                      onChanged: ctl.setLoadToolsOnDemand,
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.lock_outline_rounded)),
                      title: const Text('Read-only mode'),
                      subtitle: Text(
                        'Only tools that read: nothing is sent, changed or deleted',
                        style: context.text.bodySmall,
                      ),
                      value: s.readOnlyMode,
                      onChanged: ctl.setReadOnlyMode,
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: lead(const Icon(Icons.front_hand_outlined)),
                      title: const Text('Approvals'),
                      subtitle: Text(
                        s.approvalMode.explanation,
                        style: context.text.bodySmall,
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.text3,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ApprovalsScreen(),
                        ),
                      ),
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.mark_chat_read_outlined)),
                      title: const Text('Mark chats read when it reads them'),
                      subtitle: Text(
                        'Off: the assistant reads without touching your unread counts',
                        style: context.text.bodySmall,
                      ),
                      value: s.aiReadOnView,
                      onChanged: ctl.setAiReadOnView,
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.reply_rounded)),
                      title: const Text('Mark chats read when it replies'),
                      subtitle: Text(
                        'Like Telegram does when you answer',
                        style: context.text.bodySmall,
                      ),
                      value: s.aiReadOnReply,
                      onChanged: ctl.setAiReadOnReply,
                    ),
                  ],
                ),
                const _Header('Model'),
                _Card(
                  children: [
                    _ModelTile(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Chat model',
                      model: cat.byId(s.model),
                      id: s.model,
                      onTap: () => _pick(
                        context,
                        ref,
                        ModelType.text,
                        s.model,
                        ctl.setModel,
                      ),
                    ),
                    _fallbackTile(context, ref, s),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        Space.m,
                        Space.l,
                        Space.l,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Thinking', style: context.text.titleSmall),
                          const SizedBox(height: Space.m),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<Thinking>(
                              showSelectedIcon: false,
                              segments: [
                                for (final t in Thinking.values)
                                  ButtonSegment(value: t, label: Text(t.label)),
                              ],
                              selected: {s.thinking},
                              onSelectionChanged: (v) =>
                                  ctl.setThinking(v.first),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const _Header('Answers'),
                _Card(
                  children: [
                    ListTile(
                      leading: lead(const Icon(Icons.short_text_rounded)),
                      title: const Text('Answer length'),
                      subtitle: Text(
                        s.answerStyle.explanation,
                        style: context.text.bodySmall,
                      ),
                      trailing: DropdownButton<AnswerStyle>(
                        value: s.answerStyle,
                        underline: const SizedBox(),
                        items: [
                          for (final v in AnswerStyle.values)
                            DropdownMenuItem(value: v, child: Text(v.label)),
                        ],
                        onChanged: (v) {
                          if (v != null) ctl.setAnswerStyle(v);
                        },
                      ),
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: lead(const Icon(Icons.language_rounded)),
                      title: const Text('Answer language'),
                      subtitle: Text(
                        'The language the assistant writes in',
                        style: context.text.bodySmall,
                      ),
                      trailing: DropdownButton<String>(
                        value: s.answerLanguage,
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Same as mine'),
                          ),
                          for (final v in translateLanguages.values)
                            DropdownMenuItem(value: v, child: Text(v)),
                        ],
                        onChanged: (v) {
                          if (v != null) ctl.setAnswerLanguage(v);
                        },
                      ),
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: lead(const Icon(Icons.repeat_rounded)),
                      title: const Text('Steps per answer'),
                      subtitle: Text(
                        'Up to ${s.maxSteps} rounds of tool calls. More digs deeper but costs more.',
                        style: context.text.bodySmall,
                      ),
                    ),
                    Slider(
                      value: s.maxSteps.toDouble().clamp(4, 30),
                      min: 4,
                      max: 30,
                      divisions: 26,
                      label: '${s.maxSteps}',
                      onChanged: (v) => ctl.setMaxSteps(v.round()),
                    ),
                  ],
                ),
              ],
              if (section == SettingsSection.proactivity) ...[
                const _Header('Proactivity'),
                _Card(
                  children: [
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.bolt_rounded)),
                      title: const Text('Proactive assistant'),
                      subtitle: Text(
                        s.proactive
                            ? 'Watches, app watches, routines, jobs and briefs run on their own'
                            : 'All watches, routines and scheduled briefs are paused',
                        style: context.text.bodySmall,
                      ),
                      value: s.proactive,
                      onChanged: ctl.setProactive,
                    ),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.notifications_none_rounded)),
                      title: const Text('Notifications'),
                      subtitle: Text(
                        'What watches and routines find, reminders, briefs, and approvals they wait for',
                        style: context.text.bodySmall,
                      ),
                      value: s.notifications,
                      onChanged: ctl.setNotifications,
                    ),
                    if (s.notifications) ...[
                      SwitchListTile(
                        secondary: lead(const Icon(Icons.bedtime_outlined)),
                        title: const Text('Quiet hours'),
                        subtitle: Text(
                          s.quietHours
                              ? 'Silent from ${s.quietStart} to ${s.quietEnd}; updates still arrive in the app'
                              : 'Pause notifications overnight',
                          style: context.text.bodySmall,
                        ),
                        value: s.quietHours,
                        onChanged: ctl.setQuietHours,
                      ),
                      if (s.quietHours)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.l,
                            0,
                            Space.l,
                            Space.m,
                          ),
                          child: Row(
                            children: [
                              for (final (start, label, value) in [
                                (true, 'From', s.quietStart),
                                (false, 'To', s.quietEnd),
                              ]) ...[
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final p = value.split(':');
                                      final t = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay(
                                          hour: int.tryParse(p.first) ?? 0,
                                          minute: int.tryParse(p.last) ?? 0,
                                        ),
                                      );
                                      if (t == null) return;
                                      final v =
                                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                      start
                                          ? ctl.setQuietStart(v)
                                          : ctl.setQuietEnd(v);
                                    },
                                    child: Text('$label $value'),
                                  ),
                                ),
                                if (start) const SizedBox(width: Space.s),
                              ],
                            ],
                          ),
                        ),
                    ],
                    if (ref.watch(telegramConnectedProvider))
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.alternate_email_rounded)),
                      title: const Text('When I\'m mentioned'),
                      subtitle: Text(
                        'A notification when someone @mentions you or replies to you in a group; tap to open the chat',
                        style: context.text.bodySmall,
                      ),
                      value: s.mentionAlerts,
                      onChanged: ctl.setMentionAlerts,
                    ),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.nightlight_outlined)),
                      title: const Text('Keep running in the background'),
                      subtitle: Text(
                        'A quiet ongoing notification keeps watches, app watches and routines running after you leave the app',
                        style: context.text.bodySmall,
                      ),
                      value: s.keepAlive,
                      onChanged: ctl.setKeepAlive,
                    ),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.all_inclusive_rounded)),
                      title: const Text('Always run in the background'),
                      subtitle: Text(
                        'Once opened, Triangle stays ready in the background even with no watches on',
                        style: context.text.bodySmall,
                      ),
                      value: s.backgroundAlways,
                      onChanged: ctl.setBackgroundAlways,
                    ),
                    ListTile(
                      leading: lead(const Icon(Icons.notifications_paused_outlined)),
                      title: const Text('Background notification'),
                      subtitle: Text('${s.backgroundNotice.label} · ${s.backgroundNotice.description}', style: context.text.bodySmall),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final v = await showModalBottomSheet<BackgroundNotice>(
                          context: context,
                          showDragHandle: true,
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
                                  child: Text(
                                    'Android keeps an app running in the background only while it shows an ongoing notification. It\'s shown even when Triangle\'s alerts are off.',
                                    style: context.text.bodySmall?.copyWith(color: AppColors.text2),
                                  ),
                                ),
                                RadioGroup<BackgroundNotice>(
                                  groupValue: s.backgroundNotice,
                                  onChanged: (v) => Navigator.pop(context, v),
                                  child: Column(
                                    children: [
                                      for (final n in BackgroundNotice.values)
                                        RadioListTile<BackgroundNotice>(
                                          value: n,
                                          title: Text(n.label),
                                          subtitle: Text(n.description, style: context.text.bodySmall),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: Space.s),
                              ],
                            ),
                          ),
                        );
                        if (v != null) await ctl.setBackgroundNotice(v);
                      },
                    ),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.restart_alt_rounded)),
                      title: const Text('Start when the phone restarts'),
                      subtitle: Text(
                        'Starts in the background after a reboot, so watches and reminders carry on without opening the app',
                        style: context.text.bodySmall,
                      ),
                      value: s.startOnBoot,
                      onChanged: ctl.setStartOnBoot,
                    ),
                  ],
                ),
                const _Header('Approvals & permissions'),
                _Card(
                  children: [
                    ListTile(
                      leading: lead(const Icon(Icons.front_hand_outlined)),
                      title: const Text('Approvals'),
                      subtitle: Text(
                        s.approvalMode.label,
                        style: context.text.bodySmall,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ApprovalsScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: lead(const Icon(Icons.verified_user_outlined)),
                      title: const Text('Permissions'),
                      subtitle: Text(
                        'Battery, notifications, alarms, microphone, location, texts, calls, contacts',
                        style: context.text.bodySmall,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PermissionsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (tab == AiTab.voice) ...[
                _FeatureSwitch(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Voice',
                  on: 'Read aloud, dictation and the audio tools.',
                  off: 'Off: nothing is read aloud, dictated or generated as audio.',
                  value: s.voiceEnabled,
                  onChanged: ctl.setVoiceEnabled,
                ),
                const _Header('Voice keys'),
                _Card(
                  children: [
                    _KeyTile(
                      title: 'Addis AI',
                      subtitle: 'Addis Voices 2 for Amharic, Afaan Oromo and Tigrinya.',
                      value: s.addisKey,
                      onSave: ctl.setAddisKey,
                      verify: (k) => ref.read(aiProvider).verifyKey('addis', key: k),
                      help: Uri.parse('https://addisassistant.com/api-keys'),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    _KeyTile(
                      title: 'ElevenLabs',
                      subtitle: 'For ElevenLabs voices and dictation',
                      value: s.elevenKey,
                      onSave: ctl.setElevenKey,
                      verify: (k) => ref.read(aiProvider).verifyKey('elevenlabs', key: k),
                      help: Uri.parse(
                        'https://elevenlabs.io/app/settings/api-keys',
                      ),
                    ),
                  ],
                ),
                const _Header('Read aloud'),
                _Card(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: Space.s,
                        children: [
                          for (final engines in const [
                            [VoiceEngine.device, VoiceEngine.ai],
                            [VoiceEngine.addis, VoiceEngine.elevenLabs],
                          ])
                            SegmentedButton<VoiceEngine>(
                              showSelectedIcon: false,
                              emptySelectionAllowed: true,
                              segments: [
                                for (final e in engines)
                                  ButtonSegment(value: e, label: Text(e.label)),
                              ],
                              selected: {
                                if (engines.contains(s.voiceEngine)) s.voiceEngine,
                              },
                              onSelectionChanged: (v) {
                                if (v.isNotEmpty) ctl.setVoiceEngine(v.first);
                              },
                            ),
                        ],
                      ),
                    ),
                    if (s.voiceEngine != VoiceEngine.ai) ...[
                      const Divider(indent: 56),
                      _ModelTile(
                        icon: Icons.graphic_eq_rounded,
                        title: 'AI audio model',
                        model: cat.byId(s.speechModel),
                        id: s.speechModel,
                        onTap: () => _pick(
                          context,
                          ref,
                          ModelType.speech,
                          s.speechModel,
                          ctl.setSpeechModel,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.l,
                          0,
                          Space.l,
                          Space.m,
                        ),
                        child: Text(
                          'Used when the assistant generates audio.',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                    ...switch (s.voiceEngine) {
                      VoiceEngine.device => [
                        ListTile(
                          leading: lead(const Icon(Icons.record_voice_over_outlined)),
                          title: const Text('Device voice'),
                          subtitle: Text(
                            s.deviceVoice.isEmpty
                                ? 'System default'
                                : s.deviceVoice,
                            style: context.text.bodySmall,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.text3,
                          ),
                          onTap: () => _pickDeviceVoice(context, ref),
                        ),
                      ],
                      VoiceEngine.ai => [
                        _ModelTile(
                          icon: Icons.graphic_eq_rounded,
                          title: 'AI audio model',
                          model: cat.byId(s.speechModel),
                          id: s.speechModel,
                          onTap: () => _pick(
                            context,
                            ref,
                            ModelType.speech,
                            s.speechModel,
                            ctl.setSpeechModel,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.l,
                            0,
                            Space.l,
                            Space.m,
                          ),
                          child: Text(
                            'Used for Read aloud and AI-generated audio.',
                            style: context.text.bodySmall,
                          ),
                        ),
                        const Divider(indent: 56),
                        ListTile(
                          leading: lead(const Icon(Icons.record_voice_over_outlined)),
                          title: const Text('Voice'),
                          subtitle: Text(
                            s.aiVoice.isEmpty ? 'Model default' : s.aiVoice,
                            style: context.text.bodySmall,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.text3,
                          ),
                          onTap: () => _pickAiVoice(
                            context,
                            ref,
                            cat.byId(s.speechModel)?.voices ?? const [],
                          ),
                        ),
                      ],
                      VoiceEngine.addis => [
                        if (!s.hasAddisKey)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.l,
                              0,
                              Space.l,
                              Space.m,
                            ),
                            child: Text(
                              'Add your Addis AI key above to use Addis Voices 2.',
                              style: context.text.bodySmall?.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ListTile(
                          leading: lead(const Icon(Icons.record_voice_over_outlined)),
                          title: const Text('Addis AI voice'),
                          subtitle: Text(
                            s.aiVoice.isEmpty
                                ? 'Choose a live catalog voice'
                                : s.aiVoice,
                            style: context.text.bodySmall,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.text3,
                          ),
                          enabled: s.hasAddisKey,
                          onTap: () async {
                            final v = await showVoicePicker(context, ai: ref.read(aiProvider), source: 'addis', selected: s.aiVoice);
                            if (v != null) await ctl.setAiVoice(v.id);
                          },
                        ),
                      ],
                      VoiceEngine.elevenLabs => [
                        if (!s.hasElevenKey)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.l,
                              0,
                              Space.l,
                              Space.m,
                            ),
                            child: Text(
                              'Add your ElevenLabs key above to use its voices.',
                              style: context.text.bodySmall?.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ListTile(
                          leading: lead(const Icon(Icons.record_voice_over_outlined)),
                          title: const Text('ElevenLabs voice'),
                          subtitle: Text(
                            s.elevenVoiceName.isEmpty
                                ? 'Choose a voice'
                                : s.elevenVoiceName,
                            style: context.text.bodySmall,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.text3,
                          ),
                          enabled: s.hasElevenKey,
                          onTap: () async {
                            final v = await showVoicePicker(
                              context,
                              ai: ref.read(aiProvider),
                              source: 'elevenlabs',
                              selected: s.elevenVoiceId,
                            );
                            if (v != null) await ctl.setElevenVoice(v.id, v.name);
                          },
                        ),
                        const Divider(indent: 56),
                        ListTile(
                          leading: lead(const Icon(Icons.tune_rounded)),
                          title: const Text('ElevenLabs model'),
                          subtitle: Text(
                            ElevenLabsProvider.speechModels
                                    .where((m) => m.id == s.elevenModel)
                                    .map((m) => '${m.name} · ${m.note}')
                                    .firstOrNull ??
                                s.elevenModel,
                            style: context.text.bodySmall,
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.expand_more_rounded,
                              color: AppColors.text3,
                            ),
                            onSelected: ctl.setElevenModel,
                            itemBuilder: (_) => [
                              for (final m in ElevenLabsProvider.speechModels)
                                PopupMenuItem(
                                  value: m.id,
                                  child: Text('${m.name} · ${m.note}'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    },
                    const Divider(indent: Space.l, endIndent: Space.l),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        Space.m,
                        Space.s,
                        0,
                      ),
                      child: Row(
                        children: [
                          Text('Speed', style: context.text.titleSmall),
                          Expanded(
                            child: Slider(
                              value: s.speechRate.clamp(0.5, 2.5),
                              min: 0.5,
                              max: 2.5,
                              divisions: 20,
                              label: '${s.speechRate.toStringAsFixed(2)}×',
                              onChanged: (v) =>
                                  ctl.setSpeechRate((v * 20).round() / 20),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${s.speechRate.toStringAsFixed(2)}×',
                              style: context.text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        0,
                        Space.l,
                        Space.m,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Test voice'),
                          onPressed: () {
                            ref
                                .read(speakerProvider)
                                .play(
                                  'Hi! This is how Triangle will read your answers aloud. You have three unread messages from your channels.',
                                  title: 'Voice test',
                                );
                            showPlayerSheet(context);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (section == SettingsSection.media) ...[
                const _Header('Media'),
                _Card(
                  children: [
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.photo_outlined)),
                      title: const Text('Download photos automatically'),
                      subtitle: Text(
                        'Otherwise photos show blurred until you tap them',
                        style: context.text.bodySmall,
                      ),
                      value: s.autoPhotos,
                      onChanged: (v) => ctl.setAutoDownload(photos: v),
                    ),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.mic_none_rounded)),
                      title: const Text(
                        'Download voice messages automatically',
                      ),
                      subtitle: Text(
                        'So they play straight away',
                        style: context.text.bodySmall,
                      ),
                      value: s.autoVoice,
                      onChanged: (v) => ctl.setAutoDownload(voice: v),
                    ),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.music_note_outlined)),
                      title: const Text('Download music automatically'),
                      subtitle: Text(
                        'Songs can be large; off downloads when you press play',
                        style: context.text.bodySmall,
                      ),
                      value: s.autoMusic,
                      onChanged: (v) => ctl.setAutoDownload(music: v),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        0,
                        Space.l,
                        Space.m,
                      ),
                      child: Text(
                        'Everything downloaded stays on this phone in Telegram\'s own cache, so it opens instantly next time.',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              if (section == SettingsSection.appearance) ...[
                const _Header('Side drawer'),
                _Card(
                  children: [
                    _DrawerSectionTile(
                      icon: Icons.forum_outlined,
                      title: 'Chats',
                      subtitle: 'DMs, groups, channels, bots, contacts and calls',
                      value: s.drawerChats,
                      onChanged: ctl.setDrawerChats,
                      items: DrawerItems.chats,
                      settings: s,
                      onItem: ctl.setDrawerItem,
                    ),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.folder_outlined)),
                      title: const Text('Folders'),
                      subtitle: Text(
                        'Your Telegram chat folders',
                        style: context.text.bodySmall,
                      ),
                      value: s.drawerFolders,
                      onChanged: ctl.setDrawerFolders,
                    ),
                    _DrawerSectionTile(
                      icon: Icons.widgets_outlined,
                      title: 'Tools',
                      subtitle: 'Files, Brief, Content Canvas, Search, Browser and PC screen',
                      value: s.drawerTools,
                      onChanged: ctl.setDrawerTools,
                      items: DrawerItems.tools,
                      settings: s,
                      onItem: ctl.setDrawerItem,
                    ),
                  ],
                ),
                const _Header('Appearance'),
                _Card(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Theme', style: context.text.titleSmall),
                          const SizedBox(height: Space.m),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<AppThemeMode>(
                              showSelectedIcon: false,
                              segments: [
                                for (final (m, icon) in const [
                                  (AppThemeMode.system, Icons.brightness_auto_outlined),
                                  (AppThemeMode.light, Icons.light_mode_outlined),
                                  (AppThemeMode.dark, Icons.dark_mode_outlined),
                                ])
                                  ButtonSegment(value: m, icon: Icon(icon, size: 18), label: Text(m.label)),
                              ],
                              selected: {s.themeMode},
                              onSelectionChanged: (v) => ctl.setThemeMode(v.first),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Voice mode shape', style: context.text.titleSmall),
                          const SizedBox(height: Space.m),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<OrbShape>(
                              showSelectedIcon: false,
                              segments: [
                                for (final (o, icon) in const [
                                  (OrbShape.triangle, Icons.change_history_rounded),
                                  (OrbShape.sphere, Icons.circle_outlined),
                                ])
                                  ButtonSegment(value: o, icon: Icon(icon, size: 18), label: Text(o.label)),
                              ],
                              selected: {s.orbShape},
                              onSelectionChanged: (v) => ctl.setOrbShape(v.first),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    _AppearancePreview(
                      accent: AppColors.activeAccent,
                      fontSize: s.chatFontSize,
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Accent colour', style: context.text.titleSmall),
                          const SizedBox(height: Space.m),
                          Wrap(
                            spacing: Space.s,
                            runSpacing: Space.s,
                            children: [
                              for (final a in AccentChoice.values)
                                ChoiceChip(
                                  label: Text(a.label),
                                  selected: s.accent == a,
                                  avatar: CircleAvatar(
                                    radius: 7,
                                    backgroundColor: Color(a.value),
                                  ),
                                  onSelected: (_) => ctl.setAccent(a),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chat text size',
                            style: context.text.titleSmall,
                          ),
                          Text(
                            '${s.chatFontSize.toStringAsFixed(0)} pt',
                            style: context.text.bodySmall,
                          ),
                          Slider(
                            value: s.chatFontSize,
                            min: 13,
                            max: 21,
                            divisions: 8,
                            label: '${s.chatFontSize.toStringAsFixed(0)} pt',
                            onChanged: ctl.setChatFontSize,
                          ),
                          const SizedBox(height: Space.s),
                          Text('Chat font', style: context.text.titleSmall),
                          const SizedBox(height: Space.m),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ChatFont>(
                              showSelectedIcon: false,
                              segments: [
                                for (final f in ChatFont.values)
                                  ButtonSegment(
                                    value: f,
                                    label: Text(f.label, style: TextStyle(fontFamily: f.family)),
                                  ),
                              ],
                              selected: {s.chatFont},
                              onSelectionChanged: (v) => ctl.setChatFont(v.first),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const _Header('Opening the app'),
                _Card(
                  children: [
                    ListTile(
                      leading: lead(Icon(StartPage.parse(s.startPage).icon)),
                      title: const Text('Start on'),
                      subtitle: Text(
                        'The page Triangle opens on. Going back from it lands in the AI chat.',
                        style: context.text.bodySmall,
                      ),
                      trailing: DropdownButton<StartPage>(
                        value: StartPage.parse(s.startPage),
                        underline: const SizedBox.shrink(),
                        borderRadius: BorderRadius.circular(Radii.m),
                        items: [
                          for (final p in StartPage.values)
                            DropdownMenuItem(value: p, child: Text(p.label)),
                        ],
                        onChanged: (p) {
                          if (p != null) ctl.setStartPage(p.name);
                        },
                      ),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: false, icon: Icon(Icons.add_comment_outlined), label: Text('New chat')),
                              ButtonSegment(value: true, icon: Icon(Icons.history_rounded), label: Text('Last chat')),
                            ],
                            selected: {s.openLastChat},
                            onSelectionChanged: (v) => ctl.setOpenLastChat(v.first),
                          ),
                          const SizedBox(height: Space.s),
                          Text(
                            s.openLastChat
                                ? 'Opening Triangle shows the chat you last had open. Switching back from another app always keeps where you were.'
                                : 'Opening Triangle starts a new chat. Switching back from another app always keeps where you were.',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const _Header('Lists'),
                _Card(
                  children: [
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.format_list_bulleted_rounded)),
                      title: const Text('Leading icons'),
                      subtitle: Text('Icons at the start of rows in settings, menus and lists', style: context.text.bodySmall),
                      value: s.leadingIcons,
                      onChanged: ctl.setLeadingIcons,
                    ),
                  ],
                ),
                const _Header('Code'),
                _Card(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Highlight theme', style: context.text.titleSmall),
                          const SizedBox(height: 2),
                          Text('Code in answers and in the code editor', style: context.text.bodySmall),
                          const SizedBox(height: Space.m),
                          Wrap(
                            spacing: Space.s,
                            runSpacing: Space.s,
                            children: [
                              for (final v in CodeThemeChoice.values)
                                ChoiceChip(
                                  label: Text(v.label),
                                  selected: s.codeTheme == v,
                                  onSelected: (_) => ctl.setCodeTheme(v),
                                ),
                            ],
                          ),
                          const SizedBox(height: Space.m),
                          Container(
                            padding: const EdgeInsets.all(Space.m),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(Radii.m),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: HighlightedCode(
                              language: 'python',
                              theme: s.codeTheme,
                              code: '# Unread messages per chat\n'
                                  'def unread(chats, limit=5):\n'
                                  '    busy = [c for c in chats if c.unread > 0]\n'
                                  '    return sorted(busy, key=lambda c: -c.unread)[:limit]\n'
                                  '\n'
                                  'print(unread(my_chats), "done", 42)',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const _Header('In the chat'),
                _Card(
                  children: [
                    ..._dividedSwitches(context, [
                      (Icons.schedule_outlined, 'Dates and time', 'Times on messages and a divider for each day', s.showChatDateTime, ctl.setShowChatDateTime),
                      (Icons.copy_outlined, 'Copy button', 'Under each answer', s.showChatCopyButton, ctl.setShowChatCopyButton),
                      (Icons.volume_up_outlined, 'Speak button', 'Read an answer aloud from under it', s.showChatSpeakButton, ctl.setShowChatSpeakButton),
                      (Icons.label_outline_rounded, 'Model name', 'Which model wrote each answer', s.showModelName, ctl.setShowModelName),
                      (Icons.psychology_outlined, 'Show thinking', 'The model\'s reasoning above its answer', s.showThinking, ctl.setShowThinking),
                      (Icons.build_circle_outlined, 'Show tool calls', 'A card for each tool the assistant uses. Approvals always show.', s.showToolCalls, ctl.setShowToolCalls),
                      (Icons.density_small_rounded, 'Compact chat', 'Less space between messages', s.compactChat, ctl.setCompactChat),
                    ]),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.toll_outlined)),
                      title: const Text('Tokens and cost under answers'),
                      subtitle: Text(
                        'A small line under each reply: tokens in and out, cached and reasoning tokens, and what it cost.',
                        style: context.text.bodySmall,
                      ),
                      value: s.showMessageUsage,
                      onChanged: ctl.setShowMessageUsage,
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.web_asset_outlined)),
                      title: const Text('Link previews'),
                      subtitle: Text(
                        'The site card under messages with links',
                        style: context.text.bodySmall,
                      ),
                      value: s.showLinkPreviews,
                      onChanged: ctl.setShowLinkPreviews,
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    ListTile(
                      leading: lead(const Icon(Icons.translate_rounded)),
                      title: const Text('Translate into'),
                      subtitle: Text(
                        'For the Translate button on messages',
                        style: context.text.bodySmall,
                      ),
                      trailing: DropdownButton<String>(
                        value: s.translateTo,
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Phone language'),
                          ),
                          for (final e in translateLanguages.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) ctl.setTranslateTo(v);
                        },
                      ),
                    ),
                  ],
                ),
                const _Header('Chats'),
                _Card(
                  children: [
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.schedule_rounded)),
                      title: const Text('24-hour clock'),
                      subtitle: Text(
                        s.use24h ? '14:05' : '2:05 PM',
                        style: context.text.bodySmall,
                      ),
                      value: s.use24h,
                      onChanged: ctl.setUse24h,
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.account_circle_outlined)),
                      title: const Text('Avatars in groups'),
                      subtitle: Text(
                        'Who wrote each message, at a glance',
                        style: context.text.bodySmall,
                      ),
                      value: s.groupAvatars,
                      onChanged: ctl.setGroupAvatars,
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.view_headline_rounded)),
                      title: const Text('Compact chat lists'),
                      subtitle: Text(
                        'Smaller rows, more chats on screen',
                        style: context.text.bodySmall,
                      ),
                      value: s.compactList,
                      onChanged: ctl.setCompactList,
                    ),
                  ],
                ),
              ],
              if (tab == AiTab.voice) ...[
                const _Header('Dictation'),
                _Card(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Speech to text in the input box',
                            style: context.text.bodySmall,
                          ),
                          const SizedBox(height: Space.m),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<DictationEngine>(
                              showSelectedIcon: false,
                              segments: [
                                for (final e in DictationEngine.values)
                                  ButtonSegment(value: e, label: Text(e.label)),
                              ],
                              selected: {s.dictationEngine},
                              onSelectionChanged: (v) =>
                                  ctl.setDictationEngine(v.first),
                            ),
                          ),
                          const SizedBox(height: Space.s),
                          Text(switch (s.dictationEngine) {
                            DictationEngine.device => 'Live, on the device. Free; quality depends on your phone.',
                            DictationEngine.ai => 'Records, then a chat model that understands audio writes it out.',
                            DictationEngine.elevenLabs => 'Records, then ElevenLabs Scribe writes it out. Needs your ElevenLabs key.',
                          }, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    if (s.dictationEngine == DictationEngine.ai) ...[
                      const Divider(indent: Space.l, endIndent: Space.l),
                      _ModelTile(
                        icon: Icons.hearing_outlined,
                        title: 'Dictation model',
                        model: cat.byId(s.transcriptionModel),
                        id: s.transcriptionModel,
                        onTap: () => _pick(
                          context,
                          ref,
                          ModelType.transcription,
                          s.transcriptionModel,
                          ctl.setTranscriptionModel,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (section == SettingsSection.account) ...[
                const _Header('Presence'),
                _Card(
                  children: [
                    SwitchListTile(
                      secondary: lead(Icon(
                        Icons.circle,
                        size: 14,
                        color: AppColors.success,
                      )),
                      title: const Text('Appear online while using the app'),
                      subtitle: Text(
                        'Needed to see who is typing and live online status. You go offline as soon as you leave the app.',
                        style: context.text.bodySmall,
                      ),
                      value: s.appearOnline,
                      onChanged: ctl.setAppearOnline,
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.done_all_rounded)),
                      title: const Text('Mark chats read when I open them'),
                      subtitle: Text(
                        'Off: reading here stays invisible, and chats stay unread in Telegram.',
                        style: context.text.bodySmall,
                      ),
                      value: s.markReadOnOpen,
                      onChanged: ctl.setMarkReadOnOpen,
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.mark_chat_read_outlined)),
                      title: const Text('Mark read when the assistant replies'),
                      subtitle: Text(
                        'When it sends or answers in a DM, group or channel, the messages there show as seen.',
                        style: context.text.bodySmall,
                      ),
                      value: s.aiReadOnReply,
                      onChanged: ctl.setAiReadOnReply,
                    ),
                    const Divider(indent: 56),
                    SwitchListTile(
                      secondary: lead(const Icon(Icons.visibility_outlined)),
                      title: const Text(
                        'Mark read when the assistant opens a chat',
                      ),
                      subtitle: Text(
                        'When it reads a chat\'s messages (summaries, watches, searches). Off: the assistant reads '
                        'invisibly and chats stay unread.',
                        style: context.text.bodySmall,
                      ),
                      value: s.aiReadOnView,
                      onChanged: ctl.setAiReadOnView,
                    ),
                  ],
                ),
                const _Header('Data on this phone'),
                _Card(
                  children: [
                    ListTile(
                      leading: lead(Icon(
                        Icons.delete_sweep_outlined,
                        color: AppColors.danger,
                      )),
                      title: const Text('Delete all AI conversations'),
                      subtitle: Text(
                        'Your Telegram is not touched',
                        style: context.text.bodySmall,
                      ),
                      onTap: () async {
                        if (!await confirmAction(
                          context,
                          title: 'Delete every AI conversation?',
                          message: 'All chats with the assistant on this phone go. Watches keep running.',
                          action: 'Delete all',
                        )) {
                          return;
                        }
                        await ref
                            .read(chatControllerProvider.notifier)
                            .deleteAll();
                        if (context.mounted)
                          showSnack(context, 'Conversations deleted');
                      },
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: lead(Icon(
                        Icons.wb_twilight_rounded,
                        color: AppColors.danger,
                      )),
                      title: const Text('Delete all briefs'),
                      onTap: () async {
                        if (!await confirmAction(
                          context,
                          title: 'Delete every brief?',
                          message: 'Saved briefs go.',
                          action: 'Delete',
                        )) {
                          return;
                        }
                        await ref.read(briefStoreProvider.notifier).deleteAll();
                        if (context.mounted)
                          showSnack(context, 'Briefs deleted');
                      },
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: lead(Icon(
                        Icons.dashboard_customize_outlined,
                        color: AppColors.danger,
                      )),
                      title: const Text('Empty the Content Canvas'),
                      onTap: () async {
                        if (!await confirmAction(
                          context,
                          title: 'Empty the canvas?',
                          message: 'Every folder and saved item goes. Telegram is not touched.',
                          action: 'Empty',
                        )) {
                          return;
                        }
                        await ref.read(canvasProvider.notifier).clear();
                        if (context.mounted)
                          showSnack(context, 'Canvas emptied');
                      },
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: lead(const Icon(Icons.restart_alt_rounded)),
                      title: const Text('Reset preferences'),
                      subtitle: Text(
                        'Every setting back to its default. Keys, models and instructions stay.',
                        style: context.text.bodySmall,
                      ),
                      onTap: () async {
                        if (!await confirmAction(
                          context,
                          title: 'Reset all preferences?',
                          message: 'Tools, appearance, voice and automation settings go back to their defaults.',
                          action: 'Reset',
                        )) {
                          return;
                        }
                        await ctl.resetPreferences();
                        if (context.mounted)
                          showSnack(context, 'Preferences reset');
                      },
                    ),
                  ],
                ),
                const _Header('Telegram'),
                _Card(
                  children: [
                    ListTile(
                      leading: me == null
                          ? const Icon(Icons.person_outline_rounded)
                          : TgAvatar(
                              userId: me.id,
                              title: '${me.firstName} ${me.lastName}',
                              size: 36,
                            ),
                      title: Text(
                        me == null
                            ? 'Signed in'
                            : '${me.firstName} ${me.lastName}'.trim(),
                      ),
                      subtitle: Text(
                        [
                          if (me != null && me.phoneNumber.isNotEmpty)
                            '+${me.phoneNumber}',
                          if (store.chatsLoaded)
                            '${store.chats.values.where((c) => c.isListed).length} chats',
                        ].join(' · '),
                        style: context.text.bodySmall,
                      ),
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    const _Note(
                      icon: Icons.verified_user_outlined,
                      title: 'Read-only by design',
                      body:
                          'The assistant can list chats and read and search messages. It has no tools to leave, '
                          'delete, mute, archive or edit anything, and reading never marks messages as read.',
                    ),
                    const _Note(
                      icon: Icons.front_hand_outlined,
                      title: 'You approve every message',
                      body: 'Sending, posting or forwarding waits for you to approve it.',
                    ),
                    _Note(
                      icon: Icons.speed_rounded,
                      title: 'Gentle on Telegram',
                      body:
                          'Requests that reach Telegram\'s servers are paced (bursts of ${limiter.capacity}, then about one '
                          'a second), and the app stops completely when Telegram asks it to wait.',
                    ),
                    const Divider(indent: Space.l, endIndent: Space.l),
                    ListTile(
                      leading: lead(Icon(
                        Icons.logout_rounded,
                        color: AppColors.danger,
                      )),
                      title: Text(
                        'Sign out',
                        style: TextStyle(color: AppColors.danger),
                      ),
                      onTap: () => _signOut(context, ref),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
  }

  Future<void> _pickDeviceVoice(BuildContext context, WidgetRef ref) async {
    final voices = await ref.read(speakerProvider).loadDeviceVoices();
    if (!context.mounted) return;
    final current = ref.read(settingsProvider).deviceVoice;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 1,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              title: const Text('System default'),
              trailing: current.isEmpty
                  ? Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            if (voices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Space.xl),
                child: Text('This device didn\'t list any voices.'),
              ),
            for (final v in voices)
              ListTile(
                title: Text(v['name'] ?? ''),
                subtitle: Text(
                  v['locale'] ?? '',
                  style: context.text.bodySmall,
                ),
                trailing: v['name'] == current
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, v['name']),
              ),
          ],
        ),
      ),
    );
    if (picked != null)
      await ref.read(settingsProvider.notifier).setDeviceVoice(picked);
  }

  Future<void> _pickAiVoice(
    BuildContext context,
    WidgetRef ref,
    List<String> known,
  ) async {
    final ctrl = TextEditingController(
      text: ref.read(settingsProvider).aiVoice,
    );
    final voices = known.isNotEmpty
        ? known
        : const [
            'alloy',
            'ash',
            'ballad',
            'coral',
            'echo',
            'fable',
            'nova',
            'onyx',
            'sage',
            'shimmer',
            'verse',
          ];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Voice name, or empty for default',
              ),
            ),
            const SizedBox(height: Space.m),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in voices)
                  ActionChip(
                    label: Text(v),
                    onPressed: () => Navigator.pop(ctx, v),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (picked != null)
      await ref.read(settingsProvider.notifier).setAiVoice(picked);
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.icon,
    required this.title,
    required this.model,
    required this.id,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final ModelInfo? model;
  final String id;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = model;
    return ListTile(
      leading: lead(Icon(icon)),
      title: Text(title),
      subtitle: Text(
        [
          m?.name ?? modelLabel(id),
          AiRouter.nameOf(id),
          if (m != null) m.priceLabel,
        ].join(' · '),
        style: context.text.bodySmall,
        maxLines: 2,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m != null)
            IconButton(
              tooltip: 'Details',
              icon: Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: AppColors.text3,
              ),
              onPressed: () => showModelDetails(context, m),
            ),
          Icon(Icons.chevron_right_rounded, color: AppColors.text3),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.accent, required this.fontSize});
  final Color accent;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Space.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live preview', style: context.text.titleSmall),
        const SizedBox(height: Space.s),
        Text(
          'See chat colour and type changes as you adjust them.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.m),
        Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: accent.withValues(alpha: .45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Maya · online',
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.m,
                    vertical: Space.s,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(Radii.l),
                  ),
                  child: Text(
                    'This is how messages will read.',
                    style: TextStyle(fontSize: fontSize, color: AppColors.text),
                  ),
                ),
              ),
              const SizedBox(height: Space.s),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.s),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.s),
                ),
                child: Text(
                  'final theme = "$fontSize pt";',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: accent,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.note});
  final String text;

  /// A hint beside the title, e.g. "Any one is enough".
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, Space.xs, Space.xs),
    child: Row(
      children: [
        Text(text.toUpperCase(), style: context.text.labelSmall),
        if (note != null) ...[
          const SizedBox(width: Space.s),
          Flexible(
            child: Text(
              '· $note',
              style: context.text.labelSmall?.copyWith(color: AppColors.text2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    ),
  );
}

/// Switch rows with a divider between each: (icon, title, subtitle, value, onChanged).
List<Widget> _dividedSwitches(
  BuildContext context,
  List<(IconData, String, String, bool, ValueChanged<bool>)> rows,
) => [
  for (final (i, (icon, title, subtitle, value, onChanged)) in rows.indexed) ...[
    if (i > 0) const Divider(indent: 56),
    SwitchListTile(
      secondary: lead(Icon(icon)),
      title: Text(title),
      subtitle: Text(subtitle, style: context.text.bodySmall),
      value: value,
      onChanged: onChanged,
    ),
  ],
];

/// The parts of AI & models, one tab each.
enum AiTab {
  chat('Chat'),
  media('Images & video'),
  voice('Voice'),
  decisions('Decisions');

  const AiTab(this.label);
  final String label;
}

/// A whole feature on or off, at the top of its tab.
class _FeatureSwitch extends StatelessWidget {
  const _FeatureSwitch({
    required this.icon,
    required this.title,
    required this.on,
    required this.off,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String on;
  final String off;
  final bool value;
  final ValueChanged<bool> onChanged;

  // A row like every other setting: the page's own card, no colour of its
  // own; what's off just reads as off.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.m),
    child: _Card(
      children: [
        SwitchListTile(
          secondary: lead(Icon(icon, color: value ? AppColors.text : AppColors.text3)),
          title: Text(title),
          subtitle: Text(value ? on : off, style: context.text.bodySmall),
          value: value,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(children: children),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.text2),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall),
              const SizedBox(height: 2),
              Text(body, style: context.text.bodySmall?.copyWith(height: 1.45)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _KeyTile extends StatefulWidget {
  const _KeyTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onSave,
    required this.verify,
    required this.help,
    this.secret = true,
    this.hint = 'Paste your key',
    this.helpLabel = 'Get a key',
  });

  /// Hidden while typed (keys); an address isn't.
  final bool secret;
  final String hint;
  final String helpLabel;
  final String title;
  final String subtitle;
  final String value;
  final Future<void> Function(String) onSave;

  /// Null when the key works, or what went wrong.
  final Future<String?> Function(String) verify;
  final Uri help;

  @override
  State<_KeyTile> createState() => _KeyTileState();
}

class _KeyTileState extends State<_KeyTile> {
  late final _ctrl = TextEditingController(text: widget.value);
  late bool _obscure = widget.secret;
  bool _checking = false;
  String? _status;
  bool _ok = false;

  @override
  void didUpdateWidget(_KeyTile old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value)
      _ctrl.text = widget.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_checking) return;
    final key = _ctrl.text.trim();
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      await widget.onSave(key);
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _ok = false;
          _status = 'Could not save this setting. Try again.';
        });
      }
      return;
    }
    if (!mounted) return;
    if (key.isEmpty) {
      setState(() {
        _checking = false;
        _ok = true;
        _status = 'Removed';
      });
      return;
    }
    final error = await widget.verify(key);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _ok = error == null;
      _status = error == null
          ? 'Key saved and working'
          : 'Saved, but the check failed: $error';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: context.text.titleSmall),
                    Text(widget.subtitle, style: context.text.bodySmall),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  widget.help,
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(widget.helpLabel),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() => _status = null),
            onSubmitted: (_) => _save(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_ctrl.text.isNotEmpty)
                    IconButton(
                      tooltip: widget.secret ? 'Remove API key' : 'Clear',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: _checking ? null : () {
                        setState(() => _ctrl.clear());
                        _save();
                      },
                    ),
                  if (widget.secret)
                  IconButton(
                    tooltip: _obscure ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  IconButton(
                    tooltip: 'Save',
                    icon: _checking
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    onPressed: _checking ? null : _save,
                  ),
                ],
              ),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: Space.s),
            Text(
              _status!,
              style: context.text.bodySmall?.copyWith(
                color: _ok ? AppColors.success : AppColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The user's standing instructions for the assistant.
class _InstructionsField extends ConsumerStatefulWidget {
  const _InstructionsField();

  @override
  ConsumerState<_InstructionsField> createState() => _InstructionsFieldState();
}

class _InstructionsFieldState extends ConsumerState<_InstructionsField> {
  late final _ctrl = TextEditingController(
    text: ref.read(settingsProvider).customInstructions,
  );
  bool _dirty = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(settingsProvider).customInstructions;
    if (!_dirty && _ctrl.text != saved) _ctrl.text = saved;
    return Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Instructions', style: context.text.titleSmall),
          const SizedBox(height: 2),
          Text(
            'Always followed, in every conversation and watch.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.m),
          TextField(
            controller: _ctrl,
            minLines: 3,
            maxLines: 10,
            onChanged: (_) => setState(() => _dirty = true),
            decoration: const InputDecoration(
              hintText: 'e.g. Call me Dag. Answer in short bullet points. Never message my boss without asking.',
            ),
          ),
          if (_dirty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .setCustomInstructions(_ctrl.text.trim());
                  if (mounted) setState(() => _dirty = false);
                  if (context.mounted) showSnack(context, 'Instructions saved');
                },
                child: const Text('Save'),
              ),
            ),
        ],
      ),
    );
  }
}

// The settings pages' own building blocks, for pages kept in other files
// (Decisions, MCP & Skills) so they look the same.
typedef SettingsCard = _Card;
typedef SettingsHeader = _Header;
typedef SettingsKeyTile = _KeyTile;
typedef SettingsFeatureSwitch = _FeatureSwitch;

/// One drawer section's items as indented rows under its switch: icon,
/// name and a small switch each, joined by a guide line on the left.
class _DrawerItemChips extends StatelessWidget {
  const _DrawerItemChips({required this.items, required this.settings, required this.onChanged});
  final List<(String, String)> items;
  final AppSettings settings;
  final void Function(String key, bool shown) onChanged;

  static const _icons = <String, IconData>{
    'chats.dms': Icons.person_outline_rounded,
    'chats.bots': Icons.smart_toy_outlined,
    'chats.groups': Icons.groups_outlined,
    'chats.channels': Icons.campaign_outlined,
    'chats.contacts': Icons.contacts_outlined,
    'chats.archived': Icons.archive_outlined,
    'chats.calls': Icons.call_outlined,
    'tools.files': Icons.folder_copy_outlined,
    'tools.brief': Icons.wb_twilight_rounded,
    'tools.canvas': Icons.dashboard_customize_outlined,
    'tools.search': Icons.manage_search_rounded,
    'tools.browser': Icons.public_rounded,
    'tools.pc': Icons.desktop_windows_outlined,
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(36, 0, Space.s, Space.s),
    child: Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.line, width: 2))),
      child: Column(
        children: [
          for (final (key, label) in items)
            InkWell(
              borderRadius: BorderRadius.circular(Radii.m),
              onTap: () => onChanged(key, !settings.drawerShows(key)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 2, 0, 2),
                child: Row(
                  children: [
                    Icon(_icons[key] ?? Icons.circle_outlined, size: 19, color: settings.drawerShows(key) ? AppColors.text2 : AppColors.text3),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Text(
                        label,
                        style: context.text.bodyMedium?.copyWith(color: settings.drawerShows(key) ? AppColors.text : AppColors.text3),
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(value: settings.drawerShows(key), onChanged: (v) => onChanged(key, v)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A drawer section in Appearance: its switch, and its items folded away
/// until the row is tapped.
class _DrawerSectionTile extends StatefulWidget {
  const _DrawerSectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.items,
    required this.settings,
    required this.onItem,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final List<(String, String)> items;
  final AppSettings settings;
  final void Function(String key, bool shown) onItem;

  @override
  State<_DrawerSectionTile> createState() => _DrawerSectionTileState();
}

class _DrawerSectionTileState extends State<_DrawerSectionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final shown = widget.items.where((i) => widget.settings.drawerShows(i.$1)).length;
    final all = shown == widget.items.length;
    return Column(
      children: [
        ListTile(
          leading: lead(Icon(widget.icon)),
          title: Text(widget.title),
          subtitle: Text(
            !widget.value ? 'Hidden from the drawer' : (all ? widget.subtitle : '$shown of ${widget.items.length} shown'),
            style: context.text.bodySmall,
          ),
          onTap: () => setState(() => _open = !_open),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more_rounded, color: AppColors.text3),
              ),
              Switch(value: widget.value, onChanged: widget.onChanged),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? IgnorePointer(
                  // Items can't be picked while the whole section is off.
                  ignoring: !widget.value,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: widget.value ? 1 : 0.45,
                    child: _DrawerItemChips(items: widget.items, settings: widget.settings, onChanged: widget.onItem),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
