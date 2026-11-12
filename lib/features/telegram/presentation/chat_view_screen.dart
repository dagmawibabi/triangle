import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/open_chats.dart';
import '../../chat/data/chat_controller.dart';
import '../../chat/domain/chat_models.dart';
import '../../media/audio_center.dart';
import '../../media/audio_player_ui.dart';
import '../../settings/data/settings.dart';
import '../../voice/dictation.dart';
import '../../voice/voice_note_recorder.dart';
import '../data/content_filters.dart';
import '../data/message_content.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'attach_sheet.dart';
import 'chat_actions.dart';
import 'chat_background.dart';
import 'chat_pages.dart';
import 'expression_panel.dart';
import 'chat_profile_screen.dart';
import 'content_canvas_screen.dart' show saveManyToCanvas;
import 'direct_messages_topics.dart';
import 'pending_draft.dart';
import 'forum_topics.dart';
import 'forward_sheet.dart';
import 'hidden_message.dart';
import 'members_screen.dart';
import 'message_tile.dart';
import 'tg_avatar.dart';
import '../../../infrastructure/telegram/td_compat.dart';

/// A chat's messages, live, with a composer for writing yourself. Opening
/// it doesn't mark anything as read (unless that setting is on): it reads
/// history, and views messages only with a source TDLib doesn't read on.
/// With [threadId] it shows one forum topic.
class ChatViewScreen extends ConsumerStatefulWidget {
  const ChatViewScreen({
    super.key,
    required this.chatId,
    this.threadId,
    this.threadTitle,
    this.generalTopic = false,
    this.commentsOn,
    this.initialReply,
    this.openAt,
  });

  /// A message to scroll to and light up once the chat opens: the original
  /// of a reply or quote tapped in another chat.
  final int? openAt;
  final int chatId;

  /// A reply to start with: a message (from this chat or another) and the
  /// words of it to quote. From "Reply in another chat".
  final ({td.Message message, String? quote})? initialReply;

  /// Shows the comments under this channel post: [chatId] is then the
  /// channel's discussion group and [threadId] the post's thread there.
  final td.Message? commentsOn;
  final int? threadId;
  final String? threadTitle;

  /// A forum's General topic: the chat's messages that belong to no topic.
  final bool generalTopic;

  @override
  ConsumerState<ChatViewScreen> createState() => _ChatViewScreenState();
}

class _ChatViewScreenState extends ConsumerState<ChatViewScreen> {
  final List<td.Message> _messages = [];

  /// One key per post (an album's messages share it), to scroll to a
  /// replied-to or quoted message.
  final Map<int, GlobalKey> _postKeys = {};
  GlobalKey _keyFor(int id) => _postKeys[id] ??= GlobalKey();

  /// The post just jumped to, lit up for a moment.
  int? _highlight;
  Timer? _highlightClock;
  final _scroll = ScrollController();
  StreamSubscription<td.TdObject>? _updates;
  bool _loading = false;
  bool _end = false;
  String? _error;
  td.Message? _replyTo;

  /// The words of [_replyTo] being quoted, when replying to part of it.
  String? _quote;

