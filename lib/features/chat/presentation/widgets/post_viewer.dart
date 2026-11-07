import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../infrastructure/telegram/telegram_client.dart';
import '../../../../infrastructure/telegram/telegram_exception.dart';
import '../../../telegram/data/message_content.dart';
import '../../../telegram/data/file_loader.dart';
import '../../../telegram/data/telegram_store.dart';
import '../../../telegram/data/telegram_tools.dart';
import '../../../media/audio_center.dart';
import '../../../telegram/presentation/tg_avatar.dart';
import '../../../telegram/presentation/chat_profile_screen.dart';
import '../../../telegram/presentation/expression_panel.dart' show StickerImage;
import '../../../telegram/presentation/link_preview_card.dart';
import '../../../telegram/presentation/media_viewer.dart';
import '../../../telegram/presentation/message_tile.dart';
import '../../domain/chat_models.dart';
import '../../../telegram/presentation/formatted_text.dart';
import '../../../../infrastructure/telegram/td_compat.dart';
import '../../../account/account_router.dart';
import '../../../../infrastructure/telegram/accounts.dart';

IconData kindIcon(String kind) => switch (kind) {
  'photo' => Icons.image_outlined,
  'video' || 'video_note' || 'gif' => Icons.movie_outlined,
  'document' => Icons.description_outlined,
  'audio' => Icons.music_note_outlined,
  'voice' => Icons.mic_none_rounded,
  'poll' => Icons.poll_outlined,
  'location' => Icons.place_outlined,
  'sticker' => Icons.emoji_emotions_outlined,
  _ => Icons.notes_rounded,
};

/// A chip standing for one post the answer cited.
class PostChip extends StatelessWidget {
  const PostChip({super.key, required this.post});
  final PostSnapshot post;

  @override
  Widget build(BuildContext context) {
    final preview = post.text.replaceAll('\n', ' ').trim();
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(Radii.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: () => showPost(context, post),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref, _) => TgAvatar(
                  chatId: post.chatId,
                  title: post.chatTitle,
                  size: 26,
                  accountId: signedInAccount(ref.watch(accountsProvider), post.accountId),
                ),
              ),
              const SizedBox(width: Space.s),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      post.chatTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (post.kind != 'text') ...[
                          Icon(
                            kindIcon(post.kind),
                            size: 12,
                            color: AppColors.text3,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            preview.isEmpty ? _relative(post.date) : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.text3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.yMMMd().format(d);
}

/// Opens the original post in a sheet that can be dragged to full screen.
Future<void> showPost(BuildContext context, PostSnapshot post) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 1,
      snap: true,
      snapSizes: const [0.62],
      builder: (context, scroll) => PostView(post: post, scroll: scroll),
    ),
  );
}

/// The same view as a full page.
class PostPage extends StatelessWidget {
  const PostPage({super.key, required this.post});
  final PostSnapshot post;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(post.chatTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: PostView(post: post, fullPage: true),
  );
}

class PostView extends ConsumerStatefulWidget {
  const PostView({
    super.key,
    required this.post,
    this.scroll,
    this.fullPage = false,
  });
  final PostSnapshot post;
  final ScrollController? scroll;
  final bool fullPage;

  @override
  ConsumerState<PostView> createState() => _PostViewState();
}

class _PostViewState extends ConsumerState<PostView> {
  td.Message? _message;
  String? _imagePath;
  String? _link;
  String? _error;
  bool _loading = true;
  td.MessageProperties? _props;
  String? _readDate;
  List<td.AddedReaction> _reactors = const [];
  List<td.MessageViewer> _viewers = const [];
  StreamSubscription<td.TdObject>? _live;

