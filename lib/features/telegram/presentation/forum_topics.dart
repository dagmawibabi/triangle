import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/file_loader.dart';
import '../data/message_content.dart';
import '../data/telegram_store.dart';
import '../../../core/widgets/swipe_back.dart';
import 'chat_list_screen.dart' show allChats, shortTime;
import 'tg_avatar.dart';
import 'chat_view_screen.dart';
import '../../../infrastructure/telegram/td_compat.dart';

/// A forum group's topics, pinned first, then by latest activity.
class ForumTopicsList extends ConsumerStatefulWidget {
  const ForumTopicsList({super.key, required this.chatId, this.topPadding = 0, this.showRail = true});
  final int chatId;
  final double topPadding;

  /// The column of other chats down the left, as Telegram shows a forum.
  final bool showRail;

  @override
  ConsumerState<ForumTopicsList> createState() => _ForumTopicsListState();
}

class _ForumTopicsListState extends ConsumerState<ForumTopicsList> {
  final List<td.ForumTopic> _topics = [];
  bool _loading = false;
  bool _end = false;
  String? _error;
  (int, int, int) _offset = (0, 0, 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _end) return;
    setState(() => _loading = true);
    try {
      final r = await ref
          .read(telegramClientProvider)
          .send<td.ForumTopics>(
            td.GetForumTopics(
              chatId: widget.chatId,
              query: '',
              offsetDate: _offset.$1,
              offsetMessageId: _offset.$2,
              offsetForumTopicId: _offset.$3,
              limit: 50,
            ),
            limited: true,
          );
      _topics.addAll(r.topics.where((t) => _topics.every((x) => x.info.messageThreadId != t.info.messageThreadId)));
      _offset = (r.nextOffsetDate, r.nextOffsetMessageId, r.nextOffsetForumTopicId);
      if (r.topics.isEmpty || r.nextOffsetDate == 0) _end = true;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final rail = widget.showRail ? _ChatRail(currentChatId: widget.chatId, topPadding: widget.topPadding) : null;
    Widget list;
    if (_topics.isEmpty) {
      list = Center(
        child: _loading
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_error ?? 'No topics', style: context.text.bodySmall),
      );
    } else {
      final sorted = [..._topics]..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0);
      });
      final chat = store.chat(widget.chatId);
      list = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) _load();
          return false;
        },
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(0, widget.topPadding, 0, MediaQuery.paddingOf(context).bottom + Space.x4),
          itemCount: sorted.length,
          itemBuilder: (context, i) => _TopicRow(
            topic: sorted[i],
            chatId: widget.chatId,
            lastReadOutbox: chat?.lastReadOutboxMessageId ?? 0,
            divider: i < sorted.length - 1,
          ),
        ),
      );
    }
    if (rail == null) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rail,
        Expanded(child: list),
      ],
    );
  }
}

/// One topic as Telegram lists a forum: its icon beside the name, the
/// time (in a pin pill when pinned), then who wrote last and what, with
/// the unread count.
class _TopicRow extends ConsumerWidget {
  const _TopicRow({required this.topic, required this.chatId, required this.lastReadOutbox, required this.divider});
  final td.ForumTopic topic;
  final int chatId;
  final int lastReadOutbox;
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final t = topic;
    final last = t.lastMessage;
    String who = '';
    String body = '';
    var media = false;
    if (last != null) {
      final g = gistOf(last.content);
      who = last.isOutgoing ? 'You: ' : '${store.senderName(last.senderId).split(' ').first}: ';
      body = (g.text.isNotEmpty ? g.text : (g.detail ?? g.kind)).replaceAll('\n', ' ');
      media = g.kind != 'text' || g.text.startsWith('http');
    }
    final unread = t.unreadCount > 0;
    final muted = t.notificationSettings.muteFor > 0;
    final read = last != null && last.isOutgoing && last.id <= t.lastReadOutboxMessageId;
    final mediaColor = AppColors.isLight ? AppColors.tint : Color.lerp(AppColors.tint, const Color(0xFF8FA8FF), 0.55)!;
    final timeColor = unread && !muted ? AppColors.accent : AppColors.text3;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatViewScreen(
            chatId: chatId,
            threadId: t.info.isGeneral ? null : t.info.messageThreadId,
            generalTopic: t.info.isGeneral,
            threadTitle: t.info.name,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.m),
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 10, Space.l, 10),
          decoration: BoxDecoration(
            border: divider ? Border(bottom: BorderSide(color: AppColors.line.withValues(alpha: 0.7), width: 0.6)) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TopicIcon(info: t.info, size: 24),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      t.info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: AppColors.text),
                    ),
                  ),
                  if (t.info.isClosed) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.lock_rounded, size: 14, color: AppColors.text3),
                  ],
                  if (muted) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.volume_off_rounded, size: 14, color: AppColors.text3),
                  ],
                  const Spacer(),
                  if (last != null && last.isOutgoing) ...[
                    const SizedBox(width: Space.s),
                    Icon(read ? Icons.done_all_rounded : Icons.done_rounded, size: 17, color: read ? AppColors.accent : AppColors.text3),
                  ],
                  if (last != null) ...[
                    const SizedBox(width: 4),
                    t.isPinned
                        ? Container(
                            padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface3.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.rotate(angle: 0.6, child: Icon(Icons.push_pin_rounded, size: 12, color: AppColors.text3)),
                                const SizedBox(width: 3),
                                Text(shortTime(last.date), style: TextStyle(fontSize: 12.5, color: timeColor)),
                              ],
                            ),
                          )
                        : Text(shortTime(last.date), style: TextStyle(fontSize: 13, color: timeColor)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: who, style: TextStyle(color: AppColors.text)),
                          TextSpan(text: body, style: TextStyle(color: media ? mediaColor : AppColors.text2)),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, height: 1.3),
                    ),
                  ),
                  if (t.unreadMentionCount > 0) ...[
                    const SizedBox(width: Space.xs),
                    _Count('@', muted: false),
                  ],
                  if (unread) ...[
                    const SizedBox(width: Space.xs),
                    _Count(NumberFormat.compact().format(t.unreadCount), muted: muted),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.text, {required this.muted});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final bg = muted ? AppColors.text3.withValues(alpha: 0.45) : AppColors.accent;
    final fg = muted ? AppColors.text : (bg.computeLuminance() > 0.5 ? const Color(0xFF0B0B0D) : Colors.white);
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Telegram's side rail in a forum: the other chats as a column of faces,
/// the open one marked with a bar, so you can hop between them without
/// going back to the list.
class _ChatRail extends ConsumerWidget {
  const _ChatRail({required this.currentChatId, required this.topPadding});
  final int currentChatId;
  final double topPadding;

