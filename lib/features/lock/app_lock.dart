import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../assistant/activity_log.dart';

/// App lock: a passcode (kept only as a salted PBKDF2 hash in the platform
/// keystore) and, optionally, fingerprint or face unlock. The app locks on
/// start and after being away for [AppLockState.lockAfter]. Watches and
/// other background work keep running while it is locked; only the screens
/// are covered.
@immutable
class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.biometrics = false,
    this.lockAfter = const Duration(minutes: 1),
    this.locked = false,
    this.loaded = false,
    this.biometricsAvailable = false,
  });

  final bool enabled;

  /// Offer fingerprint or face unlock before the passcode.
  final bool biometrics;
  final Duration lockAfter;
  final bool locked;
  final bool loaded;
  final bool biometricsAvailable;

  AppLockState copyWith({
    bool? enabled,
    bool? biometrics,
    Duration? lockAfter,
    bool? locked,
    bool? loaded,
    bool? biometricsAvailable,
  }) => AppLockState(
    enabled: enabled ?? this.enabled,
    biometrics: biometrics ?? this.biometrics,
    lockAfter: lockAfter ?? this.lockAfter,
    locked: locked ?? this.locked,
    loaded: loaded ?? this.loaded,
    biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
  );
}

/// The choices for when the app locks after leaving it.
const lockAfterChoices = <(Duration, String)>[
  (Duration.zero, 'Immediately'),
  (Duration(minutes: 1), 'After 1 minute'),
  (Duration(minutes: 5), 'After 5 minutes'),
  (Duration(minutes: 15), 'After 15 minutes'),
  (Duration(hours: 1), 'After 1 hour'),
];

String lockAfterLabel(Duration d) => lockAfterChoices.where((c) => c.$1 == d).firstOrNull?.$2 ?? 'After ${d.inMinutes} minutes';

const _iterations = 60000;

