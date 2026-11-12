import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../chat/data/chat_controller.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/presentation/widgets/post_viewer.dart';
import '../../media/audio_center.dart';
import '../../settings/data/settings.dart';
import '../data/file_loader.dart';
import '../data/message_content.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'chat_list_screen.dart' show clockTime;
import 'chat_view_screen.dart' show ChatViewScreen, openComments;
import 'media_viewer.dart';
import 'expression_panel.dart' show StickerImage;
import 'formatted_text.dart';
import 'link_preview_card.dart';
import 'content_canvas_screen.dart' show saveToCanvas;
import 'forward_sheet.dart';
import 'poll_view.dart';
import 'rich_message_view.dart';
import 'stars_sheet.dart';
import 'translate_sheet.dart';
import 'td_image.dart';
import 'tg_avatar.dart';

const quickReactions = ['👍', '❤️', '🔥', '😂', '😮', '😢', '🙏', '👏'];

PostSnapshot snapshotOf(td.Message m, String chatTitle, String? sender) {
  final g = gistOf(m.content);
  return PostSnapshot(
    chatId: m.chatId,
    messageId: m.id,
    chatTitle: chatTitle,
    date: DateTime.fromMillisecondsSinceEpoch(m.date * 1000),
    text: g.text.isNotEmpty ? g.text : (g.detail ?? ''),
    sender: sender,
    kind: g.kind,
  );
}

/// Who a forwarded message originally came from.
String originName(td.MessageOrigin o, TelegramStore store) => switch (o) {
  td.MessageOriginUser(:final senderUserId) => store.userName(senderUserId),
  td.MessageOriginHiddenUser(:final senderName) => senderName,
  td.MessageOriginChat(:final senderChatId, :final authorSignature) => [
    store.chat(senderChatId)?.title ?? 'a group',
    if (authorSignature.isNotEmpty) authorSignature,
  ].join(' · '),
  td.MessageOriginChannel(:final chatId, :final authorSignature) => [
    store.chat(chatId)?.title ?? 'a channel',
    if (authorSignature.isNotEmpty) authorSignature,
  ].join(' · '),
};

int? originChatId(td.MessageOrigin o) => switch (o) {
  td.MessageOriginChannel(:final chatId) => chatId,
  td.MessageOriginChat(:final senderChatId) => senderChatId,
  _ => null,
};

