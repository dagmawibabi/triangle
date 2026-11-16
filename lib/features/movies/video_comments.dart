import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../telegram/data/message_content.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/presentation/chat_profile_screen.dart';
import '../telegram/presentation/formatted_text.dart';
import '../telegram/presentation/tg_avatar.dart';

import '../sections/skeletons.dart';
// The comments under a channel's post (its discussion group's thread), as
// a small card under a video and a sheet to read, reply and react.

/// A post's comment thread, read once and kept while the app runs.
class CommentThread {
  CommentThread({required this.account, required this.chatId, required this.threadId, required this.postChatId, required this.postId, required this.count, required this.messages, required this.next});
  final String account;

  /// The discussion group and the thread in it.
  final int chatId;
  final int threadId;

  /// The post itself.
  final int postChatId;
  final int postId;
  int count;

  /// Newest first.
  final List<td.Message> messages;

  /// Where the next (older) page starts; 0 when there is none.
  int next;
}

final _threads = <String, Future<CommentThread?>>{};

String _key(String account, int chatId, int messageId) => '$account:$chatId:$messageId';

/// Whether this post's comments were already asked for this run (then
/// there's no reason to wait before showing them).
bool commentsAsked(String account, int chatId, int messageId) => _threads.containsKey(_key(account, chatId, messageId));

/// Each post's thread as last loaded (where it lives, its count and the
/// comments' ids), kept on the device. The comments themselves come back
/// from TDLib's own store by id, so a post opened again shows its
/// comments at once, before Telegram is asked for what's new.
class _CommentMemory {
  static const _max = 300;
  static Map<String, Map<String, Object?>>? _all;
  static Future<Map<String, Map<String, Object?>>>? _reading;
  static Timer? _pending;

  static Future<File> _file() async => File('${(await getApplicationCacheDirectory()).path}/feeds/comments.json');

  static Future<Map<String, Map<String, Object?>>> _load() async => _all ?? await (_reading ??= () async {
    final out = <String, Map<String, Object?>>{};
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          for (final e in j.entries) {
            if (e.value is Map) out['${e.key}'] = Map<String, Object?>.from(e.value as Map);
          }
        }
      }
    } catch (e) {
      debugPrint('[Comments] memory read: $e');
    }
    return _all = out;
  }());

  static Future<Map<String, Object?>?> get(String key) async => (await _load())[key];

  static Future<void> put(String key, CommentThread t) async {
    final all = await _load();
    // Newest last; the oldest posts fall off past [_max].
    all.remove(key);
    all[key] = {'chat': t.chatId, 'thread': t.threadId, 'count': t.count, 'next': t.next, 'ids': [for (final m in t.messages.take(50)) m.id]};
    while (all.length > _max) {
      all.remove(all.keys.first);
    }
    _pending?.cancel();
    _pending = Timer(const Duration(seconds: 2), () async {
      try {
        final f = await _file();
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode(all));
      } catch (e) {
        debugPrint('[Comments] memory write: $e');
      }
    });
  }
}

/// The comments [chatId]/[messageId] showed last time, from the device
/// only (no request to Telegram's servers); null when none are kept.
Future<CommentThread?> cachedComments(WidgetRef ref, String account, int chatId, int messageId) async {
  try {
    final e = await _CommentMemory.get(_key(account, chatId, messageId));
    if (e == null) return null;
    final ids = [for (final x in (e['ids'] as List? ?? const [])) if (x is num) x.toInt()];
    final discussion = (e['chat'] as num?)?.toInt() ?? 0;
    final client = ref.read(telegramClientFamily(account));
    final list = ids.isEmpty || discussion == 0
        ? const <td.Message>[]
        : [for (final m in (await client.send<td.Messages>(td.GetMessages(chatId: discussion, messageIds: ids)).timeout(const Duration(seconds: 5))).messages) m];
    await ref.read(telegramStoreFamily(account)).ensureSenders([for (final m in list) m.senderId]).timeout(const Duration(seconds: 2), onTimeout: () {});
    return CommentThread(
      account: account,
      chatId: discussion,
      threadId: (e['thread'] as num?)?.toInt() ?? 0,
      postChatId: chatId,
      postId: messageId,
      count: (e['count'] as num?)?.toInt() ?? list.length,
      messages: list,
      next: (e['next'] as num?)?.toInt() ?? 0,
    );
  } catch (e) {
    debugPrint('[Comments] recall: $e');
    return null;
  }
}

