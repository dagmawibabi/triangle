import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:handy_tdlib/handy_tdlib.dart' show TdPlugin;

import '../../core/config/app_config.dart';
import 'accounts.dart';
import 'rate_limiter.dart';
import 'secure_store.dart';
import 'td_hub.dart';
import 'telegram_exception.dart';

/// One account's connection to Telegram, following telegrive's design.
///
/// Wraps TDLib's JSON interface: requests go out with an `@extra` tag and the
/// matching reply completes the future returned by [send]; everything else is
/// an update and goes to [updates]. Signing out closes the TDLib instance;
/// when it reports `authorizationStateClosed` a fresh client is created on
/// the same receiver, which lands back on the sign-in screen — unless the
/// account is being removed ([logOutForGood]).
///
/// Each account has its own TDLib instance, database folder and encryption
/// key ([AccountPaths]); all of them share the process's one [TdHub].
class TelegramClient {
  TelegramClient(this._secureStore, this._hub, {this.accountId = legacyAccountId});

  final SecureStore _secureStore;
  final TdHub _hub;

  /// The account this client belongs to (see [AccountPaths]).
  final String accountId;
  late final AccountPaths _paths = AccountPaths(accountId);
  void Function()? _unlisten;

  /// Whether a closed client is replaced by a fresh one (back to sign-in).
  /// Off while the account is being removed for good.
  bool _reopenOnClose = true;
  Completer<void> _closed = Completer<void>();

  /// Paces requests that reach Telegram's servers; see [send]'s `limited`.
  final RateLimiter limiter = RateLimiter();

  int? _clientId;
  int _requestSeq = 0;
  bool _disposed = false;
  Future<void>? _starting;

  final Map<String, Completer<td.TdObject>> _pending = {};

  final _updates = StreamController<td.TdObject>.broadcast();
  final _authStates = StreamController<td.AuthorizationState>.broadcast();
  td.AuthorizationState? _authState;
  Completer<void> _ready = Completer<void>();

  /// Set when configuration itself failed. Shown on the splash screen.
  final ValueNotifier<String?> fatalError = ValueNotifier(null);

  Stream<td.TdObject> get updates => _updates.stream;

  td.AuthorizationState? get authState => _authState;

  /// Authorization states, replaying the current one to each new listener.
  Stream<td.AuthorizationState> get authStates async* {
    final current = _authState;
    if (current != null) yield current;
    yield* _authStates.stream;
  }

  /// Completes once an account is signed in.
  Future<void> get ready => _ready.future;

