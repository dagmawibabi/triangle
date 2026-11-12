import 'dart:io';

import 'package:omni_ai/omni_ai.dart' show BrowserSession;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Desktop or mobile view for the assistant's browser (omni_ai's
/// [BrowserSession]), like Chrome's "Desktop site". The session is built
/// with a phone's user agent; in desktop mode the page gets a Windows
/// Chrome user agent and is laid out 1280 pixels wide, so sites show their
/// PC layout, and the whole width fits on the phone's screen.
abstract final class BrowserMode {
  static const _key = 'browser_desktop';
  static const _desktopAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  static const desktopWidth = 1280;

  static bool? _desktop;

  /// Whether the browser shows sites' desktop layout. Remembered.
  static Future<bool> get desktop async => _desktop ??= (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  static Future<void> setDesktop(bool on) async {
    _desktop = on;
    await (await SharedPreferences.getInstance()).setBool(_key, on);
  }

  /// Gives [session] the current mode before it loads a page. Returns
  /// whether its user agent changed, so an open page needs reloading.
  static Future<bool> apply(BrowserSession session) async {
    final c = session.controller;
    if (c == null) return false;
    final on = await desktop;
    final agent = on ? _desktopAgent : session.userAgent;
    final before = await c.getUserAgent();
    if (before == agent) return false;
    await c.setUserAgent(agent);
    if (Platform.isAndroid && c.platform is AndroidWebViewController) {
      // Wide viewport makes the WebView honour the page's (rewritten)
      // viewport width instead of always using the phone's.
      await (c.platform as AndroidWebViewController).setUseWideViewPort(on);
    }
    return true;
  }

  /// In desktop mode, lays the open page out at desktop width and zooms it
  /// to fit the screen; responsive sites switch to their PC layout.
  static Future<void> fit(BrowserSession session) async {
    final c = session.controller;
    if (c == null || !await desktop) return;
    try {
      await c.runJavaScript('''(function () {
  var w = $desktopWidth, scale = Math.min(1, (screen.width || window.outerWidth || 412) / w).toFixed(3);
  var m = document.querySelector('meta[name="viewport"]');
  if (!m) { m = document.createElement('meta'); m.name = 'viewport'; (document.head || document.documentElement).appendChild(m); }
  m.setAttribute('content', 'width=' + w + ', initial-scale=' + scale + ', minimum-scale=0.1, user-scalable=yes');
})();''');
      // Let media queries and layout catch up before the page is read.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (_) {}
  }
}