  static const width = 72.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final chats = allChats(store).take(150).toList();
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        border: Border(right: BorderSide(color: AppColors.line.withValues(alpha: 0.6), width: 0.6)),
      ),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(0, topPadding, 0, MediaQuery.paddingOf(context).bottom + Space.x4),
        itemCount: chats.length,
        itemBuilder: (context, i) {
          final c = chats[i];
          final on = c.id == currentChatId;
          final kind = store.kindOf(c);
          return Tooltip(
            message: kind == ChatKind.saved ? 'Saved Messages' : c.title,
            child: InkWell(
              onTap: on
                  ? null
                  : () => Navigator.of(context).pushReplacement(
                      InstantPageRoute<void>(builder: (_) => ChatViewScreen(chatId: c.id)),
                    ),
              child: SizedBox(
                height: 68,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      left: 0,
                      top: on ? 12 : 30,
                      bottom: on ? 12 : 30,
                      width: on ? 4 : 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(on ? 18 : 30),
                        border: Border.all(color: on ? AppColors.accent.withValues(alpha: 0.7) : Colors.transparent, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(on ? 14 : 28),
                        child: kind == ChatKind.saved
                            ? const SavedAvatar(size: 50)
                            : TgAvatar(chatId: c.id, title: c.title, size: 50),
                      ),
                    ),
                    if (c.hasUnread)
                      Positioned(
                        right: 6,
                        bottom: 8,
                        child: _Count(
                          c.unreadCount > 0 ? NumberFormat.compact().format(c.unreadCount) : '',
                          muted: c.isMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Custom-emoji stickers by id, fetched once for the session.
final _emojiStickers = <int, td.Sticker>{};
final _emojiLoads = <int, Future<void>>{};

/// A topic's icon: its custom emoji as a picture when TDLib has a still
/// image of it, the plain emoji it stands for otherwise, and Telegram's
/// coloured initial for topics without one.
class TopicIcon extends ConsumerStatefulWidget {
  const TopicIcon({super.key, required this.info, this.size = 44});
  final td.ForumTopicInfo info;
  final double size;

  @override
  ConsumerState<TopicIcon> createState() => _TopicIconState();
}

class _TopicIconState extends ConsumerState<TopicIcon> {
  String? _path;

  int get _id => widget.info.icon.customEmojiId;

  @override
  void initState() {
    super.initState();
    if (_id != 0) _load();
  }

  Future<void> _load() async {
    final client = ref.read(telegramClientProvider);
    if (!_emojiStickers.containsKey(_id)) {
      await (_emojiLoads[_id] ??= () async {
        try {
          final r = await client.send<td.Stickers>(td.GetCustomEmojiStickers(customEmojiIds: [_id]), limited: true);
          for (final s in r.stickers) {
            if (s.fullType case td.StickerFullTypeCustomEmoji(:final customEmojiId)) _emojiStickers[customEmojiId] = s;
          }
          if (r.stickers.length == 1) _emojiStickers[_id] = r.stickers.single;
        } catch (_) {}
      }());
    }
    final s = _emojiStickers[_id];
    if (s == null || !mounted) {
      if (mounted) setState(() {});
      return;
    }
    // A still picture: the sticker itself when it is WebP, or its thumbnail.
    final thumb = s.thumbnail;
    final file = s.format is td.StickerFormatWebp
        ? s.sticker
        : (thumb != null && (thumb.format is td.ThumbnailFormatWebp || thumb.format is td.ThumbnailFormatPng || thumb.format is td.ThumbnailFormatJpeg)
              ? thumb.file
              : null);
    if (file != null) {
      final p = await ref.read(fileLoaderProvider).download(file, priority: 4);
      if (mounted && p != null) setState(() => _path = p);
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final size = widget.size;
    final color = Color(0xFF000000 | info.icon.color);
    if (_path != null) {
      return SizedBox.square(dimension: size, child: Padding(padding: EdgeInsets.all(size * 0.08), child: Image.file(File(_path!))));
    }
    final emoji = _id == 0 ? null : _emojiStickers[_id]?.emoji;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (info.isGeneral ? AppColors.text3 : color).withValues(alpha: emoji == null ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: info.isGeneral
          ? Icon(Icons.tag_rounded, color: AppColors.text2, size: size * 0.5)
          : emoji != null && emoji.isNotEmpty
          ? Text(emoji, style: TextStyle(fontSize: size * 0.5))
          : Text(
              info.name.characters.first.toUpperCase(),
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.4),
            ),
    );
  }
}
