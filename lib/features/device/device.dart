import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeviceException implements Exception {
  DeviceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// An Android permission a device tool needs, as Settings → Permissions
/// shows it.
class DevicePermission {
  const DevicePermission(this.id, this.title, this.why);
  final String id;
  final String title;
  final String why;
}

/// The phone itself, through DeviceChannel.kt. A call that needs an Android
/// permission asks for it (when the app is on screen) and tries again.
abstract final class Device {
  static const _channel = MethodChannel('teleai/device');

  static const sms = DevicePermission('android.permission.READ_SMS', 'Text messages', 'Lets the assistant read your SMS inbox when you ask.');
  static const sendSms = DevicePermission('android.permission.SEND_SMS', 'Send SMS', 'Sends a text you approved. Your carrier may charge for it.');
  static const callLog = DevicePermission('android.permission.READ_CALL_LOG', 'Call log', 'Missed, incoming and outgoing calls, when you ask about them.');
  static const contacts = DevicePermission('android.permission.READ_CONTACTS', 'Contacts', 'Finds numbers to call or text, and names for messages.');
  static const phone = DevicePermission('android.permission.CALL_PHONE', 'Phone calls', 'Places calls you approved directly. Without it the dialer opens with the number.');

  static const phoneState = DevicePermission('android.permission.READ_PHONE_STATE', 'SIM cards', 'Reads the carriers, signal and network type for network checks.');

  static const all = [sms, sendSms, callLog, contacts, phone, phoneState];

  /// Tests set this to draw Android-only screens.
  @visibleForTesting
  static bool? debugSupported;

  static bool get supported => debugSupported ?? Platform.isAndroid;

  static Future<T?> call<T>(String method, [Map<String, dynamic>? args, bool retried = false]) async {
    if (!supported) throw DeviceException('Device tools work on Android only.');
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      if (e.code == 'permission' && !retried) {
        final needed = [for (final p in (e.details as List? ?? const [])) '$p'];
        final granted = await request(needed);
        if (needed.isNotEmpty && needed.every((p) => granted[p] == true)) return call<T>(method, args, true);
        final names = [for (final p in needed) all.where((d) => d.id == p).firstOrNull?.title ?? p.split('.').last];
        throw DeviceException(
          'Android permission not given: ${names.join(', ')}. The user can allow it under Settings → Permissions, or in Android\'s app settings.',
        );
      }
      throw DeviceException(e.message ?? e.code);
    } on MissingPluginException {
      throw DeviceException('Device tools need the Android app.');
    }
  }

  /// Which of [permissions] are granted.
  static Future<Map<String, bool>> status(List<String> permissions) async {
    if (!supported) return {};
    try {
      final r = await _channel.invokeMapMethod<String, bool>('status', {'permissions': permissions});
      return r ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Asks Android for [permissions]; empty when the app is in the background.
  static Future<Map<String, bool>> request(List<String> permissions) async {
    try {
      final r = await _channel.invokeMapMethod<String, bool>('request', {'permissions': permissions});
      return r ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }

  static Map<String, dynamic> map(Object? v) => v is Map ? {for (final e in v.entries) '${e.key}': _plain(e.value)} : {};
  static List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) map(x),
  ];

  static Object? _plain(Object? v) => switch (v) {
    final Map m => map(m),
    final List l => [for (final x in l) _plain(x)],
    _ => v,
  };
}

/// Icons for the device tools in Settings and on tool cards.
IconData? deviceToolIcon(String name) => switch (name) {
  'device_info' => Icons.phone_android_rounded,
  'device_battery' => Icons.battery_std_rounded,
  'network_info' => Icons.network_check_rounded,
  'installed_apps' => Icons.apps_rounded,
  'read_sms' => Icons.sms_outlined,
  'call_log' => Icons.history_rounded,
  'phone_contacts' => Icons.contacts_outlined,
  'read_clipboard' => Icons.content_paste_rounded,
  'write_clipboard' => Icons.content_copy_rounded,
  'make_call' => Icons.call_rounded,
  'send_sms' => Icons.outgoing_mail,
  'flashlight' => Icons.flashlight_on_rounded,
  'vibrate' => Icons.vibration_rounded,
  'device_volume' => Icons.volume_up_rounded,
  'ringer_mode' => Icons.notifications_paused_outlined,
  'media_control' => Icons.play_circle_outline_rounded,
  'set_alarm' => Icons.alarm_add_rounded,
  'set_timer' => Icons.timer_outlined,
  'open_app' => Icons.open_in_new_rounded,
  'open_device_settings' => Icons.settings_outlined,
  'keep_screen_on' => Icons.light_mode_outlined,
  _ => null,
};
