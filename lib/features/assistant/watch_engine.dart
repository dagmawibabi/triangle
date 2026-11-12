import '../brief/brief_store.dart';
import '../brief/home_widgets.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../../infrastructure/telegram/open_chats.dart';
import '../chat/data/chat_controller.dart';
import '../chat/domain/chat_models.dart';
import '../integrations/app_toolkits.dart';
import '../settings/data/settings.dart';
import '../telegram/data/message_content.dart';
import '../telegram/data/telegram_store.dart';
import '../voice/speaker.dart';
import 'notifications.dart';
import 'online_alerts.dart';
import 'reminders.dart';
import 'watches.dart';
import 'untrusted.dart';
import 'device_events.dart';
import 'activity_log.dart';
import '../routines/routine_runner.dart';
import '../routines/routines.dart';
import '../../infrastructure/telegram/td_compat.dart';

/// What the engine has been doing, for the Watches screen.
@immutable
class WatchStatus {
  const WatchStatus({
    this.listening = false,
    this.heard = 0,
    this.matched = 0,
    this.opened = 0,
    this.last,
    this.error,
    this.background = false,
  });
  final bool listening;

  /// Whether the background service is keeping the app alive.
  final bool background;

  /// New messages from others seen since the app started.
  final int heard;
  final int matched;

  /// Groups and channels opened so their messages arrive live.
  final int opened;
  final String? last;
  final String? error;

  WatchStatus clearError() => WatchStatus(
    listening: listening,
    heard: heard,
    matched: matched,
    opened: opened,
    last: last,
    background: background,
  );

  WatchStatus copyWith({
    bool? listening,
    int? heard,
    int? matched,
    int? opened,
    String? last,
    String? error,
    bool? background,
  }) => WatchStatus(
    background: background ?? this.background,
    listening: listening ?? this.listening,
    heard: heard ?? this.heard,
    matched: matched ?? this.matched,
    opened: opened ?? this.opened,
    last: last ?? this.last,
    error: error ?? this.error,
  );
}

/// Runs the watches: hears new messages, matches them, and on a match posts
/// an update in a chat, notifies the person or has the assistant act; and
/// fires scheduled routines on time.
///
/// Telegram only streams a group's or channel's new messages to a client
/// that has the chat open, so watched groups and channels are opened with
/// TDLib (which marks nothing as read); DMs always arrive. New messages are
/// heard from both `updateNewMessage` and `updateChatLastMessage`, once
/// each, and only those newer than the engine's start.
///
/// It works while the app's process is alive. With "Keep running in the
/// background" on, a quiet ongoing notification keeps it alive after the
/// app leaves the screen.
///
/// Every signed-in Telegram account is heard, whichever is on screen. Each
/// watch covers the accounts it was set to ([Watch.covers]); a message
/// heard in an account goes to that account's watches, and the run that
/// follows defaults to that account.
class WatchEngine {
  WatchEngine(this._ref);
  final Ref _ref;

  final status = ValueNotifier(const WatchStatus());

  /// One subscription per account heard, by account id.
  final Map<String, StreamSubscription<td.TdObject>> _subs = {};
  Timer? _clock;
  bool _started = false;
  late int _since;

  final Map<String, List<td.Message>> _pending = {};
  final Map<String, Timer> _debounce = {};
  final Map<String, DateTime> _firstPending = {};
  final Map<String, List<DateTime>> _aiRuns = {};
  final Set<String> _running = {};
  final LinkedHashSet<String> _seen = LinkedHashSet();

  /// Messages each watch has taken, so a group two accounts share fires a
  /// watch covering both once.
  final LinkedHashSet<String> _taken = LinkedHashSet();

  /// Groups and channels kept open, by account.
  final Map<String, Set<int>> _opened = {};
  final Object _openChatOwner = Object();

  /// A burst of messages is handled together once it goes quiet for the
  /// response delay chosen in Automation. A sustained burst still gets a
  /// response after at most four such windows (at least 45 seconds, at most
  /// a day), and never sooner than the delay itself.
  Duration get _quiet =>
      Duration(seconds: _ref.read(settingsProvider).watchResponseDelaySeconds);
  Duration get _maxWait {
    final q = _quiet.inSeconds;
    return Duration(seconds: math.max(q, (4 * q).clamp(45, 24 * 60 * 60).toInt()));
  }

  /// How soon a batch that arrived while its watch was busy is tried again.
  /// Never zero: with "Immediately" that would spin until the run ends.
  Duration get _busyRetry => _quiet < const Duration(seconds: 3) ? const Duration(seconds: 3) : _quiet;

  /// AI runs per watch per hour, so a busy group can't run up the bill.
  static const _maxRunsPerHour = 30;

  /// Groups and channels opened per "all groups / all channels / folder"
  /// watch: the most recently active ones.
  static const _openPerScope = 25;