  /// Takes the reply being written to another chat, chosen from a list.
  Future<void> _replyElsewhere() async {
    final reply = _replyTo;
    if (reply == null) return;
    final to = await pickChat(context, title: _quote == null ? 'Reply in another chat' : 'Quote in another chat');
    if (to == null || !mounted) return;
    final quote = _quote;
    setState(() => _replyTo = _quote = null);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatViewScreen(chatId: to, initialReply: (message: reply, quote: quote)),
    ));
  }

  /// Messages picked in selection mode, by id.
  final Set<int> _selected = {};

  /// Hidden posts (blocked sender, blocked channel, muted word) tapped open,
  /// by their first message's id.
  final Set<int> _revealed = {};
  bool get _selecting => _selected.isNotEmpty;

  void _toggle(td.Message m) => setState(() => _selected.contains(m.id) ? _selected.remove(m.id) : _selected.add(m.id));

  List<td.Message> get _picked =>
      _messages.where((m) => _selected.contains(m.id)).toList()..sort((a, b) => a.id.compareTo(b.id));
  final Map<String, _LiveChatActivity> _activities = {};
  Timer? _activityExpiry;
  Timer? _reactionsClock;
  final Object _openChatOwner = Object();

  /// The chat's pinned messages, newest first, for the bar under the
  /// header; [_pinIndex] is the one it shows.
  List<td.Message> _pins = const [];
  int _pinIndex = 0;
  Timer? _pinsClock;

  bool get _showsPins => widget.threadId == null && widget.commentsOn == null && !widget.generalTopic;

  Future<void> _loadPins() async {
    if (!_showsPins) return;
    try {
      final pins = await loadPinned(ref.read(telegramClientProvider), widget.chatId);
      if (!mounted) return;
      setState(() {
        final shown = _pins.isEmpty ? null : _pins[_pinIndex.clamp(0, _pins.length - 1)].id;
        _pins = pins;
        final keep = shown == null ? -1 : pins.indexWhere((m) => m.id == shown);
        _pinIndex = keep < 0 ? 0 : keep;
      });
    } catch (e) {
      debugPrint('[Chat] pinned: $e');
    }
  }

  /// Goes to the pinned message shown, then shows the one before it, the
  /// way Telegram's pinned bar walks back through them.
  void _tapPin() {
    if (_pins.isEmpty) return;
    final m = _pins[_pinIndex.clamp(0, _pins.length - 1)];
    unawaited(_jumpTo(m.id));
    setState(() => _pinIndex = (_pinIndex + 1) % _pins.length);
  }

  Future<void> _openPinned() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => ChatPinnedScreen(chatId: widget.chatId, initial: _pins)),
    );
    if (id != null && mounted) {
      final i = _pins.indexWhere((m) => m.id == id);
      if (i >= 0) setState(() => _pinIndex = i);
      unawaited(_jumpTo(id));
    }
  }

  void _openScheduled() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ChatScheduledScreen(chatId: widget.chatId)),
  );

  /// The oldest message fetched, which can be older than the oldest shown
  /// when the General topic filters topic messages out.
  int? _oldest;

  bool get _isForumRoot {
    final store = ref.read(telegramStoreProvider);
    final chat = store.chat(widget.chatId);
    return widget.threadId == null &&
        !widget.generalTopic &&
        chat != null &&
        (store.isForum(chat) || store.isDirectMessagesGroup(chat));
  }

  @override
  void initState() {
    super.initState();
    _replyTo = widget.initialReply?.message;
    _quote = widget.initialReply?.quote;
    if (widget.openAt case final id?) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(id));
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
      // The arrow down shows once you've scrolled a screen or so up.
      final away = _scroll.position.pixels > 400;
      if (away != _scrolledUp) {
        setState(() {
          _scrolledUp = away;
          if (!away) _newBelow = 0;
        });
      }
    });
    _updates = ref.read(telegramClientProvider).updates.listen(_onUpdate);
    unawaited(_openForLiveUpdates());
    // Counts and reactions keep moving on busy channels.
    _reactionsClock = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_messages.isNotEmpty) unawaited(_refreshInteractions(_messages.take(30).toList()));
    });
    if (ref.read(settingsProvider).markReadOnOpen) {
      final chat = ref.read(telegramStoreProvider).chat(widget.chatId);
      if (chat != null && chat.hasUnread) unawaited(ref.read(toolRunnerProvider).markRead(chat).catchError((_) {}));
    }
    if (!_isForumRoot) {
      _loadMore();
      unawaited(_loadPins());
    }
  }

  @override
  void dispose() {
    _updates?.cancel();
    _activityExpiry?.cancel();
    _reactionsClock?.cancel();
    _highlightClock?.cancel();
    _pinsClock?.cancel();
    unawaited(ref.read(openChatsProvider).release(widget.chatId, _openChatOwner));
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openForLiveUpdates() async {
    try {
      await ref.read(openChatsProvider).acquire(widget.chatId, _openChatOwner);
    } catch (e) {
      debugPrint('[Chat] open ${widget.chatId} for live actions: $e');
    }
  }

  bool _inThisView(td.Message m) =>
      m.chatId == widget.chatId &&
      (widget.generalTopic ? !m.isTopicMessage : (widget.threadId == null || m.messageThreadId == widget.threadId));

  void _onUpdate(td.TdObject u) {
    if (!mounted) return;
    int index(int id) => _messages.indexWhere((m) => m.id == id);
    switch (u) {
      case td.UpdateNewMessage(:final message) when _inThisView(message):
        if (index(message.id) < 0 && _scrolledUp && !message.isOutgoing) _newBelow++;
        if (index(message.id) < 0 && !_detached) setState(() => _messages.insert(0, message));
      case td.UpdateMessageSendSucceeded(:final message, :final oldMessageId) when message.chatId == widget.chatId:
        final i = index(oldMessageId);
        if (i >= 0) setState(() => _messages[i] = message);
      case td.UpdateMessageInteractionInfo(:final chatId, :final messageId, :final interactionInfo)
          when chatId == widget.chatId:
        final i = index(messageId);
        if (i >= 0) setState(() => _messages[i] = _messages[i].copyWith(interactionInfo: interactionInfo));
      case td.UpdateMessageContent(:final chatId, :final messageId, :final newContent) when chatId == widget.chatId:
        final i = index(messageId);
        if (i >= 0) setState(() => _messages[i] = _messages[i].copyWith(content: newContent));
      case td.UpdateChatAction(:final chatId, :final topicId, :final senderId, :final action)
          when chatId == widget.chatId && (widget.threadId == null || topicNumber(topicId) == widget.threadId):
        final key = _senderKey(senderId);
        if (action is td.ChatActionCancel) {
          setState(() => _activities.remove(key));
        } else {
          final store = ref.read(telegramStoreProvider);
          setState(() {
            _activities[key] = _LiveChatActivity(
              sender: store.senderName(senderId),
              action: action,
              updatedAt: DateTime.now(),
            );
          });
          _startActivityExpiry();
        }
      case td.UpdateDeleteMessages(:final chatId, :final messageIds, :final isPermanent)
          when chatId == widget.chatId && isPermanent:
        setState(() => _messages.removeWhere((m) => messageIds.contains(m.id)));
        if (_pins.any((m) => messageIds.contains(m.id))) unawaited(_loadPins());
      case td.UpdateMessageIsPinned(:final chatId, :final messageId, :final isPinned) when chatId == widget.chatId:
        final i = index(messageId);
        if (i >= 0) setState(() => _messages[i] = _messages[i].copyWith(isPinned: isPinned));
        _pinsClock?.cancel();
        _pinsClock = Timer(const Duration(milliseconds: 350), _loadPins);
      default:
        break;
    }
  }

  void _startActivityExpiry() {
    _activityExpiry ??= Timer.periodic(const Duration(seconds: 2), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 9));
      final expired = _activities.entries
          .where((entry) => entry.value.updatedAt.isBefore(cutoff))
          .map((entry) => entry.key)
          .toList();
      if (expired.isNotEmpty && mounted) {
        setState(() {
          for (final key in expired) {
            _activities.remove(key);
          }
        });
      }
      if (_activities.isEmpty) {
        _activityExpiry?.cancel();
        _activityExpiry = null;
      }
    });
  }

  /// One page of older messages through the rate limiter. TDLib may answer
  /// the first call with only what it has cached, so a short page is
  /// followed up once.
  Future<void> _loadMore() async {
    if (_loading || _end) return;
    setState(() => _loading = true);
    final client = ref.read(telegramClientProvider);
    try {
      var added = 0;
      for (var attempt = 0; attempt < 2 && added < 20; attempt++) {
        final from = _oldest ?? (_messages.isEmpty ? 0 : _messages.last.id);
        final List<td.Message> page = widget.threadId == null
            ? (await client.send<td.Messages>(
                td.GetChatHistory(chatId: widget.chatId, fromMessageId: from, offset: 0, limit: 40, onlyLocal: false),
                limited: true,
              )).messages.whereType<td.Message>().toList()
            : await ref.read(toolRunnerProvider).topicPage(widget.chatId, widget.threadId!, fromId: from);
        final all = page.where((m) => _messages.every((x) => x.id != m.id) && m.id != from).toList();
        if (all.isEmpty) {
          _end = true;
          break;
        }
        _oldest = all.last.id;
        final fresh = widget.generalTopic
            ? all.where((m) => !m.isTopicMessage).toList()
            : widget.commentsOn != null
            ? all.where((m) => m.id != widget.threadId).toList()
            : all;
        _messages.addAll(fresh);
        added += fresh.length;
        unawaited(_refreshInteractions(fresh));
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// History comes from TDLib's cache, so a channel's or group's views and
  /// reactions (Stars included) can be stale or missing. Telling TDLib the
  /// posts are on screen has it fetch them fresh, and the screen hears it
  /// as updateMessageInteractionInfo. The source "other" (not chat history)
  /// keeps this from marking anything as read.
  Future<void> _refreshInteractions(List<td.Message> shown) async {
    final chat = ref.read(telegramStoreProvider).chat(widget.chatId);
    if (chat == null || chat.type is td.ChatTypePrivate || chat.type is td.ChatTypeSecret) return;
    final ids = [for (final m in shown) if (m.sendingState == null && m.schedulingState == null) m.id];
    if (ids.isEmpty) return;
    try {
      await ref.read(telegramClientProvider).send<td.Ok>(
        td.ViewMessages(
          chatId: widget.chatId,
          messageIds: ids.take(100).toList(),
          source: const td.MessageSourceOther(),
          forceRead: false,
        ),
        limited: true,
      );
    } catch (e) {
      debugPrint('[Chat] refresh reactions: $e');
    }
  }

  /// The keyboard a bot put in place of the phone's, from its latest
  /// message that set or removed one.
  td.Message? get _replyKeyboard {
    for (final m in _messages.take(30)) {
      if (m.replyMarkup is td.ReplyMarkupShowKeyboard) return m;
      if (m.replyMarkup is td.ReplyMarkupRemoveKeyboard) return null;
    }
    return null;
  }

  td.Message? _find(int id) => _messages.where((m) => m.id == id).firstOrNull;

  /// Scrolls to message [id], loading older history until it's there, and
  /// lights it up: what tapping a reply or a quote does.
  /// The list shows a stretch of older history around a message jumped to,
  /// not the latest messages: new ones aren't added, and a button at the
  /// bottom goes back to the latest.
  bool _detached = false;

  /// Scrolled up from the latest message: the arrow down is showing.
  bool _scrolledUp = false;

  /// Messages that came in below while scrolled up, counted on the arrow.
  int _newBelow = 0;

  /// The arrow down: back to the latest message.
  void _toBottom() {
    if (_detached) return _backToLatest();
    if (!_scroll.hasClients) return;
    final far = _scroll.position.pixels > _scroll.position.viewportDimension * 4;
    // A long way up jumps most of it, then glides the last stretch.
    if (far) _scroll.jumpTo(_scroll.position.viewportDimension);
    _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    setState(() => _newBelow = 0);
  }

  /// Replaces the list with the messages around [id] (a pinned message or
  /// reply too far back to page to). False when Telegram has no such
  /// message.
  Future<bool> _loadAround(int id) async {
    while (_loading) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (!mounted) return false;
    setState(() => _loading = true);
    try {
      final client = ref.read(telegramClientProvider);
      var list = <td.Message>[];
      // TDLib may answer from its cache first; a second ask goes online.
      for (var attempt = 0; attempt < 2 && list.every((m) => m.id != id); attempt++) {
        final r = await client.send<td.Messages>(
          td.GetChatHistory(chatId: widget.chatId, fromMessageId: id, offset: -20, limit: 50, onlyLocal: false),
          limited: true,
        );
        list = r.messages.whereType<td.Message>().toList();
      }
      if (!mounted || list.every((m) => m.id != id)) return false;
      list.sort((a, b) => b.id.compareTo(a.id));
      final latest = ref.read(telegramStoreProvider).chat(widget.chatId)?.lastMessage?.id;
      setState(() {
        _messages
          ..clear()
          ..addAll(widget.generalTopic ? list.where((m) => !m.isTopicMessage) : list);
        _oldest = list.last.id;
        _end = false;
        _detached = latest == null || list.first.id < latest;
      });
      unawaited(_refreshInteractions(list));
      await WidgetsBinding.instance.endOfFrame;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return true;
    } catch (e) {
      debugPrint('[Chat] load around $id: $e');
      return false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Back from a stretch of old history to the latest messages.
  void _backToLatest() {
    setState(() {
      _messages.clear();
      _oldest = null;
      _end = false;
      _detached = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadMore();
  }

  Future<void> _jumpTo(int id) async {
    // A few pages back is quicker to scroll through; anything further is
    // loaded around the message itself.
    for (var page = 0; page < 4 && _find(id) == null && !_end; page++) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (_find(id) != null) break;
      await _loadMore();
    }
    if (_find(id) == null && widget.threadId == null) await _loadAround(id);
    if (!mounted) return;
    if (_find(id) == null) {
      showSnack(context, 'That message is no longer in this chat', icon: Icons.info_outline_rounded);
      return;
    }
    setState(() => _highlight = id);
    // The list builds lazily: move towards older posts until the target is
    // built, then centre it.
    for (var step = 0; step < 60 && mounted; step++) {
      await WidgetsBinding.instance.endOfFrame;
      final ctx = _postKeys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: 0.4);
        break;
      }
      if (!_scroll.hasClients) break;
      final pos = _scroll.position;
      if (pos.pixels >= pos.maxScrollExtent) break;
      _scroll.jumpTo((pos.pixels + pos.viewportDimension * 0.8).clamp(0, pos.maxScrollExtent));
    }
    _highlightClock?.cancel();
    _highlightClock = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  List<Track> _playlist() {
    final store = ref.read(telegramStoreProvider);
    return [for (final m in _messages.reversed) ?Track.of(m, store)];
  }

  void _openProfile() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatProfileScreen(chatId: widget.chatId)));

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final chat = store.chat(widget.chatId);
    final kind = chat == null ? ChatKind.private : store.kindOf(chat);
    final title = widget.threadTitle ?? (kind == ChatKind.saved ? 'Saved Messages' : (chat?.title ?? 'Chat'));
    final forumRoot = _isForumRoot;
    final activityText = _activityText(_activities.values.toList(growable: false));
    final top = MediaQuery.paddingOf(context).top;
    final headerHeight = top + 64;

    Widget body;
    if (forumRoot) {
      body = chat != null && store.isDirectMessagesGroup(chat)
          ? DirectMessagesTopicsList(chatId: widget.chatId, topPadding: headerHeight + Space.s)
          : ForumTopicsList(chatId: widget.chatId, topPadding: headerHeight + Space.s);
    } else if (_messages.isEmpty && widget.commentsOn == null) {
      body = Center(
        child: _loading
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_error ?? 'No messages', style: context.text.bodySmall),
      );
    } else {
      // An album arrives as several messages sharing a media album id; they
      // are shown as one post. Newest first, like _messages.
      final posts = <List<td.Message>>[];
      for (final m in _messages) {
        if (m.mediaAlbumId != 0 && posts.isNotEmpty && posts.last.first.mediaAlbumId == m.mediaAlbumId) {
          posts.last.add(m);
        } else {
          posts.add([m]);
        }
      }
      // Posts from people or chats you blocked, or with a muted word: either
      // gone entirely or folded behind a notice, as set in Block & mute.
      final filters = ref.watch(contentFiltersProvider);
      final blockedSenders = ref.watch(blockedSendersProvider);
      final hidden = <int, HiddenVerdict>{};
      posts.removeWhere((post) {
        final v = hiddenVerdict(
          post.first,
          album: post.skip(1).toList(),
          filters: filters,
          blockedSenders: blockedSenders,
          store: store,
          viewingChatId: widget.chatId,
        );
        if (v == null) return false;
        if (v.silent) return true;
        hidden[post.first.id] = v;
        return false;
      });
      // A bot's reply as it is being written (draft streaming), newest of all.
      final pending = switch (store.pendingMessages[widget.chatId]) {
        final p? when p.forumTopicId == (widget.threadId ?? 0) || widget.threadId == null => p,
        _ => null,
      };
      final lead = (pending == null ? 0 : 1) + (_detached ? 1 : 0);
      body = ListView.builder(
        controller: _scroll,
        reverse: true,
        // A reversed list keeps padding where it says: the top clears the
        // floating header (and the pinned bar), the bottom sits on the box.
        padding: EdgeInsets.fromLTRB(
          Space.m,
          headerHeight + Space.m + (_showsPins && _pins.isNotEmpty ? 46 : 0),
          Space.m,
          Space.m,
        ),
        itemCount: posts.length + 1 + lead,
        itemBuilder: (context, index) {
          if (_detached && index == 0) return _LatestButton(onTap: _backToLatest);
          if (pending != null && index == (_detached ? 1 : 0)) return PendingDraftBubble(update: pending);
          final i = index - lead;
          if (i == posts.length && widget.commentsOn != null && (_end || _messages.isEmpty)) {
            return _CommentedPost(post: widget.commentsOn!, loading: _loading, hasComments: posts.isNotEmpty);
          }
          if (i == posts.length) {
            return Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Center(
                child: _loading
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_end ? 'Beginning of the chat' : '', style: context.text.labelSmall),
              ),
            );
          }
          final post = posts[i];
          final album = post.length > 1 ? post.reversed.toList() : const <td.Message>[];
          // The album's caption lives on one of its messages (usually the
          // first); that one carries the post.
          final m = post.length == 1
              ? post.single
              : album.firstWhere((x) => gistOf(x.content).text.isNotEmpty, orElse: () => album.first);
          final older = i + 1 < posts.length ? posts[i + 1].first : null;
          // Under a channel post, the first comment only gets a day of its
          // own when it came on a later day than the post.
          final newDay = older == null
              ? !(widget.commentsOn != null && _end && _sameDay(widget.commentsOn!.date, m.date))
              : !_sameDay(older.date, m.date);
          final grouped = older != null && !newDay && !hidden.containsKey(older.id) && !hidden.containsKey(post.first.id) && _sameSender(older, m) && m.date - older.date < 300;
          final key = _keyFor(post.first.id);
          for (final x in post.skip(1)) {
            _postKeys[x.id] = key;
          }
          final lit = _highlight != null && post.any((x) => x.id == _highlight);
          final verdict = hidden[post.first.id];
          if (verdict != null && !_revealed.contains(post.first.id)) {
            return Column(
              key: key,
              children: [
                if (newDay) _DaySeparator(unix: m.date),
                HiddenMessageNotice(
                  verdict: verdict,
                  onReveal: () => setState(() => _revealed.add(post.first.id)),
                ),
              ],
            );
          }
          return Column(
            key: key,
            children: [
              if (newDay) _DaySeparator(unix: m.date),
              if (verdict != null)
                RevealedMessageBar(verdict: verdict, onHide: () => setState(() => _revealed.remove(post.first.id))),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: lit ? AppColors.accent.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.m),
                ),
                child: MessageTile(
                key: ValueKey(m.id),
                message: m,
                album: album,
                kind: kind,
                chatTitle: chat?.title ?? title,
                grouped: grouped,
                findMessage: _find,
                onJumpTo: _jumpTo,
                onReply: chat != null && (store.canPost(chat) || widget.commentsOn != null)
                    ? (m, {quote}) => setState(() {
                        _replyTo = m;
                        _quote = quote;
                      })
                    : null,
                playlist: _playlist,
                lastReadOutbox: chat?.lastReadOutboxMessageId ?? 0,
                // An album is picked (and forwarded) whole.
                onSelect: album.isEmpty
                    ? _toggle
                    : (_) => setState(() {
                        final on = !_selected.contains(m.id);
                        for (final x in album) {
                          on ? _selected.add(x.id) : _selected.remove(x.id);
                        }
                      }),
                selecting: _selecting,
                selected: _selected.contains(m.id),
              ),
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
                Positioned.fill(
                  child: ChatBackdrop(background: chat?.background, child: body),
                ),
                if (!forumRoot)
                  Positioned(
                    right: Space.m,
                    bottom: Space.s,
                    child: _DownArrow(
                      visible: (_scrolledUp || _detached) && !_selecting,
                      count: _newBelow,
                      onTap: _toBottom,
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      if (_selecting)
                        _SelectionBar(
                          count: _selected.length,
                          onClose: () => setState(_selected.clear),
                          onForward: () async {
                            await showForwardSheet(context, widget.chatId, [for (final m in _picked) m.id]);
                            if (mounted) setState(_selected.clear);
                          },
                          onCopy: () {
                            final text = [
                              for (final m in _picked)
                                '${m.isOutgoing ? 'You' : store.senderName(m.senderId)}: ${gistOf(m.content).text}',
                            ].join('\n');
                            Clipboard.setData(ClipboardData(text: text));
                            showSnack(context, 'Copied ${_selected.length} messages');
                            setState(_selected.clear);
                          },
                          onCanvas: () async {
                            await saveManyToCanvas(context, ref, _picked, chat?.title ?? title);
                            if (mounted) setState(_selected.clear);
                          },
                          onAskAi: () {
                            final refs = [for (final m in _picked) '[${chat?.title ?? 'msg'}](post:${m.chatId}:${m.id})'];
                            final controller = ref.read(chatControllerProvider.notifier);
                            controller.newChat();
                            controller.send(
                              'Look at these ${refs.length} messages from ${chat?.title ?? 'a chat'} '
                              '(chat_id ${widget.chatId}, message_ids ${_picked.map((m) => m.id).join(', ')}): ${refs.join(' ')}. '
                              'Read them and tell me what they say.',
                            );
                            Navigator.of(context).popUntil((r) => r.isFirst);
                          },
                          onDelete: () async {
                            final forAll = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: Text('Delete ${_selected.length} messages?'),
                                content: const Text('This can\'t be undone.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('For me')),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.danger,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('For everyone'),
                                  ),
                                ],
                              ),
                            );
                            if (forAll == null) return;
                            try {
                              await ref.read(toolRunnerProvider).deleteMessages(
                                widget.chatId,
                                _selected.toList(),
                                forEveryone: forAll,
                              );
                              if (mounted) setState(_selected.clear);
                            } catch (e) {
                              if (context.mounted) {
                                showSnack(context, 'Couldn\'t delete: $e', icon: Icons.error_outline_rounded);
                              }
                            }
                          },
                        )
                      else if (widget.commentsOn case final post?)
                        ChatPageHeader(
                          chatId: post.chatId,
                          chatTitle: store.chat(post.chatId)?.title ?? 'Channel',
                          title: () {
                            final n = _end
                                ? _messages.length
                                : (post.interactionInfo?.replyInfo?.replyCount ?? 0).clamp(_messages.length, 1 << 30);
                            return n == 0 ? 'Comments' : '$n Comment${n == 1 ? '' : 's'}';
                          }(),
                          center: true,
                        )
                      else
                      _Header(
                        title: title,
                        onScheduled: chat != null && chat.hasScheduled ? _openScheduled : null,
                        chat: chat,
                        kind: kind,
                        isThread: widget.threadId != null,
                        activityText: activityText,
                        subtitleOverride: widget.commentsOn == null
                            ? null
                            : store.chat(widget.commentsOn!.chatId)?.title,
                        onProfile: chat == null ? null : _openProfile,
                        onAskAi: chat == null
                            ? null
                            : () => askAiAbout(
                                context,
                                ref,
                                chat,
                                threadId: widget.threadId,
                                threadTitle: widget.threadTitle,
                              ),
                      ),
                      if (_showsPins && _pins.isNotEmpty && !_selecting && !forumRoot)
                        PinnedMessageBar(pins: _pins, index: _pinIndex, onTap: _tapPin, onList: _openPinned),
                      const AudioMiniBar(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_replyKeyboard case final k?)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 0),
              child: SingleChildScrollView(child: BotButtons(message: k)),
            ),
          if (chat != null && !forumRoot)
            store.canPost(chat) || widget.commentsOn != null
                ? _ChatComposer(
                    chatId: widget.chatId,
                    threadId: widget.threadId ?? 0,
                    replyTo: _replyTo,
                    quote: _quote,
                    onReplyElsewhere: _replyElsewhere,
                    hint: widget.commentsOn != null
                        ? 'Comment'
                        : (kind == ChatKind.channel ? 'Broadcast' : 'Message'),
                    onScheduled: chat.hasScheduled && widget.commentsOn == null ? _openScheduled : null,
                    onCancelReply: () => setState(() => _replyTo = _quote = null),
                    onSent: () {
                      setState(() => _replyTo = _quote = null);
                      if (_detached) return _backToLatest();
                      if (_scroll.hasClients)
                        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                    },
                  )
                : _ReadOnlyBar(chat: chat),
        ],
      ),
    );
  }

  static bool _sameDay(int a, int b) {
    final x = DateTime.fromMillisecondsSinceEpoch(a * 1000);
    final y = DateTime.fromMillisecondsSinceEpoch(b * 1000);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  static bool _sameSender(td.Message a, td.Message b) => switch ((a.senderId, b.senderId)) {
    (td.MessageSenderUser(userId: final x), td.MessageSenderUser(userId: final y)) => x == y,
    (td.MessageSenderChat(chatId: final x), td.MessageSenderChat(chatId: final y)) => x == y,
    _ => false,
  };
}

