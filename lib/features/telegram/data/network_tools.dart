import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:omni_ai/omni_ai.dart' show ProviderCredits;
import 'package:path_provider/path_provider.dart';

import 'telegram_tools.dart' show ToolOutput;

// Runs test_api_key, api_request, api_send and ai_balances (defined in
// telegram_system_tools.dart). Saved keys never leave for a host other than
// their own service's: a prompt can't send them anywhere else.

/// Looks up a saved key by service id ('' when none).
typedef SavedKey = Future<String> Function(String serviceId);

/// Tests [key] with omni_ai's check for [checkId]; null when it works.
typedef VerifyKey = Future<String?> Function(String checkId, String key);

/// omni_ai's credits for a provider id (`gateway`, `openrouter`).
typedef ReadCredits = Future<ProviderCredits> Function(String providerId);

/// How to test a key for a service the app may or may not store.
class KeyProbe {
  const KeyProbe(this.name, this.url, this.auth, {this.detail, this.hosts = const []});
  final String name;

  /// `{key}` is filled in when the key goes in the address.
  final String url;

  /// bearer, x-api-key, xi-api-key, anthropic, url (key in [url]) or
  /// header:Name.
  final String auth;

  /// A short fact from a 200 answer (account name, model count, balance).
  final String? Function(Object? body)? detail;

  /// Hosts this service's saved key may be sent to by http_request.
  final List<String> hosts;
}

String? _models(Object? b) {
  final list = b is Map ? (b['data'] ?? b['models']) : b;
  return list is List ? '${list.length} models available' : null;
}