  void start() {
    if (_started) return;
    _started = true;
    _since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30;
    // Every account is heard; accounts added or removed later join or
    // leave.
    _listenToAccounts();
    _ref.listen(accountsProvider, (_, _) => _listenToAccounts());
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    _ref.listen(watchStoreProvider, (_, _) => _sync(), fireImmediately: true);
    _ref.listen(reminderStoreProvider, (_, _) => _sync());
    _ref.listen(onlineAlertStoreProvider, (_, _) => _seedOnline(), fireImmediately: true);
    _ref.listen(settingsProvider, (_, _) => _sync());
    unawaited(_ref.read(appNotifierProvider).init());
    _ref.read(reminderStoreProvider.notifier).runJob = _runJob;
    _ref.listen(routineStoreProvider, (_, _) => unawaited(_syncKeepAlive()));
    _ref.read(deviceEventsProvider).onAppOpened = _appOpened;
    status.value = status.value.copyWith(listening: true);
  }

  /// The accounts to hear: every signed-in one, and the one on screen
  /// (the first account before its sign-in is recorded), never one still
  /// being added.
  Set<String> _accountIds() {
    final s = _ref.read(accountsProvider);
    return {
      for (final a in s.signedIn) a.id,
      if (s.activeId != s.addingId) s.activeId,
    };
  }

  void _listenToAccounts() {
    final ids = _accountIds();
    var changed = false;
    for (final id in _subs.keys.toList()) {
      if (ids.contains(id)) continue;
      // Signed out: its client is gone, and its chats with it.
      _subs.remove(id)?.cancel();
      _opened.remove(id);
      _openChats.remove(id);
      changed = true;
    }
    for (final id in ids) {
      if (_subs.containsKey(id)) continue;
      _subs[id] = _ref.read(telegramClientFamily(id)).updates.listen((u) => _onUpdate(id, u));
      changed = true;
    }
    if (changed) unawaited(_sync());
  }

  TelegramStore _store(String accountId) => _ref.read(telegramStoreFamily(accountId));

  bool get _several => _ref.read(accountsProvider).hasSeveral;

  /// " · Work" after a title when several accounts are signed in.
  String _accountSuffix(String? accountId) {
    if (accountId == null || !_several) return '';
    final a = _ref.read(accountsProvider).byId(accountId);
    return a == null ? '' : ' · ${a.label}';
  }

  /// A scheduled job is due: the assistant does what it says, in the
  /// conversation it was set up in, and the answer becomes the notification.
  Future<void> _runJob(Reminder r) async {
    final job = Watch(
      id: 'job-${r.id}',
      name: r.text,
      scope: WatchScope.schedule,
      mode: WatchMode.act,
      instructions: r.prompt,
      conversationId: r.conversationId,
      createdAt: r.createdAt,
    );
    final result = await _ref
        .read(chatControllerProvider.notifier)
        .runAutomatic(
          job,
          'Scheduled job "${r.text}" is due now${r.cron == null ? '' : ' (${Cron.describe(r.cron!)})'}. Do this: ${r.prompt}',
          accounts: r.accountIds,
        );
    if (result == null) {
      await _ref
          .read(appNotifierProvider)
          .show(r.text, 'Couldn\'t run: add an AI key in Settings.');
      return;
    }
    // First run, or its chat was deleted and the run started a new one.
    if (r.conversationId != result.conversationId) {
      await _ref
          .read(reminderStoreProvider.notifier)
          .update(
            r.id,
            (x) => x.copyWith(conversationId: result.conversationId),
          );
    }
    if (result.seen) return;
    final text = Speaker.clean(result.text);
    await _ref
        .read(appNotifierProvider)
        .show(
          r.text,
          text.isEmpty
              ? 'Done.'
              : (text.length > 400 ? '${text.substring(0, 400)}…' : text),
          conversationId: result.conversationId,
        );
  }

  void dispose() {
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _clock?.cancel();
    for (final t in _debounce.values) {
      t.cancel();
    }
    // Read while starting: providers can't be read while this one is
    // being disposed.
    for (final o in _openChats.values) {
      o.releaseAll(_openChatOwner);
    }
  }

  final Map<String, OpenChats> _openChats = {};

  List<Watch> get _active {
    final s = _ref.read(settingsProvider);
    if (!s.proactive) return const [];
    return _ref.read(watchStoreProvider).where((w) => w.enabled).toList();
  }

  Future<void> _sync() async {
    final s = _ref.read(settingsProvider);
    if (!s.loaded) return;
    // A key arrived (added, or read once the keystore unlocked): an old
    // "no key" problem is no longer true.
    if (s.hasAnyKey && (status.value.error?.startsWith('No AI key') ?? false)) status.value = status.value.clearError();
    final active = _active;
    _dropInactive(active);
    final notifier = _ref.read(appNotifierProvider);
    if ((active.any((w) => w.notify) && s.notifications) || s.mentionAlerts)
      await notifier.requestPermission();
    await _syncKeepAlive();
    // A folder watch loads its folder in the account it belongs to.
    final heard = _subs.keys.toSet();
    for (final w in active.where(
      (w) => w.scope == WatchScope.folder && w.folderId != null,
    )) {
      final account = w.folderAccountId ?? legacyAccountId;
      if (!heard.contains(account)) continue;
      await _store(account).loadFolder(w.folderId!).then((_) {}, onError: (_) {});
    }
    await _syncOpenChats();
  }

