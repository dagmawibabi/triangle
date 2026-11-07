import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';
import 'td_hub.dart';
import 'telegram_client.dart';

/// The account that existed before Triangle supported several. It keeps the
/// original folder (`tdlib/db`, `tdlib/files`) and database key, so nobody
/// is signed out by the upgrade.
const legacyAccountId = 'main';

/// Telegram's own apps allow three accounts (four with Premium); that is a
/// limit of those apps, not of Telegram or TDLib, which runs any number of
/// instances side by side. Triangle allows five: each is a full TDLib
/// instance with its own connection, database and memory, all sharing one
/// receive loop, so more would mostly cost the phone memory and battery.
const maxAccounts = 5;

/// Where one account's TDLib data lives. TDLib refuses to open one database
/// from two instances, so every account needs its own folder.
class AccountPaths {
  const AccountPaths(this.accountId);
  final String accountId;

  Future<Directory> root() async {
    final base = '${(await getApplicationSupportDirectory()).path}/tdlib';
    return Directory(accountId == legacyAccountId ? base : '$base/accounts/$accountId');
  }
}

/// A Telegram account added to Triangle, and how the assistant may use it.
@immutable
class TelegramAccount {
  const TelegramAccount({
    required this.id,
    this.userId,
    this.name = '',
    this.username,
    this.aiAccess = true,
    this.disabledTools,
    this.enabledDangerTools,
    this.mentionAlerts = true,
    this.readOnly = false,
    this.approvalMode,
  });

  final String id;

  /// The assistant may only read in this account, whatever Settings say.
  final bool readOnly;

  /// This account's own approval mode (an ApprovalMode name: ask, watches,
  /// never) for the assistant's Telegram actions in it. Null: Settings →
  /// Approvals decides.
  final String? approvalMode;

  /// Notify when someone mentions or replies to this account (with the
  /// mention alerts setting on).
  final bool mentionAlerts;

  /// Telegram's id for the signed-in user; null until sign-in completes.
  final int? userId;
  final String name;
  final String? username;

  /// Whether the assistant's Telegram tools may reach this account.
  final bool aiAccess;

  /// This account's own tool switches. Null: it follows Settings → Tools.
  final Set<String>? disabledTools;
  final Set<String>? enabledDangerTools;

  bool get signedIn => userId != null;
  bool get customTools => disabledTools != null;
  String get label => name.isNotEmpty ? name : (username != null ? '@$username' : 'Telegram account');

  TelegramAccount copyWith({
    int? userId,
    String? name,
    String? username,
    bool? aiAccess,
    Set<String>? disabledTools,
    Set<String>? enabledDangerTools,
    bool clearCustomTools = false,
    bool? mentionAlerts,
    bool? readOnly,
    String? approvalMode,
    bool clearApprovalMode = false,
  }) => TelegramAccount(
    id: id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    username: username ?? this.username,
    aiAccess: aiAccess ?? this.aiAccess,
    disabledTools: clearCustomTools ? null : (disabledTools ?? this.disabledTools),
    enabledDangerTools: clearCustomTools ? null : (enabledDangerTools ?? this.enabledDangerTools),
    mentionAlerts: mentionAlerts ?? this.mentionAlerts,
    readOnly: readOnly ?? this.readOnly,
    approvalMode: clearApprovalMode ? null : (approvalMode ?? this.approvalMode),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (userId != null) 'userId': userId,
    'name': name,
    if (username != null) 'username': username,
    'aiAccess': aiAccess,
    if (disabledTools != null) 'disabledTools': disabledTools!.toList(),
    if (enabledDangerTools != null) 'enabledDangerTools': enabledDangerTools!.toList(),
    if (!mentionAlerts) 'mentionAlerts': false,
    if (readOnly) 'readOnly': true,
    'approvalMode': ?approvalMode,
  };

  static TelegramAccount fromJson(Map<String, dynamic> j) => TelegramAccount(
    id: j['id'] as String,
    userId: (j['userId'] as num?)?.toInt(),
    name: j['name'] as String? ?? '',
    username: j['username'] as String?,
    aiAccess: j['aiAccess'] as bool? ?? true,
    disabledTools: (j['disabledTools'] as List?)?.map((e) => '$e').toSet(),
    enabledDangerTools: (j['enabledDangerTools'] as List?)?.map((e) => '$e').toSet(),
    mentionAlerts: j['mentionAlerts'] as bool? ?? true,
    readOnly: j['readOnly'] as bool? ?? false,
    approvalMode: j['approvalMode'] as String?,
  );
}

