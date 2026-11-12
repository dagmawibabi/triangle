import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../infrastructure/telegram/accounts.dart';
import '../../../../infrastructure/telegram/telegram_client.dart';
import '../../../account/account_router.dart';
import '../../../telegram/data/message_content.dart';
import '../../../telegram/presentation/tg_avatar.dart';
import '../../domain/chat_models.dart';
import 'post_viewer.dart' show kindIcon, showPost;

/// The Telegram messages an answer drew on, as a compact list: each one's
/// chat, sender and time, what it said, and what it carries (a photo or
/// video thumbnail, a file's name and size, a voice note's length), with
/// its views and reactions. Numbered in the order the answer cites them;
/// tap one to open it.
class PostSources extends ConsumerStatefulWidget {
  const PostSources({super.key, required this.posts});
  final List<PostSnapshot> posts;

  @override
  ConsumerState<PostSources> createState() => _PostSourcesState();
}

class _PostSourcesState extends ConsumerState<PostSources> {
  static const _shown = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final posts = widget.posts;
    final accounts = ref.watch(accountsProvider);
    final chats = <int, PostSnapshot>{for (final p in posts) p.chatId: p};
    final faces = chats.values.take(3).toList();
    final visible = _all ? posts : posts.take(_shown).toList();
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s),
            child: Row(
              children: [
                Icon(Icons.format_quote_rounded, size: 15, color: AppColors.text3),
                const SizedBox(width: 5),
                Text('Sources', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${posts.length} message${posts.length == 1 ? '' : 's'}${chats.length > 1 ? ' · ${chats.length} chats' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                  ),
                ),
                SizedBox(
                  width: 14.0 * faces.length + 6,
                  height: 20,
                  child: Stack(
                    children: [
                      for (var i = 0; i < faces.length; i++)
                        Positioned(
                          right: 14.0 * i,
                          child: Container(
                            padding: const EdgeInsets.all(1.2),
                            decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                            child: TgAvatar(chatId: faces[i].chatId, title: faces[i].chatTitle, size: 17, accountId: signedInAccount(accounts, faces[i].accountId)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < visible.length; i++) ...[
            Divider(height: 1, color: AppColors.line),
            _SourceRow(key: ValueKey(visible[i].key), post: visible[i], n: i + 1),
          ],
          if (posts.length > _shown) ...[
            Divider(height: 1, color: AppColors.line),
            InkWell(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_all ? 'Show fewer' : 'Show ${posts.length - _shown} more', style: context.text.labelMedium?.copyWith(color: AppColors.text2, fontWeight: FontWeight.w600)),
                    Icon(_all ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: AppColors.text2),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

typedef _Found = ({String account, td.Message? message});

/// Messages already looked up, so scrolling the chat doesn't fetch again.
final _found = <String, Future<_Found>>{};

class _SourceRow extends ConsumerStatefulWidget {
  const _SourceRow({super.key, required this.post, required this.n});
  final PostSnapshot post;
  final int n;

  @override
  ConsumerState<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends ConsumerState<_SourceRow> {
  td.Message? _m;
  String? _account;
  String? _thumb;

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    final container = ProviderScope.containerOf(context, listen: false);
    final future = _found[p.key] ??= findPost(container, p.chatId, p.messageId, hint: p.accountId)
        .then<_Found>((r) => (account: r.account, message: r.message))
        .catchError((Object _) => (account: p.accountId ?? '', message: null));
    future.then((r) {
      if (!mounted) return;
      setState(() {
        _m = r.message;
        _account = r.account.isEmpty ? null : r.account;
      });
      if (r.message != null) _loadThumb(r.message!);
    });
  }

  td.File? _thumbFile(td.MessageContent c) => switch (c) {
    td.MessagePhoto(:final photo) => pickPhotoSize(photo.sizes, minWidth: 160)?.photo,
    td.MessageAudio(:final audio) => audio.albumCoverThumbnail?.file,
    td.MessageText(:final linkPreview) => linkPreview == null ? null : _previewPhoto(linkPreview),
    final other => previewFileOf(other),
  };

  td.File? _previewPhoto(td.LinkPreview l) {
    try {
      final photo = (l.type as dynamic).photo as td.Photo?;
      return photo == null ? null : pickPhotoSize(photo.sizes, minWidth: 160)?.photo;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadThumb(td.Message m) async {
    final file = _thumbFile(m.content);
    if (file == null) return;
    if (file.local.isDownloadingCompleted && file.local.path.isNotEmpty) {
      setState(() => _thumb = file.local.path);
      return;
    }
    try {
      final client = ref.read(_account == null ? telegramClientProvider : telegramClientFamily(_account!));
      final f = await client.send<td.File>(
        td.DownloadFile(fileId: file.id, priority: 4, offset: 0, limit: 0, synchronous: true),
        timeout: const Duration(seconds: 40),
      );
      if (mounted && f.local.isDownloadingCompleted) setState(() => _thumb = f.local.path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final m = _m;
    final accounts = ref.watch(accountsProvider);
    final account = signedInAccount(accounts, _account ?? p.accountId);
    final gist = m == null ? null : gistOf(m.content);
    final kind = gist?.kind ?? p.kind;
    final text = (gist?.text.isNotEmpty == true ? gist!.text : p.text).replaceAll(RegExp(r'\s+'), ' ').trim();
    final who = p.sender != null && p.sender!.trim().isNotEmpty && p.sender != p.chatTitle ? p.sender!.trim() : null;
    // From another account than the one on screen: say which.
    final other = accounts.hasSeveral && account != null && account != accounts.activeId ? accounts.byId(account)?.label : null;
    final attachment = m == null ? null : _attachment(m.content);
    final stats = m == null ? const <Widget>[] : _stats(context, m);
    final mini = m == null ? null : _mini(m.content);
    final visual = _thumb != null || mini != null;

    return InkWell(
      onTap: () => showPost(context, p),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                TgAvatar(chatId: p.chatId, title: p.chatTitle, size: 30, accountId: account),
                Positioned(
                  right: -4,
                  bottom: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 15),
                    height: 15,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.surface, width: 1.5)),
                    child: Text('${widget.n}', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: AppColors.bg, height: 1)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: Space.s + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(p.chatTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2))),
                      Text('  ${_when(p.date)}', style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 11)),
                    ],
                  ),
                  if (who != null || other != null || m?.forwardInfo != null)
                    Text(
                      [
                        ?who,
                        if (m?.forwardInfo != null) 'forwarded',
                        if (other != null) 'in $other',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(color: AppColors.text2, fontSize: 11.5),
                    ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.35, fontSize: 12.5)),
                  ],
                  if (attachment != null || (text.isEmpty && kind != 'text')) ...[
                    const SizedBox(height: 5),
                    attachment ?? _Tag(icon: kindIcon(kind), text: _kindLabel(kind)),
                  ],
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(spacing: Space.s + 2, runSpacing: 2, children: stats),
                  ],
                ],
              ),
            ),
            if (visual) ...[
              const SizedBox(width: Space.s + 2),
              _Thumb(path: _thumb, mini: mini, video: kind == 'video' || kind == 'gif' || kind == 'video_note', duration: m == null ? null : _duration(m.content)),
            ],
          ],
        ),
      ),
    );
  }

  td.Minithumbnail? _mini(td.MessageContent c) => switch (c) {
    td.MessagePhoto(:final photo) => photo.minithumbnail,
    td.MessageVideo(:final video) => video.minithumbnail,
    td.MessageAnimation(:final animation) => animation.minithumbnail,
    td.MessageDocument(:final document) => document.minithumbnail,
    td.MessageAudio(:final audio) => audio.albumCoverMinithumbnail,
    td.MessageVideoNote(:final videoNote) => videoNote.minithumbnail,
    _ => null,
  };

  int? _duration(td.MessageContent c) => switch (c) {
    td.MessageVideo(:final video) => video.duration,
    td.MessageAnimation(:final animation) => animation.duration,
    td.MessageVideoNote(:final videoNote) => videoNote.duration,
    _ => null,
  };

  /// A line for what the message carries, when there's more to say than
  /// its kind: a file's name and size, an audio's title and length.
  Widget? _attachment(td.MessageContent c) => switch (c) {
    td.MessageDocument(:final document) => _Tag(
      icon: Icons.insert_drive_file_outlined,
      text: document.fileName.isEmpty ? 'File' : document.fileName,
      trailing: _size(document.document),
      strong: true,
    ),
    td.MessageAudio(:final audio) => _Tag(
      icon: Icons.music_note_rounded,
      text: [audio.performer, audio.title].where((s) => s.isNotEmpty).join(' – ').ifEmpty(audio.fileName.ifEmpty('Audio')),
      trailing: _clock(audio.duration),
      strong: true,
    ),
    td.MessageVoiceNote(:final voiceNote) => _Tag(icon: Icons.mic_none_rounded, text: 'Voice message', trailing: _clock(voiceNote.duration)),
    td.MessageVideoNote(:final videoNote) => _Tag(icon: Icons.videocam_outlined, text: 'Video message', trailing: _clock(videoNote.duration)),
    td.MessageVideo(:final video) => _Tag(icon: Icons.movie_outlined, text: 'Video', trailing: [_clock(video.duration), ?_size(video.video)].join(' · ')),
    td.MessagePoll(:final poll) => _Tag(icon: Icons.poll_outlined, text: '${poll.options.length} options · ${poll.totalVoterCount} votes'),
    td.MessageText(:final linkPreview?) => _Tag(
      icon: Icons.link_rounded,
      text: [linkPreview.siteName, linkPreview.title].where((s) => s.isNotEmpty).join(' — ').ifEmpty(Uri.tryParse(linkPreview.url)?.host ?? linkPreview.url),
    ),
    td.MessageVenue(:final venue) => _Tag(icon: Icons.place_outlined, text: venue.address.ifEmpty(venue.title)),
    td.MessageContact(:final contact) => _Tag(icon: Icons.person_outline_rounded, text: contact.phoneNumber),
    _ => null,
  };

  List<Widget> _stats(BuildContext context, td.Message m) {
    final info = m.interactionInfo;
    if (info == null) return const [];
    final reactions = info.reactions?.reactions ?? const <td.MessageReaction>[];
    final total = reactions.fold<int>(0, (n, r) => n + r.totalCount);
    final top = reactions.take(3).map((r) => r.type is td.ReactionTypeEmoji ? (r.type as td.ReactionTypeEmoji).emoji : '').join();
    Widget stat(IconData? icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: AppColors.text3), const SizedBox(width: 3)],
        Text(text, style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 11)),
      ],
    );
    final replies = info.replyInfo?.replyCount ?? 0;
    return [
      if (info.viewCount > 0) stat(Icons.visibility_outlined, _compact(info.viewCount)),
      if (total > 0) stat(null, '${top.isEmpty ? '♥' : top} ${_compact(total)}'),
      if (replies > 0) stat(Icons.chat_bubble_outline_rounded, _compact(replies)),
      if (info.forwardCount > 0) stat(Icons.shortcut_rounded, _compact(info.forwardCount)),
    ];
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text, this.trailing, this.strong = false});
  final IconData icon;
  final String text;
  final String? trailing;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s), border: Border.all(color: AppColors.line)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.text2),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(fontSize: 11.5, color: strong ? AppColors.text : AppColors.text2, fontWeight: strong ? FontWeight.w600 : FontWeight.w500),
          ),
        ),
        if (trailing != null && trailing!.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(trailing!, style: context.text.labelSmall?.copyWith(fontSize: 11, color: AppColors.text3, fontFeatures: tabularFigures)),
        ],
      ],
    ),
  );
}