  /// Batches waiting for a watch that was turned off or deleted are
  /// dropped, so it doesn't fire once more after the person stopped it.
  void _dropInactive(List<Watch> active) {
    final ids = {for (final w in active) w.id};
    for (final key in _pending.keys.toList()) {
      if (ids.contains(key.split('|').first)) continue;
      _pending.remove(key);
      _firstPending.remove(key);
      _debounce.remove(key)?.cancel();
    }
  }

  /// Keeps the background service running when anything needs the app
  /// alive: watches, jobs or mention alerts (which need it to hear the
  /// mention), or always when the person asked for that. Watches don't
  /// depend on the Notifications setting: that only decides whether they
  /// alert.
  Future<void> _syncKeepAlive() async {
    final s = _ref.read(settingsProvider);
    if (!s.loaded) return;
    final active = _active;
    final jobs = s.proactive
        ? _ref
              .read(reminderStoreProvider)
              .where((r) => r.enabled && r.isJob)
              .length
        : 0;
    final notifier = _ref.read(appNotifierProvider);
    // Online alerts need the app alive too, to hear the status change.
    final routines = s.proactive
        ? _ref.read(routineStoreProvider).where((r) => r.enabled && r.trigger.kind != RoutineTriggerKind.manual).length
        : 0;
    final needed = active.isNotEmpty || jobs > 0 || routines > 0 || s.mentionAlerts || _ref.read(onlineAlertStoreProvider).isNotEmpty;
    await notifier.keepAlive(
      s.backgroundAlways || (s.keepAlive && needed),
      watches: active.length + jobs + routines,
      notice: s.backgroundNotice,
    );
    if (status.value.background != notifier.alive)
      status.value = status.value.copyWith(background: notifier.alive);
  }

  /// Opens the groups and channels the watches cover, in each account they
  /// cover, and closes ones no longer watched.
  Future<void> _syncOpenChats() async {
    var opened = 0;
    for (final account in _subs.keys.toList()) {
      // Nothing to keep open in an account that isn't signed in.
      if (_ref.read(telegramClientFamily(account)).authState is! td.AuthorizationStateReady) continue;
      await _syncOpenChatsIn(account);
      opened += _opened[account]?.length ?? 0;
    }
    status.value = status.value.copyWith(opened: opened);
  }

  Future<void> _syncOpenChatsIn(String account) async {
    final store = _store(account);
    bool needsOpen(ChatInfo c) =>
        c.type is td.ChatTypeSupergroup || c.type is td.ChatTypeBasicGroup;
    final want = <int>{};
    List<ChatInfo> recent(bool Function(ChatInfo) test) {
      final list =
          store.chats.values.where((c) => c.isListed && test(c)).toList()..sort(
            (a, b) =>
                (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0),
          );
      return list.take(_openPerScope).toList();
    }

    for (final w in _active.where((w) => w.covers(account))) {
      switch (w.scope) {
        case WatchScope.chats:
          want.addAll(
            w.chatIds.where(
              (id) => store.chat(id) != null && needsOpen(store.chat(id)!),
            ),
          );
        case WatchScope.allGroups:
          want.addAll(
            recent((c) => store.kindOf(c) == ChatKind.group && needsOpen(c))
                .map((c) => c.id),
          );
        case WatchScope.allChannels:
          want.addAll(
            recent((c) => store.kindOf(c) == ChatKind.channel).map((c) => c.id),
          );
        case WatchScope.folder:
          final ids = store.folderChats[w.folderId] ?? const [];
          want.addAll(
            recent((c) => ids.contains(c.id) && needsOpen(c)).map((c) => c.id),
          );
        default:
          break;
      }
    }
    final openChats = _openChats[account] = _ref.read(openChatsFamily(account));
    final opened = _opened[account] ??= {};
    for (final id in want.difference(opened)) {
      try {
        await openChats.acquire(id, _openChatOwner);
        opened.add(id);
      } catch (e) {
        debugPrint('[Watches] open $id: $e');
      }
    }
    for (final id in opened.difference(want).toList()) {
      try {
        await openChats.release(id, _openChatOwner);
      } catch (_) {}
      opened.remove(id);
    }
  }

  bool _matches(Watch w, td.Message m, TelegramStore store) {
    final chat = store.chat(m.chatId);
    if (chat == null) return false;
    if (!w.includeMuted && chat.isMuted) return false;
    final kind = store.kindOf(chat);
    return switch (w.scope) {
      WatchScope.chats => w.chatIds.contains(m.chatId),
      WatchScope.allDms => kind == ChatKind.private,
      WatchScope.allGroups => kind == ChatKind.group,
      WatchScope.allChannels => kind == ChatKind.channel,
      WatchScope.mentions => m.containsUnreadMention,
      WatchScope.folder =>
        w.folderId != null &&
            (store.folderChats[w.folderId!]?.contains(m.chatId) ?? false),
      WatchScope.schedule || WatchScope.app || WatchScope.device => false,
    };
  }

