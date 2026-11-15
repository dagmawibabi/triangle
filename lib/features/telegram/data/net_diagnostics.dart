import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'telegram_tools.dart' show ToolOutput;

// Network diagnostics: what an address does step by step (DNS, TCP, TLS,
// redirects, first byte), DNS records, certificates, ports, the phone's
// public IP, domain registration (RDAP) and many URLs' status at once. Used
// by the http_diagnose, dns_lookup, ssl_certificate, port_check, my_ip,
// whois_lookup and url_check tools, and by the API cards' Diagnose tab.

const networkDiagnosticTools = {'http_diagnose', 'dns_lookup', 'ssl_certificate', 'port_check', 'my_ip', 'whois_lookup', 'url_check'};

Future<ToolOutput> runDiagnosticTool(String name, Map<String, dynamic> a) async {
  switch (name) {
    case 'http_diagnose':
      return ToolOutput(await diagnoseUrl('${a['url'] ?? ''}', method: '${a['method'] ?? 'GET'}'));
    case 'dns_lookup':
      return ToolOutput(await dnsLookup('${a['name'] ?? ''}', types: [for (final t in (a['types'] as List? ?? const ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS'])) '$t'.toUpperCase()]));
    case 'ssl_certificate':
      return ToolOutput(await certificateOf('${a['host'] ?? ''}', port: (a['port'] as num?)?.toInt() ?? 443));
    case 'port_check':
      return ToolOutput(await checkPorts('${a['host'] ?? ''}', [for (final p in (a['ports'] as List? ?? const [80, 443])) (p as num).toInt()]));
    case 'my_ip':
      return ToolOutput(await myIp());
    case 'whois_lookup':
      return ToolOutput(await rdap('${a['domain'] ?? ''}'));
    case 'url_check':
      return ToolOutput(await checkUrls([for (final u in (a['urls'] as List? ?? const [])) '$u']));
  }
  throw ArgumentError('Unknown tool $name');
}

String _host(String raw) {
  final s = raw.trim();
  final u = Uri.tryParse(s.contains('://') ? s : 'https://$s');
  if (u == null || u.host.isEmpty) throw ArgumentError('Give a host or address, e.g. example.com.');
  return u.host;
}

/// Step-by-step timing for [raw]: DNS, TCP connect, TLS handshake (with its
/// certificate), each redirect, first byte and total.
Future<Map<String, dynamic>> diagnoseUrl(String raw, {String method = 'GET'}) async {
  var uri = Uri.tryParse(raw.trim().contains('://') ? raw.trim() : 'https://${raw.trim()}');
  if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    throw ArgumentError('Give a full http(s) address.');
  }
  final steps = <Map<String, dynamic>>[];
  final out = <String, dynamic>{'url': uri.toString()};
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);

  // DNS.
  var clock = Stopwatch()..start();
  List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(uri.host).timeout(const Duration(seconds: 10));
    steps.add({'step': 'DNS', 'ms': clock.elapsedMilliseconds, 'ok': true, 'detail': addresses.take(4).map((a) => a.address).join(', ')});
  } catch (e) {
    steps.add({'step': 'DNS', 'ms': clock.elapsedMilliseconds, 'ok': false, 'detail': '$e'});
    return {...out, 'ok': false, 'steps': steps, 'problem': 'The name ${uri.host} doesn\'t resolve.'};
  }

  // TCP.
  clock = Stopwatch()..start();
  try {
    final s = await Socket.connect(addresses.first, port, timeout: const Duration(seconds: 10));
    steps.add({'step': 'TCP connect', 'ms': clock.elapsedMilliseconds, 'ok': true, 'detail': '${addresses.first.address}:$port'});
    s.destroy();
  } catch (e) {
    steps.add({'step': 'TCP connect', 'ms': clock.elapsedMilliseconds, 'ok': false, 'detail': '$e'});
    return {...out, 'ok': false, 'steps': steps, 'problem': 'Nothing answers on port $port.'};
  }

  // TLS.
  if (uri.scheme == 'https') {
    clock = Stopwatch()..start();
    try {
      final s = await SecureSocket.connect(uri.host, port, timeout: const Duration(seconds: 10), supportedProtocols: const ['h2', 'http/1.1']);
      final cert = s.peerCertificate;
      steps.add({'step': 'TLS handshake', 'ms': clock.elapsedMilliseconds, 'ok': true, 'detail': s.selectedProtocol ?? 'http/1.1'});
      if (cert != null) out['certificate'] = _cert(cert);
      s.destroy();
    } catch (e) {
      steps.add({'step': 'TLS handshake', 'ms': clock.elapsedMilliseconds, 'ok': false, 'detail': '$e'});
      return {...out, 'ok': false, 'steps': steps, 'problem': 'The secure connection failed (certificate or TLS).'};
    }
  }

  // HTTP, following redirects by hand so each shows.
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final redirects = <Map<String, dynamic>>[];
  try {
    for (var hop = 0; hop < 10; hop++) {
      clock = Stopwatch()..start();
      final req = await client.openUrl(method.toUpperCase(), uri!);
      req
        ..followRedirects = false
        ..headers.set('User-Agent', 'Triangle');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final firstByte = clock.elapsedMilliseconds;
      var bytes = 0;
      await for (final chunk in res) {
        bytes += chunk.length;
        if (bytes > 5 * 1024 * 1024) break;
      }
      final total = clock.elapsedMilliseconds;
      if (res.isRedirect && res.headers.value('location') != null) {
        final next = uri.resolve(res.headers.value('location')!);
        redirects.add({'status': res.statusCode, 'from': uri.toString(), 'to': next.toString(), 'ms': total});
        uri = next;
        continue;
      }
      steps.add({'step': 'First byte', 'ms': firstByte, 'ok': true, 'detail': 'HTTP ${res.statusCode}'});
      steps.add({'step': 'Download', 'ms': total - firstByte, 'ok': true, 'detail': '$bytes bytes'});
      out.addAll({
        'ok': res.statusCode < 400,
        'status': res.statusCode,
        'final_url': uri.toString(),
        'server': res.headers.value('server'),
        'content_type': res.headers.contentType?.mimeType,
        'compressed': res.compressionState != HttpClientResponseCompressionState.notCompressed,
        'size_bytes': bytes,
        'headers': {
          for (final k in ['cache-control', 'strict-transport-security', 'content-security-policy', 'x-frame-options', 'access-control-allow-origin', 'via', 'cf-cache-status', 'x-cache', 'age'])
            if (res.headers.value(k) != null) k: res.headers.value(k),
        },
      });
      break;
    }
  } catch (e) {
    steps.add({'step': 'HTTP', 'ms': clock.elapsedMilliseconds, 'ok': false, 'detail': '$e'});
    out['ok'] = false;
    out['problem'] = 'The request failed: $e';
  } finally {
    client.close(force: true);
  }
  out['steps'] = steps;
  if (redirects.isNotEmpty) out['redirects'] = redirects;
  out['total_ms'] = [for (final s in steps) s['ms'] as int].fold<int>(0, (a, b) => a + b) + [for (final r in redirects) r['ms'] as int].fold<int>(0, (a, b) => a + b);
  out.removeWhere((_, v) => v == null);
  return out;
}

Map<String, dynamic> _cert(X509Certificate c) {
  final days = c.endValidity.difference(DateTime.now()).inDays;
  String cn(String dn) => RegExp(r'CN=([^,/]+)').firstMatch(dn)?[1] ?? dn;
  return {
    'subject': cn(c.subject),
    'issuer': cn(c.issuer),
    'valid_from': c.startValidity.toIso8601String().substring(0, 10),
    'valid_until': c.endValidity.toIso8601String().substring(0, 10),
    'days_left': days,
    if (days < 0) 'expired': true,
    if (days >= 0 && days < 14) 'expires_soon': true,
  };
}

/// The certificate [host] presents.
Future<Map<String, dynamic>> certificateOf(String raw, {int port = 443}) async {
  final host = _host(raw);
  final clock = Stopwatch()..start();
  try {
    final s = await SecureSocket.connect(host, port, timeout: const Duration(seconds: 12), supportedProtocols: const ['h2', 'http/1.1']);
    final cert = s.peerCertificate;
    final out = {
      'host': host,
      'port': port,
      'valid': true,
      'protocol': s.selectedProtocol ?? 'http/1.1',
      'handshake_ms': clock.elapsedMilliseconds,
      if (cert != null) ..._cert(cert),
    };
    s.destroy();
    return out;
  } on HandshakeException catch (e) {
    return {'host': host, 'port': port, 'valid': false, 'problem': 'The certificate isn\'t trusted: ${e.message}'};
  } catch (e) {
    return {'host': host, 'port': port, 'valid': false, 'problem': '$e'};
  }
}

/// DNS records over HTTPS (Cloudflare), by type.
Future<Map<String, dynamic>> dnsLookup(String raw, {List<String> types = const ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS']}) async {
  final name = _host(raw);
  final records = <String, List<String>>{};
  await Future.wait([
    for (final t in types.take(10))
      () async {
        try {
          final r = await http
              .get(Uri.https('cloudflare-dns.com', '/dns-query', {'name': name, 'type': t}), headers: {'Accept': 'application/dns-json'})
              .timeout(const Duration(seconds: 10));
          final j = jsonDecode(r.body) as Map;
          final answers = [for (final a in (j['Answer'] as List? ?? const [])) if (a is Map) '${a['data']}'.replaceAll('"', '')];
          if (answers.isNotEmpty) records[t] = answers;
        } catch (_) {}
      }(),
  ]);
  return {'name': name, 'records': records, if (records.isEmpty) 'note': 'No records found (or the name doesn\'t exist).'};
}

/// Whether [ports] on [host] accept a connection.
Future<Map<String, dynamic>> checkPorts(String raw, List<int> ports) async {
  final host = _host(raw);
  if (ports.length > 20) throw ArgumentError('At most 20 ports at once.');
  final rows = await Future.wait([
    for (final p in ports)
      () async {
        final clock = Stopwatch()..start();
        try {
          final s = await Socket.connect(host, p, timeout: const Duration(seconds: 4));
          s.destroy();
          return {'port': p, 'open': true, 'ms': clock.elapsedMilliseconds};
        } catch (_) {
          return {'port': p, 'open': false, 'ms': clock.elapsedMilliseconds};
        }
      }(),
  ]);
  return {'host': host, 'ports': rows, 'open': [for (final r in rows) if (r['open'] == true) r['port']]};
}

/// The phone's public address and roughly where it is.
Future<Map<String, dynamic>> myIp() async {
  final r = await http.get(Uri.parse('https://ipapi.co/json/'), headers: {'User-Agent': 'Triangle'}).timeout(const Duration(seconds: 12));
  final j = jsonDecode(r.body) as Map;
  if (j['error'] == true) {
    final simple = await http.get(Uri.parse('https://api.ipify.org?format=json')).timeout(const Duration(seconds: 10));
    return {'ip': (jsonDecode(simple.body) as Map)['ip']};
  }
  return {
    'ip': j['ip'],
    'version': j['version'],
    'city': j['city'],
    'region': j['region'],
    'country': j['country_name'],
    'network': j['org'],
    'asn': j['asn'],
    'timezone': j['timezone'],
  }..removeWhere((_, v) => v == null);
}

/// A domain's registration (RDAP, the successor of WHOIS).
Future<Map<String, dynamic>> rdap(String raw) async {
  var domain = _host(raw).toLowerCase();
  final parts = domain.split('.');
  if (parts.length > 2 && !RegExp(r'\.(co|com|org|net|ac|gov)\.\w\w$').hasMatch(domain)) domain = parts.sublist(parts.length - 2).join('.');
  final r = await http.get(Uri.parse('https://rdap.org/domain/$domain'), headers: {'Accept': 'application/rdap+json'}).timeout(const Duration(seconds: 15));
  if (r.statusCode == 404) return {'domain': domain, 'registered': false, 'note': 'No registration found: it may be available.'};
  if (r.statusCode >= 300) return {'domain': domain, 'problem': 'RDAP answered ${r.statusCode}; this domain\'s registry may not support it.'};
  final j = jsonDecode(r.body) as Map;
  String? event(String action) => [
    for (final e in (j['events'] as List? ?? const []))
      if (e is Map && e['eventAction'] == action) '${e['eventDate']}'.substring(0, 10),
  ].firstOrNull;
  String? registrar() {
    for (final e in (j['entities'] as List? ?? const [])) {
      if (e is Map && (e['roles'] as List? ?? const []).contains('registrar')) {
        final card = e['vcardArray'];
        if (card is List && card.length > 1) {
          for (final f in card[1] as List) {
            if (f is List && f.first == 'fn') return '${f.last}';
          }
        }
        return e['handle'] as String?;
      }
    }
    return null;
  }

  final expires = event('expiration');
  return {
    'domain': domain,
    'registered': true,
    'registrar': registrar(),
    'created': event('registration'),
    'updated': event('last changed'),
    'expires': expires,
    if (expires != null) 'days_left': DateTime.parse(expires).difference(DateTime.now()).inDays,
    'status': [for (final s in (j['status'] as List? ?? const [])) '$s'],
    'nameservers': [for (final n in (j['nameservers'] as List? ?? const [])) if (n is Map) '${n['ldhName']}'.toLowerCase()],
  }..removeWhere((_, v) => v == null);
}

/// Status and timing of up to 15 URLs, checked at once.
Future<Map<String, dynamic>> checkUrls(List<String> urls) async {
  if (urls.isEmpty) throw ArgumentError('Give urls.');
  final rows = await Future.wait([
    for (final raw in urls.take(15))
      () async {
        final u = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
        final clock = Stopwatch()..start();
        try {
          final r = await http.get(u!, headers: {'User-Agent': 'Triangle'}).timeout(const Duration(seconds: 20));
          return {'url': raw, 'status': r.statusCode, 'up': r.statusCode < 400, 'ms': clock.elapsedMilliseconds, 'bytes': r.bodyBytes.length};
        } catch (e) {
          return {'url': raw, 'up': false, 'ms': clock.elapsedMilliseconds, 'problem': '$e'.split('\n').first};
        }
      }(),
  ]);
  return {'checked': rows.length, 'up': rows.where((r) => r['up'] == true).length, 'results': rows};
}
