import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:omni_ai/omni_ai.dart' show McpRegistry, McpServer, McpTransportKind;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme.dart';

/// Sign-in for MCP servers that use OAuth (the MCP authorization spec):
/// the server answers 401 with a `WWW-Authenticate` pointing at its
/// protected-resource metadata; from there we find the authorization
/// server, register this app as a public client, run an authorization-code
/// flow with PKCE in an in-app web page, and keep the token as the server's
/// `Authorization: Bearer` header. Refresh tokens are kept on the phone's
/// secure storage and used before the access token runs out.
abstract final class McpOAuth {
  /// Where the sign-in page sends the code. Never loaded: the web view
  /// catches it. Loopback, so servers that only allow localhost redirects
  /// for native apps accept it.
  static const redirectUri = 'http://127.0.0.1:47391/triangle/mcp-oauth/callback';

  static const _storage = FlutterSecureStorage();
  static String _key(String serverId) => 'mcp_oauth.$serverId';

  static const _jsonHeaders = {'Accept': 'application/json', 'User-Agent': 'Triangle'};

  /// Whether [url] wants OAuth: null if it answers without (or wants a
  /// plain key), else what is needed to sign in.
  static Future<McpOAuthPlan?> probe(String url, {Map<String, String> headers = const {}}) async {
    final uri = Uri.parse(url);
    http.Response r;
    try {
      r = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/event-stream',
              ...headers,
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 0,
              'method': 'initialize',
              'params': {
                'protocolVersion': '2025-06-18',
                'capabilities': {},
                'clientInfo': {'name': 'Triangle', 'version': '1'},
              },
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (r.statusCode != 401 && r.statusCode != 403) return null;
    final www = r.headers['www-authenticate'] ?? '';
    try {
      return await discover(uri, www);
    } catch (e) {
      debugPrint('[McpOAuth] discovery: $e');
      // 401 with no OAuth metadata: it wants a key in a header instead.
      return null;
    }
  }

  /// Finds the authorization server for MCP endpoint [mcp].
  static Future<McpOAuthPlan> discover(Uri mcp, String wwwAuthenticate) async {
    Map<String, dynamic>? resource;
    final hinted = RegExp(r'resource_metadata="([^"]+)"').firstMatch(wwwAuthenticate)?[1];
    final origin = '${mcp.scheme}://${mcp.authority}';
    final path = mcp.path == '/' ? '' : mcp.path;
    for (final u in [?hinted, '$origin/.well-known/oauth-protected-resource$path', '$origin/.well-known/oauth-protected-resource']) {
      resource = await _getJson(u);
      if (resource != null && resource['authorization_servers'] is List) break;
      resource = null;
    }
    final issuer = resource == null
        ? origin
        : '${(resource['authorization_servers'] as List).first}'.replaceFirst(RegExp(r'/$'), '');
    final iss = Uri.parse(issuer);
    final issOrigin = '${iss.scheme}://${iss.authority}';
    final issPath = iss.path == '/' ? '' : iss.path;
    Map<String, dynamic>? meta;
    for (final u in [
      '$issOrigin/.well-known/oauth-authorization-server$issPath',
      '$issOrigin/.well-known/openid-configuration$issPath',
      if (issPath.isNotEmpty) '$issuer/.well-known/openid-configuration',
      if (issPath.isNotEmpty) '$issuer/.well-known/oauth-authorization-server',
    ]) {
      meta = await _getJson(u);
      if (meta != null && meta['authorization_endpoint'] != null && meta['token_endpoint'] != null) break;
      meta = null;
    }
    if (meta == null) throw const McpOAuthException('This server asks for sign-in but publishes no OAuth details.');
    final scopes = [
      for (final s in (resource?['scopes_supported'] as List? ?? meta['scopes_supported'] as List? ?? const [])) '$s',
    ];
    return McpOAuthPlan(
      resource: '${resource?['resource'] ?? mcp.toString()}',
      resourceName: resource?['resource_name'] as String?,
      authorizationEndpoint: '${meta['authorization_endpoint']}',
      tokenEndpoint: '${meta['token_endpoint']}',
      registrationEndpoint: meta['registration_endpoint'] as String?,
      scopes: scopes,
    );
  }

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final r = await http.get(Uri.parse(url), headers: _jsonHeaders).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  /// Runs the whole sign-in for [serverId] and returns the access token.
  /// [clientId] skips registration (for servers that give one out).
  static Future<String?> signIn(BuildContext context, String serverId, McpOAuthPlan plan, {String? clientId}) async {
    var id = clientId;
    String? secret;
    if (id == null) {
      final saved = await _load(serverId);
      if (saved?['client_id'] != null && saved?['token_endpoint'] == plan.tokenEndpoint) {
        id = saved!['client_id'] as String;
        secret = saved['client_secret'] as String?;
      }
    }
    if (id == null) {
      if (plan.registrationEndpoint == null) {
        throw const McpOAuthException('This server needs a client id, and doesn\'t let apps register one themselves.');
      }
      final r = await http.post(
        Uri.parse(plan.registrationEndpoint!),
        headers: {..._jsonHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'client_name': 'Triangle',
          'redirect_uris': [redirectUri],
          'grant_types': ['authorization_code', 'refresh_token'],
          'response_types': ['code'],
          'token_endpoint_auth_method': 'none',
          if (plan.scopes.isNotEmpty) 'scope': plan.scopes.join(' '),
        }),
      );
      if (r.statusCode >= 300) throw McpOAuthException('Couldn\'t register with the server (${r.statusCode}): ${_short(r.body)}');
      final j = jsonDecode(r.body) as Map;
      id = '${j['client_id']}';
      secret = j['client_secret'] as String?;
    }

    final verifier = _random(64);
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final state = _random(24);
    final authorize = Uri.parse(plan.authorizationEndpoint).replace(
      queryParameters: {
        ...Uri.parse(plan.authorizationEndpoint).queryParameters,
        'response_type': 'code',
        'client_id': id,
        'redirect_uri': redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'resource': plan.resource,
        if (plan.scopes.isNotEmpty) 'scope': plan.scopes.join(' '),
      },
    );
    if (!context.mounted) return null;
    // The redirect is caught in the web view; a loopback server on the
    // redirect's port also catches it, for pages that hand it to the
    // browser or reach it by a redirect the web view doesn't report.
    final catcher = await _CallbackCatcher.start();
    Uri? back;
    try {
      back = await Navigator.of(context).push<Uri>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _SignInPage(start: authorize, title: plan.resourceName ?? serverId, caught: catcher?.caught),
        ),
      );
    } finally {
      await catcher?.close();
    }
    if (back == null) return null;
    final q = back.queryParameters;
    if (q['error'] != null) throw McpOAuthException('Sign-in was refused: ${q['error_description'] ?? q['error']}');
    if (q['state'] != state || q['code'] == null) throw const McpOAuthException('Sign-in came back without a valid code. Try again.');

    final tokens = await _token(plan.tokenEndpoint, {
      'grant_type': 'authorization_code',
      'code': q['code']!,
      'redirect_uri': redirectUri,
      'client_id': id,
      'code_verifier': verifier,
      'resource': plan.resource,
      'client_secret': ?secret,
    });
    await _save(serverId, {
      'client_id': id,
      'client_secret': ?secret,
      'token_endpoint': plan.tokenEndpoint,
      'resource': plan.resource,
      'refresh_token': ?tokens.refresh,
      'expires_at': tokens.expiresAt?.toIso8601String(),
    });
    return tokens.access;
  }

  /// Signs in and saves the token as [server]'s Authorization header.
  static Future<bool> signInAndInstall(BuildContext context, McpRegistry registry, McpServer server, McpOAuthPlan plan) async {
    final token = await signIn(context, server.id, plan);
    if (token == null) return false;
    await registry.install(_withToken(server, token));
    return true;
  }

  static McpServer _withToken(McpServer s, String token) {
    final headers = {
      for (final e in s.headers.entries)
        if (e.key.toLowerCase() != 'authorization') e.key: e.value,
      'Authorization': 'Bearer $token',
    };
    return s.transport == McpTransportKind.sse
        ? McpServer.sse(s.id, url: s.url!, headers: headers, approval: s.approval)
        : McpServer.http(s.id, url: s.url!, headers: headers, approval: s.approval);
  }

  /// Whether [serverId] signed in with OAuth here.
  static Future<bool> isOAuth(String serverId) async => (await _load(serverId)) != null;

  /// [serverId]'s sign-in, for diagnosis: whether it signed in here, when
  /// its token runs out and whether it can be refreshed. No secrets.
  static Future<({bool signedIn, DateTime? expiresAt, bool canRefresh, String? issuer})> status(String serverId) async {
    final saved = await _load(serverId);
    return (
      signedIn: saved != null,
      expiresAt: DateTime.tryParse('${saved?['expires_at']}'),
      canRefresh: saved?['refresh_token'] != null,
      issuer: saved == null ? null : Uri.tryParse('${saved['token_endpoint']}')?.host,
    );
  }

  /// Refreshes [serverId]'s token when it ends within 5 minutes (or
  /// [force]); true when the server now has a fresh one.
  static Future<bool> refresh(McpRegistry registry, String serverId, {bool force = false}) async {
    final saved = await _load(serverId);
    final server = registry[serverId];
    if (saved == null || server == null || saved['refresh_token'] == null) return false;
    final ends = DateTime.tryParse('${saved['expires_at']}');
    if (!force && ends != null && ends.difference(DateTime.now()) > const Duration(minutes: 5)) return false;
    if (!force && ends == null) return false;
    try {
      final t = await _token('${saved['token_endpoint']}', {
        'grant_type': 'refresh_token',
        'refresh_token': '${saved['refresh_token']}',
        'client_id': '${saved['client_id']}',
        if (saved['resource'] != null) 'resource': '${saved['resource']}',
        if (saved['client_secret'] != null) 'client_secret': '${saved['client_secret']}',
      });
      await _save(serverId, {
        ...saved,
        if (t.refresh != null) 'refresh_token': t.refresh,
        'expires_at': t.expiresAt?.toIso8601String(),
      });
      await registry.install(_withToken(server, t.access));
      return true;
    } catch (e) {
      debugPrint('[McpOAuth] refresh $serverId: $e');
      return false;
    }
  }

  /// Refreshes every OAuth server's token that is about to run out.
  static Future<void> refreshAll(McpRegistry registry) async {
    for (final s in registry.servers) {
      await refresh(registry, s.id);
    }
  }

  static Future<void> forget(String serverId) => _storage.delete(key: _key(serverId));

  static Future<({String access, String? refresh, DateTime? expiresAt})> _token(String endpoint, Map<String, String> form) async {
    final r = await http.post(
      Uri.parse(endpoint),
      headers: {..._jsonHeaders, 'Content-Type': 'application/x-www-form-urlencoded'},
      body: form,
    );
    if (r.statusCode >= 300) throw McpOAuthException('The server refused the token request (${r.statusCode}): ${_short(r.body)}');
    final j = jsonDecode(r.body) as Map;
    final access = j['access_token'];
    if (access is! String || access.isEmpty) throw const McpOAuthException('The server sent no access token.');
    final expires = (j['expires_in'] as num?)?.toInt();
    return (
      access: access,
      refresh: j['refresh_token'] as String?,
      expiresAt: expires == null ? null : DateTime.now().add(Duration(seconds: expires)),
    );
  }

  static Future<Map<String, dynamic>?> _load(String id) async {
    try {
      final raw = await _storage.read(key: _key(id));
      return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(String id, Map<String, dynamic> v) => _storage.write(key: _key(id), value: jsonEncode(v));

  static String _random(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String _short(String body) => body.length > 200 ? '${body.substring(0, 200)}…' : body;
}

class McpOAuthPlan {
  const McpOAuthPlan({
    required this.resource,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.registrationEndpoint,
    this.resourceName,
    this.scopes = const [],
  });
  final String resource;
  final String? resourceName;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String? registrationEndpoint;
  final List<String> scopes;

  String get host => Uri.parse(authorizationEndpoint).host;
}

class McpOAuthException implements Exception {
  const McpOAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The server's sign-in page; closes itself with the redirect it ends on.
class _SignInPage extends StatefulWidget {
  const _SignInPage({required this.start, required this.title, this.caught});
  final Uri start;
  final String title;

  /// The loopback server's catch, when the redirect goes around the web view.
  final Future<Uri>? caught;

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  late final WebViewController _web;
  int _progress = 0;
  String _host = '';
  bool _done = false;

  static bool _isCallback(String? url) => url != null && url.contains('/triangle/mcp-oauth/callback');

  /// Closes with [url] once, whichever way it arrived first.
  void _finish(String url) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(Uri.parse(url));
  }

  @override
  void initState() {
    super.initState();
    _host = widget.start.host;
    widget.caught?.then((u) => _finish(u.toString()));
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Some sign-in pages refuse embedded web views by their user agent.
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          // Redirects after a form post skip onNavigationRequest on Android:
          // the callback is caught here, as the page starts or the URL changes.
          onPageStarted: (url) {
            if (_isCallback(url)) _finish(url);
          },
          onUrlChange: (c) {
            if (_isCallback(c.url)) return _finish(c.url!);
            final u = Uri.tryParse(c.url ?? '');
            if (u != null && mounted) setState(() => _host = u.host);
          },
          onWebResourceError: (e) {
            if (_isCallback(e.url)) _finish(e.url!);
          },
          onNavigationRequest: (req) {
            if (_isCallback(req.url)) {
              _finish(req.url);
              return NavigationDecision.prevent;
            }
            final u = Uri.tryParse(req.url);
            // Telegram login and other app links open their app.
            if (u != null && u.scheme != 'http' && u.scheme != 'https' && u.scheme != 'about' && u.scheme != 'data') {
              launchUrl(u, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.start);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Cancel', onPressed: () => Navigator.pop(context)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sign in to ${widget.title}', style: context.text.titleMedium),
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 12, color: AppColors.text3),
              const SizedBox(width: 4),
              Flexible(child: Text(_host, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
            ],
          ),
        ],
      ),
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Reload', onPressed: () => _web.reload())],
      bottom: _progress < 100
          ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100, minHeight: 2))
          : null,
    ),
    body: WebViewWidget(controller: _web),
  );
}