  /// The account the post was found in; everything here reads from it.
  String? _account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final p = widget.post;
    try {
      // The account it came from, else whichever account has it.
      final found = await findPost(
        ProviderScope.containerOf(context, listen: false),
        p.chatId,
        p.messageId,
        hint: p.accountId,
      );
      if (!mounted) return;
      setState(() => _account = found.account);
      final m = found.message;
      if (m == null) throw found.error ?? const TelegramException(404, 'Not found');
      setState(() {
        _message = m;
        _loading = false;
      });
      // The inline preview is specifically for an image. Audio is downloaded
      // by AudioCenter when the user presses play; attempting to decode its
      // file as an image made the post sheet unusable for songs and notes.
      if (gistOf(m.content).kind == 'photo') {
        final file = previewFileOf(m.content);
        if (file != null) unawaited(_download(file));
      }
      unawaited(_loadExtras(m));
      final link = await ref
          .read(toolRunnerFamily(found.account))
          .messageLink(p.chatId, p.messageId);
      if (mounted) setState(() => _link = link);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is TelegramException && e.code == 404
              ? 'This message isn\'t available anymore: it was deleted, or it is in a chat you\'ve left.'
              : 'Showing the saved copy. Telegram said: ${e is TelegramException ? e.friendlyMessage : e}';
          _loading = false;
        });
      }
    }
  }

  /// Who reacted, who saw it and when it was read, where Telegram tells:
  /// small groups for viewers, private chats for the read date. Each is
  /// one paced request and quietly skipped when not allowed.
  Future<void> _loadExtras(td.Message m) async {
    final client = ref.read(telegramClientFamily(_account!));
    // The cached copy's views and reactions (Stars too) may be stale:
    // viewing it (from a source TDLib doesn't mark read) fetches them, and
    // they arrive as an update.
    _live ??= client.updates.listen((u) {
      if (u case td.UpdateMessageInteractionInfo(:final chatId, :final messageId, :final interactionInfo)
          when chatId == m.chatId && messageId == m.id && mounted) {
        setState(() => _message = _message?.copyWith(interactionInfo: interactionInfo));
      }
    });
    // Groups and channels (negative ids); private chats have nothing to fetch.
    if (m.chatId < 0) {
      unawaited(
        client
            .send<td.Ok>(
              td.ViewMessages(chatId: m.chatId, messageIds: [m.id], source: const td.MessageSourceOther(), forceRead: false),
              limited: true,
            )
            .then((_) {}, onError: (_) {}),
      );
    }
    try {
      final props = await client.send<td.MessageProperties>(
        td.GetMessageProperties(chatId: m.chatId, messageId: m.id),
        limited: true,
      );
      if (mounted) setState(() => _props = props);
      if (props.canGetReadDate) {
        final r = await client.send<td.MessageReadDate>(
          td.GetMessageReadDate(chatId: m.chatId, messageId: m.id),
          limited: true,
        );
        final text = switch (r) {
          td.MessageReadDateRead(:final readDate) => DateFormat(
            'EEE d MMM y, HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(readDate * 1000)),
          td.MessageReadDateUnread() => 'Not yet',
          td.MessageReadDateTooOld() => 'Read (too long ago to know when)',
          td.MessageReadDateUserPrivacyRestricted() => 'Hidden by their privacy settings',
          td.MessageReadDateMyPrivacyRestricted() => 'Hidden: your last seen is private',
        };
        if (mounted) setState(() => _readDate = text);
      }
      if (props.canGetViewers) {
        final v = await client.send<td.MessageViewers>(
          td.GetMessageViewers(chatId: m.chatId, messageId: m.id),
          limited: true,
        );
        if (mounted) setState(() => _viewers = v.viewers);
      }
    } catch (_) {}
    if (m.interactionInfo?.reactions?.canGetAddedReactions == true) {
      try {
        final r = await client.send<td.AddedReactions>(
          td.GetMessageAddedReactions(chatId: m.chatId, messageId: m.id, reactionType: null, offset: '', limit: 50),
          limited: true,
        );
        if (mounted) setState(() => _reactors = r.reactions);
      } catch (_) {}
    }
  }

  /// Downloads the picture the person opened; nothing else is fetched.
  Future<void> _download(td.File file) async {
    if (file.local.isDownloadingCompleted && file.local.path.isNotEmpty) {
      if (mounted) setState(() => _imagePath = file.local.path);
      return;
    }
    try {
      final f = await ref
          .read(_account == null ? telegramClientProvider : telegramClientFamily(_account!))
          .send<td.File>(
            td.DownloadFile(
              fileId: file.id,
              priority: 16,
              offset: 0,
              limit: 0,
              synchronous: true,
            ),
            timeout: const Duration(seconds: 60),
          );
      if (mounted && f.local.isDownloadingCompleted)
        setState(() => _imagePath = f.local.path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final account = signedInAccount(accounts, _account);
    final store = account == null ? ref.watch(telegramStoreProvider) : ref.watch(accountStoreProvider(account));
    // Another account than the one on screen: said under the title.
    final fromOther = account != null && account != accounts.activeId ? accounts.byId(account) : null;
    final p = widget.post;
    final m = _message;
    final gist = m == null ? null : gistOf(m.content);
    final chat = store.chat(p.chatId);
    final kind = chat == null ? null : store.kindOf(chat);
    final sender = m == null || kind == ChatKind.channel
        ? p.sender
        : (m.isOutgoing ? 'You' : store.senderName(m.senderId));
    final views = m?.interactionInfo?.viewCount ?? 0;
    final forwards = m?.interactionInfo?.forwardCount ?? 0;
    final comments = m?.interactionInfo?.replyInfo?.replyCount ?? 0;
    final reactions = m?.interactionInfo?.reactions?.reactions ?? const <td.MessageReaction>[];
    final visual =
        m != null &&
        (m.content is td.MessagePhoto || m.content is td.MessageVideo || m.content is td.MessageAnimation);
    final preview = switch (m?.content) {
      td.MessageText(:final linkPreview?) => linkPreview,
      _ => null,
    };
    final full = DateFormat('EEE d MMM y, HH:mm:ss');
    String at(int unix) => full.format(DateTime.fromMillisecondsSinceEpoch(unix * 1000));
    final bodyText = gist?.text.isNotEmpty == true ? gist!.text : p.text;

    return ListView(
      controller: widget.scroll,
      padding: EdgeInsets.fromLTRB(Space.xl, widget.fullPage ? Space.l : 0, Space.xl, Space.x4),
      children: [
        Row(
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.m),
                  onTap: chat == null
                      ? null
                      : () {
                          // The chat's page belongs to its account.
                          final nav = Navigator.of(context);
                          if (account != null) switchToOpen(context, ProviderScope.containerOf(context, listen: false), account);
                          nav.push(MaterialPageRoute<void>(builder: (_) => ChatProfileScreen(chatId: p.chatId)));
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: Space.xs),
                    child: Row(
                      children: [
                        TgAvatar(chatId: p.chatId, title: p.chatTitle, size: 40, accountId: account),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chat?.title ?? p.chatTitle,
                                style: context.text.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                [
                                  if (sender != null && sender.isNotEmpty) sender,
                                  DateFormat(
                                    'EEE d MMM, HH:mm',
                                  ).format(m == null ? p.date : DateTime.fromMillisecondsSinceEpoch(m.date * 1000)),
                                  if ((m?.editDate ?? 0) > 0) 'edited',
                                  if (fromOther != null) 'in ${fromOther.label}',
                                ].join(' · '),
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!widget.fullPage)
              IconButton(
                tooltip: 'Full screen',
                icon: Icon(Icons.open_in_full_rounded, size: 20, color: AppColors.text2),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PostPage(post: p)));
                },
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        if (m?.forwardInfo case final f?) ForwardHeader(origin: f.origin),
        if (m?.content case td.MessageVoiceNote() || td.MessageAudio())
          Padding(
            padding: const EdgeInsets.only(bottom: Space.l),
            child: _PostAudioPlayer(message: m!),
          )
        else if (visual)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.l),
            child: MediaPreview(
              content: m.content,
              onOpen: () => showMediaViewer(context, m.content, title: chat?.title ?? p.chatTitle),
            ),
          )
        else if (m?.content case td.MessageDocument(:final document))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.l),
            child: DocumentRow(document: document),
          )
        else if (m?.content case td.MessageSticker(:final sticker))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.l),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StickerImage(sticker: sticker, size: 180),
            ),
          )
        else if (_imagePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.l),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.m),
              child: Image.file(File(_imagePath!), fit: BoxFit.cover, width: double.infinity),
            ),
          )
        else if (gist != null && gist.isMedia)
          Container(
            margin: const EdgeInsets.only(bottom: Space.l),
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
            child: Row(
              children: [
                Icon(kindIcon(gist.kind), color: AppColors.text2),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    gist.detail?.isNotEmpty == true ? gist.detail! : gist.kind,
                    style: context.text.bodyMedium?.copyWith(color: AppColors.text2),
                  ),
                ),
              ],
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.xxl),
            child: Center(
              child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (gist?.kind == 'poll') ...[
          Text(gist!.text, style: context.text.titleMedium),
          if (gist.detail != null) ...[
            const SizedBox(height: Space.s),
            Text(gist.detail!, style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
          ],
        ] else if (gist?.formatted != null && gist!.formatted!.text.isNotEmpty)
          SelectableText.rich(formattedSpan(gist.formatted!, selectable: true), style: context.text.bodyLarge)
        else if (bodyText.isNotEmpty)
          SelectableText(bodyText, style: context.text.bodyLarge),
        if (preview != null) LinkPreviewCard(preview: preview),
        if (m != null && m.replyMarkup is td.ReplyMarkupInlineKeyboard) BotButtons(message: m),
        if (_error != null) ...[
          const SizedBox(height: Space.l),
          Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
        ],
        if (m != null && reactions.isNotEmpty) MessageReactions(message: m, reactions: reactions),
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.l,
          runSpacing: Space.s,
          children: [
            if (views > 0) _Stat(Icons.visibility_outlined, '${NumberFormat.decimalPattern().format(views)} views'),
            if (forwards > 0) _Stat(Icons.reply_rounded, '${NumberFormat.decimalPattern().format(forwards)} shares'),
            if (comments > 0)
              _Stat(Icons.mode_comment_outlined, '${NumberFormat.decimalPattern().format(comments)} comments'),
            if (reactions.isNotEmpty)
              _Stat(
                Icons.favorite_border_rounded,
                '${NumberFormat.decimalPattern().format(reactions.fold<int>(0, (a, r) => a + r.totalCount))} reactions',
              ),
          ],
        ),
        if (_reactors.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          const _SectionTitle('Who reacted'),
          for (final r in _reactors.take(30))
            _PersonRow(
              account: account,
              sender: r.senderId,
              trailing:
                  '${_reactionLabel(r.type)}  ${DateFormat('d MMM, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.date * 1000))}',
            ),
        ],
        if (_viewers.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          const _SectionTitle('Seen by'),
          for (final v in _viewers.take(30))
            _PersonRow(
              account: account,
              sender: td.MessageSenderUser(userId: v.userId),
              trailing: DateFormat('d MMM, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(v.viewDate * 1000)),
            ),
        ],
        if (m != null) ...[
          const SizedBox(height: Space.l),
          const _SectionTitle('Details'),
          _Detail('Sent', at(m.date)),
          if (m.editDate > 0) _Detail('Last edited', at(m.editDate)),
          if (_readDate != null) _Detail('Read', _readDate!),
          if (m.schedulingState case td.MessageSchedulingStateSendAtDate(:final sendDate))
            _Detail('Scheduled for', at(sendDate)),
          if (m.schedulingState is td.MessageSchedulingStateSendWhenOnline) const _Detail('Scheduled', 'When online'),
          if (kind != ChatKind.channel) _Detail('From', m.isOutgoing ? 'You' : store.senderName(m.senderId)),
          if (m.authorSignature.isNotEmpty) _Detail('Signed', m.authorSignature),
          if (m.viaBotUserId != 0) _Detail('Via', store.senderName(td.MessageSenderUser(userId: m.viaBotUserId))),
          if (m.forwardInfo case final f?) ...[
            _Detail('Forwarded from', _originName(store, f.origin)),
            _Detail('Originally sent', at(f.date)),
          ],
          if (m.replyTo case td.MessageReplyToMessage(:final messageId, :final chatId))
            _Detail(
              'Reply to',
              chatId == m.chatId || chatId == 0
                  ? 'Message $messageId'
                  : 'Message $messageId in ${store.chat(chatId)?.title ?? chatId}',
            ),
          if (m.replyTo case td.MessageReplyToStory(:final storyId)) _Detail('Reply to', 'Story $storyId'),
          if (m.isTopicMessage && m.messageThreadId != 0) _Detail('Topic', 'Thread ${m.messageThreadId}'),
          _Detail('Type', gist?.kind ?? 'message'),
          if (m.mediaAlbumId != 0) const _Detail('Album', 'Part of an album'),
          if (m.isPinned) const _Detail('Pinned', 'Yes'),
          if (m.selfDestructType != null)
            _Detail('Disappears', m.selfDestructIn > 0 ? 'in ${m.selfDestructIn.round()}s' : 'after opening'),
          if (m.autoDeleteIn > 0) _Detail('Auto-deletes', 'in ${_span(m.autoDeleteIn.round())}'),
          if (!m.canBeSaved) const _Detail('Protected', 'Can\'t be forwarded or saved'),
          if (m.restrictionInfo?.hasSensitiveContent == true) const _Detail('Sensitive', 'Marked sensitive'),
          if (m.restrictionReason.isNotEmpty) _Detail('Restricted', m.restrictionReason),
          if (m.factCheck case final fc?) _Detail('Fact check', fc.text.text),
          if (m.containsUnreadMention) const _Detail('Mention', 'Unread mention of you'),
          if (m.unreadReactions.isNotEmpty) _Detail('New reactions', '${m.unreadReactions.length} unread'),
          if (m.sendingState is td.MessageSendingStateFailed) const _Detail('Status', 'Failed to send'),
          if (m.sendingState is td.MessageSendingStatePending) const _Detail('Status', 'Sending…'),
          _Detail('Message ID', '${m.id}', copy: true),
          _Detail('Chat ID', '${m.chatId}', copy: true),
          if (_props case final pr?)
            _Detail(
              'You can',
              [
                if (pr.canBeEdited) 'edit',
                if (pr.canBeForwarded) 'forward',
                if (pr.canBePinned) 'pin',
                if (pr.canBeReplied) 'reply',
                if (pr.canBeDeletedForAllUsers) 'delete for everyone' else if (pr.canBeDeletedOnlyForSelf) 'delete for you',
                if (pr.canGetStatistics) 'see statistics',
              ].join(', '),
            ),
        ],
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            if (bodyText.isNotEmpty)
              _Action(Icons.copy_rounded, 'Copy text', () {
                Clipboard.setData(ClipboardData(text: bodyText));
                showSnack(context, 'Copied', icon: Icons.copy_rounded);
              }),
            if (_link != null)
              _Action(Icons.link_rounded, 'Copy link', () {
                Clipboard.setData(ClipboardData(text: _link!));
                showSnack(context, 'Link copied', icon: Icons.link_rounded);
              }),
            if (_link != null)
              _Action(
                Icons.open_in_new_rounded,
                'Open in Telegram',
                () => launchUrl(Uri.parse(_link!), mode: LaunchMode.externalApplication),
              ),
          ],
        ),
      ],
    );
  }

  static String _span(int s) => s >= 86400
      ? '${s ~/ 86400}d'
      : s >= 3600
      ? '${s ~/ 3600}h'
      : '${s ~/ 60}m';

  static String _reactionLabel(td.ReactionType t) => switch (t) {
    td.ReactionTypeEmoji(:final emoji) => emoji,
    td.ReactionTypePaid() => '⭐',
    _ => '✨',
  };

  static String _originName(TelegramStore store, td.MessageOrigin o) => switch (o) {
    td.MessageOriginUser(:final senderUserId) => store.senderName(td.MessageSenderUser(userId: senderUserId)),
    td.MessageOriginHiddenUser(:final senderName) => '$senderName (hidden account)',
    td.MessageOriginChat(:final senderChatId, :final authorSignature) =>
      '${store.chat(senderChatId)?.title ?? senderChatId}${authorSignature.isEmpty ? '' : ' ($authorSignature)'}',
    td.MessageOriginChannel(:final chatId, :final messageId, :final authorSignature) =>
      '${store.chat(chatId)?.title ?? chatId}, post $messageId${authorSignature.isEmpty ? '' : ' ($authorSignature)'}',
  };

}