/// One message, styled for the kind of chat it is in.
class MessageTile extends ConsumerWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.kind,
    required this.chatTitle,
    this.grouped = false,
    this.findMessage,
    this.onJumpTo,
    this.onReply,
    this.playlist,
    this.lastReadOutbox = 0,
    this.inComments = false,
    this.onSelect,
    this.selecting = false,
    this.selected = false,
    this.album = const [],
    this.onActions,
    this.onGoTo,
  });

  /// Shows a round arrow beside the message that takes you to it in its
  /// chat (the pinned messages list).
  final VoidCallback? onGoTo;

  /// Replaces the long-press menu (a scheduled message has its own).
  final VoidCallback? onActions;

  /// When [message] is part of an album: every message of it, oldest
  /// first, shown together as one post. [message] is the one with the
  /// caption.
  final List<td.Message> album;

  /// Scrolls the chat to a message (a tapped reply or quote).
  final void Function(int messageId)? onJumpTo;

  static bool _isVisual(td.MessageContent c) => c is td.MessagePhoto || c is td.MessageVideo || c is td.MessageAnimation;

  /// Selection mode: taps toggle [selected] through [onSelect].
  final void Function(td.Message)? onSelect;
  final bool selecting;
  final bool selected;

  /// Shown as the post at the top of its own comments page.
  final bool inComments;

  final td.Message message;
  final ChatKind kind;
  final String chatTitle;

  /// Follows a message from the same sender: no repeated name or avatar.
  final bool grouped;

  /// A message already loaded in this chat, for reply previews.
  final td.Message? Function(int messageId)? findMessage;
  /// Reply to a message, quoting [quote] of its text when given.
  final ReplyCallback? onReply;

  /// Voice notes and songs of this chat, oldest first, for the player queue.
  final List<Track> Function()? playlist;
  final int lastReadOutbox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = _tile(context, ref);
    if (!selecting) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect?.call(message),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: selected ? AppColors.accent.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.m),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.only(left: 30), child: IgnorePointer(child: tile)),
          Positioned(
            left: 2,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? AppColors.accent : AppColors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final m = message;
    // Ephemeral content (seen only by this account) replaces the message's own.
    final shown = m.ephemeralContent?.content ?? m.content;
    final g = gistOf(shown);
    // A scheduled message shows when it goes out (and how often), not when
    // it was written.
    final sched = m.schedulingState;
    final clock = clockTime(
      DateTime.fromMillisecondsSinceEpoch((sched is td.MessageSchedulingStateSendAtDate ? sched.sendDate : m.date) * 1000),
    );
    final time = switch (sched) {
      td.MessageSchedulingStateSendAtDate(:final repeatPeriod) when repeatPeriod > 0 =>
        '${repeatLabel(repeatPeriod)}, $clock',
      td.MessageSchedulingStateSendWhenOnline() => 'when online',
      _ => clock,
    };
    final sender = m.isOutgoing ? 'You' : store.senderName(m.senderId);
    void open() {
      if (selecting) {
        onSelect?.call(m);
        return;
      }
      // In the pinned list a tap goes to the message in its chat.
      if (onGoTo != null) return onGoTo!();
      if (m.content is td.MessagePhoto ||
          m.content is td.MessageVideo ||
          m.content is td.MessageAnimation) {
        showMediaViewer(context, m.content, title: chatTitle);
      } else {
        showPost(
          context,
          snapshotOf(m, chatTitle, kind == ChatKind.channel ? null : sender),
        );
      }
    }

    void actions() {
      if (selecting) {
        onSelect?.call(m);
        return;
      }
      if (onActions != null) return onActions!();
      showMessageActions(context, ref, m, chatTitle: chatTitle, onReply: onReply, onSelect: onSelect);
    }

    if (g.kind == 'service') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$sender ${g.text.toLowerCase()}',
              style: context.text.labelSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final out = m.isOutgoing && kind != ChatKind.channel;
    final views = m.interactionInfo?.viewCount ?? 0;
    final comments = m.interactionInfo?.replyInfo?.replyCount ?? 0;
    final reactions =
        m.interactionInfo?.reactions?.reactions ?? const <td.MessageReaction>[];
    final visual =
        m.content is td.MessagePhoto ||
        m.content is td.MessageVideo ||
        m.content is td.MessageAnimation;
    final textSpan = switch (g.formatted) {
      final f? when f.text.isNotEmpty => formattedSpan(f),
      _ => g.text.isEmpty || g.kind == 'poll' || g.kind == 'sticker' || g.kind == 'rich' ? null : TextSpan(text: g.text),
    };

    final preview = switch (m.content) {
      td.MessageText(:final linkPreview?) when ref.watch(settingsProvider.select((s) => s.showLinkPreviews)) =>
        linkPreview,
      _ => null,
    };

    final channel = kind == ChatKind.channel;
    // A post atop its comments is the discussion group's pinned copy.
    final pinMark = inComments;
    final footer = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (views > 0) ...[
          Icon(
            Icons.visibility_outlined,
            size: channel ? 13 : 12,
            color: AppColors.text3,
          ),
          const SizedBox(width: 3),
          Text(
            NumberFormat.compact().format(views),
            style: TextStyle(fontSize: 11.5, color: AppColors.text3),
          ),
          const SizedBox(width: Space.s),
        ],
        if (pinMark) ...[
          Icon(Icons.push_pin_rounded, size: 12, color: AppColors.text3),
          const SizedBox(width: 4),
        ],
        if (m.editDate > 0)
          Text(
            'edited  ',
            style: TextStyle(fontSize: 11.5, color: AppColors.text3),
          ),
        Text(
          time,
          style: TextStyle(fontSize: 11.5, color: AppColors.text3),
        ),
        if (out) ...[
          const SizedBox(width: 3),
          Icon(
            m.sendingState != null
                ? Icons.schedule_rounded
                : (m.id <= lastReadOutbox
                      ? Icons.done_all_rounded
                      : Icons.done_rounded),
            size: 14,
            color: m.id <= lastReadOutbox ? AppColors.accent : AppColors.text3,
          ),
        ],
      ],
    );

    // What comes above the media: who wrote it, where it was forwarded
    // from, what it replies to.
    final showChannelName =
        channel && !grouped && (inComments || (!visual && album.isEmpty) || m.replyTo != null || m.forwardInfo != null);
    final head = <Widget>[
      if (showChannelName)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  chatTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: nameColor(chatTitle)),
                ),
              ),
              if (inComments) Text('channel', style: TextStyle(fontSize: 12, color: AppColors.text3)),
            ],
          ),
        ),
      if (kind == ChatKind.group && !m.isOutgoing && !grouped)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  sender,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: nameColor(sender),
                  ),
                ),
              ),
              // The sender's member tag, as Telegram shows it by the name.
              if (m.senderTag.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  m.senderTag,
                  style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      if (m.forwardInfo case final f?) ForwardHeader(origin: f.origin),
      if (m.ephemeralContent != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.s),
            // Back to what everyone else sees.
            onTap: () => ref
                .read(telegramClientProvider)
                .send<td.Ok>(td.DeleteMessageEphemeralContent(chatId: m.chatId, messageId: m.id))
                .catchError((Object _) => const td.Ok()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: 13, color: AppColors.text3),
                SizedBox(width: 4),
                Text('Only you can see this · tap to dismiss', style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
              ],
            ),
          ),
        ),
      if (m.replyTo case final td.MessageReplyToMessage r?)
        _ReplyPreview(reply: r, findMessage: findMessage, chatId: m.chatId, onJumpTo: onJumpTo),
    ];

    // The photo, video or album grid: edge to edge in a channel post.
    final Widget? visualBlock = album.length > 1
        ? (album.any((x) => _isVisual(x.content))
              ? AlbumGrid(
                  messages: [for (final x in album) if (_isVisual(x.content)) x],
                  onOpen: (x) => selecting ? onSelect?.call(m) : showMediaViewer(context, x.content, title: chatTitle),
                )
              : null)
        : (visual ? MediaPreview(content: m.content, onOpen: open) : null);

    final commentsRow = channel && !inComments && m.schedulingState == null && m.interactionInfo?.replyInfo != null
        ? _CommentsRow(message: m, count: comments)
        : null;

    final rest = <Widget>[
      if (album.length > 1) ...[
        // An album's files and songs one under another, and one caption.
        for (final x in album)
          if (x.content case td.MessageDocument(:final document))
            Padding(padding: const EdgeInsets.only(bottom: Space.xs), child: DocumentRow(document: document))
          else if (x.content case td.MessageAudio(:final audio))
            _AudioRow(message: x, audio: audio, playlist: playlist),
      ] else ...[
        if (m.content case td.MessageAudio(:final audio))
          _AudioRow(message: m, audio: audio, playlist: playlist),
        if (m.content case td.MessageDocument(:final document))
          DocumentRow(document: document),
      ],
      if (m.content case td.MessageVoiceNote(:final voiceNote))
        _VoiceBubble(message: m, note: voiceNote, playlist: playlist),
      if (m.content case td.MessageSticker(:final sticker)) StickerImage(sticker: sticker, size: 160),
      if (!visual &&
          g.isMedia &&
          m.content is! td.MessageVoiceNote &&
          m.content is! td.MessageAudio &&
          m.content is! td.MessageDocument &&
          m.content is! td.MessageSticker)
        _GenericMedia(gist: g),
      if (preview != null && preview.showAboveText) LinkPreviewCard(preview: preview),
      if (textSpan != null)
        Padding(
          padding: EdgeInsets.only(top: g.isMedia && !(channel && visualBlock != null) ? Space.s : 0),
          child: Text.rich(
            textSpan,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: AppColors.text,
            ),
          ),
        ),
      if (preview != null && !preview.showAboveText) LinkPreviewCard(preview: preview),
      if (shown case td.MessageRichMessage(:final message))
        RichMessageView(message: message, chatId: m.chatId, messageId: m.id, title: chatTitle),
      if (m.content case td.MessagePoll(:final poll))
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240),
          child: PollView(key: ValueKey(poll.id), message: m, poll: poll),
        ),
      if (m.replyMarkup is td.ReplyMarkupInlineKeyboard) BotButtons(message: m),
      if (channel)
        // Reactions on the left, views and time on the right, on one line
        // when they fit, as Telegram lays a channel post out.
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: reactions.isEmpty ? const SizedBox.shrink() : MessageReactions(message: m, reactions: reactions),
              ),
              const SizedBox(width: Space.s),
              Padding(padding: const EdgeInsets.only(bottom: 2), child: footer),
            ],
          ),
        )
      else ...[
        if (reactions.isNotEmpty) MessageReactions(message: m, reactions: reactions),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerRight, widthFactor: 1, child: footer),
      ],
    ];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [...head, ?visualBlock, ...rest],
    );

    final reply = onReply == null || selecting ? null : () => onReply!(m);
    if (channel) {
      const radius = Radii.xl;
      final post = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (head.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(12, 9, 12, visualBlock == null ? 0 : 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: head),
            ),
          if (visualBlock != null)
            Padding(
              padding: EdgeInsets.fromLTRB(3, head.isEmpty ? 3 : 0, 3, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius - 3),
                child: visualBlock,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              visualBlock != null ? 8 : (head.isEmpty ? 9 : 0),
              12,
              commentsRow == null ? 7 : 0,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rest),
          ),
          if (commentsRow != null) ...[
            Divider(height: Space.m, thickness: 0.6, color: AppColors.line),
            commentsRow,
          ],
        ],
      );
      final share = onGoTo != null || (!inComments && !selecting && m.sendingState == null && m.schedulingState == null);
      final width = MediaQuery.sizeOf(context).width;
      return SwipeToReply(
        onReply: reply,
        child: Padding(
          padding: EdgeInsets.only(bottom: grouped ? 4 : Space.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: inComments || !share ? double.infinity : (width * 0.86).clamp(0, 560).toDouble(),
                  ),
                  child: Material(
                    color: AppColors.surface2,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(radius),
                      topRight: Radius.circular(radius),
                      bottomRight: Radius.circular(radius),
                      bottomLeft: Radius.circular(6),
                    ),
                    child: InkWell(onTap: open, onLongPress: actions, child: post),
                  ),
                ),
              ),
              if (share)
                Padding(
                  padding: const EdgeInsets.only(left: Space.s, bottom: 2),
                  child: _ShareButton(
                    icon: onGoTo == null ? Icons.shortcut_rounded : Icons.arrow_forward_rounded,
                    onTap: onGoTo ??
                        () => showForwardSheet(context, m.chatId, album.isEmpty ? [m.id] : [for (final x in album) x.id]),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.8,
      ),
      child: Material(
        color: out ? AppColors.accentDim : AppColors.surface2,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(Radii.xl),
          topRight: const Radius.circular(Radii.xl),
          bottomLeft: Radius.circular(out ? Radii.xl : 6),
          bottomRight: Radius.circular(out ? 6 : Radii.xl),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          onLongPress: actions,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
            child: content,
          ),
        ),
      ),
    );
    final showAvatar = kind == ChatKind.group && !out && ref.watch(settingsProvider.select((s) => s.groupAvatars));
    return SwipeToReply(
      onReply: reply,
      child: Padding(
      padding: EdgeInsets.only(bottom: grouped ? 3 : Space.s),
      child: Row(
        mainAxisAlignment: out
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar) ...[
            grouped
                ? const SizedBox(width: 32)
                : switch (m.senderId) {
                    td.MessageSenderUser(:final userId) => TgAvatar(
                      userId: userId,
                      title: sender,
                      size: 32,
                    ),
                    td.MessageSenderChat(:final chatId) => TgAvatar(
                      chatId: chatId,
                      title: sender,
                      size: 32,
                    ),
                  },
            const SizedBox(width: Space.s),
          ],
          if (onGoTo != null && out) ...[_ShareButton(icon: Icons.arrow_forward_rounded, onTap: onGoTo!), const SizedBox(width: Space.s)],
          Flexible(child: bubble),
          if (onGoTo != null && !out) ...[const SizedBox(width: Space.s), _ShareButton(icon: Icons.arrow_forward_rounded, onTap: onGoTo!)],
        ],
      ),
    ),
    );
  }

  static const _names = [
    Color(0xFF8AB4FF),
    Color(0xFFB69CFF),
    Color(0xFF6FCF97),
    Color(0xFFF2C46D),
    Color(0xFFFF9B85),
    Color(0xFF7FD6E8),
  ];
  static Color nameColor(String name) =>
      _names[name.hashCode.abs() % _names.length];
}