/// Whether a watch, job or brief limited to [ids] covers [accountId]. Null
/// means every account, including ones added later.
bool coversAccount(List<String>? ids, String accountId) => ids == null || ids.contains(accountId);

@immutable
class AccountsState {
  const AccountsState({
    required this.accounts,
    required this.activeId,
    this.addingId,
    this.returnToId,
    this.notice,
  });

  static const initial = AccountsState(
    accounts: [TelegramAccount(id: legacyAccountId)],
    activeId: legacyAccountId,
  );

  final List<TelegramAccount> accounts;
  final String activeId;

  /// An account being signed in from "Add account"; it is active meanwhile.
  final String? addingId;

  /// The account to go back to if adding is cancelled.
  final String? returnToId;

  /// A one-off message for the sign-in page ("already added", …).
  final String? notice;

  TelegramAccount get active => byId(activeId) ?? accounts.first;
  TelegramAccount? byId(String id) => accounts.where((a) => a.id == id).firstOrNull;

  /// Signed-in accounts, the one being added excluded.
  List<TelegramAccount> get signedIn => [
    for (final a in accounts)
      if (a.signedIn && a.id != addingId) a,
  ];

  bool get hasSeveral => signedIn.length > 1;
  bool get canAdd => addingId == null && signedIn.length < maxAccounts;

  /// The accounts the assistant's Telegram tools may use.
  List<TelegramAccount> get forAi => [
    for (final a in signedIn)
      if (a.aiAccess) a,
  ];

  /// Signed-in accounts within [ids] (null: all of them).
  List<TelegramAccount> within(List<String>? ids) => [
    for (final a in signedIn)
      if (coversAccount(ids, a.id)) a,
  ];

  /// What an automatic run (a watch, job or brief) may use: only the
  /// accounts in [ids] (null: all), defaulting to [preferred], the account
  /// a message was heard in. Accounts outside are left out of the
  /// assistant's reach for that run.
  AccountsState limitedTo(List<String>? ids, {String? preferred}) {
    final allowed = [
      for (final a in accounts)
        if (coversAccount(ids, a.id)) a.id,
    ];
    final ai = [
      for (final a in forAi)
        if (allowed.contains(a.id)) a.id,
    ];
    final defaultId = preferred != null && ai.contains(preferred)
        ? preferred
        : ai.contains(activeId)
        ? activeId
        : (ai.firstOrNull ?? activeId);
    return AccountsState(
      accounts: [
        for (final a in accounts)
          allowed.contains(a.id) ? a : a.copyWith(aiAccess: false),
      ],
      activeId: defaultId,
      addingId: addingId,
      returnToId: returnToId,
    );
  }

  AccountsState copyWith({
    List<TelegramAccount>? accounts,
    String? activeId,
    String? addingId,
    String? returnToId,
    String? notice,
    bool clearAdding = false,
    bool clearNotice = false,
  }) => AccountsState(
    accounts: accounts ?? this.accounts,
    activeId: activeId ?? this.activeId,
    addingId: clearAdding ? null : (addingId ?? this.addingId),
    returnToId: clearAdding ? null : (returnToId ?? this.returnToId),
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}

/// The list of accounts, kept in SharedPreferences. It is read before the
/// app starts so TDLib opens the right account first.
class AccountRegistry {
  static const _accountsKey = 'tg_accounts';
  static const _activeKey = 'tg_active_account';

  static Future<AccountsState> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_accountsKey);
      if (raw == null) return AccountsState.initial;
      final list = [
        for (final e in jsonDecode(raw) as List) TelegramAccount.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      // An "Add account" the app was closed in the middle of is dropped;
      // its folder is cleared by [AccountsController.cleanUpLeftovers].
      final kept = [
        for (final a in list)
          if (a.signedIn || a.id == legacyAccountId) a,
      ];
      if (kept.isEmpty) kept.add(const TelegramAccount(id: legacyAccountId));
      final active = p.getString(_activeKey);
      return AccountsState(
        accounts: kept,
        activeId: kept.any((a) => a.id == active) ? active! : kept.first.id,
      );
    } catch (e) {
      debugPrint('[Accounts] Could not read the account list: $e');
      return AccountsState.initial;
    }
  }

  static Future<void> save(AccountsState s) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_accountsKey, jsonEncode([for (final a in s.accounts) a.toJson()]));
      // While an account is being added, the one to come back to is what a
      // restart should open.
      await p.setString(_activeKey, s.addingId != null ? (s.returnToId ?? s.activeId) : s.activeId);
    } catch (e) {
      debugPrint('[Accounts] Could not save the account list: $e');
    }
  }
}