  // ---- online alerts -------------------------------------------------------

  /// Whether each alerted person was online at the last status heard, so
  /// an alert fires when they come online, not every time Telegram repeats
  /// that they are.
  final Map<int, bool> _wasOnline = {};

  /// New alerts start from what the app knows now: someone already online
  /// when the alert is made fires next time they come online.
  void _seedOnline() {
    final stores = [for (final id in _accountIds()) _store(id)];
    for (final a in _ref.read(onlineAlertStoreProvider)) {
      _wasOnline.putIfAbsent(a.userId, () => stores.any((s) => s.users[a.userId]?.status is td.UserStatusOnline));
    }
    unawaited(_syncKeepAlive());
  }

  /// Status updates for one person arrive from every account that sees
  /// them; [_wasOnline] makes the first one count and the rest repeat it.
  Future<void> _statusChanged(String account, int userId, td.UserStatus status) async {
    final online = status is td.UserStatusOnline;
    final was = _wasOnline[userId] ?? false;
    _wasOnline[userId] = online;
    if (!online || was) return;
    final alerts = _ref.read(onlineAlertStoreProvider.notifier);
    final a = alerts.of(userId);
    if (a == null) return;
    // A repeating alert stays quiet for a while after it fires.
    if (!a.once && a.lastFired != null && DateTime.now().difference(a.lastFired!) < const Duration(minutes: 15)) return;
    final store = _store(account);
    final name = store.users.containsKey(userId) ? store.userName(userId) : a.name;
    await alerts.fired(userId);
    await _ref.read(appNotifierProvider).show(
      '$name is online',
      a.once ? 'Tap to open your chat.' : 'Tap to open your chat. You\'ll hear again next time they come online.',
      // A private chat's id is the user's id; it opens in the account that
      // saw them come online.
      conversationId: 'chat:$userId@$account',
    );
  }

  void _onUpdate(String account, td.TdObject u) {
    switch (u) {
      case td.UpdateUserStatus(:final userId, :final status) when _wasOnline.containsKey(userId) || _ref.read(onlineAlertStoreProvider.notifier).of(userId) != null:
        unawaited(_statusChanged(account, userId, status));
      case td.UpdateNewMessage(:final message):
        _consider(account, message);
        if (message.containsUnreadMention && !message.isOutgoing)
          unawaited(_mentioned(account, message));
      case td.UpdateChatLastMessage(:final lastMessage?):
        _consider(account, lastMessage);
      case td.UpdateChatUnreadMentionCount(
        :final chatId,
        :final unreadMentionCount,
      ):
        // Groups the app hasn't opened don't send their messages, but the
        // mention count always arrives: a rise means a new mention.
        final key = '$account:$chatId';
        final before =
            _mentionCounts[key] ??
            _store(account).chat(chatId)?.unreadMentionCount ??
            0;
        _mentionCounts[key] = unreadMentionCount;
        if (unreadMentionCount > before) unawaited(_latestMention(account, chatId));
      default:
        break;
    }
  }

  final Map<String, int> _mentionCounts = {};
  final LinkedHashSet<String> _mentionSeen = LinkedHashSet();

  Future<void> _latestMention(String account, int chatId) async {
    try {
      final r = await _ref
          .read(telegramClientFamily(account))
          .send<td.FoundChatMessages>(
            td.SearchChatMessages(
              chatId: chatId,
              query: '',
              senderId: null,
              fromMessageId: 0,
              offset: 0,
              limit: 1,
              filter: const td.SearchMessagesFilterUnreadMention(),
              topicId: null,
            ),
            limited: true,
          );
      if (r.messages.isNotEmpty) await _mentioned(account, r.messages.first);
    } catch (e) {
      debugPrint('[Mentions] $chatId: $e');
    }
  }

  /// Someone mentioned the account (or replied to it): a notification that
  /// opens the chat, unless the person turned these off, for every account
  /// or for this one (Settings → Telegram → Accounts).
  Future<void> _mentioned(String account, td.Message m) async {
    if (!_ref.read(settingsProvider).mentionAlerts) return;
    if (!(_ref.read(accountsProvider).byId(account)?.mentionAlerts ?? true)) return;
    if (m.date < _since) return;
    if (!_mentionSeen.add('$account:${m.chatId}:${m.id}')) return;
    if (_mentionSeen.length > 500) _mentionSeen.remove(_mentionSeen.first);
    final store = _store(account);
    final chat = store.chat(m.chatId)?.title ?? 'a chat';
    final who = store.senderName(m.senderId);
    final g = gistOf(m.content);
    final text = g.text.isNotEmpty ? g.text : (g.detail ?? g.kind);
    await _ref
        .read(appNotifierProvider)
        .show(
          '$who mentioned you in $chat${_accountSuffix(account)}',
          text.length > 300 ? '${text.substring(0, 300)}…' : text,
          conversationId: 'chat:${m.chatId}@$account',
        );
  }