String _senderKey(td.MessageSender sender) => switch (sender) {
  td.MessageSenderUser(:final userId) => 'user:$userId',
  td.MessageSenderChat(:final chatId) => 'chat:$chatId',
};

class _LiveChatActivity {
  const _LiveChatActivity({required this.sender, required this.action, required this.updatedAt});
  final String sender;
  final td.ChatAction action;
  final DateTime updatedAt;
}

String? _activityText(List<_LiveChatActivity> activities) {
  if (activities.isEmpty) return null;
  final primary = _activityInfo(activities.first.action);
  final sameAction = activities.every((activity) => activity.action.runtimeType == activities.first.action.runtimeType);
  final text = sameAction
      ? _activitySentence(activities.map((activity) => activity.sender).toList(), primary.label)
      : activities
            .take(2)
            .map((activity) => '${activity.sender} is ${_activityInfo(activity.action).label}')
            .join(' · ');
  return primary.progress == null ? text : '$text · ${primary.progress}%';
}

({String label, int? progress}) _activityInfo(td.ChatAction action) => switch (action) {
  td.ChatActionTyping() => (label: 'typing…', progress: null),
  td.ChatActionRecordingVideo() => (label: 'recording a video', progress: null),
  td.ChatActionUploadingVideo(:final progress) => (label: 'uploading a video', progress: progress),
  td.ChatActionRecordingVoiceNote() => (label: 'recording a voice message', progress: null),
  td.ChatActionUploadingVoiceNote(:final progress) => (label: 'uploading a voice message', progress: progress),
  td.ChatActionUploadingPhoto(:final progress) => (label: 'uploading a photo', progress: progress),
  td.ChatActionUploadingDocument(:final progress) => (label: 'uploading a file', progress: progress),
  td.ChatActionChoosingSticker() => (label: 'choosing a sticker', progress: null),
  td.ChatActionChoosingLocation() => (label: 'choosing a location', progress: null),
  td.ChatActionChoosingContact() => (label: 'choosing a contact', progress: null),
  td.ChatActionStartPlayingGame() => (label: 'playing a game', progress: null),
  td.ChatActionRecordingVideoNote() => (label: 'recording a video message', progress: null),
  td.ChatActionUploadingVideoNote(:final progress) => (label: 'uploading a video message', progress: progress),
  td.ChatActionWatchingAnimations() => (label: 'watching animations', progress: null),
  td.ChatActionCancel() => (label: 'active', progress: null),
};