/// The registry as it was read at launch (overridden in main()).
final initialAccountsProvider = Provider<AccountsState>((ref) => AccountsState.initial);

class AccountsController extends Notifier<AccountsState> {
  @override
  AccountsState build() => ref.read(initialAccountsProvider);

  void _set(AccountsState next) {
    state = next;
    unawaited(AccountRegistry.save(next));
  }

  void switchTo(String id) {
    if (id == state.activeId || state.byId(id)?.signedIn != true) return;
    _set(state.copyWith(activeId: id));
  }

  /// Starts signing in another account. It becomes the active account so the
  /// usual sign-in screens drive it; [cancelAdd] goes back.
  String beginAdd() {
    if (state.addingId != null) return state.addingId!;
    if (!state.canAdd) {
      throw StateError('You can add up to $maxAccounts Telegram accounts.');
    }
    final id = 'a${DateTime.now().millisecondsSinceEpoch}';
    _set(
      state.copyWith(
        accounts: [...state.accounts, TelegramAccount(id: id)],
        addingId: id,
        returnToId: state.activeId,
        activeId: id,
        clearNotice: true,
      ),
    );
    ref.read(telegramClientFamily(id));
    return id;
  }

  /// Abandons the account being added and goes back to the previous one.
  Future<void> cancelAdd({String? notice}) async {
    final id = state.addingId;
    if (id == null) return;
    final back = state.returnToId ?? state.signedIn.firstOrNull?.id ?? legacyAccountId;
    _set(
      state.copyWith(
        accounts: [for (final a in state.accounts) if (a.id != id) a],
        activeId: back,
        notice: notice,
        clearAdding: true,
      ),
    );
    await _discard(id);
  }

  void clearNotice() => state = state.copyWith(clearNotice: true);

  /// TDLib reports [id] signed in: record who it is. Adding an account that
  /// is already here is undone (Telegram would just see a second session).
  Future<void> onReady(String id, TelegramClient client) async {
    td.User me;
    try {
      me = await client.send<td.User>(const td.GetMe());
    } catch (e) {
      debugPrint('[Accounts] getMe for $id failed: $e');
      return;
    }
    final duplicate = state.accounts.any((a) => a.id != id && a.userId == me.id);
    if (duplicate && id == state.addingId) {
      final existing = state.accounts.firstWhere((a) => a.id != id && a.userId == me.id);
      // Signs this new session out on Telegram's side too, so it doesn't
      // linger in the account's Devices list.
      await cancelAdd(notice: '${existing.label} is already added.');
      _set(state.copyWith(activeId: existing.id));
      return;
    }
    final name = '${me.firstName} ${me.lastName}'.trim();
    final names = me.usernames?.activeUsernames ?? const <String>[];
    _set(
      state.copyWith(
        accounts: [
          for (final a in state.accounts)
            if (a.id == id) a.copyWith(userId: me.id, name: name, username: names.isEmpty ? null : names.first) else a,
        ],
        clearAdding: id == state.addingId,
        activeId: id == state.addingId ? id : null,
      ),
    );
  }

  /// Signs [id] out. With other accounts signed in it is removed and another
  /// becomes active; the last account instead goes back to the sign-in
  /// screen, as before. Returns whether the account was removed.
  Future<bool> signOut(String id) async {
    final others = [for (final a in state.signedIn) if (a.id != id) a];
    if (others.isEmpty) {
      await ref.read(telegramClientFamily(id)).logOut();
      _set(state.copyWith(accounts: [for (final a in state.accounts) a.id == id ? TelegramAccount(id: a.id) : a]));
      return false;
    }
    _set(
      state.copyWith(
        accounts: [for (final a in state.accounts) if (a.id != id) a],
        activeId: state.activeId == id ? others.first.id : null,
      ),
    );
    await _discard(id);
    return true;
  }

  /// Signs [id] out of Telegram (or just closes it, mid sign-in), closes its
  /// TDLib instance and deletes its folder and key.
  Future<void> _discard(String id) async {
    try {
      await ref.read(telegramClientFamily(id)).logOutForGood();
    } catch (e) {
      debugPrint('[Accounts] closing $id: $e');
    }
    ref.invalidate(telegramClientFamily(id));
    await _deleteData(id);
  }