/// The comments of [chatId]/[messageId]; null when the post has none on.
/// Throws when they couldn't be loaded (offline, slow), so the caller can
/// offer to try again; failures aren't kept. What loads is kept on the
/// device for [cachedComments].
Future<CommentThread?> loadComments(WidgetRef ref, String account, int chatId, int messageId, {bool fresh = false}) {
  final key = _key(account, chatId, messageId);
  if (fresh) _threads.remove(key);
  return _threads[key] ??= () async {
    final client = ref.read(telegramClientFamily(account));
    try {
      // What the post says about its thread, from the device. Only a hint:
      // posts that came from a search often don't carry their reply info
      // yet, so a "no" here doesn't settle it; Telegram is asked anyway.
      final (post, props) = await (
        client.send<td.Message>(td.GetMessage(chatId: chatId, messageId: messageId)).then<td.Message?>((m) => m, onError: (_) => null),
        client.send<td.MessageProperties>(td.GetMessageProperties(chatId: chatId, messageId: messageId)).then<td.MessageProperties?>((p) => p, onError: (_) => null),
      ).wait.timeout(const Duration(seconds: 10), onTimeout: () => (null, null));
      final saysThread = (props?.canGetMessageThread ?? false) || post?.interactionInfo?.replyInfo != null;
      td.MessageThreadInfo? info;
      // Said to have one: a "not found" is the thread still on its way, so
      // try again. Not said: one answer is enough.
      for (var attempt = 0; attempt < (saysThread ? 3 : 1) && info == null; attempt++) {
        try {
          info = await client.send<td.MessageThreadInfo>(td.GetMessageThread(chatId: chatId, messageId: messageId), limited: true).timeout(const Duration(seconds: 15));
        } catch (e) {
          final off = RegExp(r'MSG_ID_INVALID|not found|can.t get message thread|Message has no thread|thread not found', caseSensitive: false).hasMatch('$e');
          if (!saysThread && off) return null;
          if (!saysThread) rethrow;
          if (attempt < 2) await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
        }
      }
      if (info == null) throw 'Couldn’t reach the comments';
      final page = await client
          .send<td.Messages>(td.GetMessageThreadHistory(chatId: chatId, messageId: messageId, fromMessageId: 0, offset: 0, limit: 50), limited: true)
          .timeout(const Duration(seconds: 15));
      final list = [for (final m in page.messages) if (m.id != info.messageThreadId) m];
      // Names and pictures: a short wait at most; they fill in as they come.
      await ref.read(telegramStoreFamily(account)).ensureSenders([for (final m in list) m.senderId]).timeout(const Duration(seconds: 3), onTimeout: () {});
      final t = CommentThread(
        account: account,
        chatId: info.chatId,
        threadId: info.messageThreadId,
        postChatId: chatId,
        postId: messageId,
        count: info.replyInfo?.replyCount ?? post?.interactionInfo?.replyInfo?.replyCount ?? list.length,
        messages: list,
        next: list.length < 20 ? 0 : list.last.id,
      );
      unawaited(_CommentMemory.put(key, t));
      return t;
    } catch (e) {
      debugPrint('[Comments] $e');
      _threads.remove(key);
      rethrow;
    }
  }();
}

/// The small card under a video's description: how many comments and the
/// newest one. Tapping opens the sheet.
class CommentsPreview extends ConsumerStatefulWidget {
  const CommentsPreview({super.key, required this.account, required this.chatId, required this.messageId});
  final String account;
  final int chatId;
  final int messageId;

  @override
  ConsumerState<CommentsPreview> createState() => _CommentsPreviewState();
}

class _CommentsPreviewState extends ConsumerState<CommentsPreview> {
  /// How long after a video opens its comments are asked for: the video
  /// gets the connection to itself to start, then the comments follow.
  static const _delay = Duration(seconds: 3);

  CommentThread? _t;
  bool _failed = false;

  /// Telegram says this post has no comments.
  bool _none = false;
  Timer? _wait;

