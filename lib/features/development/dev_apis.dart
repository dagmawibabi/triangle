import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;
import 'package:http/http.dart' as http;

/// A failed Vercel or Resend call, with what the service said.
class DevApiException implements Exception {
  const DevApiException(this.service, this.message, {this.status, this.code});
  final String service;
  final String message;
  final int? status;
  final String? code;
  @override
  String toString() => message;
}

/// The Vercel REST API (api.vercel.com) with an access token. Calls carry
/// the team when one is set.
class VercelApi {
  VercelApi({required this.token, this.teamId = '', http.Client? client}) : _http = client ?? http.Client();
  final String token;
  final String teamId;
  final http.Client _http;

  static const base = 'https://api.vercel.com';

  Uri uri(String path, [Map<String, String>? query]) {
    final p = path.startsWith('http') ? Uri.parse(path) : Uri.parse('$base${path.startsWith('/') ? '' : '/'}$path');
    final q = {...p.queryParameters, ...?query};
    if (teamId.isNotEmpty && !q.containsKey('teamId') && !q.containsKey('slug')) q['teamId'] = teamId;
    q.removeWhere((_, v) => v.isEmpty);
    return p.replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> call(String method, String path, {Map<String, String>? query, Object? body, Duration timeout = const Duration(seconds: 60)}) async {
    final req = http.Request(method.toUpperCase(), uri(path, query))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = body is String ? body : jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      json = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json ?? (text.isEmpty ? {'ok': true} : text);
    final err = json is Map ? (json['error'] is Map ? json['error'] as Map : json) : const {};
    final message = '${err['message'] ?? (text.isEmpty ? 'HTTP ${res.statusCode}' : text)}';
    throw DevApiException(
      'vercel',
      res.statusCode == 401 || res.statusCode == 403 ? 'Vercel refused the token: $message' : message,
      status: res.statusCode,
      code: err['code'] as String?,
    );
  }

  /// Uploads one file for a deployment; returns its sha1.
  Future<String> uploadFile(Uint8List bytes) async {
    final sha = sha1.convert(bytes).toString();
    final res = await _http
        .post(
          uri('/v2/files'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/octet-stream',
            'x-vercel-digest': sha,
            'Content-Length': '${bytes.length}',
          },
          body: bytes,
        )
        .timeout(const Duration(minutes: 3));
    _decode(res);
    return sha;
  }

  /// A deployment's build events, oldest first: the latest [limit] of them.
  /// Vercel answers with a JSON array, or with one JSON event per line.
  Future<List<Map<String, dynamic>>> events(String deploymentId, {int limit = 300}) async {
    List<Map<String, dynamic>> parse(Object? r) {
      final List list;
      if (r is List) {
        list = r;
      } else if (r is Map) {
        list = (r['events'] ?? r['logs']) as List? ?? const [];
      } else if (r is String) {
        list = [
          for (final line in const LineSplitter().convert(r))
            if (line.trim().startsWith('{')) _tryDecode(line),
        ];
      } else {
        list = const [];
      }
      return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
    }

    int at(Map e) => ((e['created'] ?? (e['payload'] as Map?)?['date'] ?? 0) as num).toInt();
    List<Map<String, dynamic>> ordered(List<Map<String, dynamic>> list) {
      list.sort((a, b) => at(a).compareTo(at(b)));
      return list.length > limit ? list.sublist(list.length - limit) : list;
    }

    final path = '/v3/deployments/$deploymentId/events';
    DevApiException? first;
    try {
      final list = parse(await call('GET', path, query: {'limit': '$limit', 'direction': 'backward', 'builds': '1'}));
      if (list.isNotEmpty) return ordered(list);
    } on DevApiException catch (e) {
      first = e;
    }
    // Some deployments only answer the plain form: every event, oldest first.
    try {
      return ordered(parse(await call('GET', path, query: {'limit': '-1'})));
    } on DevApiException {
      if (first != null) throw first;
      rethrow;
    }
  }

  static Object? _tryDecode(String line) {
    try {
      return jsonDecode(line);
    } catch (_) {
      return null;
    }
  }

  void close() => _http.close();
}

/// Resend (api.resend.com): email, domains, audiences, contacts,
/// broadcasts, API keys and webhooks.
class ResendApi {
  ResendApi({required this.key, http.Client? client}) : _http = client ?? http.Client();
  final String key;
  final http.Client _http;

  static const base = 'https://api.resend.com';

  Future<dynamic> call(String method, String path, {Map<String, String>? query, Object? body, Map<String, String>? headers}) async {
    for (var attempt = 0; ; attempt++) {
      final u = Uri.parse('$base${path.startsWith('/') ? '' : '/'}$path').replace(queryParameters: (query == null || query.isEmpty) ? null : query);
      final req = http.Request(method.toUpperCase(), u)
        ..headers['Authorization'] = 'Bearer $key'
        ..headers['Accept'] = 'application/json'
        ..headers['User-Agent'] = 'Triangle';
      if (headers != null) req.headers.addAll(headers);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = body is String ? body : jsonEncode(body);
      }
      final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 60)));
      // Resend allows a few requests a second; wait once and retry.
      if (res.statusCode == 429 && attempt < 2) {
        final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 1;
        await Future<void>.delayed(Duration(milliseconds: 600 + wait * 400));
        continue;
      }
      final text = utf8.decode(res.bodyBytes, allowMalformed: true);
      Object? json;
      try {
        json = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        json = null;
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return json ?? {'ok': true};
      final err = json is Map ? json : const {};
      final message = '${err['message'] ?? (text.isEmpty ? 'HTTP ${res.statusCode}' : text)}';
      throw DevApiException(
        'resend',
        res.statusCode == 401 || res.statusCode == 403 ? 'Resend refused the key: $message' : message,
        status: res.statusCode,
        code: err['name'] as String?,
      );
    }
  }

  void close() => _http.close();
}
