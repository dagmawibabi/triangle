import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui show ImageByteFormat, instantiateImageCodec;
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'browser_mode.dart';

/// A second browser engine (flutter_inappwebview) next to the assistant's
/// main browser, for what that one can't do: screenshots of a page (the
/// screen or the whole page), inspecting a page (its console messages,
/// network requests, cookies and the HTML its scripts produced), and
/// scripts that await (fetch from the page's own site, wait for things).
/// Both engines are Android's WebView, so they share cookies: a site signed
/// in to in one is signed in in the other.
///
/// It also hosts the code sandbox ([Sandbox]), on a blank page of its own.
class InAppEngine {
  HeadlessInAppWebView? _view;
  InAppWebViewController? _c;
  Completer<void>? _load;
  final List<String> _console = [];
  String? _error;

  static bool get supported => Platform.isAndroid || Platform.isIOS;
  static const _mobileViewport = Size(412, 915);
  static const _desktopViewport = Size(1280, 800);
  static const _mobileAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
  static const _desktopAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  /// Follows the browser's "Desktop site" setting ([BrowserMode]).
  bool _desktop = false;
  Size get _viewport => _desktop ? _desktopViewport : _mobileViewport;

  Future<InAppWebViewController> _ensure() async {
    if (!supported) throw UnsupportedError('This works on Android and iOS only.');
    final c = _c;
    if (c != null) return c;
    final ready = Completer<InAppWebViewController>();
    _view = HeadlessInAppWebView(
      initialSize: _viewport,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _desktop ? _desktopAgent : _mobileAgent,
        mediaPlaybackRequiresUserGesture: true,
        useWideViewPort: true,
      ),
      onWebViewCreated: (c) {
        _c = c;
        if (!ready.isCompleted) ready.complete(c);
      },
      onLoadStart: (_, _) {
        _error = null;
        if (_load == null || _load!.isCompleted) _load = Completer<void>();
      },
      onLoadStop: (_, _) {
        if (_load?.isCompleted == false) _load!.complete();
      },
      onReceivedError: (_, req, err) {
        if (req.isForMainFrame ?? true) _error = err.description;
      },
      onConsoleMessage: (_, m) {
        _console.add('[${m.messageLevel.toNativeValue() == 3 ? 'error' : m.messageLevel.toString().split('.').last.toLowerCase()}] ${m.message}');
        if (_console.length > 200) _console.removeAt(0);
      },
    );
    try {
      await _view!.run();
    } on MissingPluginException {
      // The app's Dart side knows the plugin but this install's native side
      // doesn't: a hot restart after adding it, or an older install.
      _view = null;
      throw UnsupportedError('The screenshot browser isn\'t in this install of the app. Reinstall it fully (not a hot restart), then try again.');
    }
    return ready.future.timeout(const Duration(seconds: 15));
  }

  /// Loads [url] and waits for the page and its scripts to settle.
  Future<void> open(String url, {Duration settle = const Duration(milliseconds: 1500)}) async {
    await _followMode();
    final c = await _ensure();
    _console.clear();
    _load = Completer<void>();
    await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    await _load!.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    await Future<void>.delayed(settle);
  }

  Future<String?> get url async => (await _c?.getUrl())?.toString();

  /// Matches the browser's desktop or mobile view: a new user agent and
  /// width, so the next page loads in that layout.
  Future<void> _followMode() async {
    final desktop = await BrowserMode.desktop;
    if (desktop == _desktop) return;
    _desktop = desktop;
    final c = _c;
    if (c == null) return;
    await c.setSettings(settings: InAppWebViewSettings(userAgent: desktop ? _desktopAgent : _mobileAgent));
    await _view?.setSize(_viewport);
  }

  /// A PNG of the page: what fits the phone's screen, or the whole page
  /// (up to [maxHeight] points tall). Saved with the app's files.
  ///
  /// The hidden page joins the app's screen when it is made. Made while
  /// Triangle had no screen (started in the background), or after that
  /// screen was replaced, it draws nothing and the picture comes out empty
  /// (black). Then it is made again on the current screen, the page is
  /// loaded again, and the picture retaken.
  Future<File> screenshot({bool fullPage = false, int maxHeight = 6000}) async {
    var bytes = await _capture(fullPage: fullPage, maxHeight: maxHeight);
    if (await _blank(bytes)) {
      final current = await url;
      await dispose();
      if (current != null && current.startsWith('http')) {
        await open(current, settle: const Duration(milliseconds: 2500));
      } else {
        await _ensure();
      }
      bytes = await _capture(fullPage: fullPage, maxHeight: maxHeight);
      if (await _blank(bytes)) {
        throw StateError(
          'The page drew nothing, so the screenshot would be black. Page screenshots need Triangle open on the screen: '
          'open the app and try again.',
        );
      }
    }
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/screenshots');
    if (!await dir.exists()) await dir.create(recursive: true);
    final host = Uri.tryParse(await url ?? '')?.host.replaceAll('.', '_') ?? 'page';
    return File('${dir.path}/${host}_${DateTime.now().millisecondsSinceEpoch}.png').writeAsBytes(bytes);
  }

  /// Whether a PNG is empty: every sampled pixel see-through, or all one
  /// near-black colour. A real page always has something on it.
  static Future<bool> _blank(Uint8List png) async {
    try {
      final codec = await ui.instantiateImageCodec(png, targetWidth: 64);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return false;
      final px = data.buffer.asUint8List();
      var solid = 0;
      var light = 0;
      for (var i = 0; i + 3 < px.length; i += 4 * 7) {
        if (px[i + 3] > 16) solid++;
        if (px[i] > 24 || px[i + 1] > 24 || px[i + 2] > 24) light++;
      }
      return solid == 0 || light == 0;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List> _capture({required bool fullPage, required int maxHeight}) async {
    await _followMode();
    final c = await _ensure();
    if (fullPage) {
      final h = await c.evaluateJavascript(
        source: 'Math.max(document.body ? document.body.scrollHeight : 0, document.documentElement.scrollHeight)',
      );
      final height = (h is num ? h.toDouble() : double.tryParse('$h') ?? _viewport.height).clamp(_viewport.height, maxHeight.toDouble());
      await _view!.setSize(Size(_viewport.width, height));
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    try {
      final bytes = await c.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.PNG),
      );
      if (bytes == null || bytes.isEmpty) throw StateError('The page gave an empty screenshot.');
      return bytes;
    } finally {
      if (fullPage) await _view!.setSize(_viewport);
    }
  }

  /// What a developer would look at: console output, the requests the page
  /// made, its cookies, and the HTML as its scripts left it.
  Future<Map<String, dynamic>> inspect({int htmlChars = 6000}) async {
    final c = await _ensure();
    final requests = await c.evaluateJavascript(
      source: '''JSON.stringify(performance.getEntriesByType('resource').slice(-80).map(function (e) {
        return {url: e.name, type: e.initiatorType, ms: Math.round(e.duration), bytes: e.transferSize || undefined};
      }))''',
    );
    final current = await url;
    final cookies = current == null ? const <Cookie>[] : await CookieManager.instance().getCookies(url: WebUri(current));
    final html = await c.getHtml() ?? '';
    return {
      'url': current,
      'title': await c.getTitle(),
      'error': ?_error,
      'console': List.of(_console.take(80)),
      'requests': _decode(requests) ?? const [],
      'cookies': [for (final k in cookies) k.name],
      'html_length': html.length,
      'html': html.length > htmlChars ? '${html.substring(0, htmlChars)}…' : html,
    };
  }

  /// Runs [body] as an async function in the page (it may `await`), with
  /// [args] as named variables; its return value comes back.
  Future<Object?> runAsync(String body, {Map<String, dynamic> args = const {}, Duration timeout = const Duration(seconds: 60)}) async {
    final c = await _ensure();
    final r = await c.callAsyncJavaScript(functionBody: body, arguments: args).timeout(timeout);
    if (r == null) return null;
    if (r.error != null) throw StateError(r.error!);
    return r.value;
  }

  static Object? _decode(Object? v) {
    if (v is String) {
      try {
        return jsonDecode(v);
      } catch (_) {
        return v;
      }
    }
    return v;
  }

  /// Stops loading, and any script still running, by leaving the page.
  Future<void> stop() async {
    if (_load?.isCompleted == false) _load!.complete();
    try {
      await _c?.stopLoading();
      await _c?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _view?.dispose();
    _view = null;
    _c = null;
  }
}

final inAppEngineProvider = Provider<InAppEngine>((ref) {
  final e = InAppEngine();
  ref.onDispose(e.dispose);
  return e;
});