/// How often a repeating scheduled message goes out, in Telegram's words.
String repeatLabel(int seconds) => switch (seconds) {
  86400 => 'daily',
  604800 => 'weekly',
  1209600 => 'biweekly',
  2592000 => 'monthly',
  7776000 => 'every 3 months',
  15552000 => 'every 6 months',
  31536000 => 'yearly',
  _ when seconds % 86400 == 0 => 'every ${seconds ~/ 86400} days',
  _ => 'repeating',
};

/// Under a channel post: who commented last, how many, and the way in.
class _CommentsRow extends ConsumerWidget {
  const _CommentsRow({required this.message, required this.count});
  final td.Message message;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final repliers = message.interactionInfo?.replyInfo?.recentReplierIds ?? const <td.MessageSender>[];
    final color = AppColors.activeAccent;
    Widget avatar(td.MessageSender s) {
      final name = store.senderName(s);
      return Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
        child: switch (s) {
          td.MessageSenderUser(:final userId) => TgAvatar(userId: userId, title: name, size: 24),
          td.MessageSenderChat(:final chatId) => TgAvatar(chatId: chatId, title: name, size: 24),
        },
      );
    }

    final shown = repliers.take(3).toList();
    return InkWell(
      onTap: () => openComments(context, ref, message),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(
          children: [
            if (shown.isEmpty)
              Icon(Icons.mode_comment_outlined, size: 20, color: color)
            else
              SizedBox(
                width: 27.0 + (shown.length - 1) * 17,
                height: 27,
                child: Stack(
                  children: [
                    for (final (i, s) in shown.indexed.toList().reversed)
                      Positioned(left: i * 17.0, child: avatar(s)),
                  ],
                ),
              ),
            const SizedBox(width: Space.s + 2),
            Expanded(
              child: Text(
                count == 0 ? 'Leave a comment' : '${NumberFormat.compact().format(count)} comment${count == 1 ? '' : 's'}',
                style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 22, color: color),
          ],
        ),
      ),
    );
  }
}

/// The round share arrow beside a channel post.
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap, this.icon = Icons.shortcut_rounded});
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface2.withValues(alpha: 0.85),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: 36,
        child: Icon(icon, size: 19, color: AppColors.text),
      ),
    ),
  );
}