/// Known services, by id. Ids that match a saved key (list_api_keys) test
/// that key when no key is given.
final keyProbes = <String, KeyProbe>{
  'openai': const KeyProbe('OpenAI', 'https://api.openai.com/v1/models', 'bearer', detail: _models, hosts: ['api.openai.com']),
  'anthropic': const KeyProbe('Anthropic', 'https://api.anthropic.com/v1/models', 'anthropic', detail: _models, hosts: ['api.anthropic.com']),
  'groq': const KeyProbe('Groq', 'https://api.groq.com/openai/v1/models', 'bearer', detail: _models, hosts: ['api.groq.com']),
  'mistral': const KeyProbe('Mistral', 'https://api.mistral.ai/v1/models', 'bearer', detail: _models, hosts: ['api.mistral.ai']),
  'deepseek': KeyProbe('DeepSeek', 'https://api.deepseek.com/user/balance', 'bearer', hosts: const ['api.deepseek.com'], detail: (b) {
    final infos = b is Map ? b['balance_infos'] : null;
    if (infos is! List || infos.isEmpty) return null;
    return 'Balance ${infos.map((i) => '${i['total_balance']} ${i['currency']}').join(', ')}';
  }),
  'xai': const KeyProbe('xAI', 'https://api.x.ai/v1/models', 'bearer', detail: _models, hosts: ['api.x.ai']),
  'together': const KeyProbe('Together AI', 'https://api.together.xyz/v1/models', 'bearer', detail: _models, hosts: ['api.together.xyz']),
  'fireworks': const KeyProbe('Fireworks', 'https://api.fireworks.ai/inference/v1/models', 'bearer', detail: _models, hosts: ['api.fireworks.ai']),
  'cerebras': const KeyProbe('Cerebras', 'https://api.cerebras.ai/v1/models', 'bearer', detail: _models, hosts: ['api.cerebras.ai']),
  'cohere': const KeyProbe('Cohere', 'https://api.cohere.com/v1/models', 'bearer', detail: _models, hosts: ['api.cohere.com']),
  'perplexity': const KeyProbe('Perplexity', 'https://api.perplexity.ai/models', 'bearer', detail: _models, hosts: ['api.perplexity.ai']),
  'huggingface': KeyProbe('Hugging Face', 'https://huggingface.co/api/whoami-v2', 'bearer', hosts: const ['huggingface.co', 'api-inference.huggingface.co'],
      detail: (b) => b is Map && b['name'] != null ? 'Signed in as ${b['name']}' : null),
  'github': KeyProbe('GitHub', 'https://api.github.com/user', 'bearer', hosts: const ['api.github.com'],
      detail: (b) => b is Map && b['login'] != null ? 'Signed in as ${b['login']}' : null),
  'stripe': KeyProbe('Stripe', 'https://api.stripe.com/v1/balance', 'bearer', hosts: const ['api.stripe.com'],
      detail: (b) => b is Map ? (b['livemode'] == true ? 'Live mode key' : 'Test mode key') : null),
  'telegram_bot': KeyProbe('Telegram bot token', 'https://api.telegram.org/bot{key}/getMe', 'url', hosts: const ['api.telegram.org'],
      detail: (b) => b is Map && b['result'] is Map ? 'Bot @${(b['result'] as Map)['username']}' : null),
  'replicate': KeyProbe('Replicate', 'https://api.replicate.com/v1/account', 'bearer', hosts: const ['api.replicate.com'],
      detail: (b) => b is Map && b['username'] != null ? 'Account ${b['username']}' : null),
  'resend': KeyProbe('Resend', 'https://api.resend.com/domains', 'bearer', hosts: const ['api.resend.com'],
      detail: (b) => b is Map && b['data'] is List ? '${(b['data'] as List).length} sending domain(s)' : null),
  'vercel_token': KeyProbe('Vercel', 'https://api.vercel.com/v2/user', 'bearer', hosts: const ['api.vercel.com'],
      detail: (b) => b is Map && b['user'] is Map ? 'Signed in as ${(b['user'] as Map)['username']}' : null),
  'sendgrid': const KeyProbe('SendGrid', 'https://api.sendgrid.com/v3/scopes', 'bearer', hosts: ['api.sendgrid.com']),
  'notion': const KeyProbe('Notion', 'https://api.notion.com/v1/users/me', 'header:Authorization', hosts: ['api.notion.com']),
  // Services the app keeps a key for.
  'openrouter': KeyProbe('OpenRouter', 'https://openrouter.ai/api/v1/key', 'bearer', hosts: const ['openrouter.ai'], detail: (b) {
    final d = b is Map ? b['data'] : null;
    if (d is! Map) return null;
    final left = d['limit_remaining'];
    return [if (d['label'] != null) 'Key "${d['label']}"', if (left != null) '\$$left left on its limit', if (d['is_free_tier'] == true) 'free tier']
        .join(' · ');
  }),
  'vercel': const KeyProbe('Vercel AI Gateway', 'https://ai-gateway.vercel.sh/v1/credits', 'bearer', hosts: ['ai-gateway.vercel.sh']),
  'gemini': const KeyProbe('Google AI Studio', 'https://generativelanguage.googleapis.com/v1beta/models?key={key}', 'url',
      detail: _models, hosts: ['generativelanguage.googleapis.com']),
  'elevenlabs': KeyProbe('ElevenLabs', 'https://api.elevenlabs.io/v1/user/subscription', 'xi-api-key', hosts: const ['api.elevenlabs.io'],
      detail: (b) => b is Map && b['tier'] != null ? '${b['tier']} plan' : null),
  'youtube': const KeyProbe('YouTube Data API', 'https://www.googleapis.com/youtube/v3/i18nRegions?part=snippet&key={key}', 'url',
      hosts: ['www.googleapis.com', 'youtube.googleapis.com']),
  'nasa': const KeyProbe('NASA', 'https://api.nasa.gov/planetary/apod?api_key={key}', 'url', hosts: ['api.nasa.gov']),
  'coingecko': const KeyProbe('CoinGecko', 'https://api.coingecko.com/api/v3/ping?x_cg_demo_api_key={key}', 'url',
      hosts: ['api.coingecko.com', 'pro-api.coingecko.com']),
  'cloudflare': KeyProbe('Cloudflare', 'https://api.cloudflare.com/client/v4/user/tokens/verify', 'bearer', hosts: const ['api.cloudflare.com'],
      detail: (b) => b is Map && b['result'] is Map ? 'Token ${(b['result'] as Map)['status']}' : null),
};

