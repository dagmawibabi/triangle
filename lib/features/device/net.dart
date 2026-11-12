import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device.dart';

/// A speed test while it runs: the phase, the live speed, how far along,
/// and what is known so far (provider, ping, download…).
@immutable
class SpeedProgress {
  const SpeedProgress({this.phase = 'starting', this.mbps = 0, this.fraction = 0, this.info = const {}, this.done = false});
  final String phase;
  final double mbps;
  final double fraction;
  final Map<String, dynamic> info;
  final bool done;

  SpeedProgress copyWith({String? phase, double? mbps, double? fraction, Map<String, dynamic>? info, bool? done}) => SpeedProgress(
    phase: phase ?? this.phase,
    mbps: mbps ?? this.mbps,
    fraction: fraction ?? this.fraction,
    info: info ?? this.info,
    done: done ?? this.done,
  );
}

/// The connection, SIM cards, speed tests, data usage per app and the
/// phone's notifications, through NetChannel.kt (Android 10+).
abstract final class Net {
  static const _channel = MethodChannel('teleai/net');

  /// Running and recent speed tests by id (a tool call's id, or a card's).
  static final speed = ValueNotifier<Map<String, SpeedProgress>>(const {});

  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'speedProgress') return;
      final m = Device.map(call.arguments);
      final id = '${m['id']}';
      final now = speed.value[id] ?? const SpeedProgress();
      final info = m['info'];
      speed.value = {
        ...speed.value,
        id: info is Map
            ? now.copyWith(info: {...now.info, ...Device.map(info)})
            : now.copyWith(
                phase: '${m['phase'] ?? now.phase}',
                mbps: (m['mbps'] as num?)?.toDouble() ?? now.mbps,
                fraction: (m['fraction'] as num?)?.toDouble() ?? now.fraction,
              ),
      };
    });
  }

  static Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (!Device.supported) throw DeviceException('This works on Android only.');
    _listen();
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      if (e.code == 'access') {
        throw DeviceException(
          method.contains('sage')
              ? 'Usage access is off for Triangle. Turn it on under Android Settings → Usage access → Triangle, then try again.'
              : 'Android didn\'t allow this: ${e.message}',
        );
      }
      throw DeviceException(e.message ?? e.code);
    } on MissingPluginException {
      throw DeviceException('This needs the Android app.');
    }
  }

  /// The connection, Wi-Fi and every SIM. Asks for the phone-state
  /// permission first, so carriers and signal can be read.
  static Future<Map<String, dynamic>> snapshot() async {
    final state = await Device.status([Device.phoneState.id]);
    if (state[Device.phoneState.id] != true) await Device.request([Device.phoneState.id]);
    return Device.map(await _call<Map>('snapshot'));
  }

  /// Runs a speed test; [id] names its live progress in [speed].
  static Future<Map<String, dynamic>> speedTest(String id, {String profile = 'light', String metrics = 'ping,download,upload'}) async {
    speed.value = {...speed.value, id: const SpeedProgress()};
    try {
      final r = Device.map(await _call<Map>('speedTest', {'id': id, 'profile': profile, 'metrics': metrics}));
      speed.value = {...speed.value, id: (speed.value[id] ?? const SpeedProgress()).copyWith(done: true, fraction: 1, info: {...?speed.value[id]?.info, ...r})};
      return r;
    } finally {
      Timer(const Duration(minutes: 2), () {
        if (speed.value[id]?.done ?? true) speed.value = {...speed.value}..remove(id);
      });
    }
  }

  static Future<void> cancelSpeedTest(String id) async {
    try {
      await _call<bool>('cancelSpeedTest', {'id': id});
    } catch (_) {}
  }

  static Future<bool> usageAccess() async {
    try {
      return await _call<bool>('usageAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUsageAccess() => _call<bool>('openUsageAccess');

  static Future<List<Map<String, dynamic>>> appUsage(DateTime start, DateTime end) async =>
      Device.list(await _call<List>('appUsage', {'start': start.millisecondsSinceEpoch, 'end': end.millisecondsSinceEpoch}));

  static Future<List<Map<String, dynamic>>> dailyUsage(int days) async => Device.list(await _call<List>('dailyUsage', {'days': days}));

  static Future<Map<String, dynamic>> hotspotUsage(int days) async => Device.map(await _call<Map>('hotspotUsage', {'days': days}));

  static final _icons = <String, Future<Uint8List?>>{};

  /// An installed app's icon (PNG), cached.
  static Future<Uint8List?> appIcon(String package) => _icons[package] ??= () async {
    try {
      return await _call<Uint8List>('appIcon', {'package': package});
    } catch (_) {
      return null;
    }
  }();

  static Future<bool> notificationAccess() async {
    try {
      return await _call<bool>('notificationAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openNotificationAccess() => _call<bool>('openNotificationAccess');

  static Future<List<Map<String, dynamic>>> notifications({DateTime? since, String? app, String? query, int limit = 100}) async => Device.list(
    await _call<List>('notifications', {
      'since': since?.millisecondsSinceEpoch ?? 0,
      'package': app,
      'query': query,
      'limit': limit,
    }),
  );

  static Future<void> clearNotifications() => _call<bool>('clearNotifications');
}