/// Replying to [m], quoting [quote] of its text when given.
typedef ReplyCallback = void Function(td.Message m, {String? quote});

/// The message text to select from; returns the selected words to quote.
Future<String?> pickQuote(BuildContext context, String text) {
  var selected = '';
  return showFormSheet<String>(
    context,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Quote & reply', style: sheet.text.titleMedium),
          const SizedBox(height: Space.xs),
          Text('Select the words to quote.', style: sheet.text.bodySmall),
          const SizedBox(height: Space.m),
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: sheet.text.bodyLarge,
                onSelectionChanged: (s, _) => setSheet(() => selected = s.textInside(text).trim()),
              ),
            ),
          ),
          const SizedBox(height: Space.l),
          FilledButton.icon(
            onPressed: selected.isEmpty ? null : () => Navigator.pop(sheet, selected),
            icon: const Icon(Icons.format_quote_rounded),
            label: Text(selected.isEmpty ? 'Select some text' : 'Quote and reply'),
          ),
        ],
      ),
    ),
  );
}

/// Swipe a message left to reply to it, as in Telegram: the bubble follows
/// the finger, a reply arrow fills in, and letting go past it replies.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.onReply, required this.child});
  final VoidCallback? onReply;
  final Widget child;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  static const _trigger = 64.0;
  double _dx = 0;
  bool _armed = false;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _end() {
    if (_armed) widget.onReply?.call();
    _armed = false;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final progress = (-_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        final next = (_dx + d.delta.dx).clamp(-_trigger * 1.4, 0.0);
        final armed = -next >= _trigger;
        if (armed && !_armed) HapticFeedback.selectionClick();
        setState(() {
          _dx = next;
          _armed = armed;
        });
      },
      onHorizontalDragEnd: (_) => _end(),
      onHorizontalDragCancel: _end,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Positioned(
            right: Space.s,
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.6 + 0.4 * progress,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _armed ? AppColors.accent : AppColors.surface3,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.reply_rounded, size: 18, color: _armed ? AppColors.bg : AppColors.text2),
                ),
              ),
            ),
          ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