Map<String, String> _authHeaders(String auth, String key) => switch (auth) {
  'bearer' => {'Authorization': 'Bearer $key'},
  'x-api-key' => {'x-api-key': key},
  'xi-api-key' => {'xi-api-key': key},
  'anthropic' => {'x-api-key': key, 'anthropic-version': '2023-06-01'},
  'url' => const {},
  final h when h.startsWith('header:') => {
    h.substring(7): h.substring(7).toLowerCase() == 'authorization' ? 'Bearer $key' : key,
    if (h == 'header:Authorization') 'Notion-Version': '2022-06-28',
  },
  _ => {'Authorization': 'Bearer $key'},
};

String _ending(String key) => key.length <= 8 ? '…' : '…${key.substring(key.length - 4)}';

Future<ToolOutput> runNetworkTool(String name, Map<String, dynamic> a, {required SavedKey savedKey, required VerifyKey verify, required String? Function(String id) checkIdOf, required List<String> savedServiceIds, required ReadCredits credits}) async {
  switch (name) {
    case 'test_api_key':
      return _testKey(a, savedKey: savedKey, verify: verify, checkIdOf: checkIdOf);
    case 'api_request' || 'api_send':
      return _request(name, a, savedKey: savedKey);
    case 'ai_balances':
      return _balances(savedKey: savedKey, credits: credits);
  }
  throw ArgumentError('Unknown tool $name');
}

Future<ToolOutput> _testKey(Map<String, dynamic> a, {required SavedKey savedKey, required VerifyKey verify, required String? Function(String id) checkIdOf}) async {
  final service = '${a['service'] ?? ''}'.trim().toLowerCase();
  final given = '${a['key'] ?? ''}'.trim();
  final customUrl = '${a['url'] ?? ''}'.trim();
  if (service.isEmpty && customUrl.isEmpty) throw ArgumentError('Give service (or url with key).');

  // A custom endpoint only with a key the user gave: a saved key never goes
  // to an address the model picked.
  if (customUrl.isNotEmpty) {
    if (given.isEmpty) throw ArgumentError('A custom url needs the key to test in key; saved keys only go to their own service.');
    final uri = Uri.tryParse(customUrl);
    if (uri == null || uri.scheme != 'https') throw ArgumentError('url must be a full https:// address.');
    final probe = KeyProbe(uri.host, customUrl, '${a['auth'] ?? 'bearer'}');
    return _runProbe(service.isEmpty ? uri.host : service, probe, given, saved: false);
  }

  final key = given.isNotEmpty ? given : (await savedKey(service)).trim();
  if (key.isEmpty) {
    return ToolOutput({
      'service': service,
      'works': false,
      'problem': keyProbes.containsKey(service) ? 'No key given and none saved for $service.' : 'Unknown service "$service" and no key saved.',
      'known_services': keyProbes.keys.toList(),
    });
  }
  final probe = keyProbes[service];
  if (probe != null) return _runProbe(service, probe, key, saved: given.isEmpty);
  final check = checkIdOf(service);
  if (check != null) {
    final clock = Stopwatch()..start();
    final problem = await verify(check, key);
    return ToolOutput({
      'service': service,
      'name': service,
      'works': problem == null,
      'problem': ?problem,
      'latency_ms': clock.elapsedMilliseconds,
      'ends_with': _ending(key),
      'saved_key': given.isEmpty,
    });
  }
  throw ArgumentError('No way to test "$service" here. Known: ${keyProbes.keys.join(', ')}; or pass url, auth and key.');
}