  /// Bumped for each post shown, so a late answer for another is dropped.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(CommentsPreview old) {
    super.didUpdateWidget(old);
    if (old.messageId != widget.messageId || old.chatId != widget.chatId || old.account != widget.account) _start();
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  /// Last time's comments at once, from the device; then, a moment after
  /// the video has started (at once when already asked this run), what's
  /// new from Telegram.
  void _start() {
    final gen = ++_gen;
    _wait?.cancel();
    _t = null;
    _failed = false;
    _none = false;
    cachedComments(ref, widget.account, widget.chatId, widget.messageId).then((c) {
      if (mounted && gen == _gen && c != null && _t == null && !_none) setState(() => _t = c);
    });
    if (commentsAsked(widget.account, widget.chatId, widget.messageId)) {
      _fetch(gen);
    } else {
      _wait = Timer(_delay, () => _fetch(gen));
    }
  }

  Future<void> _fetch(int gen, {bool fresh = false}) async {
    try {
      final t = await loadComments(ref, widget.account, widget.chatId, widget.messageId, fresh: fresh);
      if (!mounted || gen != _gen) return;
      setState(() {
        _t = t;
        _none = t == null;
        _failed = false;
      });
    } catch (_) {
      // Kept comments stay up when the refresh fails.
      if (mounted && gen == _gen) setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _fetch(_gen, fresh: true);
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      final t = _t;
      final failed = _failed && t == null;
      final loading = t == null && !_failed && !_none;
      if (_none) return const SizedBox.shrink();
      final first = t?.messages.firstOrNull;
      final store = ref.read(telegramStoreFamily(widget.account));
      final faces = <td.MessageSender>[];
      final seen = <String>{};
      for (final m in t?.messages ?? const <td.Message>[]) {
        if (seen.add('${m.senderId.toJson()}')) faces.add(m.senderId);
        if (faces.length == 3) break;
      }
      return Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: failed
              ? _retry
              : (t == null ? null : () => showCommentsSheet(context, account: widget.account, chatId: widget.chatId, messageId: widget.messageId).then((_) => _fetch(_gen))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Comments', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    if (t != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(99)),
                        child: Text('${t.count}', style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                    const Spacer(),
                    if (faces.length > 1)
                      SizedBox(
                        width: 18.0 * faces.length + 6,
                        height: 24,
                        child: Stack(
                          children: [
                            for (final (i, f) in faces.indexed)
                              Positioned(
                                left: i * 18.0,
                                child: Container(
                                  padding: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
                                  child: SenderAvatar(account: widget.account, sender: f, title: store.senderName(f), size: 21),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Icon(failed ? Icons.refresh_rounded : Icons.unfold_more_rounded, size: 18, color: AppColors.text3),
                  ],
                ),
                const SizedBox(height: Space.s),
                if (loading)
                  Row(
                    children: [
                      Container(width: 26, height: 26, decoration: BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle)),
                      const SizedBox(width: Space.s),
                      Expanded(child: Container(height: 12, decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(6)))),
                      const SizedBox(width: 60),
                    ],
                  )
                else if (failed)
                  Text('Couldn’t load the comments — tap to try again', style: context.text.bodySmall?.copyWith(color: AppColors.text3))
                else if (first == null)
                  Text('No comments yet — be the first', style: context.text.bodySmall?.copyWith(color: AppColors.text3))
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SenderAvatar(account: widget.account, sender: first.senderId, title: store.senderName(first.senderId), size: 26),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${store.senderName(first.senderId)}  ', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text2)),
                              TextSpan(text: gistOf(first.content).text),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(color: AppColors.text, height: 1.35),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A comment's author's picture: a person's profile photo, or the chat's
/// when a channel or group wrote it.
class SenderAvatar extends StatelessWidget {
  const SenderAvatar({super.key, required this.account, required this.sender, required this.title, this.size = 34});
  final String account;
  final td.MessageSender sender;
  final String title;
  final double size;

  @override
  Widget build(BuildContext context) => switch (sender) {
    td.MessageSenderUser(:final userId) => TgAvatar(userId: userId, accountId: account, title: title, size: size),
    td.MessageSenderChat(:final chatId) => TgAvatar(chatId: chatId, accountId: account, title: title, size: size),
  };
}

/// Opens the profile of whoever wrote a comment.
Future<void> openSender(BuildContext context, WidgetRef ref, String account, td.MessageSender sender) async {
  final nav = Navigator.of(context);
  try {
    final chatId = switch (sender) {
      td.MessageSenderChat(:final chatId) => chatId,
      td.MessageSenderUser(:final userId) =>
        (await ref.read(telegramClientFamily(account)).send<td.Chat>(td.CreatePrivateChat(userId: userId, force: false), limited: true)).id,
    };
    if (nav.mounted) await nav.push(MaterialPageRoute<void>(builder: (_) => ChatProfileScreen(chatId: chatId)));
  } catch (_) {
    if (context.mounted) showSnack(context, 'Couldn’t open that profile', icon: Icons.error_outline_rounded);
  }
}

/// The comments sheet: comments with their replies folded under them,
/// hearts, replying, and writing a comment.
Future<void> showCommentsSheet(BuildContext context, {required String account, required int chatId, required int messageId}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.surface,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
  builder: (_) => _CommentsSheet(account: account, chatId: chatId, messageId: messageId),
);

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.account, required this.chatId, required this.messageId});
  final String account;
  final int chatId;
  final int messageId;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  CommentThread? _t;
  bool _loading = true;
  String? _error;

  /// Top (most hearts and replies) or newest first.
  bool _top = true;
  bool _more = false;
  bool _sending = false;
  td.Message? _replyTo;
  final _open = <int>{};
  final _text = TextEditingController();
  final _focus = FocusNode();

  /// Hearts given or taken here, over what the message says.
  final _hearted = <int, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load({bool fresh = false}) async {
    if (fresh) setState(() => _loading = _t == null);
    // Last time's comments first, while Telegram is asked for what's new.
    if (_t == null) {
      final kept = await cachedComments(ref, widget.account, widget.chatId, widget.messageId);
      if (mounted && kept != null && _t == null) {
        setState(() {
          _t = kept;
          _loading = false;
        });
      }
    }
    try {
      final t = await loadComments(ref, widget.account, widget.chatId, widget.messageId, fresh: fresh);
      if (mounted) {
        setState(() {
          _t = t;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final t = _t;
    if (t == null || t.next == 0 || _more) return;
    setState(() => _more = true);
    try {
      final page = await ref.read(telegramClientFamily(widget.account)).send<td.Messages>(
        td.GetMessageThreadHistory(chatId: t.postChatId, messageId: t.postId, fromMessageId: t.next, offset: 0, limit: 50),
        limited: true,
      ).timeout(const Duration(seconds: 15));
      final have = {for (final m in t.messages) m.id};
      final fresh = [for (final m in page.messages) if (m.id != t.threadId && have.add(m.id)) m];
      await ref.read(telegramStoreFamily(widget.account)).ensureSenders([for (final m in fresh) m.senderId]);
      t.messages.addAll(fresh);
      t.next = fresh.isEmpty ? 0 : fresh.last.id;
    } catch (_) {}
    if (mounted) setState(() => _more = false);
  }

  int? _parentOf(td.Message m) {
    final r = m.replyTo;
    if (r is td.MessageReplyToMessage && r.messageId != _t?.threadId) return r.messageId;
    return null;
  }

  bool _isHearted(td.Message m) => _hearted[m.id] ?? (m.interactionInfo?.reactions?.reactions.any((r) => r.isChosen) ?? false);

  int _hearts(td.Message m) {
    final base = m.interactionInfo?.reactions?.reactions.fold<int>(0, (a, r) => a + r.totalCount) ?? 0;
    final was = m.interactionInfo?.reactions?.reactions.any((r) => r.isChosen) ?? false;
    final now = _isHearted(m);
    return base + (now == was ? 0 : (now ? 1 : -1));
  }

  Future<void> _heart(td.Message m) async {
    final on = !_isHearted(m);
    setState(() => _hearted[m.id] = on);
    final client = ref.read(telegramClientFamily(widget.account));
    const heart = td.ReactionTypeEmoji(emoji: '❤');
    try {
      if (on) {
        await client.send<td.Ok>(td.AddMessageReaction(chatId: m.chatId, messageId: m.id, reactionType: heart, isBig: false, updateRecentReactions: true), limited: true);
      } else {
        // Takes back whichever reaction was ours.
        final mine = m.interactionInfo?.reactions?.reactions.where((r) => r.isChosen).firstOrNull?.type ?? heart;
        await client.send<td.Ok>(td.RemoveMessageReaction(chatId: m.chatId, messageId: m.id, reactionType: mine), limited: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hearted.remove(m.id));
        showSnack(context, 'This group doesn’t allow that reaction', icon: Icons.heart_broken_outlined);
      }
    }
  }

  Future<void> _send() async {
    final t = _t;
    final text = _text.text.trim();
    if (t == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final m = await ref.read(telegramClientFamily(widget.account)).send<td.Message>(
        td.SendMessage(
          chatId: t.chatId,
          topicId: td.MessageTopicThread(messageThreadId: t.threadId),
          replyTo: td.InputMessageReplyToMessage(messageId: _replyTo?.id ?? t.threadId, checklistTaskId: 0, pollOptionId: ''),
          inputMessageContent: td.InputMessageText(text: td.FormattedText(text: text, entities: const []), clearDraft: true),
        ),
        limited: true,
      );
      setState(() {
        t.messages.insert(0, m);
        t.count++;
        if (_replyTo != null) _open.add(_replyTo!.id);
        _replyTo = null;
        _text.clear();
      });
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn’t send: $e', icon: Icons.error_outline_rounded);
    }
    if (mounted) setState(() => _sending = false);
  }

  Widget _comment(td.Message m, {bool reply = false, int replies = 0}) {
    final store = ref.read(telegramStoreFamily(widget.account));
    final name = store.senderName(m.senderId);
    final content = m.content;
    final formatted = content is td.MessageText ? content.text : null;
    final hearted = _isHearted(m);
    final hearts = _hearts(m);
    return Padding(
      padding: EdgeInsets.fromLTRB(reply ? 56 : Space.l, reply ? Space.xs : Space.m, Space.s, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => openSender(context, ref, widget.account, m.senderId),
            child: SenderAvatar(account: widget.account, sender: m.senderId, title: name, size: reply ? 26 : 34),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name.isEmpty ? 'Someone' : name,
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text2, fontSize: 12.5),
                        recognizer: TapGestureRecognizer()..onTap = () => openSender(context, ref, widget.account, m.senderId),
                      ),
                      TextSpan(text: '  ${_ago(m.date)}', style: TextStyle(color: AppColors.text3, fontSize: 11.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  formatted != null ? formattedSpan(formatted) : TextSpan(text: gistOf(content).text),
                  style: context.text.bodyMedium?.copyWith(height: 1.35, color: AppColors.text),
                ),
                Row(
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, minimumSize: const Size(0, 30), foregroundColor: AppColors.text3),
                      onPressed: () {
                        setState(() => _replyTo = m);
                        _focus.requestFocus();
                      },
                      child: const Text('Reply', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                    if (replies > 0) ...[
                      const SizedBox(width: Space.m),
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, minimumSize: const Size(0, 30), foregroundColor: AppColors.text2),
                        onPressed: () => setState(() => _open.contains(m.id) ? _open.remove(m.id) : _open.add(m.id)),
                        child: Text(_open.contains(m.id) ? 'Hide replies' : 'View $replies ${replies == 1 ? 'reply' : 'replies'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          InkResponse(
            onTap: () => _heart(m),
            radius: 22,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(
                      hearted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      key: ValueKey(hearted),
                      size: 18,
                      color: hearted ? (AppLook.minimalExplore ? AppColors.text : const Color(0xFFFF4D6D)) : AppColors.text3,
                    ),
                  ),
                  if (hearts > 0) Text('$hearts', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final height = MediaQuery.sizeOf(context).height * 0.78;
    final all = t?.messages ?? const <td.Message>[];
    final ids = {for (final m in all) m.id};
    final children = <int, List<td.Message>>{};
    final tops = <td.Message>[];
    for (final m in all) {
      final p = _parentOf(m);
      if (p != null && ids.contains(p)) {
        children.putIfAbsent(p, () => []).add(m);
      } else {
        tops.add(m);
      }
    }
    // Replies read oldest first under their comment.
    for (final l in children.values) {
      l.sort((a, b) => a.date.compareTo(b.date));
    }
    if (_top) {
      int score(td.Message m) => _hearts(m) * 2 + (children[m.id]?.length ?? 0) * 3;
      tops.sort((a, b) {
        final d = score(b).compareTo(score(a));
        return d != 0 ? d : b.date.compareTo(a.date);
      });
    }
    final store = ref.read(telegramStoreFamily(widget.account));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: Space.s),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99))),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.s),
              child: Row(
                children: [
                  Text('Comments', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  if (t != null) Text('${t.count}', style: context.text.bodyMedium?.copyWith(color: AppColors.text3)),
                  const Spacer(),
                  if (tops.length > 2)
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      segments: const [ButtonSegment(value: true, label: Text('Top')), ButtonSegment(value: false, label: Text('Newest'))],
                      selected: {_top},
                      onSelectionChanged: (v) => setState(() => _top = v.first),
                    ),
                  IconButton(tooltip: 'Refresh', icon: Icon(Icons.refresh_rounded, color: AppColors.text2), onPressed: () => _load(fresh: true)),
                  IconButton(tooltip: 'Close', icon: Icon(Icons.close_rounded, color: AppColors.text2), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.line),
            Expanded(
              child: _loading
                  ? const SingleChildScrollView(child: SkeletonRows(count: 7, art: 34, artRadius: 99, lines: 2))
                  : _error != null && t == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 36, color: AppColors.text3),
                          const SizedBox(height: Space.s),
                          Text('Couldn’t load the comments', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: Space.s),
                          OutlinedButton.icon(onPressed: () => _load(fresh: true), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
                        ],
                      ),
                    )
                  : t == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.comments_disabled_outlined, size: 36, color: AppColors.text3),
                          const SizedBox(height: Space.s),
                          Text('Comments are off for this post', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                        ],
                      ),
                    )
                  : tops.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, size: 36, color: AppColors.text3),
                          const SizedBox(height: Space.s),
                          Text('No comments yet', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text('Start the conversation', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                        ],
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.extentAfter < 400) _loadMore();
                        return false;
                      },
                      child: RefreshIndicator(
                        onRefresh: () => _load(fresh: true),
                        child: ListView(
                        padding: const EdgeInsets.only(bottom: Space.l),
                        children: [
                          for (final m in tops) ...[
                            _comment(m, replies: children[m.id]?.length ?? 0),
                            if (_open.contains(m.id))
                              for (final r in children[m.id] ?? const <td.Message>[]) _comment(r, reply: true),
                          ],
                          if (_more) const Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                        ],
                      ),
                      ),
                    ),
            ),
            if (t != null) ...[
              Divider(height: 1, color: AppColors.line),
              if (_replyTo != null)
                Container(
                  color: AppColors.surface2,
                  padding: const EdgeInsets.fromLTRB(Space.l, 6, Space.xs, 6),
                  child: Row(
                    children: [
                      Icon(Icons.reply_rounded, size: 16, color: AppColors.text3),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to ${store.senderName(_replyTo!.senderId)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(color: AppColors.text2, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.close_rounded, size: 18, color: AppColors.text3), onPressed: () => setState(() => _replyTo = null)),
                    ],
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.s, Space.s),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: _replyTo == null ? 'Add a comment…' : 'Add a reply…',
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.surface2,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 10),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: AppColors.text, foregroundColor: AppColors.bg, disabledBackgroundColor: AppColors.surface3),
                        icon: _sending ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg)) : const Icon(Icons.arrow_upward_rounded),
                        onPressed: _text.text.trim().isEmpty ? null : _send,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _ago(int unix) {
  final e = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(unix * 1000));
  if (e.inMinutes < 1) return 'now';
  if (e.inHours < 1) return '${e.inMinutes}m';
  if (e.inDays < 1) return '${e.inHours}h';
  if (e.inDays < 7) return '${e.inDays}d';
  if (e.inDays < 365) return '${e.inDays ~/ 7}w';
  return '${e.inDays ~/ 365}y';
}