class ForwardHeader extends ConsumerWidget {
  const ForwardHeader({required this.origin});
  final td.MessageOrigin origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final chatId = originChatId(origin);
    // A channel this account isn't in may not be known yet; ask once.
    if (chatId != null && store.chat(chatId) == null) {
      ref
          .read(telegramClientProvider)
          .send<td.Chat>(td.GetChat(chatId: chatId), limited: true)
          .ignore();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shortcut_rounded, size: 14, color: AppColors.activeAccent),
          const SizedBox(width: 4),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Forwarded from '),
                  TextSpan(
                    text: originName(origin, store),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: AppColors.activeAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyPreview extends ConsumerStatefulWidget {
  const _ReplyPreview({required this.reply, this.findMessage, required this.chatId, this.onJumpTo});
  final td.MessageReplyToMessage reply;
  final td.Message? Function(int messageId)? findMessage;

  /// The chat the replying message is in.
  final int chatId;
  final void Function(int messageId)? onJumpTo;

  @override
  ConsumerState<_ReplyPreview> createState() => _ReplyPreviewState();
}

class _ReplyPreviewState extends ConsumerState<_ReplyPreview> {
  td.Message? _fetched;

  @override
  void initState() {
    super.initState();
    final r = widget.reply;
    if (r.content == null &&
        r.chatId != 0 &&
        widget.findMessage?.call(r.messageId) == null) {
      ref
          .read(telegramClientProvider)
          .send<td.Message>(
            td.GetMessage(chatId: r.chatId, messageId: r.messageId),
            limited: true,
          )
          .then((m) {
            if (mounted) setState(() => _fetched = m);
          })
          .ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final r = widget.reply;
    final m = widget.findMessage?.call(r.messageId) ?? _fetched;
    final who = r.origin != null
        ? originName(r.origin!, store)
        : (m == null
              ? 'Reply'
              : (m.isOutgoing ? 'You' : store.senderName(m.senderId)));
    final content = r.content ?? m?.content;
    final g = content == null ? null : gistOf(content);
    final quote = r.quote?.text.text;
    final preview = quote != null && quote.isNotEmpty
        ? quote
        : (g == null
              ? '…'
              : (g.text.isNotEmpty ? g.text : (g.detail ?? g.kind)));
    final color = MessageTile.nameColor(who);
    // A reply in the same chat scrolls to the original; one to another chat
    // (or a channel post) opens it.
    void open() {
      if (r.messageId == 0) return;
      if ((r.chatId == 0 || r.chatId == widget.chatId) && widget.onJumpTo != null) {
        widget.onJumpTo!(r.messageId);
        return;
      }
      // The original lives in another chat this account can open: go there,
      // at that message.
      if (r.chatId != 0 && store.chat(r.chatId) != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: r.chatId, openAt: r.messageId)),
        );
        return;
      }
      final original = m;
      if (original != null) {
        final chatTitle = store.chat(original.chatId)?.title ?? 'Chat';
        showPost(context, snapshotOf(original, chatTitle, original.isOutgoing ? 'You' : store.senderName(original.senderId)));
      } else if (r.chatId != 0) {
        ref
            .read(telegramClientProvider)
            .send<td.Message>(td.GetMessage(chatId: r.chatId, messageId: r.messageId), limited: true)
            .then((x) {
              if (!context.mounted) return;
              final chatTitle = store.chat(x.chatId)?.title ?? 'Chat';
              showPost(context, snapshotOf(x, chatTitle, x.isOutgoing ? 'You' : store.senderName(x.senderId)));
            })
            .catchError((Object _) {
              if (context.mounted) showSnack(context, 'That message isn\'t available', icon: Icons.info_outline_rounded);
            });
      }
    }

    // Like Telegram: a tinted block with a rounded bar in the sender's
    // colour, their name, then the replied-to words (a quote gets a mark).
    final quoted = quote != null && quote.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: open,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        quoted ? preview : preview.replaceAll('\n', ' '),
                        maxLines: quoted ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, height: 1.3, color: AppColors.text),
                      ),
                    ],
                  ),
                ),
              ),
              if (quoted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 6, 0),
                  child: Icon(Icons.format_quote_rounded, size: 16, color: color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MessageReactions extends ConsumerWidget {
  const MessageReactions({required this.message, required this.reactions});
  final td.Message message;
  final List<td.MessageReaction> reactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Stars first, as Telegram shows them.
    final sorted = [
      ...reactions.where((r) => r.type is td.ReactionTypePaid),
      ...reactions.where((r) => r.type is! td.ReactionTypePaid),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final r in sorted)
            Builder(
              builder: (context) {
                final paid = r.type is td.ReactionTypePaid;
                // Like Telegram: your own reaction is a solid pill in the
                // accent colour, the rest quiet; no outlines (Stars keep
                // their gold edge).
                final mine = r.isChosen && !paid;
                return Material(
                  color: paid
                      ? starGold.withValues(alpha: r.isChosen ? 0.3 : 0.16)
                      : mine
                      ? AppColors.accent
                      : AppColors.surface3,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: switch (r.type) {
                      td.ReactionTypePaid() => () => showStarSheet(context, message),
                      td.ReactionTypeEmoji(:final emoji) => () => toggleReaction(ref, message, emoji, chosen: r.isChosen),
                      _ => () => showReactorsSheet(context, message),
                    },
                    onLongPress: () => paid ? showStarSheet(context, message) : showReactorsSheet(context, message),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: paid
                            ? Border.all(color: starGold.withValues(alpha: r.isChosen ? 1 : 0.5))
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReactionIcon(type: r.type, size: 15),
                          const SizedBox(width: 4),
                          Text(
                            NumberFormat.compact().format(r.totalCount),
                            style: TextStyle(
                              fontSize: 13,
                              color: paid ? starGold : (mine ? AppColors.bg : AppColors.text),
                              fontWeight: paid || mine ? FontWeight.w600 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Adds or takes back the account's reaction. The chat hears about it from
/// TDLib's interaction-info update.
Future<void> toggleReaction(
  WidgetRef ref,
  td.Message m,
  String emoji, {
  required bool chosen,
}) async {
  final client = ref.read(telegramClientProvider);
  final type = td.ReactionTypeEmoji(emoji: emoji);
  try {
    if (chosen) {
      await client.send<td.Ok>(
        td.RemoveMessageReaction(
          chatId: m.chatId,
          messageId: m.id,
          reactionType: type,
        ),
        limited: true,
      );
    } else {
      await client.send<td.Ok>(
        td.AddMessageReaction(
          chatId: m.chatId,
          messageId: m.id,
          reactionType: type,
          isBig: false,
          updateRecentReactions: true,
        ),
        limited: true,
      );
    }
  } catch (e) {
    debugPrint('[Reaction] $e');
  }
}

/// Long-press menu: react, reply, copy, open.
Future<void> showMessageActions(
  BuildContext context,
  WidgetRef ref,
  td.Message m, {
  required String chatTitle,
  ReplyCallback? onReply,
  void Function(td.Message)? onSelect,
}) async {
  final g = gistOf(m.content);
  final store = ref.read(telegramStoreProvider);
  final runner = ref.read(toolRunnerProvider);
  final me = store.me?.id;
  final chosen = {
    for (final r
        in m.interactionInfo?.reactions?.reactions ??
            const <td.MessageReaction>[])
      if (r.isChosen && r.type is td.ReactionTypeEmoji)
        (r.type as td.ReactionTypeEmoji).emoji,
  };
  List<String> emojis = quickReactions;
  // Channels that take Stars offer the paid reaction first.
  var stars = m.interactionInfo?.reactions?.reactions.any((r) => r.type is td.ReactionTypePaid) ?? false;
  try {
    final available = await ref
        .read(telegramClientProvider)
        .send<td.AvailableReactions>(
          td.GetMessageAvailableReactions(
            chatId: m.chatId,
            messageId: m.id,
            rowSize: 8,
          ),
        );
    final top = [
      for (final r in [
        ...available.topReactions,
        ...available.popularReactions,
      ])
        if (r.type is td.ReactionTypeEmoji && !r.needsPremium)
          (r.type as td.ReactionTypeEmoji).emoji,
    ];
    emojis = top.toSet().take(16).toList();
    stars = stars || [...available.topReactions, ...available.popularReactions].any((r) => r.type is td.ReactionTypePaid);
  } catch (_) {
    // Reactions may be off in this chat; the defaults are offered and
    // Telegram refuses any it doesn't allow.
  }
  if (!context.mounted) return;
  Widget action(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {bool danger = false}) => ListTile(
    dense: true,
    leading: lead(Icon(icon, color: danger ? AppColors.danger : null)),
    title: Text(label, style: TextStyle(fontSize: 15, color: danger ? AppColors.danger : null)),
    onTap: () {
      Navigator.pop(ctx);
      onTap();
    },
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (emojis.isNotEmpty || stars)
              Container(
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s),
                  child: Row(
                    children: [
                      if (stars)
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            Navigator.pop(ctx);
                            showStarSheet(context, m);
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.star_rounded, size: 31, color: starGold),
                          ),
                        ),
                      for (final e in emojis)
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            Navigator.pop(ctx);
                            toggleReaction(
                              ref,
                              m,
                              e,
                              chosen: chosen.contains(e),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: chosen.contains(e)
                                  ? AppColors.accent.withValues(alpha: 0.25)
                                  : null,
                            ),
                            child: Text(
                              e,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Space.m),
            if (onReply != null)
              ListTile(
                leading: lead(const Icon(Icons.reply_rounded)),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply(m);
                },
              ),
            if (onReply != null && g.text.trim().isNotEmpty)
              ListTile(
                leading: lead(const Icon(Icons.format_quote_rounded)),
                title: const Text('Quote & reply'),
                subtitle: Text('Pick the words to quote', style: ctx.text.bodySmall),
                onTap: () async {
                  Navigator.pop(ctx);
                  final quote = await pickQuote(context, g.text);
                  if (quote != null) onReply(m, quote: quote);
                },
              ),
            if (g.text.isNotEmpty)
              ListTile(
                leading: lead(const Icon(Icons.copy_rounded)),
                title: const Text('Copy text'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: g.text));
                  showSnack(context, 'Copied');
                },
              ),
            if (g.text.isNotEmpty)
              action(ctx, Icons.translate_rounded, 'Translate', () => showTranslation(context, m)),
            action(ctx, Icons.forward_rounded, 'Forward…', () => showForwardSheet(context, m.chatId, [m.id])),
            if (me != null && m.chatId != me)
              action(ctx, Icons.bookmark_add_outlined, 'Save to Saved Messages', () async {
                try {
                  await runner.forwardTo(me, m.chatId, [m.id]);
                  if (context.mounted) showSnack(context, 'Saved', icon: Icons.bookmark_added_outlined);
                } catch (e) {
                  if (context.mounted) showSnack(context, 'Couldn\'t save: $e', icon: Icons.error_outline_rounded);
                }
              }),
            action(ctx, Icons.dashboard_customize_outlined, 'Save to Content Canvas', () => saveToCanvas(context, ref, m, chatTitle)),
            if (onSelect != null) action(ctx, Icons.check_circle_outline_rounded, 'Select', () => onSelect(m)),
            action(ctx, Icons.link_rounded, 'Copy link', () async {
              final link = await runner.messageLink(m.chatId, m.id);
              if (!context.mounted) return;
              if (link == null) {
                showSnack(context, 'This message has no public link', icon: Icons.link_off_rounded);
              } else {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) showSnack(context, 'Link copied', icon: Icons.link_rounded);
              }
            }),
            action(ctx, m.isPinned ? Icons.push_pin : Icons.push_pin_outlined, m.isPinned ? 'Unpin' : 'Pin', () async {
              try {
                final client = ref.read(telegramClientProvider);
                if (m.isPinned) {
                  await client.send<td.Ok>(td.UnpinChatMessage(chatId: m.chatId, messageId: m.id), limited: true);
                } else {
                  await client.send<td.Ok>(
                    td.PinChatMessage(chatId: m.chatId, messageId: m.id, disableNotification: true, onlyForSelf: false),
                    limited: true,
                  );
                }
                if (context.mounted) showSnack(context, m.isPinned ? 'Unpinned' : 'Pinned', icon: Icons.push_pin_outlined);
              } catch (e) {
                if (context.mounted) showSnack(context, 'Couldn\'t pin: $e', icon: Icons.error_outline_rounded);
              }
            }),
            action(ctx, Icons.auto_awesome_outlined, 'Ask AI about this', () {
              final controller = ref.read(chatControllerProvider.notifier);
              controller.newChat();
              controller.send(
                'Tell me about this message: [$chatTitle](post:${m.chatId}:${m.id}) (chat_id ${m.chatId}, message_id ${m.id}). '
                'Read it (and its context if useful) and explain it.',
              );
              Navigator.of(context).popUntil((r) => r.isFirst);
            }),
            action(ctx, Icons.info_outline_rounded, 'Details', () => showPost(context, snapshotOf(m, chatTitle, null))),
            action(ctx, Icons.delete_outline_rounded, 'Delete', danger: true, () async {
              final forAll = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete this message?'),
                  content: const Text('This can\'t be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Delete for me')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('For everyone'),
                    ),
                  ],
                ),
              );
              if (forAll == null) return;
              try {
                await runner.deleteMessages(m.chatId, [m.id], forEveryone: forAll);
              } catch (e) {
                if (context.mounted) showSnack(context, 'Couldn\'t delete: $e', icon: Icons.error_outline_rounded);
              }
            }),
          ],
        ),
        ),
      ),
    ),
  );
}