/// A tiny server on the redirect's loopback port while a sign-in is open:
/// if the callback reaches it (in the web view or the phone's browser), it
/// hands the code back and tells the person to return to the app.
class _CallbackCatcher {
  _CallbackCatcher._(this._server);
  final HttpServer _server;
  final _caught = Completer<Uri>();

  Future<Uri> get caught => _caught.future;

  static Future<_CallbackCatcher?> start() async {
    final uri = Uri.parse(McpOAuth.redirectUri);
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, uri.port, shared: true);
      final c = _CallbackCatcher._(server);
      server.listen((req) async {
        final hit = req.uri.path == uri.path;
        if (hit && !c._caught.isCompleted) c._caught.complete(uri.replace(query: req.uri.query));
        req.response
          ..statusCode = hit ? 200 : 404
          ..headers.contentType = ContentType.html
          ..write(hit ? _page : 'Not found');
        await req.response.close();
      });
      return c;
    } catch (e) {
      debugPrint('[McpOAuth] loopback catcher: $e');
      return null;
    }
  }

  Future<void> close() => _server.close(force: true);

  static const _page = '<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">'
      '<body style="font-family:system-ui;background:#111;color:#eee;display:grid;place-items:center;height:90vh;text-align:center">'
      '<div><div style="font-size:48px">✓</div><h2>Signed in</h2><p>You can go back to Triangle now.</p></div>';
}
