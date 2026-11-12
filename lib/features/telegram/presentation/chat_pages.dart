import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/message_content.dart';
import '../data/telegram_store.dart';
import 'chat_actions.dart' show confirmAction;
import 'chat_background.dart';
import 'message_tile.dart';
import 'scheduled_screen.dart' show showScheduledMessageSheet;
import 'tg_avatar.dart';

/// Whether the account may pin and unpin messages in [c].
bool canPinIn(TelegramStore store, ChatInfo c) {
  if (c.type is td.ChatTypePrivate || c.type is td.ChatTypeSecret) return true;
  final channel = c.type is td.ChatTypeSupergroup && (c.type as td.ChatTypeSupergroup).isChannel;
  return switch (store.myStatus(c)) {
    td.ChatMemberStatusCreator() => true,
    td.ChatMemberStatusAdministrator(:final rights) => channel ? rights.canEditMessages : rights.canPinMessages,
    _ => false,
  };
}

/// The chat's pinned messages, newest first.
Future<List<td.Message>> loadPinned(TelegramClient client, int chatId) async {
  final out = <td.Message>[];
  var from = 0;
  for (var page = 0; page < 5; page++) {
    final r = await client.send<td.FoundChatMessages>(
      td.SearchChatMessages(
        chatId: chatId,
        query: '',
        fromMessageId: from,
        offset: 0,
        limit: 100,
        filter: const td.SearchMessagesFilterPinned(),
        topicId: null,
      ),
      limited: true,
    );
    for (final m in r.messages) {
      if (out.every((x) => x.id != m.id)) out.add(m);
    }
    if (r.nextFromMessageId == 0 || r.messages.isEmpty) break;
    from = r.nextFromMessageId;
  }
  out.sort((a, b) => b.id.compareTo(a.id));
  return out;
}

/// A small frosted label floating over the chat: a day, "Discussion
/// started", "Scheduled for November 13".
class ChatPill extends StatelessWidget {
  const ChatPill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.m),
    child: Center(
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
      ),
    ),
  );
}

/// A day as Telegram heads it: "November 12", with the year when it isn't
/// this one.
String dayLabel(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year ? DateFormat('MMMM d').format(d) : DateFormat('MMMM d, y').format(d);
}

bool _sameDay(int a, int b) {
  final x = DateTime.fromMillisecondsSinceEpoch(a * 1000);
  final y = DateTime.fromMillisecondsSinceEpoch(b * 1000);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// The floating header of a page that belongs to a chat: back, and a pill
/// with the chat's picture and what the page is.
class ChatPageHeader extends StatelessWidget {
  const ChatPageHeader({super.key, required this.chatId, required this.chatTitle, required this.title, this.center = false});
  final int chatId;
  final String chatTitle;
  final String title;

  /// The pill sits in the middle (the comments page), not stretched.
  final bool center;

  @override
  Widget build(BuildContext context) {
    final pill = Glass(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, Space.l + 2, 4),
        child: Row(
          mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
          children: [
            TgAvatar(chatId: chatId, title: chatTitle, size: 40),
            const SizedBox(width: Space.s + 2),
            Flexible(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
            ),
          ],
        ),
      ),
    );
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
        child: Row(
          children: [
            GlassIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: Space.s),
            if (center)
              Expanded(
                child: Align(alignment: Alignment.center, child: pill),
              )
            else
              Expanded(child: pill),
            if (center) const SizedBox(width: 44 + Space.s),
          ],
        ),
      ),
    );
  }
}

