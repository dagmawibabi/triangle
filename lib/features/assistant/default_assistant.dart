import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What opens when Triangle is called up as the phone's assistant.
enum AssistOpens {
  voice('Voice mode', 'Start talking straight away'),
  chat('A new chat', 'Type a question, with the keyboard up');

  const AssistOpens(this.label, this.explanation);
  final String label;
  final String explanation;
}

class AssistOpensController extends Notifier<AssistOpens> {
  static const _key = 'assist_opens';

  @override
  AssistOpens build() {
    SharedPreferences.getInstance().then((p) {
      final v = AssistOpens.values.asNameMap()[p.getString(_key)];
      if (v != null && ref.mounted) state = v;
    });
    return AssistOpens.voice;
  }

  Future<void> set(AssistOpens v) async {
    state = v;
    await (await SharedPreferences.getInstance()).setString(_key, v.name);
  }
}

final assistOpensProvider = NotifierProvider<AssistOpensController, AssistOpens>(AssistOpensController.new);

/// The Android side of being the default assistant (AssistChannel.kt).
abstract final class DefaultAssistant {
  static const _channel = MethodChannel('teleai/assist');

  static bool get supported => Platform.isAndroid;

  /// Calls [onAssist] each time the user calls the assistant up, including
  /// the call that started the app. [voice]: it came from a headset's
  /// voice button.
  static void listen(void Function(bool voice) onAssist) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'assist' && await _take()) onAssist((call.arguments as Map?)?['voice'] == true);
    });
    // An assist that started the app arrived before this listened.
    _take().then((pending) {
      if (pending) onAssist(false);
    });
  }

  static Future<bool> _take() async {
    try {
      return await _channel.invokeMethod<bool>('takePending') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether Triangle is the phone's assistant app now.
  static Future<bool> isDefault() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isDefault') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's screen for picking the assistant app.
  static Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