/// A photo or video thumbnail. Photos download on their own when Settings
/// say so; otherwise the blurry preview waits for a tap.
class MediaPreview extends ConsumerStatefulWidget {
  const MediaPreview({super.key, required this.content, this.onOpen, this.fill = false});
  final td.MessageContent content;
  final VoidCallback? onOpen;

  /// Covers the box it is given (an album cell) instead of keeping its own
  /// shape; the picture is cropped, never stretched.
  final bool fill;

  @override
  ConsumerState<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends ConsumerState<MediaPreview> {
  String? _path;
  bool _asked = false;

  td.Minithumbnail? get _mini => switch (widget.content) {
    td.MessagePhoto(:final photo) => photo.minithumbnail,
    td.MessageVideo(:final video) => video.minithumbnail,
    td.MessageAnimation(:final animation) => animation.minithumbnail,
    _ => null,
  };

  (int, int)? get _dims => switch (widget.content) {
    td.MessagePhoto(:final photo) =>
      photo.sizes.isEmpty
          ? null
          : (photo.sizes.last.width, photo.sizes.last.height),
    td.MessageVideo(:final video) => (video.width, video.height),
    td.MessageAnimation(:final animation) => (
      animation.width,
      animation.height,
    ),
    _ => null,
  };

  td.File? get _file => switch (widget.content) {
    td.MessagePhoto(:final photo) => pickPhotoSize(
      photo.sizes,
      minWidth: 600,
    )?.photo,
    _ => previewFileOf(widget.content),
  };

  void _load({bool force = false}) {
    final file = _file;
    if (file == null) return;
    final loader = ref.read(fileLoaderProvider);
    final cached = loader.cachedPath(file);
    if (cached != null) {
      _path = cached;
      return;
    }
    // Video and GIF thumbnails are tiny, so they always load.
    final auto =
        ref.read(settingsProvider).autoPhotos ||
        widget.content is! td.MessagePhoto;
    if (!force && !auto) return;
    _asked = true;
    loader.download(file, priority: force ? 24 : 4).then((p) {
      if (mounted && p != null) setState(() => _path = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_asked && _path == null) _load();
    final c = widget.content;
    final file = _file;
    final dims = _dims;
    final ratio = dims == null || dims.$2 == 0
        ? 4 / 3
        : (dims.$1 / dims.$2).clamp(0.6, 2.0);
    final mini = _mini;
    final waiting = _path == null && file != null;
    return GestureDetector(
      onTap: waiting && !_asked
          ? () => setState(() => _load(force: true))
          : widget.onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.fill ? 0 : Radii.l),
        child: _Shape(
          fill: widget.fill,
          ratio: ratio.toDouble(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_path != null)
                Image.file(
                  File(_path!),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // A bubble is never wider than ~440 pt: decoding the full
                  // photo for it made long channels stutter.
                  cacheWidth: (440 * MediaQuery.devicePixelRatioOf(context)).round(),
                )
              else if (mini != null)
                Image.memory(
                  base64Decode(mini.data),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              else
                Container(color: AppColors.surface3),
              if (waiting)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: _asked
                        ? ValueListenableBuilder<double>(
                            valueListenable: ref
                                .read(fileLoaderProvider)
                                .progress(file),
                            builder: (_, v, _) => SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                value: v > 0 ? v : null,
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                          ),
                  ),
                )
              else if (c is td.MessageVideo || c is td.MessageAnimation)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(Space.s),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (c case td.MessageVideo(:final video))
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      formatDuration(video.duration),
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceBubble extends ConsumerWidget {
  const _VoiceBubble({
    required this.message,
    required this.note,
    this.playlist,
  });
  final td.Message message;
  final td.VoiceNote note;
  final List<Track> Function()? playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioCenterProvider);
    final store = ref.read(telegramStoreProvider);
    if (ref.read(settingsProvider).autoVoice)
      ref.read(fileLoaderProvider).download(note.voice, priority: 2);
    final current = audio.isCurrent(message.chatId, message.id);
    final playing = current && audio.playing;
    final bars = decodeWaveform(note.waveform, bars: 36);
    final total = note.duration;
    final played = current && audio.duration.inMilliseconds > 0
        ? audio.position.inMilliseconds / audio.duration.inMilliseconds
        : 0.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlayButton(
          playing: playing,
          loading: current && audio.loading,
          onTap: () {
            final t = Track.of(message, store);
            if (t != null) audio.play(t, playlist: playlist?.call());
          },
        ),
        const SizedBox(width: Space.s + 2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 26,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, v) in bars.indexed)
                    Container(
                      width: 3,
                      height: 3 + v * 0.75,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: i / bars.length <= played
                            ? AppColors.accent
                            : AppColors.text3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              current
                  ? '${formatDuration(audio.position.inSeconds)} / ${formatDuration(total)}'
                  : formatDuration(total),
              style: TextStyle(fontSize: 11.5, color: AppColors.text2),
            ),
          ],
        ),
      ],
    );
  }
}