  /// Loads TDLib, starts receiving and creates the first client.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    if (!AppConfig.hasTelegramCredentials) {
      fatalError.value =
          'Telegram API credentials are missing. Copy lib/core/config/telegram_api.example.dart '
          'to telegram_api.dart and fill in your api_id and api_hash from my.telegram.org.';
      return;
    }
    try {
      _root = await _paths.root();
      await _root!.create(recursive: true);
      // A client this process opened and never closed: a hot restart, or
      // Android starting a new Flutter engine in the same process after the
      // app was backed out of. TDLib still has it open and holds the
      // database lock, so it is taken over rather than opened twice.
      final leftOpen = await _leftOpenClient();
      await _hub.start();
      _unlisten ??= _hub.listen(_handlePayload);
      if (leftOpen != null) {
        _adopt(leftOpen);
      } else {
        _createClient();
      }
    } catch (e) {
      _starting = null;
      fatalError.value = 'Could not start Telegram: $e';
      rethrow;
    }
  }

  Directory? _root;

  File? get _clientFile =>
      _root == null ? null : File('${_root!.path}/client.json');

  /// The client id `client.json` names, when this very process wrote it.
  Future<int?> _leftOpenClient() async {
    try {
      final saved = jsonDecode(await _clientFile!.readAsString());
      if (saved is Map && saved['pid'] == pid && saved['clientId'] is int)
        return saved['clientId'] as int;
    } catch (_) {
      // None saved, or unreadable: nothing to take over.
    }
    return null;
  }

  Future<void> _saveClient(int clientId) async {
    try {
      await _clientFile?.writeAsString(
        jsonEncode({'pid': pid, 'clientId': clientId}),
      );
    } catch (e) {
      debugPrint('[Telegram] Could not save the client id: $e');
    }
  }

  void _createClient() {
    final clientId = _clientId = TdPlugin.instance.tdCreateClientId();
    debugPrint('[Telegram] Client $clientId created');
    unawaited(_saveClient(clientId));
    // TDLib emits its first authorization state in response to any request.
    unawaited(_sendQuietly(const td.GetOption(name: 'version')));
  }

  /// Carries on with [clientId], which TDLib still has open. It sends no
  /// update for a state it is already in, so the state is asked for; the
  /// chat list is replayed by the store's next loadChats.
  void _adopt(int clientId) {
    _clientId = clientId;
    debugPrint('[Telegram] Client $clientId taken over');
    unawaited(() async {
      try {
        _onAuthorizationState(
          await send<td.AuthorizationState>(const td.GetAuthorizationState()),
        );
      } catch (e) {
        debugPrint('[Telegram] Could not take client $clientId over: $e');
        if (!_disposed) _createClient();
      }
    }());
  }

  /// Sends [function] and waits for its typed reply.
  ///
  /// With [limited], the request waits its turn in [limiter] first: use it
  /// for anything that may reach Telegram's servers rather than TDLib's
  /// local database. A short flood wait (≤ 10 s) is sat out once and the
  /// request retried; a longer one pauses the limiter and surfaces as a
  /// [TelegramException].
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
    bool limited = false,
  }) async {
    if (limited) await limiter.acquire();
    try {
      return await _sendOnce<T>(function, timeout);
    } on TelegramException catch (e) {
      final wait = e.retryAfterSeconds;
      if (!e.isFloodWait || wait == null) rethrow;
      limiter.floodWait(wait);
      if (wait > 10) rethrow;
      await Future<void>.delayed(Duration(seconds: wait, milliseconds: 250));
      return _sendOnce<T>(function, timeout);
    }
  }

  Future<T> _sendOnce<T extends td.TdObject>(
    td.TdFunction function,
    Duration timeout,
  ) async {
    final clientId = _clientId;
    if (clientId == null)
      throw const TelegramException(500, 'Telegram is not running');
    final extra = '${++_requestSeq}';
    final completer = Completer<td.TdObject>();
    _pending[extra] = completer;
    TdPlugin.instance.tdSend(clientId, jsonEncode(function.toJson(extra)));

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(extra);
        throw const TelegramException(408, 'Request timeout');
      },
    );
    if (result is! T) {
      throw TelegramException(
        500,
        'Expected $T from ${function.runtimeType}, got ${result.runtimeType}',
      );
    }
    return result;
  }

  void _handlePayload(Map<String, dynamic> map) {
    final owner = map['@client_id'];
    if (owner != null && owner != _clientId) return;

    if (map.containsKey('@extra')) {
      final completer = _pending.remove('${map['@extra']}');
      if (completer == null) return;
      final object = td.convertMapToObject(map);
      if (object == null) {
        completer.completeError(
          TelegramException(500, 'Unreadable reply: ${map['@type']}'),
        );
      } else if (object is td.TdError) {
        completer.completeError(TelegramException(object.code, object.message));
      } else {
        completer.complete(object);
      }
      return;
    }

    final object = td.convertMapToObject(map);
    if (object == null) return;
    if (object is td.UpdateAuthorizationState)
      _onAuthorizationState(object.authorizationState);
    if (!_updates.isClosed) _updates.add(object);
  }

  void _onAuthorizationState(td.AuthorizationState state) {
    debugPrint('[Telegram] Auth state → ${state.runtimeType}');
    _authState = state;
    if (!_authStates.isClosed) _authStates.add(state);

    switch (state) {
      case td.AuthorizationStateWaitTdlibParameters():
        unawaited(_configure());
      case td.AuthorizationStateReady():
        if (!_ready.isCompleted) _ready.complete();
        unawaited(setOnline(_wantOnline));
      case td.AuthorizationStateLoggingOut():
        _waitForSignIn();
      case td.AuthorizationStateClosed():
        _waitForSignIn();
        _failPending();
        if (!_closed.isCompleted) _closed.complete();
        if (!_disposed && _reopenOnClose) {
          _closed = Completer<void>();
          _createClient();
        }
      default:
        break;
    }
  }

  void _waitForSignIn() {
    if (_ready.isCompleted) _ready = Completer<void>();
  }

  Future<void> _configure() async {
    final root = await _paths.root();
    final databaseDir = Directory('${root.path}/db');
    final filesDir = Directory('${root.path}/files');
    await databaseDir.create(recursive: true);
    await filesDir.create(recursive: true);

    // Encrypted from the very first launch; TDLib only allows changing the
    // key after sign-in, so there is no "encrypt later".
    var key = await _secureStore.readDatabaseKey(accountId);
    if (key == null || key.isEmpty) {
      key = SecureStore.generateDatabaseKey();
      await _secureStore.writeDatabaseKey(key, accountId);
    }

    td.SetTdlibParameters parameters(String key) => td.SetTdlibParameters(
      useTestDc: false,
      databaseDirectory: databaseDir.path,
      filesDirectory: filesDir.path,
      databaseEncryptionKey: key,
      useFileDatabase: true,
      useChatInfoDatabase: true,
      useMessageDatabase: true,
      useSecretChats: false,
      apiId: AppConfig.telegramApiId,
      apiHash: AppConfig.telegramApiHash,
      systemLanguageCode: Platform.localeName.split('_').first,
      deviceModel: '${AppConfig.appName} on ${Platform.operatingSystem}',
      systemVersion: Platform.operatingSystemVersion,
      applicationVersion: AppConfig.version,
    );

    try {
      await send<td.Ok>(parameters(key));
    } on TelegramException catch (e) {
      // Another client in this process still holds the database. It is
      // sound, so it is never started over; that client is taken over on
      // the next start.
      if (e.message.contains('already in use')) {
        fatalError.value = 'Telegram is still closing from the last run. Close the app fully and open it again.';
        return;
      }
      // The database and its key disagree — typically restored app data
      // without the keystore entry. The local cache is only a cache.
      debugPrint('[Telegram] Parameters rejected (${e.message}); resetting');
      await databaseDir.delete(recursive: true);
      await databaseDir.create(recursive: true);
      final fresh = SecureStore.generateDatabaseKey();
      await _secureStore.writeDatabaseKey(fresh, accountId);
      try {
        await send<td.Ok>(parameters(fresh));
      } on TelegramException catch (e) {
        fatalError.value = e.friendlyMessage;
      }
    }
  }

  bool _wantOnline = false;

  /// Whether Telegram sees this session as online. Telegram only sends an
  /// online session other people's typing and live status, so the app is
  /// online while it is on screen (when Settings allow) and offline otherwise.
  Future<void> setOnline(bool online) async {
    _wantOnline = online;
    if (_authState is! td.AuthorizationStateReady) return;
    await _sendQuietly(
      td.SetOption(
        name: 'online',
        value: td.OptionValueBoolean(value: online),
      ),
    );
  }

  Future<void> logOut() => _sendQuietly(const td.LogOut());

  /// Signs out (TDLib destroys the account's local data) and does not open a
  /// fresh client afterwards: the account is being removed. Completes once
  /// TDLib has closed the instance, or after [timeout].
  Future<void> logOutForGood({Duration timeout = const Duration(seconds: 20)}) async {
    _reopenOnClose = false;
    if (_clientId == null || _authState is td.AuthorizationStateClosed) return;
    final closed = _closed.future;
    // An account that never finished signing in has nothing on the server
    // to sign out of; closing is enough.
    final signedIn = _authState is td.AuthorizationStateReady;
    await _sendQuietly(signedIn ? const td.LogOut() : const td.Close());
    await closed.timeout(timeout, onTimeout: () {});
  }

  /// Abandons a QR sign-in attempt and starts a fresh authorization flow.
  ///
  /// TDLib can't switch directly from `authorizationStateWaitOtherDeviceConfirmation`
  /// to a phone-number request. Logging out is the documented way to close
  /// that unauthenticated client; the closed-state handler then creates a new
  /// client which proceeds to `authorizationStateWaitPhoneNumber`.
  Future<void> restartAfterQrAuthentication() async {
    if (_authState is! td.AuthorizationStateWaitOtherDeviceConfirmation) {
      return;
    }
    await _sendQuietly(const td.LogOut());
  }

  Future<void> _sendQuietly(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      await send<td.TdObject>(function, timeout: timeout);
    } catch (e) {
      debugPrint('[Telegram] ${function.runtimeType} failed: $e');
    }
  }

  void _failPending() {
    final pending = Map.of(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      completer.completeError(
        const TelegramException(500, 'Telegram session closed'),
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    // All instances must be closed for the database to stay consistent
    // (td_json_client.h); one already closed has nothing left to close.
    if (_clientId != null && _authState is! td.AuthorizationStateClosed) {
      await _sendQuietly(const td.Close());
    }
    _unlisten?.call();
    _unlisten = null;
    _failPending();
    await _updates.close();
    await _authStates.close();
    fatalError.dispose();
  }
}

/// The active account's client. Everything that works with "the" Telegram
/// account reads this, so switching accounts rebuilds it all.
final telegramClientProvider = Provider<TelegramClient>((ref) {
  return ref.watch(telegramClientFamily(ref.watch(activeAccountIdProvider)));
});

/// The live TDLib authorization state of the active account.
final authStateProvider = StreamProvider<td.AuthorizationState>((ref) {
  return ref.watch(telegramClientProvider).authStates;
});