  void _consider(String account, td.Message m) {
    // Only what others write, and only new: the account's own messages,
    // the assistant's replies included, never trigger a watch.
    if (m.isOutgoing || m.sendingState != null || m.schedulingState != null)
      return;
    if (m.date < _since) return;
    if (gistOf(m.content).kind == 'service') return;
    final key = '$account:${m.chatId}:${m.id}';
    if (!_seen.add(key)) return;
    if (_seen.length > 2000) _seen.remove(_seen.first);
    status.value = status.value.copyWith(heard: status.value.heard + 1);

    final store = _store(account);
    for (final w in _active) {
      if (!w.covers(account) || !_matches(w, m, store)) continue;
      // A supergroup or channel both accounts are in delivers the same
      // message to each (their message ids are shared); it fires once.
      // Elsewhere message ids are each account's own, so nothing is merged.
      if (store.chat(m.chatId)?.type is td.ChatTypeSupergroup) {
        if (!_taken.add('${w.id}:${m.chatId}:${m.id}')) continue;
        if (_taken.length > 2000) _taken.remove(_taken.first);
      }
      status.value = status.value.copyWith(
        matched: status.value.matched + 1,
        last:
            '${w.name}: ${store.chat(m.chatId)?.title ?? 'a chat'} at ${DateFormat.Hm().format(DateTime.now())}',
      );
      // One batch per watch, account and chat: a burst in one chat is one
      // run about that chat, never mixed with whatever else matched.
      final key = '${w.id}|$account|${m.chatId}';
      (_pending[key] ??= []).add(m);
      _firstPending[key] ??= DateTime.now();
      _debounce[key]?.cancel();
      final waited = DateTime.now().difference(_firstPending[key]!);
      final wait = waited + _quiet > _maxWait ? _maxWait - waited : _quiet;
      _debounce[key] = Timer(
        wait.isNegative ? Duration.zero : wait,
        () => _flush(key),
      );
    }
  }

  void _tick() {
    // Nothing runs before settings (and so the keys) have loaded.
    if (!_ref.read(settingsProvider).loaded) return;
    unawaited(_syncKeepAlive());
    unawaited(_syncOpenChats());
    unawaited(_ref.read(briefStoreProvider.notifier).tick());
    unawaited(_ref.read(reminderStoreProvider.notifier).tick());
    final now = DateTime.now();
    _ref.read(routineRunnerProvider).tick(now);
    unawaited(_pollDevice());
    for (final w in _active.where((w) => w.scope == WatchScope.schedule || w.scope == WatchScope.app)) {
      // Quiet at night: the run waits for the morning.
      if (w.quietAtNight && Watch.isNight(now)) continue;
      final last = w.lastRunAt;
      var due = false;
      // An app watch checks its app every so often (15 minutes unless set).
      final every = w.everyMinutes ?? (w.scope == WatchScope.app ? 15 : null);
      if (every != null) {
        due = last == null || now.difference(last).inMinutes >= every;
      } else if (w.dailyAt != null) {
        final parts = w.dailyAt!.split(':');
        final h = int.tryParse(parts.first) ?? 0,
            min = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
        final today = DateTime(now.year, now.month, now.day, h, min);
        due =
            !now.isBefore(today) &&
            (last == null || last.isBefore(today)) &&
            now.difference(today).inHours < 2;
      }
      if (due && !_running.contains(w.id))
        unawaited(_fire(w, const [], scheduled: true));
    }
  }

  // ---- phone triggers ------------------------------------------------------

  bool _polling = false;

  /// Watches and routines that start on something on the phone, as owners
  /// for the device monitor: "w:<id>" and "r:<id>".
  List<(String, DeviceCondition)> _deviceOwners({bool opened = false}) {
    final s = _ref.read(settingsProvider);
    if (!s.proactive) return const [];
    bool wanted(DeviceCondition c) => opened == (c.kind == DeviceTriggerKind.appOpened);
    return [
      for (final w in _active)
        if (w.scope == WatchScope.device && w.device != null && wanted(w.device!)) ('w:${w.id}', w.device!),
      for (final r in _ref.read(routineStoreProvider))
        if (r.enabled && r.trigger.kind == RoutineTriggerKind.device && r.trigger.device != null && wanted(r.trigger.device!))
          ('r:${r.id}', r.trigger.device!),
    ];
  }

  Future<void> _pollDevice() async {
    if (_polling) return;
    final owners = _deviceOwners();
    if (owners.isEmpty) return;
    _polling = true;
    try {
      for (final f in await _ref.read(deviceEventsProvider).poll(owners)) {
        _deviceFired(f.ownerId, f.event, owners.firstWhere((o) => o.$1 == f.ownerId).$2);
      }
    } catch (e) {
      debugPrint('[Watches] phone: $e');
    } finally {
      _polling = false;
    }
  }

