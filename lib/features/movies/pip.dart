import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Picture-in-picture for videos (PipChannel.kt). While a video plays,
/// leaving the app shrinks it to a floating window; [inPip] tells the app
/// to show only the video then. Does nothing on a build without it.
abstract final class Pip {
  static const _channel = MethodChannel('teleai/pip');
  static final inPip = ValueNotifier<bool>(false);
  static bool _listening = false;
  static bool _missing = !Platform.isAndroid;
  static String _last = '';

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') inPip.value = call.arguments == true;
    });
  }

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (_missing) return null;
    _listen();
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      _missing = true;
      return null;
    } catch (e) {
      debugPrint('[Pip] $e');
      return null;
    }
  }

  /// Whether this build and phone can do it.
  static Future<bool> supported() async => await _call<bool>('supported') ?? false;

  /// Shrinks the app to a window the shape of [size] now.
  static Future<bool> enter(Size size) async => await _call<bool>('enter', {'w': size.width.round(), 'h': size.height.round()}) ?? false;

  /// Leaving the app goes to picture-in-picture while [on].
  static Future<void> setAuto(bool on, [Size size = const Size(16, 9)]) async {
    final sig = '$on|${size.width.round()}x${size.height.round()}';
    if (sig == _last) return;
    _last = sig;
    await _call<bool>('setAuto', {'enabled': on, 'w': size.width.round(), 'h': size.height.round()});
  }
}