class _AudioRow extends ConsumerWidget {
  const _AudioRow({required this.message, required this.audio, this.playlist});
  final td.Message message;
  final td.Audio audio;
  final List<Track> Function()? playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final center = ref.watch(audioCenterProvider);
    final store = ref.read(telegramStoreProvider);
    if (ref.read(settingsProvider).autoMusic)
      ref.read(fileLoaderProvider).download(audio.audio, priority: 1);
    final current = center.isCurrent(message.chatId, message.id);
    final title = audio.title.isNotEmpty ? audio.title : audio.fileName;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlayButton(
          playing: current && center.playing,
          loading: current && center.loading,
          cover: audio.albumCoverMinithumbnail,
          onTap: () {
            final t = Track.of(message, store);
            if (t != null) center.play(t, playlist: playlist?.call());
          },
        ),
        const SizedBox(width: Space.m),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  if (audio.performer.isNotEmpty) audio.performer,
                  formatDuration(audio.duration),
                  formatBytes(audio.audio.size),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: AppColors.text2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.onTap,
    this.cover,
  });
  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  final td.Minithumbnail? cover;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.activeAccent,
          image: cover == null
              ? null
              : DecorationImage(
                  image: MemoryImage(base64Decode(cover!.data)),
                  fit: BoxFit.cover,
                  colorFilter: const ColorFilter.mode(
                    Colors.black38,
                    BlendMode.darken,
                  ),
                ),
        ),
        child: loading
            ? Padding(
                padding: EdgeInsets.all(13),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.bg,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: cover == null ? AppColors.bg : Colors.white,
                size: 28,
              ),
      ),
    );
  }
}

class DocumentRow extends ConsumerWidget {
  const DocumentRow({required this.document});
  final td.Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loader = ref.watch(fileLoaderProvider);
    final file = document.document;
    final path = loader.cachedPath(file);
    final mime = document.mimeType.toLowerCase();
    final visual = mime.startsWith('image/') || mime.startsWith('video/');
    final thumb = document.thumbnail;
    return ValueListenableBuilder<double>(
      valueListenable: loader.progress(file),
      builder: (context, progress, _) {
        final downloading = loader.isDownloading(file);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: path != null
                  ? () => openDocument(context, document, path)
                  : downloading
                  ? () => loader.cancel(file)
                  // Downloads, then opens: one tap, like Telegram.
                  : () async {
                      final p = await loader.download(file, priority: 24);
                      if (p != null && context.mounted) await openDocument(context, document, p);
                    },
              onLongPress: path == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: path));
                      showSnack(context, 'Path copied');
                    },
              child: Container(
                width: 46,
                height: 46,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.activeAccent,
                  shape: visual && thumb != null ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: visual && thumb != null ? BorderRadius.circular(Radii.s) : null,
                ),
                child: visual && thumb != null && !downloading
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          TdFileImage(file: thumb.file, minithumbnail: document.minithumbnail),
                          if (path == null)
                            const Center(child: Icon(Icons.download_rounded, color: Colors.white, size: 20)),
                        ],
                      )
                    : downloading
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          value: progress > 0 ? progress : null,
                          strokeWidth: 2,
                          color: AppColors.bg,
                        ),
                      )
                    : Icon(
                        path != null
                            ? Icons.insert_drive_file_rounded
                            : Icons.download_rounded,
                        color: AppColors.bg,
                      ),
              ),
            ),
            const SizedBox(width: Space.m),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    document.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    downloading
                        ? '${formatBytes((file.size * progress).round())} of ${formatBytes(file.size)}'
                        : formatBytes(file.size),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A photo's, video's or GIF's width over height, kept to a sensible range.
double mediaRatio(td.MessageContent c) {
  final (w, h) = switch (c) {
    td.MessagePhoto(:final photo) when photo.sizes.isNotEmpty => (photo.sizes.last.width, photo.sizes.last.height),
    td.MessageVideo(:final video) => (video.width, video.height),
    td.MessageAnimation(:final animation) => (animation.width, animation.height),
    _ => (4, 3),
  };
  if (w <= 0 || h <= 0) return 4 / 3;
  return (w / h).clamp(0.5, 2.4).toDouble();
}

/// Keeps a picture's own shape, or covers the box it is given.
class _Shape extends StatelessWidget {
  const _Shape({required this.fill, required this.ratio, required this.child});
  final bool fill;
  final double ratio;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      fill ? SizedBox.expand(child: child) : AspectRatio(aspectRatio: ratio, child: child);
}