/// A full player inside an AI-cited post, backed by the same queue and
/// downloader as Telegram chat rows.
class _PostAudioPlayer extends ConsumerWidget {
  const _PostAudioPlayer({required this.message});
  final td.Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = Track.of(message, ref.read(telegramStoreProvider));
    if (track == null) return const SizedBox.shrink();
    final center = ref.watch(audioCenterProvider);
    final current = center.isCurrent(message.chatId, message.id);
    final progress = current && center.duration.inMilliseconds > 0
        ? (center.position.inMilliseconds / center.duration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: current && center.playing ? 'Pause' : 'Play',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.activeAccent,
              foregroundColor: AppColors.bg,
            ),
            onPressed: () {
              if (current) {
                center.toggle();
              } else {
                center.play(track);
              }
            },
            icon: current && center.loading
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.bg,
                    ),
                  )
                : Icon(
                    current && center.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      track.voice
                          ? Icons.mic_none_rounded
                          : Icons.music_note_rounded,
                      size: 16,
                      color: AppColors.activeAccent,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  track.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Space.s),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(99),
                  color: AppColors.activeAccent,
                  backgroundColor: AppColors.surface3,
                ),
                const SizedBox(height: 3),
                Text(
                  current
                      ? '${formatDuration(center.position.inSeconds)} / ${formatDuration(track.seconds)}'
                      : formatDuration(track.seconds),
                  style: context.text.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: AppColors.text3),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(fontSize: 12.5, color: AppColors.text3),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s),
    child: Text(text.toUpperCase(), style: context.text.labelSmall?.copyWith(letterSpacing: 0.8)),
  );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value, {this.copy = false});
  final String label;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) => InkWell(
    onLongPress: () {
      Clipboard.setData(ClipboardData(text: value));
      showSnack(context, 'Copied', icon: Icons.copy_rounded);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.text3)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13.5, color: AppColors.text)),
          ),
          if (copy) Icon(Icons.copy_rounded, size: 13, color: AppColors.text3),
        ],
      ),
    ),
  );
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({required this.sender, required this.trailing, this.account});
  final td.MessageSender sender;
  final String trailing;

  /// The account the post was read in: names come from there.
  final String? account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = account == null ? ref.watch(telegramStoreProvider) : ref.watch(accountStoreProvider(account!));
    final name = store.senderName(sender);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          switch (sender) {
            td.MessageSenderUser(:final userId) => TgAvatar(userId: userId, title: name, size: 28, accountId: account),
            td.MessageSenderChat(:final chatId) => TgAvatar(chatId: chatId, title: name, size: 28, accountId: account),
          },
          const SizedBox(width: Space.s),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(trailing, style: TextStyle(fontSize: 12.5, color: AppColors.text3)),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.text,
      side: BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
    ),
    icon: Icon(icon, size: 17),
    label: Text(label),
    onPressed: onTap,
  );
}
