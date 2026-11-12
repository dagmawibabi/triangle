import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/files/download_progress.dart';

/// Plain HTTP for the assistant: reading pages without running their
/// scripts (fast, cheap, fine for blogs and docs), calling APIs, and
/// downloading files. Cookies are kept per host for the session, so a form
/// fetched and then posted carries its session cookie.
class WebFetcher {
  final _client = http.Client();
  final Map<String, Map<String, String>> _cookies = {};

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
  static const _maxBody = 4 * 1024 * 1024;

  /// Adds https:// to a bare address like "dagmawibabi.com/blog".
  static Uri normalize(String url) {
    var u = url.trim();
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(u)) u = 'https://$u';
    final uri = Uri.parse(u);
    if (uri.scheme != 'http' && uri.scheme != 'https') throw ArgumentError('Only http and https addresses work.');
    if (uri.host.isEmpty) throw ArgumentError('"$url" isn\'t a web address.');
    return uri;
  }

  Future<http.Response> request(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? body,
    int redirects = 8,
  }) async {
    final (streamed, req) = await _open(method, url, headers: headers, body: body, redirects: redirects);
    final bytes = <int>[];
    await for (final chunk in streamed.stream) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) break;
    }
    return http.Response.bytes(bytes, streamed.statusCode, headers: streamed.headers, request: req, reasonPhrase: streamed.reasonPhrase);
  }

  /// Sends a request, following redirects and keeping cookies, and returns
  /// the final response still streaming, with the request that got it.
  Future<(http.StreamedResponse, http.Request)> _open(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? body,
    int redirects = 8,
  }) async {
    var uri = url;
    var m = method.toUpperCase();
    Object? b = body;
    for (var hop = 0; hop <= redirects; hop++) {
      final req = http.Request(m, uri)
        ..followRedirects = false
        ..headers.addAll({
          'user-agent': userAgent,
          'accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
          'accept-language': 'en-US,en;q=0.9',
          ...headers,
        });
      final jar = _cookies[uri.host];
      if (jar != null && jar.isNotEmpty && !headers.keys.any((k) => k.toLowerCase() == 'cookie')) {
        req.headers['cookie'] = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
      }
      if (b is String) {
        req.body = b;
      } else if (b is List<int>) {
        req.bodyBytes = b;
      } else if (b is Map<String, String>) {
        req.bodyFields = b;
      }
      final streamed = await _client.send(req).timeout(const Duration(seconds: 30));
      _keepCookies(uri.host, streamed.headers['set-cookie']);
      final location = streamed.headers['location'];
      if (streamed.isRedirect || (streamed.statusCode >= 300 && streamed.statusCode < 400 && location != null)) {
        await streamed.stream.drain<void>();
        uri = uri.resolve(location!);
        // 303 (and 301/302 after a POST, as browsers do) turn into a GET.
        if (streamed.statusCode == 303 || ((streamed.statusCode == 301 || streamed.statusCode == 302) && m == 'POST')) {
          m = 'GET';
          b = null;
        }
        continue;
      }
      return (streamed, req);
    }
    throw ArgumentError('Too many redirects.');
  }

  void _keepCookies(String host, String? header) {
    if (header == null || header.isEmpty) return;
    // Several Set-Cookie headers arrive joined with commas; dates contain
    // commas too, so split only where a new name=value starts.
    for (final c in header.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
      final pair = c.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      (_cookies[host] ??= {})[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
  }

  static String decodeBody(http.Response r) {
    try {
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(r.bodyBytes);
    }
  }

  static bool isHtml(http.Response r) {
    final type = r.headers['content-type'] ?? '';
    return type.contains('html') || (type.isEmpty && decodeBody(r).trimLeft().startsWith('<'));
  }

  static bool isJson(http.Response r) => (r.headers['content-type'] ?? '').contains('json');

  /// Whether a file starting with [head] is a picture the app can show. Goes by
  /// the bytes: addresses often have no extension, and an error page can be
  /// saved under a .jpg name.
  static bool isPicture(List<int> head) => const {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/bmp',
  }.contains(lookupMimeType('', headerBytes: head));

  /// Saves [url] to the app's downloads folder, streaming to disk (no size
  /// limit) and reporting progress to the tool call that asked for it.
  Future<File> download(Uri url, {String? name}) async {
    final (r, _) = await _open('GET', url, headers: const {'accept': '*/*'});
    if (r.statusCode >= 400) {
      await r.stream.drain<void>();
      throw HttpException('HTTP ${r.statusCode}', uri: url);
    }
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    var file = name?.trim();
    if (file == null || file.isEmpty) {
      final disposition = r.headers['content-disposition'] ?? '';
      file = RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''').firstMatch(disposition)?.group(1);
      file ??= url.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'download';
    }
    file = Uri.decodeComponent(file).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final out = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$file');
    final track = DownloadProgress.start(file, url: url.toString(), total: r.contentLength);
    final sink = out.openWrite();
    try {
      // On a tool card the person can pause, resume or cancel it.
      if (track != null) {
        await track.pipe(r.stream, sink);
      } else {
        await sink.addStream(r.stream);
      }
    } catch (e) {
      track?.fail('$e');
      await sink.close();
      // A cancelled or broken download leaves nothing half-written.
      await out.delete().catchError((Object _) => out);
      rethrow;
    }
    await sink.close();
    track?.finish(out.path);
    return out;
  }
}

/// A web page read without running its scripts.
class ReadablePage {
  ReadablePage._(this.title, this.description, this.text, this.links, this.forms, this.scripts);

  final String title;
  final String? description;
  final String text;
  final List<Map<String, String>> links;
  final List<Map<String, dynamic>> forms;
  final List<String> scripts;

  factory ReadablePage.parse(String source, Uri base) {
    final doc = html.parse(source);
    final title = doc.querySelector('title')?.text.trim() ?? doc.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '';
    final description =
        doc.querySelector('meta[name="description"]')?.attributes['content'] ??
        doc.querySelector('meta[property="og:description"]')?.attributes['content'];

    String abs(String? href) {
      if (href == null || href.isEmpty) return '';
      try {
        return base.resolve(href).toString();
      } catch (_) {
        return href;
      }
    }

    final scripts = <String>{
      for (final s in doc.querySelectorAll('script[src]')) abs(s.attributes['src']),
      for (final l in doc.querySelectorAll('link[rel="modulepreload"], link[rel="preload"][as="script"]')) abs(l.attributes['href']),
    }.where((s) => s.isNotEmpty).toList();

    final forms = <Map<String, dynamic>>[];
    for (final (i, f) in doc.querySelectorAll('form').indexed) {
      forms.add({
        'form': i,
        'method': (f.attributes['method'] ?? 'GET').toUpperCase(),
        'action': abs(f.attributes['action'] ?? base.toString()),
        'fields': [
          for (final el in f.querySelectorAll('input, textarea, select'))
            if (el.attributes['name'] case final name? when name.isNotEmpty)
              {
                'name': name,
                'type': el.localName == 'input' ? (el.attributes['type'] ?? 'text') : el.localName!,
                if (el.attributes['value'] case final v? when v.isNotEmpty) 'value': v,
                if (el.localName == 'textarea' && el.text.isNotEmpty) 'value': el.text,
                'placeholder': ?el.attributes['placeholder'],
                if (el.attributes.containsKey('required')) 'required': true,
                if (el.localName == 'select')
                  'options': [for (final o in el.querySelectorAll('option')) o.attributes['value'] ?? o.text.trim()],
              },
        ],
      });
    }

    final links = <Map<String, String>>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = abs(a.attributes['href']);
      if (href.isEmpty || href.startsWith('javascript:') || !seen.add(href)) continue;
      final text = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      links.add({'text': text.length > 100 ? '${text.substring(0, 100)}…' : text, 'url': href});
    }

    for (final junk in doc.querySelectorAll('script, style, noscript, svg, template, iframe, nav, footer, header, form')) {
      junk.remove();
    }
    final root = doc.querySelector('article') ?? doc.querySelector('main') ?? doc.querySelector('[role="main"]') ?? doc.body;
    var text = root == null ? '' : _text(root);
    if (text.length < 200 && root != doc.body && doc.body != null) text = _text(doc.body!);
    return ReadablePage._(title, description, text, links, forms, scripts);
  }

  /// Block elements become lines; headings and list items get markdown
  /// marks so structure survives.
  static String _text(dom.Element root) {
    final out = StringBuffer();
    void walk(dom.Node n) {
      if (n is dom.Text) {
        out.write(n.text.replaceAll(RegExp(r'\s+'), ' '));
        return;
      }
      if (n is! dom.Element) return;
      final tag = n.localName ?? '';
      const blocks = {'p', 'div', 'section', 'article', 'li', 'tr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'br', 'pre', 'blockquote', 'ul', 'ol', 'table', 'time'};
      final block = blocks.contains(tag);
      if (block) out.write('\n');
      if (tag.length == 2 && tag[0] == 'h' && int.tryParse(tag[1]) != null) out.write('${'#' * int.parse(tag[1])} ');
      if (tag == 'li') out.write('- ');
      for (final c in n.nodes) {
        walk(c);
      }
      if (block) out.write('\n');
    }

    walk(root);
    return out
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

final webFetcherProvider = Provider<WebFetcher>((ref) => WebFetcher());

/// What a page says about itself for link previews: its share image, site
/// name, author, publish date, theme colour and icon, from Open Graph,
/// Twitter and standard meta tags. Absent ones are left out.
Map<String, String> pagePreviewMeta(String source, Uri base) {
  final doc = html.parse(source);
  String? meta(List<String> keys) {
    for (final k in keys) {
      final v = (doc.querySelector('meta[property="$k"]') ?? doc.querySelector('meta[name="$k"]'))?.attributes['content']?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  String? abs(String? href) {
    if (href == null || href.isEmpty) return null;
    try {
      final u = base.resolve(href);
      return u.scheme == 'http' || u.scheme == 'https' ? u.toString() : null;
    } catch (_) {
      return null;
    }
  }

  final icon = doc.querySelectorAll('link[rel]').where((l) => '${l.attributes['rel']}'.toLowerCase().contains('icon')).map((l) => l.attributes['href']).firstOrNull;
  // Without a share image, the first picture in the content that's big
  // enough to show: not a logo, icon, avatar, badge or tracking pixel.
  String? contentImage() {
    final skip = RegExp(r'logo|icon|sprite|avatar|badge|pixel|spacer|emoji|gravatar|1x1|blank|placeholder|\.svg', caseSensitive: false);
    final root = doc.querySelector('article') ?? doc.querySelector('main') ?? doc.body;
    for (final img in root?.querySelectorAll('img') ?? const <dom.Element>[]) {
      final a = img.attributes;
      final src = a['src'] ?? a['data-src'] ?? a['data-original'] ?? (a['srcset'] ?? '').split(',').firstOrNull?.trim().split(' ').firstOrNull;
      if (src == null || src.isEmpty || src.startsWith('data:') || skip.hasMatch(src) || skip.hasMatch('${a['class'] ?? ''} ${a['alt'] ?? ''}')) continue;
      final w = int.tryParse((a['width'] ?? '').replaceAll('px', ''));
      final h = int.tryParse((a['height'] ?? '').replaceAll('px', ''));
      if ((w != null && w < 200) || (h != null && h < 120)) continue;
      final u = abs(src);
      if (u != null) return u;
    }
    return null;
  }

  final published = meta(['article:published_time', 'og:published_time', 'datePublished', 'date', 'pubdate', 'dc.date']) ?? doc.querySelector('time[datetime]')?.attributes['datetime'];
  return {
    'image': ?(abs(meta(['og:image', 'og:image:url', 'og:image:secure_url', 'twitter:image', 'twitter:image:src'])) ?? abs(doc.querySelector('link[rel="image_src"]')?.attributes['href']) ?? contentImage()),
    'site_name': ?meta(['og:site_name', 'application-name', 'apple-mobile-web-app-title']),
    'author': ?meta(['author', 'article:author', 'twitter:creator']),
    'published': ?published,
    'theme_color': ?meta(['theme-color']),
    'icon': ?abs(icon),
    'type': ?meta(['og:type']),
  };
}
