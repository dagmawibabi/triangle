import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device/device.dart';

/// Screen control: the assistant reads and uses other apps through
/// Triangle's accessibility service (ScreenControl.kt), once the person turns
/// it on in Android's Accessibility settings.
///
/// The service itself refuses password fields, Triangle's own screens and
/// Android's permission and install screens; the apps in [ScreenOffLimits]
/// are sent with every call and refused too.
abstract final class ScreenControl {
  static const _channel = MethodChannel('teleai/screen');

  static bool get supported => Device.supported;

  /// {enabled, running, package, app, screenshots}.
  static Future<Map<String, dynamic>> status() async {
    if (!supported) return const {'enabled': false, 'running': false};
    final r = await _channel.invokeMapMethod<String, dynamic>('status');
    return r ?? const {};
  }

  static Future<void> openSettings() => _channel.invokeMethod<bool>('openSettings');

  /// Runs [method] in the service, with the off-limits apps attached.
  /// Throws [ScreenControlError] with a sentence the assistant can pass on.
  static Future<Map<String, dynamic>> call(String method, [Map<String, dynamic> args = const {}]) async {
    if (!supported) throw const ScreenControlError('Screen control needs the Android app.');
    final blocked = await ScreenOffLimits.load();
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(method, {...args, 'blocked': blocked.toList()});
      return r ?? const {};
    } on PlatformException catch (e) {
      throw ScreenControlError(e.message ?? e.code);
    } on MissingPluginException {
      throw const ScreenControlError('Screen control isn\'t in this build of the app yet: reinstall the latest version.');
    }
  }
}

class ScreenControlError implements Exception {
  const ScreenControlError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Apps the assistant may never read or use, by package. Banking and
/// password apps are good candidates.
abstract final class ScreenOffLimits {
  static const key = 'screen_off_limits';

  static Future<Set<String>> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(key) ?? const []).toSet();
  }

  static Future<void> save(Set<String> packages) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(key, packages.toList()..sort());
  }
}

/// The off-limits apps, for Settings → Screen control.
class ScreenOffLimitsController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    unawaited(ScreenOffLimits.load().then((v) => state = v));
    return const {};
  }

  Future<void> add(String package) async {
    state = {...state, package};
    await ScreenOffLimits.save(state);
  }

  Future<void> remove(String package) async {
    state = {...state}..remove(package);
    await ScreenOffLimits.save(state);
  }
}

final screenOffLimitsProvider = NotifierProvider<ScreenOffLimitsController, Set<String>>(ScreenOffLimitsController.new);