/// An album's photos and videos laid out like Telegram does: rows whose
/// height follows the pictures' shapes, each picture as wide as its shape
/// asks, so every row runs edge to edge and the edges line up. Pictures
/// are cropped a little to fit, never stretched.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.messages, required this.onOpen});
  final List<td.Message> messages;
  final void Function(td.Message) onOpen;

  static const _gap = 2.0;

  /// Splits the album into rows: a wide or lone first picture on top when
  /// there are three or more, then rows of two or three, never a lone one
  /// at the end.
  static List<List<int>> _rows(List<double> ratios) {
    final n = ratios.length;
    if (n <= 2) return [List.generate(n, (i) => i)];
    if (n == 3) {
      // One across the top when it's wide, else one tall beside two.
      return ratios[0] >= 1.2 ? [[0], [1, 2]] : [[0, 1, 2]];
    }
    final rows = <List<int>>[[0]];
    var i = 1;
    while (i < n) {
      final left = n - i;
      final take = left == 4 ? 2 : (left >= 3 ? 3 : left);
      rows.add([for (var k = i; k < i + take; k++) k]);
      i += take;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (messages.length == 1) {
      return MediaPreview(key: ValueKey(messages.single.id), content: messages.single.content, onOpen: () => onOpen(messages.single));
    }
    final ratios = [for (final m in messages) mediaRatio(m.content)];
    // Rounded as one picture; the cells inside meet with a hairline gap.
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.l),
      child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 320.0;
        Widget cell(int i) => MediaPreview(
          key: ValueKey(messages[i].id),
          content: messages[i].content,
          fill: true,
          onOpen: () => onOpen(messages[i]),
        );
        final rows = _rows(ratios);
        // Three in one row with the first tall: it spans the height of the
        // other two stacked.
        if (rows.length == 1 && rows.single.length == 3) {
          final right = 1 / (1 / ratios[1] + 1 / ratios[2]);
          final h = ((w - _gap) / (ratios[0] + right)).clamp(w * 0.5, w * 1.1).toDouble();
          return SizedBox(
            height: h,
            child: Row(
              children: [
                Expanded(flex: (ratios[0] * 1000).round(), child: cell(0)),
                const SizedBox(width: _gap),
                Expanded(
                  flex: (right * 1000).round(),
                  child: Column(
                    children: [
                      Expanded(flex: (1000 / ratios[1]).round(), child: cell(1)),
                      const SizedBox(height: _gap),
                      Expanded(flex: (1000 / ratios[2]).round(), child: cell(2)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (r, row) in rows.indexed) ...[
              if (r > 0) const SizedBox(height: _gap),
              Builder(
                builder: (_) {
                  final sum = row.fold<double>(0, (t, i) => t + ratios[i]);
                  final inner = w - _gap * (row.length - 1);
                  // The height that fits them all edge to edge, kept within
                  // reason (a lone panorama doesn't become a sliver).
                  final h = (inner / sum).clamp(w * 0.22, row.length == 1 ? w * 0.8 : w * 0.65).toDouble();
                  return SizedBox(
                    height: h,
                    child: Row(
                      children: [
                        for (final (k, i) in row.indexed) ...[
                          if (k > 0) const SizedBox(width: _gap),
                          Expanded(flex: (ratios[i] * 1000).round(), child: cell(i)),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        );
      },
      ),
    );
  }
}

/// Opens a downloaded file: pictures and videos in the app's viewer,
/// anything else in the phone's app for that type.
Future<void> openDocument(BuildContext context, td.Document document, String path) async {
  final mime = document.mimeType.toLowerCase();
  if (mime.startsWith('image/') || mime.startsWith('video/')) {
    return showMediaViewer(
      context,
      td.MessageDocument(document: document, caption: const td.FormattedText(text: '', entities: [])),
      title: document.fileName,
    );
  }
  final r = await OpenFilex.open(path, type: document.mimeType.isEmpty ? null : document.mimeType);
  if (r.type != ResultType.done && context.mounted) {
    showSnack(
      context,
      r.type == ResultType.noAppToOpen ? 'No app on this phone opens ${document.fileName}' : 'Couldn\'t open it: ${r.message}',
      icon: Icons.info_outline_rounded,
    );
  }
}

class _GenericMedia extends StatelessWidget {
  const _GenericMedia({required this.gist});
  final MessageGist gist;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(kindIcon(gist.kind), size: 20, color: AppColors.activeAccent),
      const SizedBox(width: Space.s),
      Flexible(
        child: Text(
          gist.detail?.isNotEmpty == true
              ? gist.detail!
              : gist.kind.replaceAll('_', ' '),
          style: TextStyle(fontSize: 14, color: AppColors.text2),
        ),
      ),
    ],
  );
}

/// A bot message's buttons, as Telegram lays them out. Callback buttons ask
/// the bot and show its answer; links open in the browser; reply-keyboard
/// buttons send their text.
class BotButtons extends ConsumerStatefulWidget {
  const BotButtons({super.key, required this.message});
  final td.Message message;

  @override
  ConsumerState<BotButtons> createState() => _BotButtonsState();
}

class _BotButtonsState extends ConsumerState<BotButtons> {
  String? _busy;

  Future<void> _press(BotButton b) async {
    setState(() => _busy = '${b.row}:${b.column}');
    try {
      final r = await ref.read(toolRunnerProvider).pressButton(widget.message, b);
      if (!mounted) return;
      if (r.url.isNotEmpty) {
        await launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication);
      } else if (r.alert && r.text.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            content: Text(r.text),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
      } else if (r.text.isNotEmpty) {
        showSnack(context, r.text, icon: Icons.smart_toy_outlined);
      }
    } catch (e) {
      if (mounted) showSnack(context, '${e is ArgumentError ? e.message : e}', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttons = botButtonsOf(widget.message);
    if (buttons.isEmpty) return const SizedBox.shrink();
    final rows = <int, List<BotButton>>{};
    for (final b in buttons) {
      (rows[b.row] ??= []).add(b);
    }
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Column(
        children: [
          for (final row in rows.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final (i, b) in row.indexed) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Material(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(Radii.s),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.s),
                          onTap: _busy != null ? null : () => _press(b),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_busy == '${b.row}:${b.column}')
                                  const SizedBox.square(
                                    dimension: 12,
                                    child: CircularProgressIndicator(strokeWidth: 1.5),
                                  )
                                else
                                  Flexible(
                                    child: Text(
                                      b.text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                if (b.kind == 'url' || b.kind == 'web_app' || b.kind == 'login_url') ...[
                                  const SizedBox(width: 3),
                                  Icon(Icons.north_east_rounded, size: 12, color: AppColors.text3),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