  void _appOpened() {
    final monitor = _ref.read(deviceEventsProvider);
    for (final (id, c) in _deviceOwners(opened: true)) {
      if (monitor.openedMayFire(id, c)) _deviceFired(id, 'The user just opened the Triangle app.', c);
    }
  }

  void _deviceFired(String owner, String event, DeviceCondition c) {
    // Texts and caller names are other people's words.
    final text = const {DeviceTriggerKind.newSms, DeviceTriggerKind.missedCall, DeviceTriggerKind.notification, DeviceTriggerKind.moneyIn, DeviceTriggerKind.moneyOut, DeviceTriggerKind.pageChanged, DeviceTriggerKind.youtubeUpload}.contains(c.kind)
        ? fence(event, 'phone ${c.kind.label.toLowerCase()}')
        : event;
    if (owner.startsWith('r:')) {
      _ref.read(routineRunnerProvider).fireDevice(owner.substring(2), text);
      return;
    }
    final w = _active.where((x) => 'w:${x.id}' == owner).firstOrNull;
    if (w == null || _running.contains(w.id)) return;
    status.value = status.value.copyWith(last: '${w.name}: ${c.describe()} at ${DateFormat.Hm().format(DateTime.now())}');
    unawaited(_fire(w, const [], scheduled: true, deviceEvent: text));
  }

  Future<void> _flush(String key) async {
    final parts = key.split('|');
    final watchId = parts.first;
    final account = parts[1];
    final messages = _pending.remove(key) ?? const [];
    _firstPending.remove(key);
    _debounce.remove(key);
    // Only a watch that is still on: one turned off or deleted while the
    // batch waited stays quiet.
    final w = _active.where((x) => x.id == watchId).firstOrNull;
    if (w == null || messages.isEmpty) return;
    if (_running.contains(w.id)) {
      // Still busy with the last batch: these join the next one.
      _pending[key] = [...messages, ...?_pending[key]];
      _firstPending[key] ??= DateTime.now();
      _debounce[key]?.cancel();
      _debounce[key] = Timer(_busyRetry, () => _flush(key));
      return;
    }
    await _fire(w, messages, account: account);
  }

  /// Fires [w] now, with the newest matching message there is (or as a
  /// scheduled run), so the person can see it work.
  Future<String?> runNow(Watch w) async {
    if (w.scope == WatchScope.device) {
      await _fire(w, const [], scheduled: true, test: true, deviceEvent: '(Test, not a real event) ${w.device?.describe() ?? 'A phone event'}.');
      return null;
    }
    if (w.scope == WatchScope.schedule || w.scope == WatchScope.app) {
      await _fire(w, const [], scheduled: true, test: true);
      return null;
    }
    // The newest matching message in any account the watch covers.
    (td.Message, String)? newest;
    for (final account in _accountIds().where(w.covers)) {
      final store = _store(account);
      for (final c in store.chats.values) {
        final m = c.lastMessage;
        if (m == null || m.isOutgoing || !_matches(w, m, store)) continue;
        if (newest == null || m.date > newest.$1.date) newest = (m, account);
      }
    }
    if (newest == null)
      return 'No message from someone else matches this watch yet.';
    await _fire(w, [newest.$1], test: true, account: newest.$2);
    return null;
  }

  String _line(td.Message m, TelegramStore store) {
    final g = gistOf(m.content);
    final chat = store.chat(m.chatId);
    final kind = chat == null ? null : store.kindOf(chat);
    final who = kind == ChatKind.channel ? null : store.senderName(m.senderId);
    final text = g.text.isNotEmpty ? g.text : (g.detail ?? g.kind);
    return '${who == null ? '' : '$who: '}${g.kind == 'text' ? '' : '[${g.kind}] '}$text${_replied[m.id] ?? ''}';
  }

  /// What each pending message replies to, as " (replying to …)".
  final Map<int, String> _replied = {};

  /// Looks up the messages [messages] reply to, so the assistant knows what
  /// someone is answering ("yes" to which question?).
  Future<void> _loadReplies(List<td.Message> messages, TelegramStore store, String account) async {
    final client = _ref.read(telegramClientFamily(account));
    for (final m in messages.take(12)) {
      final r = m.replyTo;
      if (r is! td.MessageReplyToMessage || r.messageId == 0 || _replied.containsKey(m.id)) continue;
      final quote = r.quote?.text.text ?? '';
      try {
        final o = await client.send<td.Message>(td.GetRepliedMessage(chatId: m.chatId, messageId: m.id), limited: true);
        final g = gistOf(o.content);
        final said = g.text.isNotEmpty ? g.text : (g.detail ?? g.kind);
        final who = o.isOutgoing ? 'you (the user)' : store.senderName(o.senderId);
        _replied[m.id] =
            ' (replying to $who, message_id ${o.id}: "${_clip(said, 160)}"${quote.isEmpty ? '' : ', quoting "${_clip(quote, 120)}"'})';
      } catch (_) {
        if (quote.isNotEmpty) _replied[m.id] = ' (replying, quoting "${_clip(quote, 120)}")';
      }
    }
    if (_replied.length > 500) _replied.remove(_replied.keys.first);
  }