/// PBKDF2-HMAC-SHA256, one 32-byte block.
Uint8List _pbkdf2(({String passcode, List<int> salt}) a) {
  final hmac = Hmac(sha256, utf8.encode(a.passcode));
  var u = hmac.convert([...a.salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < _iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

class AppLockController extends Notifier<AppLockState> {
  static const _storage = FlutterSecureStorage();
  static const _hashKey = 'app_lock.hash';
  final _auth = LocalAuthentication();

  DateTime? _leftAt;

  /// True while the system's biometric prompt is up: it can pause the app,
  /// which mustn't count as leaving it.
  bool _authenticating = false;

  /// Wrong passcodes in a row, and when typing may resume after too many.
  int _failures = 0;
  DateTime? _waitUntil;

  @override
  AppLockState build() {
    final listener = AppLifecycleListener(onStateChange: _lifecycle);
    ref.onDispose(listener.dispose);
    unawaited(_load());
    return const AppLockState();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    var available = false;
    try {
      available = await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {}
    final hash = await _readHash();
    final enabled = (p.getBool('app_lock_enabled') ?? false) && hash != null;
    state = state.copyWith(
      enabled: enabled,
      biometrics: p.getBool('app_lock_biometrics') ?? false,
      lockAfter: Duration(seconds: p.getInt('app_lock_after_seconds') ?? 60),
      locked: enabled,
      loaded: true,
      biometricsAvailable: available,
    );
  }

  Future<String?> _readHash() async {
    try {
      return await _storage.read(key: _hashKey);
    } catch (_) {
      return null;
    }
  }

  void _lifecycle(AppLifecycleState s) {
    if (!state.enabled || _authenticating) return;
    switch (s) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _leftAt ??= DateTime.now();
        if (state.lockAfter == Duration.zero) state = state.copyWith(locked: true);
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left != null && DateTime.now().difference(left) >= state.lockAfter) {
          state = state.copyWith(locked: true);
        }
      default:
        break;
    }
  }

  static Future<String> _hash(String passcode, List<int> salt) async {
    final bytes = await compute(_pbkdf2, (passcode: passcode, salt: salt));
    return '${base64Encode(salt)}:${base64Encode(bytes)}';
  }

  /// Turns the lock on with [passcode], or changes the passcode.
  /// Notes a lock event in the activity log.
  void _audit(String title, [String detail = '']) =>
      ref.read(activityLogProvider.notifier).recordEvent(kind: ActivityKind.security, title: title, detail: detail);

  Future<void> setPasscode(String passcode) async {
    _audit(state.enabled ? 'App lock passcode changed' : 'App lock turned on');
    final rnd = Random.secure();
    final salt = [for (var i = 0; i < 16; i++) rnd.nextInt(256)];
    await _storage.write(key: _hashKey, value: await _hash(passcode, salt));
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_lock_enabled', true);
    state = state.copyWith(enabled: true, locked: false);
  }

  /// Seconds until another passcode may be tried, after too many wrong ones.
  int get waitSeconds {
    final until = _waitUntil;
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds;
    return left > 0 ? left + 1 : 0;
  }

  /// Whether [passcode] is the saved one. Too many wrong ones in a row make
  /// the next tries wait, longer each time.
  Future<bool> verify(String passcode) async {
    if (waitSeconds > 0) return false;
    final saved = await _readHash();
    if (saved == null) return false;
    final parts = saved.split(':');
    if (parts.length != 2) return false;
    final check = await _hash(passcode, base64Decode(parts[0]));
    // Constant time, so timing doesn't reveal how close a guess was.
    final a = utf8.encode(check), b = utf8.encode(saved);
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    if (diff == 0) {
      _failures = 0;
      _waitUntil = null;
      return true;
    }
    _failures++;
    if (_failures >= 5) _waitUntil = DateTime.now().add(Duration(seconds: 30 * (_failures - 4)));
    // Repeated wrong passcodes are worth knowing about.
    if (_failures == 3 || _failures >= 5) _audit('Wrong app lock passcode, $_failures times in a row', _failures >= 5 ? 'Further tries now have to wait.' : '');
    return false;
  }

  /// Unlocks with [passcode]; false when it is wrong.
  Future<bool> unlockWithPasscode(String passcode) async {
    if (!await verify(passcode)) return false;
    _leftAt = null;
    state = state.copyWith(locked: false);
    return true;
  }

  /// Shows the system's fingerprint/face prompt; unlocks when it succeeds.
  Future<bool> unlockWithBiometrics() async {
    if (!state.biometrics || !state.biometricsAvailable || _authenticating) return false;
    _authenticating = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Triangle',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        _leftAt = null;
        state = state.copyWith(locked: false);
      }
      return ok;
    } catch (e) {
      debugPrint('[AppLock] biometrics: $e');
      return false;
    } finally {
      _authenticating = false;
    }
  }

  /// Turns biometric unlock on (after the system prompt succeeds) or off.
  Future<bool> setBiometrics(bool on) async {
    if (on) {
      _authenticating = true;
      try {
        final ok = await _auth.authenticate(localizedReason: 'Use your fingerprint or face to unlock Triangle', biometricOnly: true);
        if (!ok) return false;
      } catch (e) {
        debugPrint('[AppLock] biometrics: $e');
        return false;
      } finally {
        _authenticating = false;
      }
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_lock_biometrics', on);
    if (on != state.biometrics) _audit(on ? 'Fingerprint or face unlock turned on' : 'Fingerprint or face unlock turned off');
    state = state.copyWith(biometrics: on);
    return true;
  }

  Future<void> setLockAfter(Duration d) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('app_lock_after_seconds', d.inSeconds);
    if (d != state.lockAfter) _audit('App lock delay set to ${d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s'}');
    state = state.copyWith(lockAfter: d);
  }

  /// Turns the lock off; the caller has checked the passcode.
  Future<void> disable() async {
    _audit('App lock turned off');
    await _storage.delete(key: _hashKey);
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_lock_enabled', false);
    state = state.copyWith(enabled: false, locked: false);
  }

  void lockNow() {
    if (state.enabled) state = state.copyWith(locked: true);
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