Future<ToolOutput> _runProbe(String id, KeyProbe p, String key, {required bool saved}) async {
  final uri = Uri.parse(p.url.replaceAll('{key}', Uri.encodeComponent(key)));
  final clock = Stopwatch()..start();
  http.Response r;
  try {
    r = await http
        .get(uri, headers: {'Accept': 'application/json', 'User-Agent': 'Triangle', ..._authHeaders(p.auth, key)})
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    return ToolOutput({'service': id, 'name': p.name, 'works': false, 'problem': 'Couldn\'t reach ${uri.host}: $e', 'ends_with': _ending(key)});
  }
  final ms = clock.elapsedMilliseconds;
  Object? body;
  try {
    body = jsonDecode(r.body);
  } catch (_) {}
  final ok = r.statusCode >= 200 && r.statusCode < 300;
  String? problem;
  if (!ok) {
    final msg = body is Map ? (body['error'] is Map ? (body['error'] as Map)['message'] : (body['error'] ?? body['message'] ?? body['detail'])) : null;
    problem = switch (r.statusCode) {
      401 => 'The key was refused (401 unauthorized)',
      403 => 'The key works but lacks permission for this (403)',
      402 => 'Out of credit or billing not set up (402)',
      429 => 'Rate limited right now (429); the key is probably valid',
      _ => 'HTTP ${r.statusCode}',
    };
    if (msg != null) problem = '$problem: ${'$msg'.length > 160 ? '${'$msg'.substring(0, 160)}…' : msg}';
  }
  return ToolOutput({
    'service': id,
    'name': p.name,
    'works': ok,
    'status': r.statusCode,
    'latency_ms': ms,
    if (ok && p.detail != null) 'detail': ?p.detail!(body),
    'problem': ?problem,
    'ends_with': _ending(key),
    'saved_key': saved,
    'endpoint': '${uri.scheme}://${uri.host}${uri.path}',
  });
}

// ---- http ----------------------------------------------------------------

const _readMethods = {'GET', 'HEAD', 'OPTIONS'};
const _maxModelBody = 12000;
const _maxCardBody = 200000;