  PostSnapshot _snapshot(td.Message m, TelegramStore store, String account) {
    final g = gistOf(m.content);
    final chat = store.chat(m.chatId);
    return PostSnapshot(
      chatId: m.chatId,
      messageId: m.id,
      chatTitle: chat?.title ?? 'Chat',
      date: DateTime.fromMillisecondsSinceEpoch(m.date * 1000),
      text: g.text.isNotEmpty ? g.text : (g.detail ?? ''),
      sender: chat != null && store.kindOf(chat) == ChatKind.channel
          ? null
          : store.senderName(m.senderId),
      kind: g.kind,
      accountId: account,
    );
  }

  Future<void> _fire(
    Watch w,
    List<td.Message> messages, {
    bool scheduled = false,
    bool test = false,
    String? account,
    String? deviceEvent,
  }) async {
    final settings = _ref.read(settingsProvider);
    final notifier = _ref.read(appNotifierProvider);
    // The account the messages came from; a scheduled run reads the first
    // account it covers for chat titles.
    final String storeAccount =
        account ?? _accountIds().where((id) => coversAccount(w.runAccounts, id)).firstOrNull ?? _ref.read(activeAccountIdProvider);
    final store = _store(storeAccount);
    final controller = _ref.read(chatControllerProvider.notifier);
    final started = DateTime.now();
    _running.add(w.id);
    try {
      await _ref
          .read(watchStoreProvider.notifier)
          .update(
            w.id,
            (x) => x.copyWith(lastRunAt: DateTime.now(), runs: x.runs + 1),
          );
      await _loadReplies(messages, store, storeAccount);
      final chats = {for (final m in messages) m.chatId};
      final where = '${chats.length == 1 ? (store.chat(chats.first)?.title ?? 'a chat') : '${chats.length} chats'}'
          '${_accountSuffix(account)}';

      if (w.mode == WatchMode.notify && deviceEvent != null) {
        // A phone event, straight to the chat and the shade; no AI.
        final shown = deviceEvent.replaceAll(RegExp(r'</?external[^>]*>'), '');
        final placed = await controller.postNotice(w, '${test ? 'Test run · ' : ''}${w.device?.describe() ?? 'Phone event'}', shown, const []);
        unawaited(_ref.read(activityLogProvider.notifier).recordRun(source: ActivitySource.watch, name: w.name, ok: true, text: 'Notified: $shown', conversationId: placed.conversationId));
        if (settings.notifications && w.notify && !placed.seen) {
          await notifier.show(w.name, shown.length > 400 ? '${shown.substring(0, 400)}…' : shown, conversationId: placed.conversationId);
        }
        return;
      }

      if (w.mode == WatchMode.notify && !scheduled) {
        // Straight to the chat and the notification shade; no AI.
        final markdown = [
          '**${chats.length == 1 ? where : w.name}** · ${messages.length} new message${messages.length == 1 ? '' : 's'}',
          '',
          for (final m in messages.take(12))
            '- ${chats.length > 1 ? '${store.chat(m.chatId)?.title ?? ''} · ' : ''}'
                '[${_clip(_line(m, store), 160)}](post:${m.chatId}:${m.id})',
          if (messages.length > 12) '- …and ${messages.length - 12} more',
        ].join('\n');
        final event =
            '${test ? 'Test run · ' : ''}${messages.length} new message${messages.length == 1 ? '' : 's'} in $where';
        final placed = await controller.postNotice(w, event, markdown, [
          for (final m in messages) _snapshot(m, store, storeAccount),
        ]);
        unawaited(_ref.read(activityLogProvider.notifier).recordRun(source: ActivitySource.watch, name: w.name, ok: true, text: 'Notified: $event', conversationId: placed.conversationId));
        if (settings.notifications && w.notify && !placed.seen) {
          final body = [
            for (final m in messages.take(6))
              '${chats.length > 1 ? '${store.chat(m.chatId)?.title ?? ''} · ' : ''}${_line(m, store)}',
            if (messages.length > 6) '+${messages.length - 6} more',
          ].join('\n');
          await notifier.show(
            chats.length == 1 ? where : w.name,
            body,
            conversationId: placed.conversationId,
          );
        }
        return;
      }

      final runs = (_aiRuns[w.id] ?? [])
        ..removeWhere((t) => DateTime.now().difference(t).inMinutes >= 60);
      if (runs.length >= _maxRunsPerHour) {
        status.value = status.value.copyWith(
          error: '${w.name} paused for this hour after $_maxRunsPerHour runs',
        );
        if (settings.notifications && w.notify)
          await notifier.show(
            w.name,
            'Paused for this hour: it already ran $_maxRunsPerHour times.',
          );
        return;
      }
      _aiRuns[w.id] = [...runs, DateTime.now()];

      final appName = w.app == null || w.app == 'any' ? 'the user\'s connected apps' : appLabel(w.app!);
      final event = deviceEvent != null
          ? '${test ? 'Test run · ' : ''}Phone event (${w.device?.describe() ?? 'on the phone'}): $deviceEvent'
          : w.scope == WatchScope.app
          ? '${test ? 'Test run · ' : ''}App watch: check $appName for anything new${w.query.isEmpty ? '' : ' matching: ${w.query}'}'
                '${w.lastRunAt == null || test ? ' (look at roughly the last day)' : ' since ${w.lastRunAt!.toIso8601String().substring(0, 16)}'}. '
                'Read only with the app\'s tools; then follow the instructions for what you found. '
                'If there is nothing new that matches, answer with exactly $nothingNew and nothing else.'
          : w.id == checkInWatchId
          ? '${test ? 'Test run · ' : ''}Check-in (every ${(w.everyMinutes ?? 360) ~/ 60} hours). It is '
                '${DateFormat('EEEE HH:mm').format(DateTime.now())}. '
                '${w.lastRunAt == null || test ? 'This is the first check-in: look at roughly the last day.' : 'The last check-in was at ${w.lastRunAt!.toIso8601String().substring(0, 16)}; only what is new since then counts.'} '
                'If there is nothing worth telling the user, answer with exactly $nothingNew and nothing else.'
          : scheduled
          ? '${test ? 'Test run · ' : ''}Scheduled run (${w.dailyAt != null ? 'daily at ${w.dailyAt}' : 'every ${w.everyMinutes} minutes'}).'
          : '${test ? 'Test run with the latest matching message · ' : ''}New messages arrived in $where:\n${[for (final m in messages) '- ${store.chat(m.chatId)?.title ?? 'Chat'} (chat_id ${m.chatId}, message_id ${m.id}, ref post:${m.chatId}:${m.id}'
                  '${m.isTopicMessage ? ', topic_id ${m.messageThreadId}' : ''}'
                  '${switch (m.senderId) {
                    td.MessageSenderUser(:final userId) => ', from user_id $userId',
                    _ => '',
                  }}): ${fence(_line(m, store), 'telegram message')}'].join('\n')}';
      // With several accounts, the run is told where the messages came from
      // and which accounts it may use.
      final accountsNote = !_several
          ? ''
          : account != null
          ? '\n(Heard in the user\'s Telegram account ${_ref.read(accountsProvider).byId(account)?.label ?? account}: act there unless the instructions say otherwise.)'
          : '\n(This run covers ${w.runAccounts == null ? 'all of the user\'s Telegram accounts' : 'these Telegram accounts: ${_ref.read(accountsProvider).within(w.runAccounts).map((a) => a.label).join(', ')}'}; say which account each finding is from.)';
      final result = await controller.runAutomatic(
        w,
        '$event$accountsNote',
        accounts: w.runAccounts,
        account: account,
        // Replies to these chats don't need approval after reading them.
        sourceChats: scheduled || w.scope == WatchScope.app ? null : chats,
      );
      // The app may have shut down while the run went on.
      if (!_ref.mounted) return;
      // A widget's refresh: its history says whether it updated.
      await _ref.read(homeWidgetsProvider.notifier).recordRun(
        w.id,
        started: started,
        result: result?.text ?? 'No AI key: add one in Settings.',
        failed: result == null,
      );
      if (result == null) {
        status.value = status.value.copyWith(
          error: 'No AI key: add one in Settings so watches can run.',
        );
        return;
      }
      // It ran: an earlier problem is no longer current.
      if (status.value.error != null) status.value = status.value.clearError();
      // An app watch, the check-in or a schedule that found nothing stays quiet.
      if ((w.scope == WatchScope.app || w.scope == WatchScope.schedule) && result.text.trim().contains(nothingNew)) return;
      if (!settings.notifications || !w.notify || result.seen) return;
      final text = Speaker.clean(result.text);
      await notifier.show(
        w.name,
        text.isEmpty
            ? 'New update in $where'
            : (text.length > 400 ? '${text.substring(0, 400)}…' : text),
        conversationId: result.conversationId,
      );
    } catch (e) {
      debugPrint('[Watch ${w.name}] $e');
      status.value = status.value.copyWith(error: '${w.name}: $e');
      if (_ref.mounted) await _ref.read(homeWidgetsProvider.notifier).recordRun(w.id, started: started, result: '$e', failed: true);
    } finally {
      _running.remove(w.id);
    }
  }

  static String _clip(String s, int max) {
    final one = s
        .replaceAll('\n', ' ')
        .replaceAll('[', '(')
        .replaceAll(']', ')');
    return one.length <= max ? one : '${one.substring(0, max)}…';
  }
}

/// What an app watch answers when it found nothing, so nobody is notified.
const nothingNew = 'NOTHING_NEW';

final watchEngineProvider = Provider<WatchEngine>((ref) {
  final engine = WatchEngine(ref);
  ref.onDispose(engine.dispose);
  return engine;
});
