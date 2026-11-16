import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's own media player for what plays in Music: a MediaSession with
/// a MediaStyle notification (MediaSessionChannel.kt), so it shows as the
/// player card in quick settings and on the lock screen, with the cover,
/// a seek bar and working headset buttons.
///
/// [available] turns false when the app was built without it; the caller
/// then falls back to the plain notification.
class MediaSessionBridge {
  MediaSessionBridge._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action') {
        final a = call.arguments as Map;
        actions.add((action: '${a['action']}', arg: a['arg']));
      }
    });
  }
  static final instance = MediaSessionBridge._();
  static const _channel = MethodChannel('teleai/media_session');

  final actions = StreamController<({String action, Object? arg})>.broadcast();
  bool available = Platform.isAndroid;

  Future<bool> update({
    required String title,
    required String subtitle,
    required bool playing,
    String? art,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    double speed = 1,
    bool hasNext = false,
    bool hasPrevious = true,
  }) async {
    if (!available) return false;
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'subtitle': subtitle,
        'playing': playing,
        'art': art,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'speed': speed,
        'hasNext': hasNext,
        'hasPrevious': hasPrevious,
      });
      return true;
    } on MissingPluginException {
      available = false;
      return false;
    } catch (e) {
      debugPrint('[MediaSession] $e');
      return false;
    }
  }

  Future<void> clear() async {
    if (!available) return;
    try {
      await _channel.invokeMethod('clear');
    } on MissingPluginException {
      available = false;
    } catch (_) {}
  }
}