  Future<void> _deleteData(String id) async {
    try {
      final dir = await AccountPaths(id).root();
      if (id == legacyAccountId) {
        // The first account's folder also holds the others; only its own
        // parts go.
        for (final part in ['db', 'files', 'client.json']) {
          final e = File('${dir.path}/$part');
          if (await e.exists()) await e.delete();
          final d = Directory('${dir.path}/$part');
          if (await d.exists()) await d.delete(recursive: true);
        }
      } else if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await ref.read(secureStoreProvider).clearDatabaseKey(id);
    } catch (e) {
      debugPrint('[Accounts] deleting $id data: $e');
    }
  }

  /// Folders of accounts no longer listed (an "Add account" the app was
  /// closed during): nothing uses them, so they're deleted.
  Future<void> cleanUpLeftovers() async {
    try {
      final base = Directory('${(await getApplicationSupportDirectory()).path}/tdlib/accounts');
      if (!await base.exists()) return;
      final known = {for (final a in state.accounts) a.id};
      await for (final e in base.list()) {
        final id = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is Directory && !known.contains(id)) {
          await e.delete(recursive: true);
          await ref.read(secureStoreProvider).clearDatabaseKey(id);
        }
      }
    } catch (e) {
      debugPrint('[Accounts] cleanup: $e');
    }
  }

  // ---- what the assistant may do in each account ------------------------

  void _updateAccount(String id, TelegramAccount Function(TelegramAccount) change) => _set(
    state.copyWith(accounts: [for (final a in state.accounts) a.id == id ? change(a) : a]),
  );

  void setAiAccess(String id, bool on) => _updateAccount(id, (a) => a.copyWith(aiAccess: on));

  void setMentionAlerts(String id, bool on) => _updateAccount(id, (a) => a.copyWith(mentionAlerts: on));

  void setReadOnly(String id, bool on) => _updateAccount(id, (a) => a.copyWith(readOnly: on));

  /// [mode] is an ApprovalMode name, or null to follow Settings.
  void setApprovalMode(String id, String? mode) =>
      _updateAccount(id, (a) => a.copyWith(approvalMode: mode, clearApprovalMode: mode == null));

  /// Gives [id] its own tool switches, starting from [disabled]/[danger]
  /// (the shared ones), or with [on] false returns it to the shared ones.
  void setCustomTools(String id, bool on, {Set<String> disabled = const {}, Set<String> danger = const {}}) =>
      _updateAccount(
        id,
        (a) => on ? a.copyWith(disabledTools: {...disabled}, enabledDangerTools: {...danger}) : a.copyWith(clearCustomTools: true),
      );

  void setAccountTool(String id, String tool, bool enabled, {required bool destructive}) => _updateAccount(id, (a) {
    if (!a.customTools) return a;
    if (destructive) {
      final next = {...?a.enabledDangerTools};
      enabled ? next.add(tool) : next.remove(tool);
      return a.copyWith(enabledDangerTools: next);
    }
    final next = {...?a.disabledTools};
    enabled ? next.remove(tool) : next.add(tool);
    return a.copyWith(disabledTools: next);
  });
}

final accountsProvider = NotifierProvider<AccountsController, AccountsState>(AccountsController.new);

final activeAccountIdProvider = Provider<String>((ref) => ref.watch(accountsProvider.select((s) => s.activeId)));

/// Every account's TDLib client, started as soon as it is first read. Each
/// lives until its account is removed.
final telegramClientFamily = Provider.family<TelegramClient, String>((ref, id) {
  final client = TelegramClient(ref.watch(secureStoreProvider), ref.watch(tdHubProvider), accountId: id);
  final sub = client.authStates.listen((s) {
    if (s is td.AuthorizationStateReady) unawaited(ref.read(accountsProvider.notifier).onReady(id, client));
  });
  // Only listed accounts start TDLib: something still showing an account
  // just removed must not open a fresh instance in its deleted folder.
  final listed = id == legacyAccountId || ref.read(accountsProvider).byId(id) != null;
  if (listed) unawaited(client.start().catchError((_) {}));
  ref.onDispose(() {
    sub.cancel();
    unawaited(client.dispose());
  });
  return client;
});

/// The authorization state of one account.
final accountAuthProvider = StreamProvider.family<td.AuthorizationState, String>((ref, id) {
  return ref.watch(telegramClientFamily(id)).authStates;
});