/// The bar under a chat's header with its pinned messages, newest first.
/// Tapping goes to the one shown and moves on to the one before it; the
/// list button opens them all.
class PinnedMessageBar extends ConsumerWidget {
  const PinnedMessageBar({
    super.key,
    required this.pins,
    required this.index,
    required this.onTap,
    required this.onList,
  });
  final List<td.Message> pins;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = index.clamp(0, pins.length - 1);
    final m = pins[i];
    final g = gistOf(m.content);
    final text = (g.text.isNotEmpty ? g.text : (g.detail ?? g.kind)).replaceAll('\n', ' ');
    final mini = switch (m.content) {
      td.MessagePhoto(:final photo) => photo.minithumbnail,
      td.MessageVideo(:final video) => video.minithumbnail,
      td.MessageAnimation(:final animation) => animation.minithumbnail,
      td.MessageDocument(:final document) => document.minithumbnail,
      _ => null,
    };
    // Up to four segments, as Telegram draws them: the newest at the bottom.
    final segments = pins.length.clamp(1, 4);
    final active = segments - 1 - i.clamp(0, segments - 1);
    final title = pins.length > 1 && i > 0 ? 'Pinned Message #${pins.length - i}' : 'Pinned Message';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, 6, Space.m, 0),
      child: Glass(
        radius: Radii.l,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.l),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 4, 2, 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 2.5,
                    height: 30,
                    child: Column(
                      children: [
                        for (var s = 0; s < segments; s++) ...[
                          if (s > 0) const SizedBox(height: 2),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: s == active ? AppColors.accent : AppColors.accent.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  if (mini != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.memory(
                        base64Decode(mini.data),
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                    const SizedBox(width: Space.s),
                  ],
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(m.id),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.accent),
                          ),
                          Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, height: 1.25, color: AppColors.text2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // A plain InkWell: IconButton keeps a 48 px tap target,
                  // which made the bar tall.
                  Tooltip(
                    message: 'All pinned messages',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onList,
                      child: SizedBox.square(
                        dimension: 32,
                        child: Icon(Icons.format_list_bulleted_rounded, size: 19, color: AppColors.text2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every pinned message of a chat, newest at the bottom, each with a way
/// back to it in the chat. Pops with the id of the message to go to.
class ChatPinnedScreen extends ConsumerStatefulWidget {
  const ChatPinnedScreen({super.key, required this.chatId, this.initial});
  final int chatId;

  /// Pins already loaded by the chat, shown while the list refreshes.
  final List<td.Message>? initial;

  @override
  ConsumerState<ChatPinnedScreen> createState() => _ChatPinnedScreenState();
}

class _ChatPinnedScreenState extends ConsumerState<ChatPinnedScreen> {
  List<td.Message>? _pins;
  String? _error;
  StreamSubscription<td.TdObject>? _updates;
  Timer? _debounce;
  bool _unpinning = false;

  @override
  void initState() {
    super.initState();
    _pins = widget.initial == null ? null : [...widget.initial!];
    _load();
    _updates = ref.read(telegramClientProvider).updates.listen((u) {
      if (!mounted) return;
      switch (u) {
        case td.UpdateMessageIsPinned(:final chatId) when chatId == widget.chatId:
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), _load);
        case td.UpdateMessageInteractionInfo(:final chatId, :final messageId, :final interactionInfo)
            when chatId == widget.chatId:
          final i = _pins?.indexWhere((m) => m.id == messageId) ?? -1;
          if (i >= 0) setState(() => _pins![i] = _pins![i].copyWith(interactionInfo: interactionInfo));
        case td.UpdateMessageContent(:final chatId, :final messageId, :final newContent) when chatId == widget.chatId:
          final i = _pins?.indexWhere((m) => m.id == messageId) ?? -1;
          if (i >= 0) setState(() => _pins![i] = _pins![i].copyWith(content: newContent));
        case td.UpdateDeleteMessages(:final chatId, :final messageIds, :final isPermanent)
            when chatId == widget.chatId && isPermanent:
          setState(() => _pins?.removeWhere((m) => messageIds.contains(m.id)));
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pins = await loadPinned(ref.read(telegramClientProvider), widget.chatId);
      if (mounted) setState(() => _pins = pins);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _unpinAll() async {
    final n = _pins?.length ?? 0;
    if (!await confirmAction(
      context,
      title: 'Unpin all messages?',
      message: 'All $n pinned message${n == 1 ? '' : 's'} will be unpinned for everyone in this chat.',
      action: 'Unpin all',
    )) {
      return;
    }
    setState(() => _unpinning = true);
    try {
      await ref.read(telegramClientProvider).send<td.Ok>(td.UnpinAllChatMessages(chatId: widget.chatId), limited: true);
      if (mounted) {
        showSnack(context, 'All messages unpinned', icon: Icons.push_pin_outlined);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t unpin: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _unpinning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final chat = store.chat(widget.chatId);
    final kind = chat == null ? ChatKind.private : store.kindOf(chat);
    final chatTitle = kind == ChatKind.saved ? 'Saved Messages' : (chat?.title ?? 'Chat');
    final pins = _pins;
    final n = pins?.length ?? 0;
    final top = MediaQuery.paddingOf(context).top + 64;
    final canPin = chat != null && canPinIn(store, chat);

    Widget body;
    if (pins == null) {
      body = Center(
        child: _error != null
            ? Text(_error!, style: context.text.bodySmall)
            : const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (pins.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.push_pin_outlined, size: 44, color: AppColors.text3),
            const SizedBox(height: Space.m),
            Text('No pinned messages', style: context.text.bodySmall),
          ],
        ),
      );
    } else {
      body = ListView.builder(
        reverse: true,
        // A reversed list keeps padding where it says: the top clears the
        // floating header.
        padding: EdgeInsets.fromLTRB(Space.m, top + Space.l, Space.m, Space.m),
        itemCount: pins.length,
        itemBuilder: (context, i) {
          final m = pins[i];
          final older = i + 1 < pins.length ? pins[i + 1] : null;
          final newDay = older == null || !_sameDay(older.date, m.date);
          return Column(
            key: ValueKey(m.id),
            children: [
              if (newDay) ChatPill(dayLabel(DateTime.fromMillisecondsSinceEpoch(m.date * 1000))),
              MessageTile(
                message: m,
                kind: kind,
                chatTitle: chatTitle,
                findMessage: (id) => pins.where((x) => x.id == id).firstOrNull,
                lastReadOutbox: chat?.lastReadOutboxMessageId ?? 0,
                onGoTo: () => Navigator.of(context).pop(m.id),
              ),
            ],
          );
        },
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: ChatBackdrop(background: chat?.background, child: body)),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ChatPageHeader(
                    chatId: widget.chatId,
                    chatTitle: chatTitle,
                    title: pins == null ? 'Pinned Messages' : '$n Pinned Message${n == 1 ? '' : 's'}',
                    center: true,
                  ),
                ),
              ],
            ),
          ),
          if (canPin && n > 0)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
                child: Glass(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _unpinning ? null : _unpinAll,
                      child: SizedBox(
                        height: 50,
                        child: Center(
                          child: _unpinning
                              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(
                                  n == 1 ? 'Unpin Message' : 'Unpin All Messages',
                                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.text2),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A chat's scheduled messages laid out like the chat itself, the one going
/// out soonest at the bottom, the furthest off at the top.
class ChatScheduledScreen extends ConsumerStatefulWidget {
  const ChatScheduledScreen({super.key, required this.chatId});
  final int chatId;

  @override
  ConsumerState<ChatScheduledScreen> createState() => _ChatScheduledScreenState();
}

class _ChatScheduledScreenState extends ConsumerState<ChatScheduledScreen> {
  List<td.Message>? _messages;
  String? _error;
  StreamSubscription<td.TdObject>? _updates;
  Timer? _debounce;

  static const _never = 1 << 40;

  static int _sendAt(td.Message m) => switch (m.schedulingState) {
    td.MessageSchedulingStateSendAtDate(:final sendDate) => sendDate,
    td.MessageSchedulingStateSendWhenVideoProcessed(:final sendDate) => sendDate,
    _ => _never,
  };

  @override
  void initState() {
    super.initState();
    _load();
    _updates = ref.read(telegramClientProvider).updates.listen((u) {
      if (!mounted) return;
      final touched = switch (u) {
        td.UpdateNewMessage(:final message) => message.chatId == widget.chatId && message.schedulingState != null,
        td.UpdateDeleteMessages(:final chatId) => chatId == widget.chatId,
        td.UpdateMessageContent(:final chatId) => chatId == widget.chatId,
        td.UpdateMessageEdited(:final chatId) => chatId == widget.chatId,
        td.UpdateChatHasScheduledMessages(:final chatId) => chatId == widget.chatId,
        _ => false,
      };
      if (touched) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), _load);
      }
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref
          .read(telegramClientProvider)
          .send<td.Messages>(td.GetChatScheduledMessages(chatId: widget.chatId), limited: true);
      final list = r.messages.whereType<td.Message>().toList()
        ..sort((a, b) {
          final c = _sendAt(a).compareTo(_sendAt(b));
          return c != 0 ? c : a.id.compareTo(b.id);
        });
      if (mounted) setState(() => _messages = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  static String _bucket(td.Message m) {
    final at = _sendAt(m);
    if (at >= _never) return 'Scheduled for when online';
    final d = DateTime.fromMillisecondsSinceEpoch(at * 1000);
    final now = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return 'Scheduled for today';
    if (days == 1) return 'Scheduled for tomorrow';
    return 'Scheduled for ${dayLabel(d)}';
  }

  static String _until(int at) {
    final diff = DateTime.fromMillisecondsSinceEpoch(at * 1000).difference(DateTime.now());
    if (diff.isNegative || diff.inMinutes < 1) return 'any moment';
    if (diff.inDays > 0) return 'in ${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'in ${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final chat = store.chat(widget.chatId);
    final kind = chat == null ? ChatKind.private : store.kindOf(chat);
    final chatTitle = kind == ChatKind.saved ? 'Saved Messages' : (chat?.title ?? 'Chat');
    final list = _messages;
    final top = MediaQuery.paddingOf(context).top + 64;

    Widget body;
    if (list == null) {
      body = Center(
        child: _error != null
            ? Text(_error!, style: context.text.bodySmall)
            : const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (list.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_send_outlined, size: 44, color: AppColors.text3),
            const SizedBox(height: Space.m),
            Text('No scheduled messages', style: context.text.bodySmall),
          ],
        ),
      );
    } else {
      // Soonest first, drawn from the bottom up: what goes out next sits
      // right above the bottom bar.
      body = ListView.builder(
        reverse: true,
        // A reversed list keeps padding where it says: the top clears the
        // floating header.
        padding: EdgeInsets.fromLTRB(Space.m, top + Space.l, Space.m, Space.m),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final m = list[i];
          final later = i + 1 < list.length ? list[i + 1] : null;
          final header = later == null || _bucket(later) != _bucket(m);
          return Column(
            key: ValueKey(m.id),
            children: [
              if (header) ChatPill(_bucket(m)),
              MessageTile(
                message: m,
                kind: kind,
                chatTitle: chatTitle,
                findMessage: (id) => list.where((x) => x.id == id).firstOrNull,
                onActions: () => showScheduledMessageSheet(context, ref, m, onChanged: _load),
              ),
            ],
          );
        },
      );
    }

    final next = list?.where((m) => _sendAt(m) < _never).firstOrNull;
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: ChatBackdrop(background: chat?.background, child: body)),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ChatPageHeader(chatId: widget.chatId, chatTitle: chatTitle, title: 'Scheduled Messages'),
                ),
              ],
            ),
          ),
          if (list != null && list.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
                child: Glass(
                  child: SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        const SizedBox(width: Space.l),
                        Icon(Icons.schedule_send_outlined, size: 20, color: AppColors.text2),
                        const SizedBox(width: Space.s + 2),
                        Expanded(
                          child: Text(
                            [
                              '${list.length} scheduled',
                              if (next != null) 'next ${_until(_sendAt(next))}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, color: AppColors.text2),
                          ),
                        ),
                        Text('Hold a message for options', style: TextStyle(fontSize: 12, color: AppColors.text3)),
                        const SizedBox(width: Space.l),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