String _activitySentence(List<String> names, String label) {
  if (names.length == 1) return '${names.first} is $label';
  if (names.length == 2) return '${names.first} and ${names.last} are $label';
  return '${names.first} and ${names.length - 1} others are $label';
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.title,
    required this.chat,
    required this.kind,
    required this.isThread,
    this.activityText,
    required this.onProfile,
    required this.onAskAi,
    this.subtitleOverride,
    this.onScheduled,
  });

  final String? subtitleOverride;

  /// Opens the chat's scheduled messages; null when it has none.
  final VoidCallback? onScheduled;
  final String title;
  final ChatInfo? chat;
  final ChatKind kind;
  final bool isThread;
  final String? activityText;
  final VoidCallback? onProfile;
  final VoidCallback? onAskAi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final c = chat;
    final username = c == null ? null : store.chatUsername(c);
    final members = c == null ? null : store.memberCount(c);
    String? status;
    if (c != null && c.type is td.ChatTypePrivate) {
      final u = store.users[(c.type as td.ChatTypePrivate).userId];
      status = switch (u?.status) {
        td.UserStatusOnline() => 'online',
        td.UserStatusRecently() => 'last seen recently',
        td.UserStatusOffline(:final wasOnline) =>
          'last seen ${DateFormat('d MMM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(wasOnline * 1000))}',
        td.UserStatusLastWeek() => 'last seen within a week',
        td.UserStatusLastMonth() => 'last seen within a month',
        _ => kind == ChatKind.bot ? 'bot' : null,
      };
    }
    final subtitle =
        activityText ??
        (subtitleOverride != null
            ? subtitleOverride!
            : isThread
            ? c?.title
            : [
                if (members != null && members > 0)
                  '${NumberFormat.compact().format(members)} ${kind == ChatKind.channel ? 'subscribers' : 'members'}',
                if (c != null && kind == ChatKind.group && (store.onlineMembers[c.id] ?? 0) > 1)
                  '${store.onlineMembers[c.id]} online',
                ?status,
                if (status == null && members == null && username != null) '@$username',
              ].join(' · '));
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
            Expanded(
              child: Glass(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onProfile,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, Space.l, 4),
                      child: Row(
                        children: [
                          if (kind == ChatKind.saved)
                            const SavedAvatar(size: 40)
                          else
                            TgAvatar(chatId: c?.id, title: c?.title ?? title, size: 40),
                          const SizedBox(width: Space.s + 2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.titleMedium,
                                ),
                                if (subtitle != null && subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: activityText != null || status == 'online'
                                          ? AppColors.accent
                                          : AppColors.text2,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (c != null && c.isMuted)
                            Icon(Icons.volume_off_rounded, size: 16, color: AppColors.text3),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.s),
            Glass(
              child: PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_vert_rounded, color: AppColors.text),
                onSelected: (v) {
                  switch (v) {
                    case 'profile':
                      onProfile?.call();
                    case 'ai':
                      onAskAi?.call();
                    case 'mute':
                      if (c != null) setChatMuted(ref, c, !c.isMuted, context: context);
                    case 'archive':
                      if (c != null) setChatArchived(ref, c, !c.inArchive, context: context);
                    case 'background':
                      if (c != null) showBackgroundPicker(context, ref, c.id);
                    case 'members':
                      if (c != null) {
                        Navigator.of(
                          context,
                        ).push(MaterialPageRoute<void>(builder: (_) => MembersScreen(chatId: c.id)));
                      }
                    case 'scheduled':
                      if (c != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => ChatScheduledScreen(chatId: c.id)),
                        );
                      }
                    case 'pinned':
                      if (c != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => ChatPinnedScreen(chatId: c.id)),
                        );
                      }
                    case 'more':
                      if (c != null) showChatMenu(context, ref, c);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'profile', child: Text('View profile')),
                  const PopupMenuItem(value: 'ai', child: Text('Ask AI about this chat')),
                  if (c != null) ...[
                    PopupMenuItem(value: 'mute', child: Text(c.isMuted ? 'Unmute' : 'Mute')),
                    if (kind != ChatKind.saved)
                      PopupMenuItem(value: 'archive', child: Text(c.inArchive ? 'Unarchive' : 'Archive')),
                    const PopupMenuItem(value: 'background', child: Text('Chat background')),
                    if (c.hasScheduled || store.canPost(c))
                      const PopupMenuItem(value: 'scheduled', child: Text('Scheduled messages')),
                    const PopupMenuItem(value: 'pinned', child: Text('Pinned messages')),
                    if (kind == ChatKind.group || (kind == ChatKind.channel && store.isAdmin(c)))
                      PopupMenuItem(
                        value: 'members',
                        child: Text(kind == ChatKind.channel ? 'Subscribers' : 'Members'),
                      ),
                    const PopupMenuItem(value: 'more', child: Text('More…')),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Replaces the header while messages are selected.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onClose,
    required this.onForward,
    required this.onCopy,
    required this.onCanvas,
    required this.onAskAi,
    required this.onDelete,
  });
  final int count;
  final VoidCallback onClose, onForward, onCopy, onCanvas, onAskAi, onDelete;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
      child: Glass(
        child: Row(
          children: [
            IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close_rounded), onPressed: onClose),
            Expanded(child: Text('$count selected', style: context.text.titleMedium)),
            IconButton(tooltip: 'Forward', icon: const Icon(Icons.forward_rounded), onPressed: onForward),
            IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy_rounded), onPressed: onCopy),
            IconButton(
              tooltip: 'Save to Content Canvas',
              icon: const Icon(Icons.dashboard_customize_outlined),
              onPressed: onCanvas,
            ),
            IconButton(tooltip: 'Ask AI', icon: const Icon(Icons.auto_awesome_outlined), onPressed: onAskAi),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    ),
  );
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.unix});
  final int unix;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    return ChatPill(days == 0 ? 'Today' : (days == 1 ? 'Yesterday' : dayLabel(d)));
  }
}