/// The picture a message carries, small: the blurred inline preview first,
/// then the real thumbnail, with a play mark and length on videos.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.mini, required this.video, this.duration});
  final String? path;
  final td.Minithumbnail? mini;
  final bool video;
  final int? duration;

  @override
  Widget build(BuildContext context) {
    Widget? image;
    if (path != null) {
      image = Image.file(File(path!), fit: BoxFit.cover, cacheWidth: 180, gaplessPlayback: true);
    } else if (mini != null) {
      try {
        image = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Image.memory(base64Decode(mini!.data), fit: BoxFit.cover, gaplessPlayback: true),
        );
      } catch (_) {}
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.m),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.surface2),
            ?image,
            if (video)
              Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                ),
              ),
            if (duration != null && duration! > 0)
              Positioned(
                right: 3,
                bottom: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                  child: Text(_clock(duration!), style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

String? _size(td.File f) {
  final b = f.size > 0 ? f.size : f.expectedSize;
  if (b <= 0) return null;
  if (b < 1024) return '$b B';
  if (b < 1 << 20) return '${(b / 1024).round()} KB';
  if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
}

String _clock(int s) => s >= 3600 ? '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

String _compact(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)}M' : (n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K' : '$n');

String _when(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat(d.year == DateTime.now().year ? 'd MMM' : 'd MMM y').format(d);
}

String _kindLabel(String kind) => switch (kind) {
  'photo' => 'Photo',
  'video' => 'Video',
  'video_note' => 'Video message',
  'gif' => 'GIF',
  'document' => 'File',
  'audio' => 'Audio',
  'voice' => 'Voice message',
  'poll' => 'Poll',
  'location' => 'Location',
  'sticker' => 'Sticker',
  'contact' => 'Contact',
  _ => 'Message',
};