Future<ToolOutput> _request(String tool, Map<String, dynamic> a, {required SavedKey savedKey}) async {
  final method = '${a['method'] ?? (tool == 'api_send' ? 'POST' : 'GET')}'.toUpperCase();
  if (tool == 'api_request' && !_readMethods.contains(method)) {
    throw ArgumentError('api_request only reads (GET, HEAD, OPTIONS). Use api_send for $method.');
  }
  if (tool == 'api_send' && _readMethods.contains(method)) {
    throw ArgumentError('Use api_request for $method.');
  }
  var uri = Uri.tryParse('${a['url'] ?? ''}'.trim());
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
    throw ArgumentError('url must be a full http(s) address.');
  }
  final query = a['query'];
  if (query is Map && query.isNotEmpty) {
    uri = uri.replace(queryParameters: {...uri.queryParameters, for (final e in query.entries) '${e.key}': '${e.value}'});
  }
  final headers = <String, String>{
    'User-Agent': 'Triangle',
    'Accept': 'application/json, text/plain;q=0.9, */*;q=0.5',
    if (a['headers'] is Map)
      for (final e in (a['headers'] as Map).entries) '${e.key}': '${e.value}',
  };

  // A saved key, only to its own service's hosts.
  final useKey = '${a['use_key'] ?? ''}'.trim().toLowerCase();
  if (useKey.isNotEmpty) {
    final probe = keyProbes[useKey];
    if (probe == null || !probe.hosts.contains(uri.host)) {
      throw ArgumentError(
        'use_key "$useKey" can only be sent to ${probe == null ? 'its own service' : probe.hosts.join(', ')}, not ${uri.host}.',
      );
    }
    final key = (await savedKey(useKey)).trim();
    if (key.isEmpty) throw ArgumentError('No saved key for $useKey.');
    if (probe.auth == 'url') {
      uri = Uri.parse(uri.toString().replaceAll('{key}', Uri.encodeComponent(key)));
    } else {
      headers.addAll(_authHeaders(probe.auth, key));
    }
  }

  String? body;
  if (a['json'] != null) {
    body = jsonEncode(a['json']);
    headers.putIfAbsent('Content-Type', () => 'application/json');
  } else if (a['body'] != null) {
    body = '${a['body']}';
  }

  final req = http.Request(method, uri)..headers.addAll(headers);
  if (body != null) req.body = body;
  final client = http.Client();
  final clock = Stopwatch()..start();
  late http.Response r;
  try {
    r = await http.Response.fromStream(await client.send(req).timeout(Duration(seconds: ((a['timeout_seconds'] as num?)?.toInt() ?? 30).clamp(1, 120))));
  } catch (e) {
    return ToolOutput({'method': method, 'url': _shown(uri, useKey), 'ok': false, 'error': 'Request failed: $e', 'latency_ms': clock.elapsedMilliseconds});
  } finally {
    client.close();
  }
  final ms = clock.elapsedMilliseconds;
  final type = r.headers['content-type'] ?? '';
  final bytes = r.bodyBytes.length;
  final textual = type.isEmpty || RegExp(r'json|text|xml|javascript|html|csv|yaml|x-www-form').hasMatch(type);
  String text = '';
  Object? parsed;
  if (textual) {
    text = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (type.contains('json') || text.trimLeft().startsWith('{') || text.trimLeft().startsWith('[')) {
      try {
        parsed = jsonDecode(text);
      } catch (_) {}
    }
  }
  // Pictures, audio, video and PDFs are saved for the card to show.
  Map<String, dynamic>? media;
  if (!textual && bytes > 0 && RegExp(r'^(image|audio|video)/|pdf').hasMatch(type)) {
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/api_media');
      await dir.create(recursive: true);
      final ext = switch (type.split(';').first.trim()) {
        'image/jpeg' => 'jpg',
        'image/svg+xml' => 'svg',
        'audio/mpeg' => 'mp3',
        'application/pdf' => 'pdf',
        final t => t.split('/').last.replaceAll(RegExp(r'[^a-z0-9]'), ''),
      };
      final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(r.bodyBytes);
      media = {
        'path': file.path,
        'kind': type.startsWith('image/') ? 'image' : type.startsWith('audio/') ? 'audio' : type.startsWith('video/') ? 'video' : 'pdf',
        'type': type.split(';').first.trim(),
      };
    } catch (_) {}
  }
  final keepHeaders = {
    for (final e in r.headers.entries)
      if (!const {'set-cookie', 'cf-ray', 'report-to', 'nel', 'alt-svc'}.contains(e.key)) e.key: e.value,
  };
  final base = {
    'method': method,
    'url': _shown(uri, useKey),
    'status': r.statusCode,
    'reason': r.reasonPhrase,
    'ok': r.statusCode >= 200 && r.statusCode < 300,
    'latency_ms': ms,
    'size_bytes': bytes,
    'content_type': type,
    'used_key': useKey.isEmpty ? null : useKey,
  }..removeWhere((_, v) => v == null);
  final forModel = {
    ...base,
    'headers': {
      for (final k in ['content-type', 'location', 'retry-after', 'x-ratelimit-remaining', 'etag', 'last-modified'])
        if (keepHeaders[k] != null) k: keepHeaders[k],
    },
    if (!textual)
      'body': '[$bytes bytes of $type${media == null ? '' : ', saved and shown to the user on the card'}]'
    else if (parsed != null && text.length <= _maxModelBody)
      'json': parsed
    else
      'body': text.length > _maxModelBody ? '${text.substring(0, _maxModelBody)}… [${text.length - _maxModelBody} more characters]' : text,
  };
  return ToolOutput(forModel, full: {
    ...base,
    'headers': keepHeaders,
    if (parsed != null && text.length <= _maxCardBody) 'json': parsed else if (textual) 'body': text.length > _maxCardBody ? text.substring(0, _maxCardBody) : text,
    if (body != null) 'request_body': body.length > 4000 ? '${body.substring(0, 4000)}…' : body,
    'media': ?media,
    'request_headers': {
      for (final e in headers.entries)
        e.key: RegExp(r'auth|key|token|secret', caseSensitive: false).hasMatch(e.key) ? '•••' : e.value,
    },
  });
}