/// For chats the account can only read: mute toggle and Ask AI, the way
/// Telegram shows a Mute button under a channel.
class _ReadOnlyBar extends ConsumerWidget {
  const _ReadOnlyBar({required this.chat});
  final ChatInfo chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
        child: Row(
          children: [
            Expanded(
              child: Glass(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setChatMuted(ref, chat, !chat.isMuted, context: context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            chat.isMuted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                            size: 20,
                          ),
                          const SizedBox(width: Space.s),
                          Text(chat.isMuted ? 'Unmute' : 'Mute', style: context.text.titleSmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.s),
            Glass(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => askAiAbout(context, ref, chat),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Space.xl, vertical: 14),
                    child: Text('Ask AI', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Write and send yourself: text, a reply, photos, videos and files, and
/// dictation into the box.
class _ChatComposer extends ConsumerStatefulWidget {
  const _ChatComposer({
    required this.chatId,
    required this.threadId,
    required this.replyTo,
    this.quote,
    this.onReplyElsewhere,
    required this.onCancelReply,
    required this.onSent,
    this.hint = 'Message',
    this.onScheduled,
  });

  /// What the empty box says: Message, Broadcast, Comment.
  final String hint;

  /// Opens the chat's scheduled messages, shown as a calendar by the send
  /// button while the box is empty; null when there are none.
  final VoidCallback? onScheduled;
  final int chatId;
  final int threadId;
  final td.Message? replyTo;

  /// Part of [replyTo]'s text to quote.
  final String? quote;

  /// Tapping the reply bar: carry the reply (or quote) to another chat.
  final VoidCallback? onReplyElsewhere;
  final VoidCallback onCancelReply;
  final VoidCallback onSent;

  @override
  ConsumerState<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<_ChatComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  /// The quote as Telegram wants it: its text and where it starts.
  td.InputTextQuote? get _inputQuote {
    final q = widget.quote, reply = widget.replyTo;
    if (q == null || q.isEmpty || reply == null) return null;
    final at = gistOf(reply.content).text.indexOf(q);
    return td.InputTextQuote(text: td.FormattedText(text: q, entities: const []), richTexts: const [], position: at < 0 ? 0 : at);
  }

  @override
  void didUpdateWidget(_ChatComposer old) {
    super.didUpdateWidget(old);
    // Choosing a message to reply to puts the cursor in the box.
    if (widget.replyTo != null && widget.replyTo?.id != old.replyTo?.id) _focus.requestFocus();
  }

  /// The Emoji / GIFs / Stickers panel is open in place of the keyboard.
  bool _panel = false;

  void _insertEmoji(String e) {
    final v = _text.value;
    final at = v.selection.isValid ? v.selection.start : v.text.length;
    final end = v.selection.isValid ? v.selection.end : v.text.length;
    final text = v.text.replaceRange(at, end, e);
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at + e.length),
    );
  }

  Future<void> _sendNow(Future<Object?> Function() send) async {
    try {
      await send();
      widget.onSent();
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t send: $e', icon: Icons.error_outline_rounded);
    }
  }

  final List<Attachment> _files = [];

  /// Pictures and videos in the draft go uncompressed, as files.
  bool _asFiles = false;

  /// The animated effect the next message goes with; 0 for none.
  int _effect = 0;
  String _effectEmoji = '';

  Future<void> _pickEffect() async {
    final store = ref.read(telegramStoreProvider);
    final chat = store.chat(widget.chatId);
    if (chat == null || chat.type is! td.ChatTypePrivate || store.messageEffectIds.isEmpty) {
      showSnack(context, 'Message effects work in private chats', icon: Icons.info_outline_rounded);
      return;
    }
    final client = ref.read(telegramClientProvider);
    final effects = <td.MessageEffect>[];
    for (final id in store.messageEffectIds.take(48)) {
      try {
        effects.add(await client.send<td.MessageEffect>(td.GetMessageEffect(effectId: id)));
      } catch (_) {}
    }
    if (!mounted) return;
    final premium = store.me?.isPremium ?? false;
    final picked = await showModalBottomSheet<td.MessageEffect?>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send with an effect', style: ctx.text.titleMedium),
              const SizedBox(height: Space.m),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in effects)
                    InkWell(
                      borderRadius: BorderRadius.circular(Radii.m),
                      onTap: e.isPremium && !premium ? null : () => Navigator.pop(ctx, e),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: e.id == _effect ? AppColors.accent.withValues(alpha: 0.2) : null,
                          borderRadius: BorderRadius.circular(Radii.m),
                        ),
                        child: Opacity(opacity: e.isPremium && !premium ? 0.35 : 1, child: Text(e.emoji, style: const TextStyle(fontSize: 28))),
                      ),
                    ),
                ],
              ),
              if (_effect != 0) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No effect')),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _effect = picked?.id ?? 0;
      _effectEmoji = picked?.emoji ?? '';
    });
  }
  bool _sending = false;
  bool _adding = false;
  String _typed = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if ((text.isEmpty && _files.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(toolRunnerProvider)
          .sendToChat(
            chatId: widget.chatId,
            text: text,
            files: [for (final f in _files) f.path],
            asFiles: _asFiles,
            effectId: _effect,
            replyToMessageId: widget.replyTo?.id,
            quote: _inputQuote,
            replyInChatId: widget.replyTo?.chatId,
            threadId: widget.threadId,
          );
      _text.clear();
      _files.clear();
      _asFiles = false;
      _effect = 0;
      widget.onSent();
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t send: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// The attach sheet: files join the draft (so they can take a caption);
  /// a location, poll or contact goes straight out.
  Future<void> _attach() async {
    final result = await showAttachSheet(context);
    if (result == null || !mounted) return;
    final runner = ref.read(toolRunnerProvider);
    try {
      switch (result) {
        case AttachFiles(:final files, :final asFiles):
          setState(() {
            _adding = true;
            if (_files.isEmpty || asFiles) _asFiles = asFiles;
          });
          for (final (path, name) in files) {
            final a = await ChatController.attach(path, name: name);
            if (mounted) setState(() => _files.add(a));
          }
        case AttachLocation(:final liveMinutes):
          await runner.sendLocation(widget.chatId, liveMinutes: liveMinutes);
          widget.onSent();
        case AttachPoll(:final draft):
          await runner.sendPoll(widget.chatId, draft, threadId: widget.threadId);
          widget.onSent();
        case AttachContact(:final userId):
          await runner.sendContact(widget.chatId, userId);
          widget.onSent();
      }
    } catch (e) {
      if (mounted)
        showSnack(context, 'Couldn\'t send: ${e is ArgumentError ? e.message : e}', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _dictate() async {
    final d = ref.read(dictationProvider);
    if (d.listening) return d.stop();
    _typed = _text.text;
    await d.start(onText: (words, done) {
      if (!mounted) return;
      final t = joinDictation(_typed, words);
      _text.value = TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    });
    if (d.error != null && mounted) showSnack(context, d.error!, icon: Icons.mic_off_rounded);
  }

  Future<void> _recordVoice() async {
    if (_sending) return;
    final note = await recordVoiceNote(context);
    if (note == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(toolRunnerProvider)
          .sendVoiceNote(
            chatId: widget.chatId,
            path: note.path,
            duration: note.duration,
            caption: _text.text,
            replyToMessageId: widget.replyTo?.id,
            threadId: widget.threadId,
          );
      _text.clear();
      widget.onSent();
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Couldn\'t send voice message: $e', icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final dictation = ref.watch(dictationProvider);
    final reply = widget.replyTo;
    final canSend = _text.text.trim().isNotEmpty || _files.isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.xl + 4),
                border: Border.all(
                  color: dictation.listening ? AppColors.accent.withValues(alpha: 0.6) : AppColors.line,
                ),
              ),
              padding: const EdgeInsets.all(5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (reply != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(Radii.l),
                      onTap: widget.onReplyElsewhere,
                      child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.m, 4, 0, 2),
                      child: Row(
                        children: [
                          Icon(
                            widget.quote == null ? Icons.reply_rounded : Icons.format_quote_rounded,
                            size: 18,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: Space.s),
                          Container(width: 2.5, height: 32, color: AppColors.accent),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${widget.quote == null ? 'Reply to' : 'Quote from'} ${reply.isOutgoing ? 'yourself' : store.senderName(reply.senderId)}${reply.chatId == widget.chatId ? '' : ' in ${store.chat(reply.chatId)?.title ?? 'another chat'}'}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  () {
                                    if (widget.quote case final q?) return '“${q.replaceAll('\n', ' ')}”';
                                    final g = gistOf(reply.content);
                                    return (g.text.isNotEmpty ? g.text : (g.detail ?? g.kind)).replaceAll('\n', ' ');
                                  }(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, color: AppColors.text2),
                                ),
                              ],
                            ),
                          ),
                          _ComposerButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Cancel reply',
                            size: 32,
                            iconSize: 18,
                            onTap: widget.onCancelReply,
                          ),
                        ],
                      ),
                    ),
                    ),
                  if (_files.isNotEmpty || _adding)
                    SizedBox(
                      height: 64,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                        children: [
                          for (final a in _files)
                            Padding(
                              padding: const EdgeInsets.only(right: Space.s),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(Radii.s),
                                    child: a.isImage
                                        ? Image.file(File(a.path), width: 52, height: 52, fit: BoxFit.cover)
                                        : Container(
                                            width: 130,
                                            height: 52,
                                            color: AppColors.surface3,
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              a.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                  ),
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _files.remove(a)),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
                                        child: Icon(Icons.close_rounded, size: 13, color: AppColors.bg),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_adding)
                            const Padding(
                              padding: EdgeInsets.all(Space.m),
                              child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          if (_files.any((a) => a.isImage || a.isVideo))
                            Center(
                              child: Tooltip(
                                message: _asFiles ? 'Sent uncompressed, as files' : 'Sent compressed, shown in the chat',
                                child: FilterChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(_asFiles ? Icons.insert_drive_file_outlined : Icons.photo_outlined, size: 16),
                                  label: Text(_asFiles ? 'As files' : 'Compressed', style: const TextStyle(fontSize: 12)),
                                  selected: _asFiles,
                                  onSelected: (v) => setState(() => _asFiles = v),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _ComposerButton(icon: Icons.add_rounded, tooltip: 'Attach', onTap: _attach),
                      _ComposerButton(
                        icon: _panel ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                        tooltip: _panel ? 'Keyboard' : 'Emoji, GIFs and stickers',
                        active: _panel,
                        onTap: () {
                          if (_panel) {
                            _focus.requestFocus();
                          } else {
                            FocusScope.of(context).unfocus();
                          }
                          setState(() => _panel = !_panel);
                        },
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: TextField(
                          focusNode: _focus,
                          onTap: () {
                            if (_panel) setState(() => _panel = false);
                          },
                          controller: _text,
                          minLines: 1,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          style: context.text.bodyLarge?.copyWith(height: 1.35),
                          decoration: InputDecoration(
                            hintText: dictation.listening
                                ? 'Listening…'
                                : (_files.isEmpty ? widget.hint : 'Add a caption'),
                            hintMaxLines: 1,
                            hintStyle: TextStyle(color: AppColors.text3, overflow: TextOverflow.ellipsis),
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      if (widget.onScheduled != null && !canSend && !dictation.listening)
                        _ComposerButton(
                          icon: Icons.event_note_outlined,
                          tooltip: 'Scheduled messages',
                          onTap: widget.onScheduled,
                        ),
                      // Like Telegram: the mic records a voice message; hold
                      // it to dictate into the box instead. Hold send to pick
                      // an animated effect (private chats).
                      _ComposerButton(
                        tooltip: canSend ? 'Send' : (dictation.listening ? 'Stop dictation' : 'Voice message (hold to dictate)'),
                        icon: canSend
                            ? Icons.arrow_upward_rounded
                            : (dictation.listening ? Icons.stop_rounded : Icons.mic_none_rounded),
                        filled: canSend || dictation.listening,
                        busy: _sending || dictation.transcribing,
                        label: canSend && _effect != 0 ? _effectEmoji : null,
                        onTap: _sending ? null : (canSend ? _send : (dictation.listening ? _dictate : _recordVoice)),
                        onLongPress: _sending ? null : (canSend ? _pickEffect : _dictate),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_panel)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: ExpressionPanel(
                  onEmoji: _insertEmoji,
                  onSendGif: (g) => _sendNow(
                    () => ref.read(toolRunnerProvider).sendGif(widget.chatId, g.id, threadId: widget.threadId),
                  ),
                  onSendSticker: (st) => _sendNow(
                    () => ref.read(toolRunnerProvider).sendStickerTo(widget.chatId, st, threadId: widget.threadId),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The channel post a comments page belongs to, shown above its comments:
/// its day, the post, then where the discussion starts.
class _CommentedPost extends ConsumerWidget {
  const _CommentedPost({required this.post, required this.loading, required this.hasComments});
  final td.Message post;
  final bool loading;
  final bool hasComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    return Column(
      children: [
        ChatPill(dayLabel(DateTime.fromMillisecondsSinceEpoch(post.date * 1000))),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: MessageTile(
            message: post,
            kind: ChatKind.channel,
            chatTitle: store.chat(post.chatId)?.title ?? 'Channel',
            inComments: true,
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(Space.m),
            child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          ChatPill(hasComments ? 'Discussion started' : 'No comments here yet'),
      ],
    );
  }
}

/// Opens the comments under a channel post.
Future<void> openComments(BuildContext context, WidgetRef ref, td.Message post) async {
  final client = ref.read(telegramClientProvider);
  try {
    final info = await client.send<td.MessageThreadInfo>(
      td.GetMessageThread(chatId: post.chatId, messageId: post.id),
      limited: true,
    );
    if (ref.read(telegramStoreProvider).chat(info.chatId) == null) {
      await client.send<td.Chat>(td.GetChat(chatId: info.chatId), limited: true);
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatViewScreen(
          chatId: info.chatId,
          threadId: info.messageThreadId,
          threadTitle: 'Comments',
          commentsOn: post,
        ),
      ),
    );
  } catch (e) {
    if (context.mounted)
      showSnack(context, 'Comments are not available for this post.', icon: Icons.mode_comment_outlined);
  }
}

/// A composer button the size of the AI box's: 36 px, a plain icon, or a
/// filled circle for send.
class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.onLongPress,
    this.filled = false,
    this.active = false,
    this.busy = false,
    this.label,
    this.size = 36,
    this.iconSize,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool filled;

  /// Lit in the accent colour (the emoji panel is open).
  final bool active;
  final bool busy;

  /// Shown instead of the icon: the chosen effect's emoji.
  final String? label;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.bg : (active ? AppColors.accent : AppColors.text2);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? AppColors.text : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox.square(
            dimension: size,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : label != null
                ? Center(child: Text(label!, style: const TextStyle(fontSize: 18)))
                : Icon(icon, size: iconSize ?? (filled ? 20 : 22), color: fg),
          ),
        ),
      ),
    );
  }
}

/// At the bottom of a stretch of older history: back to the latest.
class _LatestButton extends StatelessWidget {
  const _LatestButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.m),
    child: Center(
      child: Glass(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_double_arrow_down_rounded, size: 17, color: AppColors.text),
                  const SizedBox(width: 6),
                  Text('Latest messages', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The round arrow that takes a chat back to its latest message, with how
/// many came in meanwhile.
class _DownArrow extends StatelessWidget {
  const _DownArrow({required this.visible, required this.count, required this.onTap});
  final bool visible;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: visible ? 1 : 0,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        scale: visible ? 1 : 0.6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Glass(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: AppColors.text),
                  ),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: -6,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 20),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.bg),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