/// The address as shown: a key put in it never appears.
String _shown(Uri uri, String useKey) {
  if (useKey.isEmpty || keyProbes[useKey]?.auth != 'url') return uri.toString();
  return uri.replace(queryParameters: {
    for (final e in uri.queryParameters.entries) e.key: RegExp(r'key|token', caseSensitive: false).hasMatch(e.key) ? '•••' : e.value,
  }).toString().replaceAll(RegExp(r'/bot[^/]+/'), '/bot•••/');
}

// ---- balances ------------------------------------------------------------

Future<ToolOutput> _balances({required SavedKey savedKey, required ReadCredits credits}) async {
  Future<Map<String, dynamic>> one(String id, String name, Future<Map<String, dynamic>> Function(String key) read) async {
    final key = (await savedKey(id)).trim();
    if (key.isEmpty) return {'service': id, 'name': name, 'set': false};
    try {
      return {'service': id, 'name': name, 'set': true, ...await read(key).timeout(const Duration(seconds: 20))};
    } catch (e) {
      return {'service': id, 'name': name, 'set': true, 'problem': '$e'.replaceFirst('Exception: ', '')};
    }
  }

  Future<Object?> getJson(String url, Map<String, String> headers) async {
    final r = await http.get(Uri.parse(url), headers: {'Accept': 'application/json', ...headers});
    if (r.statusCode >= 300) throw Exception('HTTP ${r.statusCode}');
    return jsonDecode(r.body);
  }

  double? n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

  // OpenRouter and Vercel through omni_ai (`OmniAI.credits`): OpenRouter
  // falls back to the key's own limit when the key may not read the
  // account's credits.
  Map<String, dynamic> fromCredits(ProviderCredits c) => {
    'currency': 'USD',
    'balance': ?c.balance,
    'used': ?c.used,
    // With a key-only answer the "total" is the key's limit.
    if ((c.total ?? c.limit) != null) 'total': c.total ?? c.limit,
    'source': c.source,
    if (c.source == 'key' && c.limit == null) 'note': 'This key has no spending limit, and it can\'t read the account\'s credits.',
    if (c.source == 'key' && c.limit != null) 'note': 'This key\'s own limit; it can\'t read the account\'s credits.',
    if (c.raw['is_free_tier'] == true) 'plan': 'Free tier',
  };

  final rows = await Future.wait([
    one('openrouter', 'OpenRouter', (_) async => fromCredits(await credits('openrouter'))),
    one('vercel', 'Vercel AI Gateway', (_) async => fromCredits(await credits('gateway'))),
    one('elevenlabs', 'ElevenLabs', (k) async {
      final s = await getJson('https://api.elevenlabs.io/v1/user/subscription', {'xi-api-key': k}) as Map;
      final limit = n(s['character_limit']) ?? 0, used = n(s['character_count']) ?? 0;
      final reset = (s['next_character_count_reset_unix'] as num?)?.toInt();
      return {
        'unit': 'characters',
        'balance': limit - used,
        'total': limit,
        'used': used,
        'plan': s['tier'],
        if (reset != null) 'resets': DateTime.fromMillisecondsSinceEpoch(reset * 1000).toIso8601String().substring(0, 10),
      };
    }),
    one('opencode', 'OpenCode Zen', (_) async => {'note': 'OpenCode Zen has no balance API; see opencode.ai/console.'}),
    one('gemini', 'Google AI Studio', (_) async => {'note': 'Google has no balance API for AI Studio keys; free-tier limits reset daily, paid use is billed in Google Cloud.'}),
  ]);
  return ToolOutput({'balances': rows.where((r) => r['set'] == true).toList(), 'without_key': [for (final r in rows) if (r['set'] != true) r['name']]});
}
