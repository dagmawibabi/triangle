import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'info_keys.dart';

// Free public lookups for the assistant: packages (npm, PyPI, pub.dev),
// domains (RDAP, DNS over HTTPS, the TLS certificate), xkcd, metal and
// fuel prices, earthquakes (USGS) and disasters (GDACS), recipes
// (TheMealDB) and food (Open Food Facts), air quality, UV, pollen and the
// sun (Open-Meteo), words (Free Dictionary, MyMemory, LibreTranslate) and
// Wikipedia. None needs an account except metals.dev.

class InfoException implements Exception {
  const InfoException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _ua = 'Triangle/1.0 (assistant app)';

class InfoApi {
  InfoApi._();
  static final instance = InfoApi._();

  final _client = http.Client();
  final _cache = <String, (DateTime, Object?)>{};

  Future<Object?> _get(Uri url, {Map<String, String> headers = const {}, Duration cache = const Duration(minutes: 5), String? source, bool allow404 = false}) async {
    final key = url.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < cache) return hit.$2;
    final http.Response r;
    try {
      r = await _client.get(url, headers: {'User-Agent': _ua, 'Accept': 'application/json', ...headers}).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw InfoException('${source ?? url.host} took too long to answer; try again.');
    } on SocketException {
      throw InfoException('Couldn\'t reach ${source ?? url.host}; check the connection.');
    }
    if (r.statusCode == 404 && allow404) return null;
    if (r.statusCode == 404) throw InfoException('Not found on ${source ?? url.host}.');
    if (r.statusCode == 429) throw InfoException('${source ?? url.host} is rate-limiting requests; wait a minute.');
    if (r.statusCode >= 400) throw InfoException('${source ?? url.host} answered ${r.statusCode}.');
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final Object? j;
    try {
      j = body.trim().isEmpty ? null : jsonDecode(body);
    } on FormatException {
      throw InfoException('${source ?? url.host} sent something unexpected.');
    }
    _cache[key] = (DateTime.now(), j);
    if (_cache.length > 300) _cache.remove(_cache.keys.first);
    return j;
  }

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
  static num? _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
  static String? _s(Object? v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static String? _cleanUrl(Object? v) {
    var s = _s(v);
    if (s == null) return null;
    s = s.replaceFirst(RegExp(r'^git\+'), '').replaceFirst(RegExp(r'\.git$'), '').replaceFirst('git://', 'https://').replaceFirst('ssh://git@', 'https://');
    return s.startsWith('http') ? s : null;
  }

  // ---- packages ---------------------------------------------------------------------

  Future<Map<String, dynamic>> package(String registry, String name) async {
    name = name.trim();
    if (name.isEmpty) throw const InfoException('Which package?');
    return switch (registry) {
      'npm' => _npm(name),
      'pypi' => _pypi(name),
      'pub' => _pub(name),
      _ => throw InfoException('Registry is npm, pypi or pub, not "$registry".'),
    };
  }

  Future<Map<String, dynamic>> _npm(String name) async {
    final enc = name.startsWith('@') ? '@${Uri.encodeComponent(name.substring(1))}' : Uri.encodeComponent(name);
    // The latest version's manifest; the full document can run to many MB.
    final v = _m(await _get(Uri.parse('https://registry.npmjs.org/$enc/latest'), source: 'npm'));
    if (v.isEmpty || v['version'] == null) throw InfoException('No npm package "$name".');
    final pkg = '${v['name'] ?? name}';
    Map<String, dynamic>? dl;
    Map<String, dynamic>? hit;
    await Future.wait([
      () async {
        try {
          dl = _m(await _get(Uri.parse('https://api.npmjs.org/downloads/point/last-week/$enc'), source: 'npm'));
        } catch (_) {}
      }(),
      () async {
        try {
          final s = _m(await _get(Uri.https('registry.npmjs.org', '/-/v1/search', {'text': pkg, 'size': '5'}), source: 'npm'));
          hit = _l(s['objects']).map((o) => _m(o['package'])).where((p) => p['name'] == pkg).firstOrNull;
        } catch (_) {}
      }(),
    ]);
    final deps = _m(v['dependencies']);
    final links = _m(hit?['links']);
    return {
      'registry': 'npm',
      'name': pkg,
      'version': v['version'],
      'description': _s(v['description']),
      'license': _s(v['license'] is Map ? _m(v['license'])['type'] : v['license']),
      'homepage': _cleanUrl(v['homepage'] ?? links['homepage']),
      'repository': _cleanUrl(v['repository'] is Map ? _m(v['repository'])['url'] : v['repository']) ?? _cleanUrl(links['repository']),
      'published': _s(hit?['date']),
      'weekly_downloads': ?_n(dl?['downloads']),
      'dependencies': deps.length,
      'dependency_names': deps.keys.take(20).toList(),
      'peer_dependencies': _m(v['peerDependencies']).keys.take(10).toList(),
      'keywords': [for (final k in (v['keywords'] as List? ?? const []).take(10)) '$k'],
      'maintainers': [for (final m in _l(v['maintainers']).take(6)) m['name']],
      'engines': _m(v['engines']).map((k, x) => MapEntry(k, '$x')),
      'unpacked_size': ?_n(_m(v['dist'])['unpackedSize']),
      'deprecated': ?_s(v['deprecated']),
      'types': v['types'] != null || v['typings'] != null,
      'install': 'npm install $pkg',
      'url': 'https://www.npmjs.com/package/$pkg',
    };
  }

  Future<Map<String, dynamic>> _pypi(String name) async {
    final j = _m(await _get(Uri.parse('https://pypi.org/pypi/${Uri.encodeComponent(name)}/json'), source: 'PyPI'));
    final info = _m(j['info']);
    if (info.isEmpty) throw InfoException('No PyPI package "$name".');
    final urls = _m(info['project_urls']);
    final files = _l(j['urls']);
    final releases = _m(j['releases']);
    final dated = <MapEntry<String, String>>[];
    releases.forEach((ver, list) {
      final f = _l(list);
      if (f.isNotEmpty) dated.add(MapEntry(ver, '${f.first['upload_time_iso_8601'] ?? f.first['upload_time'] ?? ''}'));
    });
    dated.sort((a, b) => b.value.compareTo(a.value));
    Map<String, dynamic>? stats;
    try {
      stats = _m(_m(await _get(Uri.parse('https://pypistats.org/api/packages/${Uri.encodeComponent(name.toLowerCase())}/recent'), source: 'pypistats', cache: const Duration(hours: 1)))['data']);
    } catch (_) {}
    String? repo;
    for (final e in urls.entries) {
      if (RegExp('source|repo|code|github', caseSensitive: false).hasMatch(e.key)) repo = _cleanUrl(e.value);
    }
    final classifiers = [for (final c in (info['classifiers'] as List? ?? const [])) '$c'];
    return {
      'registry': 'pypi',
      'name': info['name'] ?? name,
      'version': info['version'],
      'description': _s(info['summary']),
      'license': _s(info['license_expression']) ??
          (_s(info['license']) != null && '${info['license']}'.length < 60 ? _s(info['license']) : null) ??
          classifiers.where((c) => c.startsWith('License ::')).map((c) => c.split('::').last.trim()).firstOrNull,
      'homepage': _cleanUrl(info['home_page']) ?? _cleanUrl(urls['Homepage'] ?? urls['homepage'] ?? urls['Documentation']),
      'repository': repo,
      'published': files.isEmpty ? null : _s(files.first['upload_time_iso_8601']),
      'requires_python': _s(info['requires_python']),
      'author': _s(info['author']) ?? _s(info['author_email'])?.split('<').first.trim(),
      'versions_count': releases.length,
      'recent_versions': [for (final e in dated.take(8)) {'version': e.key, 'date': e.value.length >= 10 ? e.value.substring(0, 10) : e.value}],
      'weekly_downloads': ?_n(stats?['last_week']),
      'monthly_downloads': ?_n(stats?['last_month']),
      'dependencies': (info['requires_dist'] as List?)?.where((d) => !'$d'.contains('extra ==')).length ?? 0,
      'dependency_names': [for (final d in (info['requires_dist'] as List? ?? const []).where((d) => !'$d'.contains('extra ==')).take(20)) '$d'.split(RegExp(r'[ ;<>=!~\[(]')).first],
      'keywords': _s(info['keywords'])?.split(RegExp(r'[,\s]+')).where((k) => k.isNotEmpty).take(10).toList() ?? const [],
      'yanked': info['yanked'] == true,
      'install': 'pip install ${info['name'] ?? name}',
      'url': 'https://pypi.org/project/${info['name'] ?? name}/',
    };
  }

  Future<Map<String, dynamic>> _pub(String name) async {
    final j = _m(await _get(Uri.parse('https://pub.dev/api/packages/${Uri.encodeComponent(name)}'), source: 'pub.dev'));
    final latest = _m(j['latest']);
    final spec = _m(latest['pubspec']);
    if (spec.isEmpty) throw InfoException('No pub.dev package "$name".');
    Map<String, dynamic> score = {};
    try {
      score = _m(await _get(Uri.parse('https://pub.dev/api/packages/${Uri.encodeComponent(name)}/score'), source: 'pub.dev'));
    } catch (_) {}
    final versions = _l(j['versions']);
    final tags = [for (final t in (score['tags'] as List? ?? const [])) '$t'];
    final deps = _m(spec['dependencies']);
    return {
      'registry': 'pub',
      'name': j['name'] ?? name,
      'version': latest['version'],
      'description': _s(spec['description']),
      'homepage': _cleanUrl(spec['homepage']),
      'repository': _cleanUrl(spec['repository'] ?? spec['homepage']),
      'published': _s(latest['published']),
      'versions_count': versions.length,
      'recent_versions': [
        for (final v in versions.reversed.take(8)) {'version': v['version'], 'date': '${v['published'] ?? ''}'.length >= 10 ? '${v['published']}'.substring(0, 10) : ''},
      ],
      'likes': ?_n(score['likeCount']),
      'pub_points': ?_n(score['grantedPoints']),
      'max_points': ?_n(score['maxPoints']),
      'monthly_downloads': ?_n(score['downloadCount30Days']),
      'platforms': [for (final t in tags) if (t.startsWith('platform:')) t.substring(9)],
      'sdk': [for (final t in tags) if (t.startsWith('sdk:')) t.substring(4)],
      'publisher': tags.where((t) => t.startsWith('publisher:')).map((t) => t.substring(10)).firstOrNull,
      'null_safe': tags.contains('is:null-safe'),
      'dart3': tags.contains('is:dart3-compatible'),
      'license': tags.where((t) => t.startsWith('license:') && t != 'license:fsf-libre' && t != 'license:osi-approved').map((t) => t.substring(8).toUpperCase()).firstOrNull,
      'dependencies': deps.length,
      'dependency_names': deps.keys.take(20).toList(),
      'environment': _m(spec['environment']).map((k, v) => MapEntry(k, '$v')),
      'install': '${tags.contains('sdk:flutter') && !tags.contains('sdk:dart') ? 'flutter' : 'dart'} pub add ${j['name'] ?? name}',
      'url': 'https://pub.dev/packages/${j['name'] ?? name}',
    };
  }

  Future<List<Map<String, dynamic>>> packageSearch(String registry, String query, {int limit = 10}) async {
    query = query.trim();
    if (query.isEmpty) throw const InfoException('Search for what?');
    switch (registry) {
      case 'npm':
        final j = _m(await _get(Uri.https('registry.npmjs.org', '/-/v1/search', {'text': query, 'size': '$limit'}), source: 'npm'));
        return [
          for (final o in _l(j['objects']))
            () {
              final p = _m(o['package']);
              return {
                'registry': 'npm',
                'name': p['name'],
                'version': p['version'],
                'description': _s(p['description']),
                'published': _s(p['date']),
                'weekly_downloads': ?_n(_m(o['downloads'])['weekly']),
                'url': 'https://www.npmjs.com/package/${p['name']}',
              };
            }(),
        ];
      case 'pub':
        final j = _m(await _get(Uri.https('pub.dev', '/api/search', {'q': query}), source: 'pub.dev'));
        final names = [for (final p in _l(j['packages']).take(limit)) '${p['package']}'];
        final out = await Future.wait(names.map((n) async {
          try {
            final d = await _pub(n);
            return <String, dynamic>{
              for (final k in ['registry', 'name', 'version', 'description', 'published', 'likes', 'pub_points', 'monthly_downloads', 'url']) k: d[k],
            };
          } catch (_) {
            return <String, dynamic>{'registry': 'pub', 'name': n, 'url': 'https://pub.dev/packages/$n'};
          }
        }));
        return out;
      case 'pypi':
        // PyPI has no search API: look the query up as a name, with the
        // usual spellings.
        final tries = {query, query.toLowerCase(), query.toLowerCase().replaceAll(' ', '-'), 'python-${query.toLowerCase()}', 'py${query.toLowerCase()}'};
        final out = <Map<String, dynamic>>[];
        for (final t in tries) {
          try {
            final d = await _pypi(t);
            if (out.any((o) => o['name'] == d['name'])) continue;
            out.add({for (final k in ['registry', 'name', 'version', 'description', 'published', 'weekly_downloads', 'url']) k: d[k]});
          } catch (_) {}
        }
        return out;
      default:
        throw InfoException('Registry is npm, pypi or pub, not "$registry".');
    }
  }

  // ---- domains ----------------------------------------------------------------------

  static String _domain(String input) {
    var d = input.trim().toLowerCase();
    d = d.replaceFirst(RegExp(r'^[a-z]+://'), '').split('/').first.split('?').first.split(':').first;
    if (d.startsWith('www.') && d.split('.').length > 2) d = d.substring(4);
    if (!RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(d)) throw InfoException('"$input" isn\'t a domain name.');
    return d;
  }

  Future<Map<String, dynamic>> domain(String input, {Set<String> checks = const {'whois', 'dns', 'ssl'}}) async {
    final d = _domain(input);
    final out = <String, dynamic>{'domain': d};
    await Future.wait([
      if (checks.contains('whois')) () async {
        try {
          out['whois'] = await _rdap(d);
        } catch (e) {
          out['whois'] = {'error': '$e'};
        }
      }(),
      if (checks.contains('dns')) () async {
        try {
          out['dns'] = await _dns(d);
        } catch (e) {
          out['dns'] = {'error': '$e'};
        }
      }(),
      if (checks.contains('ssl')) () async {
        try {
          out['ssl'] = await _ssl(d);
        } catch (e) {
          out['ssl'] = {'error': '$e'};
        }
      }(),
    ]);
    return out;
  }

  Future<Map<String, dynamic>> _rdap(String d) async {
    // RDAP knows the registered domain, not subdomains: walk up until found.
    final parts = d.split('.');
    Map<String, dynamic> j = {};
    for (var i = 0; i <= parts.length - 2; i++) {
      final name = parts.sublist(i).join('.');
      final r = await _get(Uri.parse('https://rdap.org/domain/$name'), source: 'RDAP', allow404: true, cache: const Duration(hours: 1), headers: {'Accept': 'application/rdap+json, application/json'});
      if (r != null) {
        j = _m(r);
        break;
      }
    }
    if (j.isEmpty) return {'registered': false, 'note': 'No registration record found (it may be unregistered, or its registry has no RDAP).'};
    final events = {for (final e in _l(j['events'])) '${e['eventAction']}': '${e['eventDate']}'};
    String? vcardName(Map<String, dynamic> ent) {
      final v = ent['vcardArray'];
      if (v is List && v.length > 1 && v[1] is List) {
        for (final f in v[1] as List) {
          if (f is List && f.length > 3 && (f[0] == 'fn' || f[0] == 'org') && '${f[3]}'.trim().isNotEmpty) return '${f[3]}';
        }
      }
      return null;
    }

    String? registrar;
    String? registrarUrl;
    String? abuse;
    String? registrant;
    for (final ent in _l(j['entities'])) {
      final roles = [for (final r in (ent['roles'] as List? ?? const [])) '$r'];
      if (roles.contains('registrar')) {
        registrar = vcardName(ent);
        registrarUrl = _l(ent['links']).where((l) => '${l['href']}'.startsWith('http') && !'${l['href']}'.contains('rdap')).map((l) => '${l['href']}').firstOrNull;
        for (final sub in _l(ent['entities'])) {
          if ((sub['roles'] as List? ?? const []).contains('abuse')) {
            final v = sub['vcardArray'];
            if (v is List && v.length > 1) {
              for (final f in v[1] as List) {
                if (f is List && f[0] == 'email') abuse = '${f[3]}';
              }
            }
          }
        }
      }
      if (roles.contains('registrant')) registrant = vcardName(ent);
    }
    final expires = DateTime.tryParse(events['expiration'] ?? '');
    final created = DateTime.tryParse(events['registration'] ?? '');
    return {
      'registered': true,
      'name': _s(j['ldhName'])?.toLowerCase(),
      'registrar': registrar,
      'registrar_url': registrarUrl,
      'registrant': ?registrant,
      'abuse_email': ?abuse,
      'created': events['registration'],
      'updated': events['last changed'],
      'expires': events['expiration'],
      if (expires != null) 'days_until_expiry': expires.difference(DateTime.now()).inDays,
      if (created != null) 'age_years': (DateTime.now().difference(created).inDays / 365.25 * 10).round() / 10,
      'status': [for (final s in (j['status'] as List? ?? const [])) '$s'],
      'nameservers': [for (final n in _l(j['nameservers'])) '${n['ldhName']}'.toLowerCase()],
      'dnssec': _m(j['secureDNS'])['delegationSigned'] == true,
    };
  }

  Future<Map<String, dynamic>> _dns(String d) async {
    const types = ['A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT', 'CAA'];
    final out = <String, dynamic>{};
    await Future.wait(types.map((t) async {
      final j = _m(await _get(Uri.https('dns.google', '/resolve', {'name': d, 'type': t}), source: 'Google DNS', cache: const Duration(minutes: 2)));
      final answers = [
        for (final a in _l(j['Answer']))
          if (a['type'] == _dnsType[t]) {'value': '${a['data']}'.replaceFirst(RegExp(r'\.$'), ''), 'ttl': a['TTL']},
      ];
      if (answers.isNotEmpty) out[t] = answers;
    }));
    final txt = [for (final a in (out['TXT'] as List? ?? const [])) '${(a as Map)['value']}'];
    return {
      'records': {for (final t in types) if (out.containsKey(t)) t: out[t]},
      'has_spf': txt.any((t) => t.contains('v=spf1')),
      'mail': out.containsKey('MX'),
      'ipv6': out.containsKey('AAAA'),
    };
  }

  static const _dnsType = {'A': 1, 'NS': 2, 'CNAME': 5, 'MX': 15, 'TXT': 16, 'AAAA': 28, 'CAA': 257};

  Future<Map<String, dynamic>> _ssl(String d) async {
    var trusted = true;
    final SecureSocket s;
    try {
      s = await SecureSocket.connect(d, 443, timeout: const Duration(seconds: 10), onBadCertificate: (_) {
        trusted = false;
        return true;
      }, supportedProtocols: ['h2', 'http/1.1']);
    } on SocketException catch (e) {
      throw InfoException('No HTTPS on $d (${e.osError?.message ?? e.message}).');
    } on HandshakeException catch (e) {
      throw InfoException('The TLS handshake with $d failed: ${e.message}');
    }
    try {
      final c = s.peerCertificate;
      if (c == null) throw InfoException('$d sent no certificate.');
      String? field(String dn, String key) => RegExp('(?:^|[/,]\\s*)$key=([^/,]+)').firstMatch(dn)?.group(1)?.trim();
      final days = c.endValidity.difference(DateTime.now()).inDays;
      return {
        'valid': trusted && days >= 0,
        'trusted': trusted,
        'subject': field(c.subject, 'CN') ?? c.subject,
        'issuer': field(c.issuer, 'O') ?? field(c.issuer, 'CN') ?? c.issuer,
        'issuer_cn': field(c.issuer, 'CN'),
        'valid_from': c.startValidity.toIso8601String().substring(0, 10),
        'expires': c.endValidity.toIso8601String().substring(0, 10),
        'days_left': days,
        'protocol': s.selectedProtocol,
        'lifetime_days': c.endValidity.difference(c.startValidity).inDays,
      };
    } finally {
      s.destroy();
    }
  }

  // ---- xkcd -------------------------------------------------------------------------

  Future<Map<String, dynamic>> xkcd({int? number, bool random = false}) async {
    final latest = _m(await _get(Uri.parse('https://xkcd.com/info.0.json'), source: 'xkcd', cache: const Duration(minutes: 30)));
    final max = (latest['num'] as num?)?.toInt() ?? 1;
    var n = number;
    if (random) {
      n = 1 + math.Random().nextInt(max);
      if (n == 404) n = 405;
    }
    final j = n == null || n == max ? latest : _m(await _get(Uri.parse('https://xkcd.com/$n/info.0.json'), source: 'xkcd', cache: const Duration(days: 30)));
    final num_ = (j['num'] as num?)?.toInt() ?? n ?? max;
    return {
      'number': num_,
      'title': j['safe_title'] ?? j['title'],
      'alt': j['alt'],
      'image': j['img'],
      'date': '${j['year']}-${'${j['month']}'.padLeft(2, '0')}-${'${j['day']}'.padLeft(2, '0')}',
      'latest': max,
      'url': 'https://xkcd.com/$num_/',
      'explain_url': 'https://www.explainxkcd.com/wiki/index.php/$num_',
      if (_s(j['transcript']) != null) 'transcript': j['transcript'],
    };
  }

  // ---- prices -----------------------------------------------------------------------

  static const _metalNames = {'gold': 'Gold', 'silver': 'Silver', 'platinum': 'Platinum', 'palladium': 'Palladium', 'copper': 'Copper', 'aluminum': 'Aluminium', 'nickel': 'Nickel', 'zinc': 'Zinc', 'lead': 'Lead'};

  Future<Map<String, dynamic>> metals({String currency = 'USD', String unit = 'toz'}) async {
    final key = InfoKeysNotifier.current.metalsKey.trim();
    if (key.isEmpty) throw const InfoException('Metal prices need a free metals.dev key: the user can add it in Settings → More apps → Lookups.');
    final cur = currency.toUpperCase().trim();
    final j = _m(await _get(
      Uri.https('api.metals.dev', '/v1/latest', {'api_key': key, 'currency': cur, 'unit': unit}),
      source: 'metals.dev',
      cache: const Duration(minutes: 10),
    ));
    if (j['status'] == 'failure') throw InfoException('metals.dev: ${j['error_message'] ?? j['error_code'] ?? 'request refused'}.');
    final m = _m(j['metals']);
    final ts = _m(j['timestamps']);
    // Karat prices of gold, per gram whatever the unit asked.
    final gold = _n(m['gold']);
    final perGram = gold == null ? null : gold / (switch (unit) { 'toz' => 31.1035, 'kg' => 1000.0, 'mt' => 1e6, 'oz' => 28.3495, _ => 1.0 });
    return {
      'currency': cur,
      'unit': unit,
      'unit_label': switch (unit) { 'toz' => 'troy ounce', 'g' => 'gram', 'kg' => 'kilogram', 'oz' => 'ounce', 'mt' => 'tonne', _ => unit },
      'metals': [
        for (final e in _metalNames.entries)
          if (_n(m[e.key]) != null) {'metal': e.key, 'name': e.value, 'price': _n(m[e.key])},
      ],
      if (perGram != null)
        'gold_per_gram': {
          '24k': (perGram * 100).round() / 100,
          '22k': (perGram * 22 / 24 * 100).round() / 100,
          '21k': (perGram * 21 / 24 * 100).round() / 100,
          '18k': (perGram * 18 / 24 * 100).round() / 100,
          '14k': (perGram * 14 / 24 * 100).round() / 100,
        },
      'updated': ts['metal'],
      'source': 'metals.dev',
    };
  }

  static const fuelTypes = {'gasoline': 'gasoline_prices', 'diesel': 'diesel_prices', 'lpg': 'lpg_prices', 'kerosene': 'kerosene_prices', 'electricity': 'electricity_prices'};

  static String _countrySlug(String c) {
    final t = c.trim();
    const aliases = {
      'usa': 'USA', 'us': 'USA', 'united states': 'USA', 'america': 'USA', 'uk': 'United-Kingdom', 'britain': 'United-Kingdom', //
      'uae': 'United-Arab-Emirates', 'south korea': 'South-Korea', 'korea': 'South-Korea', 'drc': 'Democratic-Republic-of-the-Congo',
    };
    final a = aliases[t.toLowerCase()];
    if (a != null) return a;
    return t.split(RegExp(r'[\s_-]+')).map((w) => w.isEmpty ? w : (w.toLowerCase() == 'and' || w.toLowerCase() == 'of' || w.toLowerCase() == 'the' ? w.toLowerCase() : w[0].toUpperCase() + w.substring(1).toLowerCase())).join('-');
  }

  /// One country's fuel prices from GlobalPetrolPrices.com (weekly or
  /// monthly), in local currency, USD and EUR.
  Future<Map<String, dynamic>> fuel(String country, {List<String> types = const ['gasoline', 'diesel']}) async {
    if (country.trim().isEmpty) throw const InfoException('Which country?');
    final slug = _countrySlug(country);
    final out = <Map<String, dynamic>>[];
    String? updated;
    for (final t in types) {
      final path = fuelTypes[t];
      if (path == null) continue;
      final url = Uri.parse('https://www.globalpetrolprices.com/$slug/$path/');
      final key = url.toString();
      String body;
      final hit = _cache[key];
      if (hit != null && DateTime.now().difference(hit.$1) < const Duration(hours: 6)) {
        body = hit.$2 as String;
      } else {
        try {
          final r = await _client.get(url, headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) $_ua'}).timeout(const Duration(seconds: 20));
          if (r.statusCode == 404) continue;
          if (r.statusCode >= 400) throw InfoException('GlobalPetrolPrices answered ${r.statusCode}.');
          body = utf8.decode(r.bodyBytes, allowMalformed: true);
          _cache[key] = (DateTime.now(), body);
        } on TimeoutException {
          throw const InfoException('GlobalPetrolPrices took too long to answer.');
        } on SocketException {
          throw const InfoException('Couldn\'t reach GlobalPetrolPrices; check the connection.');
        }
      }
      final doc = html_parser.parse(body);
      final table = doc.querySelectorAll('table').where((t) => t.text.contains('Liter') || t.text.contains('kWh')).firstOrNull;
      if (table == null) continue;
      final prices = <String, num>{};
      for (final row in table.querySelectorAll('tr')) {
        final cells = row.children.where((c) => c.localName == 'td' || c.localName == 'th').map((c) => c.text.replaceAll(' ', ' ').trim()).where((c) => c.isNotEmpty).toList();
        if (cells.length >= 2 && RegExp(r'^[A-Z]{3}$').hasMatch(cells[0])) {
          final v = num.tryParse(cells[1].replaceAll(',', ''));
          if (v != null) prices[cells[0]] = v;
        }
      }
      if (prices.isEmpty) continue;
      final title = doc.querySelector('title')?.text ?? '';
      updated ??= RegExp(r'(\d{2}-[A-Za-z]{3}-\d{4})').firstMatch(title)?.group(1);
      final text = doc.body?.text.replaceAll(RegExp(r'\s+'), ' ') ?? '';
      final avg = RegExp(r'average price of [a-z ]+ in the world for this period is ([\d.,]+) ([A-Za-z .]+?)\.').firstMatch(text);
      final local = prices.keys.firstWhere((k) => k != 'USD' && k != 'EUR', orElse: () => 'USD');
      out.add({
        'fuel': t,
        'unit': t == 'electricity' ? 'kWh' : 'litre',
        'local_currency': local,
        'price_local': prices[local],
        'price_usd': prices['USD'],
        'price_eur': prices['EUR'],
        if (avg != null) 'world_average_local': num.tryParse(avg.group(1)!.replaceAll(',', '')),
        'url': key,
      });
    }
    if (out.isEmpty) throw InfoException('No fuel prices found for "$country". Use the country\'s English name, like "Ethiopia" or "United Kingdom".');
    return {'country': slug.replaceAll('-', ' '), 'updated': updated, 'prices': out, 'source': 'GlobalPetrolPrices.com'};
  }

  // ---- earthquakes and disasters ----------------------------------------------------

  Future<Map<String, dynamic>> earthquakes({
    double? minMagnitude,
    int days = 7,
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? place,
    int limit = 20,
    String order = 'time',
  }) async {
    String? near;
    if (place != null && place.trim().isNotEmpty && latitude == null) {
      final g = await geocode(place);
      latitude = g['latitude'] as double;
      longitude = g['longitude'] as double;
      near = '${g['name']}${g['country'] == null ? '' : ', ${g['country']}'}';
      radiusKm ??= 500;
    }
    final start = DateTime.now().toUtc().subtract(Duration(days: days.clamp(1, 365)));
    final j = _m(await _get(
      Uri.https('earthquake.usgs.gov', '/fdsnws/event/1/query', {
        'format': 'geojson',
        'starttime': start.toIso8601String().substring(0, 19),
        'minmagnitude': '${minMagnitude ?? (latitude == null ? 4.5 : 2.5)}',
        'limit': '${limit.clamp(1, 100)}',
        'orderby': order == 'magnitude' ? 'magnitude' : 'time',
        if (latitude != null && longitude != null) ...{'latitude': '$latitude', 'longitude': '$longitude', 'maxradiuskm': '${(radiusKm ?? 300).clamp(1, 20001)}'},
      }),
      source: 'USGS',
      cache: const Duration(minutes: 2),
    ));
    final quakes = [
      for (final f in _l(j['features']))
        () {
          final p = _m(f['properties']);
          final c = (_m(f['geometry'])['coordinates'] as List?) ?? const [];
          final lat = _n(c.elementAtOrNull(1))?.toDouble(), lon = _n(c.elementAtOrNull(0))?.toDouble();
          return {
            'id': f['id'],
            'magnitude': _n(p['mag']),
            'mag_type': p['magType'],
            'place': p['place'],
            'time': p['time'] is num ? DateTime.fromMillisecondsSinceEpoch((p['time'] as num).toInt()).toIso8601String().substring(0, 16) : null,
            'time_utc': p['time'] is num ? DateTime.fromMillisecondsSinceEpoch((p['time'] as num).toInt(), isUtc: true).toIso8601String().substring(0, 16) : null,
            'depth_km': _n(c.elementAtOrNull(2)),
            'latitude': lat,
            'longitude': lon,
            if (latitude != null && lat != null && lon != null) 'distance_km': _distance(latitude, longitude!, lat, lon).round(),
            'felt_reports': ?_n(p['felt']),
            'alert': ?_s(p['alert']),
            'tsunami': p['tsunami'] == 1,
            'significance': _n(p['sig']),
            'url': p['url'],
          };
        }(),
    ];
    return {
      'count': quakes.length,
      'days': days,
      'min_magnitude': minMagnitude ?? (latitude == null ? 4.5 : 2.5),
      'near': ?near,
      if (latitude != null) 'radius_km': radiusKm ?? 300,
      if (quakes.isNotEmpty) 'strongest': (quakes.toList()..sort((a, b) => ((b['magnitude'] as num?) ?? 0).compareTo((a['magnitude'] as num?) ?? 0))).first,
      'earthquakes': quakes,
      'source': 'USGS',
    };
  }

  static double _distance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lon2 - lon1) / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static const disasterTypes = {'EQ': 'Earthquake', 'TC': 'Tropical cyclone', 'FL': 'Flood', 'VO': 'Volcano', 'DR': 'Drought', 'WF': 'Wildfire', 'TS': 'Tsunami'};

  Future<Map<String, dynamic>> disasters({List<String> types = const [], String minAlert = 'green', String? country, int days = 30, int limit = 25}) async {
    final levels = switch (minAlert.toLowerCase()) {
      'red' => 'Red',
      'orange' => 'Orange;Red',
      _ => 'Green;Orange;Red',
    };
    final codes = [for (final t in types) t.toUpperCase()].where(disasterTypes.containsKey).toList();
    final from = DateTime.now().toUtc().subtract(Duration(days: days.clamp(1, 365)));
    final j = _m(await _get(
      Uri.https('www.gdacs.org', '/gdacsapi/api/events/geteventlist/SEARCH', {
        'eventlist': (codes.isEmpty ? disasterTypes.keys.where((k) => k != 'TS') : codes).join(';'),
        'alertlevel': levels,
        'fromDate': from.toIso8601String().substring(0, 10),
        'toDate': DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String().substring(0, 10),
      }),
      source: 'GDACS',
      cache: const Duration(minutes: 5),
    ));
    var events = [
      for (final f in _l(j['features']))
        () {
          final p = _m(f['properties']);
          final c = (_m(f['geometry'])['coordinates'] as List?) ?? const [];
          final sev = _m(p['severitydata']);
          return <String, dynamic>{
            'id': '${p['eventtype']}${p['eventid']}',
            'type': disasterTypes[p['eventtype']] ?? p['eventtype'],
            'type_code': p['eventtype'],
            'name': _s(p['eventname']) ?? _s(p['name']),
            'title': _s(p['name']),
            'alert': '${p['alertlevel'] ?? ''}'.toLowerCase(),
            'country': _s(p['country']),
            'from': '${p['fromdate'] ?? ''}'.length >= 10 ? '${p['fromdate']}'.substring(0, 10) : null,
            'to': '${p['todate'] ?? ''}'.length >= 10 ? '${p['todate']}'.substring(0, 10) : null,
            'ongoing': '${p['iscurrent']}' == 'true',
            'severity': _s(sev['severitytext']),
            'latitude': _n(c.elementAtOrNull(1)),
            'longitude': _n(c.elementAtOrNull(0)),
            'description': _s(p['htmldescription']) ?? _s(p['description']),
            'icon': _s(p['icon']),
            'url': _s(_m(p['url'])['report']),
          };
        }(),
    ];
    if (country != null && country.trim().isNotEmpty) {
      final c = country.trim().toLowerCase();
      events = events.where((e) => '${e['country'] ?? ''} ${e['title'] ?? ''}'.toLowerCase().contains(c)).toList();
    }
    const rank = {'red': 0, 'orange': 1, 'green': 2};
    events.sort((a, b) {
      final r = (rank[a['alert']] ?? 3).compareTo(rank[b['alert']] ?? 3);
      return r != 0 ? r : '${b['from']}'.compareTo('${a['from']}');
    });
    final counts = <String, int>{};
    for (final e in events) {
      counts['${e['type']}'] = (counts['${e['type']}'] ?? 0) + 1;
    }
    return {
      'count': events.length,
      'days': days,
      'by_type': counts,
      'red': events.where((e) => e['alert'] == 'red').length,
      'orange': events.where((e) => e['alert'] == 'orange').length,
      'events': events.take(limit.clamp(1, 60)).toList(),
      'source': 'GDACS',
    };
  }

  // ---- recipes and food -------------------------------------------------------------

  static const _mealDb = 'www.themealdb.com';

  Map<String, dynamic> _meal(Map<String, dynamic> m, {bool full = true}) {
    final ingredients = <Map<String, String>>[];
    for (var i = 1; i <= 20; i++) {
      final ing = _s(m['strIngredient$i']);
      if (ing == null) continue;
      ingredients.add({'name': ing, 'measure': _s(m['strMeasure$i']) ?? '', 'image': 'https://www.themealdb.com/images/ingredients/${Uri.encodeComponent(ing)}-Small.png'});
    }
    final steps = (_s(m['strInstructions']) ?? '')
        .split(RegExp(r'\r?\n+'))
        .map((s) => s.replaceFirst(RegExp(r'^(step\s*\d+[:.)]?|\d+[.)])\s*', caseSensitive: false), '').trim())
        .where((s) => s.isNotEmpty && !RegExp(r'^step\s*\d*$', caseSensitive: false).hasMatch(s))
        .toList();
    return {
      'id': m['idMeal'],
      'name': m['strMeal'],
      'image': m['strMealThumb'],
      'category': ?_s(m['strCategory']),
      'cuisine': ?_s(m['strArea']),
      if (full) ...{
        'tags': _s(m['strTags'])?.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList() ?? const [],
        'ingredients': ingredients,
        'steps': steps,
        'youtube': ?_s(m['strYoutube']),
        'source': ?_s(m['strSource']),
      },
    };
  }

  Future<Map<String, dynamic>> recipes({String? query, String? ingredient, String? category, String? cuisine, bool random = false, int limit = 12}) async {
    Future<List<Map<String, dynamic>>> list(String path, Map<String, String> q) async =>
        _l(_m(await _get(Uri.https(_mealDb, '/api/json/v1/1/$path', q), source: 'TheMealDB', cache: const Duration(hours: 1)))['meals']);
    List<Map<String, dynamic>> meals;
    var filter = 'search';
    if (random) {
      final picks = await Future.wait(List.generate(limit.clamp(1, 6), (_) => _get(Uri.https(_mealDb, '/api/json/v1/1/random.php'), source: 'TheMealDB', cache: Duration.zero)));
      meals = [for (final p in picks) ..._l(_m(p)['meals'])];
      filter = 'random';
    } else if ((ingredient ?? '').trim().isNotEmpty) {
      meals = await list('filter.php', {'i': ingredient!.trim().replaceAll(' ', '_')});
      filter = 'ingredient';
    } else if ((category ?? '').trim().isNotEmpty) {
      meals = await list('filter.php', {'c': category!.trim()});
      filter = 'category';
    } else if ((cuisine ?? '').trim().isNotEmpty) {
      meals = await list('filter.php', {'a': cuisine!.trim()});
      filter = 'cuisine';
    } else {
      final q = (query ?? '').trim();
      if (q.isEmpty) throw const InfoException('Search by name, ingredient, category or cuisine, or ask for random.');
      meals = await list('search.php', {'s': q});
      if (meals.isEmpty && q.contains(' ')) meals = await list('search.php', {'s': q.split(' ').last});
    }
    final seen = <String>{};
    meals = meals.where((m) => seen.add('${m['idMeal']}')).toList();
    final full = filter == 'search' || filter == 'random';
    return {
      'filter': filter,
      'count': meals.length,
      'recipes': [for (final m in meals.take(limit.clamp(1, 30))) _meal(m, full: false)..addAll(full ? {'ingredient_count': _meal(m)['ingredients'].length} : const {})],
      if (meals.isEmpty) 'note': 'No recipes matched. TheMealDB names ingredients like "chicken_breast" and cuisines like "Italian", "Indian", "Moroccan".',
      'source': 'TheMealDB',
    };
  }

  Future<Map<String, dynamic>> recipe(String idOrName) async {
    final t = idOrName.trim();
    if (t.isEmpty) throw const InfoException('Which recipe?');
    final j = RegExp(r'^\d+$').hasMatch(t)
        ? _m(await _get(Uri.https(_mealDb, '/api/json/v1/1/lookup.php', {'i': t}), source: 'TheMealDB', cache: const Duration(hours: 6)))
        : _m(await _get(Uri.https(_mealDb, '/api/json/v1/1/search.php', {'s': t}), source: 'TheMealDB', cache: const Duration(hours: 1)));
    final m = _l(j['meals']).firstOrNull;
    if (m == null) throw InfoException('No recipe "$t" on TheMealDB.');
    return {..._meal(m), 'source_name': 'TheMealDB'};
  }

  static const _offFields = 'code,product_name,generic_name,brands,quantity,serving_size,image_front_url,image_url,nutriscore_grade,nova_group,ecoscore_grade,'
      'nutriments,nutrient_levels,ingredients_text,allergens_tags,traces_tags,additives_tags,labels_tags,categories_tags,countries_tags';

  Map<String, dynamic> _food(Map<String, dynamic> p) {
    final n = _m(p['nutriments']);
    num? g(String k) {
      final v = _n(n['${k}_100g']);
      return v == null ? null : (v * 10).round() / 10;
    }

    String tag(Object t) => '$t'.split(':').last.replaceAll('-', ' ');
    return {
      'barcode': p['code'],
      'name': _s(p['product_name']) ?? _s(p['generic_name']) ?? 'Unnamed product',
      'brand': (p['brands'] is List ? _s((p['brands'] as List).firstOrNull) : _s(p['brands'])?.split(',').first.trim()),
      'quantity': _s(p['quantity']),
      'serving': _s(p['serving_size']),
      'image': _s(p['image_front_url']) ?? _s(p['image_url']),
      'nutriscore': _s(p['nutriscore_grade']) == null || const {'unknown', 'not-applicable'}.contains(p['nutriscore_grade']) ? null : '${p['nutriscore_grade']}'.toUpperCase(),
      'nova': _n(p['nova_group']),
      'ecoscore': _s(p['ecoscore_grade']) == null || const {'unknown', 'not-applicable'}.contains(p['ecoscore_grade']) ? null : '${p['ecoscore_grade']}'.toUpperCase(),
      'per_100g': {
        'energy_kcal': _n(n['energy-kcal_100g'])?.round(),
        'fat': g('fat'),
        'saturated_fat': g('saturated-fat'),
        'carbohydrates': g('carbohydrates'),
        'sugars': g('sugars'),
        'fiber': g('fiber'),
        'protein': g('proteins'),
        'salt': g('salt'),
      }..removeWhere((k, v) => v == null),
      if (_n(n['energy-kcal_serving']) != null) 'per_serving_kcal': _n(n['energy-kcal_serving'])!.round(),
      'levels': _m(p['nutrient_levels']).map((k, v) => MapEntry(k.replaceAll('-', '_'), '$v')),
      'ingredients': _s(p['ingredients_text']),
      'allergens': [for (final a in (p['allergens_tags'] as List? ?? const [])) tag(a)],
      'traces': [for (final a in (p['traces_tags'] as List? ?? const [])) tag(a)],
      'additives': [for (final a in (p['additives_tags'] as List? ?? const []).take(15)) tag(a).toUpperCase()],
      'labels': [for (final a in (p['labels_tags'] as List? ?? const []).take(8)) tag(a)],
      'vegan': (p['labels_tags'] as List? ?? const []).contains('en:vegan'),
      'vegetarian': (p['labels_tags'] as List? ?? const []).contains('en:vegetarian'),
      'url': 'https://world.openfoodfacts.org/product/${p['code']}',
    };
  }

  Future<Map<String, dynamic>> foodByBarcode(String code) async {
    final c = code.replaceAll(RegExp(r'\D'), '');
    if (c.length < 6) throw InfoException('"$code" isn\'t a product barcode.');
    final j = _m(await _get(Uri.https('world.openfoodfacts.org', '/api/v2/product/$c.json', {'fields': _offFields}), source: 'Open Food Facts', allow404: true, cache: const Duration(hours: 6)));
    if (j['status'] != 1 || j['product'] == null) {
      throw InfoException('Barcode $c isn\'t in Open Food Facts yet. It can be added at world.openfoodfacts.org.');
    }
    return {..._food(_m(j['product'])), 'source': 'Open Food Facts'};
  }

  Future<Map<String, dynamic>> foodSearch(String query, {int limit = 10}) async {
    List<Map<String, dynamic>> found;
    try {
      // Open Food Facts' search service first; the classic search often sheds load.
      final j = _m(await _get(
        Uri.https('search.openfoodfacts.org', '/search', {'q': query.trim(), 'page_size': '${limit.clamp(1, 24)}', 'fields': _offFields}),
        source: 'Open Food Facts',
        cache: const Duration(hours: 1),
      ));
      found = _l(j['hits']);
    } on InfoException {
      final j = _m(await _get(
        Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {'search_terms': query.trim(), 'search_simple': '1', 'action': 'process', 'json': '1', 'page_size': '${limit.clamp(1, 24)}', 'fields': _offFields}),
        source: 'Open Food Facts',
        cache: const Duration(hours: 1),
      ));
      found = _l(j['products']);
    }
    final products = [for (final p in found) _food(p)];
    return {'count': products.length, 'products': products, 'source': 'Open Food Facts'};
  }

  // ---- places, air and the sun ------------------------------------------------------

  Future<Map<String, dynamic>> geocode(String place) async {
    final q = place.trim();
    final g = _m(await _get(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': q.split(',').first.trim(), 'count': '5'}), source: 'Open-Meteo', cache: const Duration(days: 1)));
    final results = _l(g['results']);
    if (results.isEmpty) throw InfoException('No place called "$q".');
    // "Paris, Texas": prefer the result whose country or region matches.
    final hint = q.contains(',') ? q.split(',').skip(1).join(',').trim().toLowerCase() : '';
    final r = hint.isEmpty
        ? results.first
        : results.where((r) => '${r['country']} ${r['admin1']} ${r['country_code']}'.toLowerCase().contains(hint)).firstOrNull ?? results.first;
    return {'name': r['name'], 'region': r['admin1'], 'country': r['country'], 'latitude': _n(r['latitude'])!.toDouble(), 'longitude': _n(r['longitude'])!.toDouble()};
  }

  /// Where the phone is, when the person allowed location.
  Future<Map<String, dynamic>> here() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw const InfoException('Name a place: location access is off.');
      final pos = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)));
      return {'name': 'Your location', 'latitude': pos.latitude, 'longitude': pos.longitude, 'here': true};
    } on InfoException {
      rethrow;
    } catch (_) {
      throw const InfoException('Couldn\'t get this phone\'s location; name a place instead.');
    }
  }

  Future<Map<String, dynamic>> _where({String? place, double? latitude, double? longitude}) async {
    if (latitude != null && longitude != null) return {'name': '${latitude.toStringAsFixed(2)}, ${longitude.toStringAsFixed(2)}', 'latitude': latitude, 'longitude': longitude};
    if ((place ?? '').trim().isNotEmpty) return geocode(place!);
    return here();
  }

  static String _aqiLevel(num? aqi) => aqi == null
      ? 'unknown'
      : aqi <= 50
      ? 'good'
      : aqi <= 100
      ? 'moderate'
      : aqi <= 150
      ? 'unhealthy for sensitive groups'
      : aqi <= 200
      ? 'unhealthy'
      : aqi <= 300
      ? 'very unhealthy'
      : 'hazardous';

  static String _uvLevel(num? uv) => uv == null
      ? 'unknown'
      : uv < 3
      ? 'low'
      : uv < 6
      ? 'moderate'
      : uv < 8
      ? 'high'
      : uv < 11
      ? 'very high'
      : 'extreme';

  static String _pollenLevel(num? v) => v == null
      ? 'none'
      : v < 1
      ? 'none'
      : v < 20
      ? 'low'
      : v < 100
      ? 'moderate'
      : v < 500
      ? 'high'
      : 'very high';

  Future<Map<String, dynamic>> air({String? place, double? latitude, double? longitude}) async {
    final w = await _where(place: place, latitude: latitude, longitude: longitude);
    const pollen = ['alder_pollen', 'birch_pollen', 'grass_pollen', 'mugwort_pollen', 'olive_pollen', 'ragweed_pollen'];
    final results = await Future.wait([
      _get(
        Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
          'latitude': '${w['latitude']}',
          'longitude': '${w['longitude']}',
          'current': 'us_aqi,european_aqi,pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,dust,uv_index,uv_index_clear_sky,${pollen.join(',')}',
          'hourly': 'us_aqi,uv_index,pm2_5',
          'timezone': 'auto',
          'forecast_days': '2',
        }),
        source: 'Open-Meteo',
        cache: const Duration(minutes: 10),
      ),
      _get(
        Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': '${w['latitude']}',
          'longitude': '${w['longitude']}',
          'daily': 'sunrise,sunset,daylight_duration,sunshine_duration,uv_index_max',
          'timezone': 'auto',
          'forecast_days': '3',
        }),
        source: 'Open-Meteo',
        cache: const Duration(minutes: 30),
      ),
    ]);
    final a = _m(results[0]);
    final f = _m(results[1]);
    final cur = _m(a['current']);
    final hourly = _m(a['hourly']);
    final daily = _m(f['daily']);
    List l(Map m, String k) => m[k] as List? ?? const [];
    final now = '${cur['time'] ?? ''}';
    final times = l(hourly, 'time').map((t) => '$t').toList();
    final from = times.indexWhere((t) => t.compareTo(now) >= 0).clamp(0, times.length);
    String hm(Object? t) => '$t'.length >= 16 ? '$t'.substring(11, 16) : '$t';
    String dur(num? s) => s == null ? '—' : '${s ~/ 3600} h ${((s % 3600) / 60).round().toString().padLeft(2, '0')} min';
    final usAqi = _n(cur['us_aqi']);
    final uv = _n(cur['uv_index']);
    final pollenNow = {
      for (final p in pollen)
        if (_n(cur[p]) != null) p.replaceAll('_pollen', ''): {'grains_m3': _n(cur[p]), 'level': _pollenLevel(_n(cur[p]))},
    };
    final days = [
      for (var i = 0; i < l(daily, 'time').length; i++)
        {
          'date': l(daily, 'time')[i],
          'sunrise': hm(l(daily, 'sunrise').elementAtOrNull(i)),
          'sunset': hm(l(daily, 'sunset').elementAtOrNull(i)),
          'daylight': dur(_n(l(daily, 'daylight_duration').elementAtOrNull(i))),
          'daylight_seconds': _n(l(daily, 'daylight_duration').elementAtOrNull(i)),
          'sunshine': dur(_n(l(daily, 'sunshine_duration').elementAtOrNull(i))),
          'uv_max': _n(l(daily, 'uv_index_max').elementAtOrNull(i)),
        },
    ];
    final d0 = days.firstOrNull ?? const {};
    final d1 = days.elementAtOrNull(1);
    return {
      'place': w['name'],
      'region': ?w['region'],
      'country': ?w['country'],
      'latitude': w['latitude'],
      'longitude': w['longitude'],
      'timezone': a['timezone'],
      'time': now,
      'aqi': {
        'us': usAqi,
        'us_level': _aqiLevel(usAqi),
        'european': _n(cur['european_aqi']),
      },
      'pollutants': {
        'pm2_5': _n(cur['pm2_5']),
        'pm10': _n(cur['pm10']),
        'ozone': _n(cur['ozone']),
        'nitrogen_dioxide': _n(cur['nitrogen_dioxide']),
        'sulphur_dioxide': _n(cur['sulphur_dioxide']),
        'carbon_monoxide': _n(cur['carbon_monoxide']),
        'dust': _n(cur['dust']),
      }..removeWhere((k, v) => v == null),
      'pollutant_unit': 'µg/m³',
      'uv': {'now': uv, 'level': _uvLevel(uv), 'clear_sky': _n(cur['uv_index_clear_sky']), 'max_today': d0['uv_max'], 'max_level': _uvLevel(d0['uv_max'] as num?)},
      if (pollenNow.isNotEmpty) 'pollen': pollenNow else 'pollen_note': 'Pollen forecasts cover Europe only.',
      'sun': {
        'sunrise': d0['sunrise'],
        'sunset': d0['sunset'],
        'daylight': d0['daylight'],
        if (d1 != null && d0['daylight_seconds'] is num && d1['daylight_seconds'] is num) 'daylight_change_tomorrow_minutes': (((d1['daylight_seconds'] as num) - (d0['daylight_seconds'] as num)) / 60 * 10).round() / 10,
      },
      'days': days,
      'hourly': [
        for (var i = from; i < from + 24 && i < times.length; i++)
          {'time': hm(times[i]), 'us_aqi': _n(l(hourly, 'us_aqi').elementAtOrNull(i)), 'uv': _n(l(hourly, 'uv_index').elementAtOrNull(i)), 'pm2_5': _n(l(hourly, 'pm2_5').elementAtOrNull(i))},
      ],
      'source': 'Open-Meteo (CAMS)',
    };
  }

  // ---- words ------------------------------------------------------------------------

  Future<Map<String, dynamic>> define(String word, {String language = 'en'}) async {
    final w = word.trim();
    if (w.isEmpty) throw const InfoException('Define which word?');
    final r = await _get(Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/${Uri.encodeComponent(language)}/${Uri.encodeComponent(w)}'), source: 'Free Dictionary', allow404: true, cache: const Duration(days: 1));
    final entries = r is List ? _l(r) : <Map<String, dynamic>>[];
    if (entries.isEmpty) throw InfoException('No dictionary entry for "$w".');
    final phonetics = [for (final e in entries) ..._l(e['phonetics'])];
    final audio = phonetics.map((p) => _s(p['audio'])).whereType<String>().where((a) => a.startsWith('http')).toList()
      ..sort((a, b) => (b.contains('-us') ? 1 : 0).compareTo(a.contains('-us') ? 1 : 0));
    final meanings = <Map<String, dynamic>>[];
    for (final e in entries) {
      for (final m in _l(e['meanings'])) {
        meanings.add({
          'part_of_speech': m['partOfSpeech'],
          'definitions': [
            for (final d in _l(m['definitions']).take(6))
              {
                'definition': d['definition'],
                'example': ?_s(d['example']),
                if ((d['synonyms'] as List?)?.isNotEmpty ?? false) 'synonyms': [for (final s in (d['synonyms'] as List).take(6)) '$s'],
              },
          ],
          'synonyms': [for (final s in (m['synonyms'] as List? ?? const []).take(10)) '$s'],
          'antonyms': [for (final s in (m['antonyms'] as List? ?? const []).take(10)) '$s'],
        });
      }
    }
    return {
      'word': entries.first['word'] ?? w,
      'phonetic': _s(entries.first['phonetic']) ?? phonetics.map((p) => _s(p['text'])).whereType<String>().firstOrNull,
      'audio': audio.firstOrNull,
      'meanings': meanings,
      'origin': ?_s(entries.first['origin']),
      'source_url': (entries.first['sourceUrls'] as List?)?.firstOrNull,
      'source': 'Free Dictionary API (Wiktionary)',
    };
  }

  Future<Map<String, dynamic>> translate(String text, {required String to, String? from}) async {
    final t = text.trim();
    if (t.isEmpty) throw const InfoException('Translate what?');
    final target = to.trim().toLowerCase();
    final src = (from ?? '').trim().toLowerCase();
    final keys = InfoKeysNotifier.current;
    if (keys.libreReady) {
      final base = keys.libreUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      try {
        final r = await _client
            .post(
              Uri.parse('$base/translate'),
              headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
              body: jsonEncode({'q': t, 'source': src.isEmpty ? 'auto' : src, 'target': target, 'format': 'text', 'alternatives': 3, if (keys.libreKey.isNotEmpty) 'api_key': keys.libreKey}),
            )
            .timeout(const Duration(seconds: 25));
        final j = _m(jsonDecode(utf8.decode(r.bodyBytes)));
        if (r.statusCode >= 400 || j['error'] != null) throw InfoException('LibreTranslate: ${j['error'] ?? r.statusCode}');
        final det = _m(j['detectedLanguage']);
        return {
          'text': t,
          'translation': j['translatedText'],
          'from': _s(det['language']) ?? src,
          if (_n(det['confidence']) != null) 'detected_confidence': _n(det['confidence']),
          'to': target,
          'alternatives': [for (final a in (j['alternatives'] as List? ?? const [])) '$a'],
          'engine': 'LibreTranslate',
        };
      } on TimeoutException {
        throw const InfoException('LibreTranslate took too long to answer.');
      } on SocketException {
        throw const InfoException('Couldn\'t reach the LibreTranslate server; check its address in Settings.');
      }
    }
    if (t.length > 500) throw const InfoException('MyMemory translates up to 500 characters at a time; split the text or turn on LibreTranslate.');
    final j = _m(await _get(
      Uri.https('api.mymemory.translated.net', '/get', {'q': t, 'langpair': '${src.isEmpty ? 'Autodetect' : src}|$target'}),
      source: 'MyMemory',
      cache: const Duration(hours: 1),
    ));
    final status = _n(j['responseStatus']);
    if (status != null && status != 200) throw InfoException('MyMemory: ${j['responseDetails'] ?? status}');
    final data = _m(j['responseData']);
    final matches = _l(j['matches']);
    final detected = _s(data['detectedLanguage']) ?? matches.map((m) => _s(m['source'])).whereType<String>().firstOrNull;
    final translation = '${data['translatedText'] ?? ''}';
    if (translation.toUpperCase().contains('MYMEMORY WARNING')) throw const InfoException('MyMemory\'s free daily limit is used up; try tomorrow or turn on LibreTranslate.');
    return {
      'text': t,
      'translation': translation,
      'from': (detected ?? src).split('-').first.toLowerCase(),
      'to': target,
      if (_n(data['match']) != null) 'match': ((_n(data['match'])! * 100).round()),
      'alternatives': {
        for (final m in matches)
          if (_s(m['translation']) != null && m['translation'] != translation) '${m['translation']}',
      }.take(3).toList(),
      'engine': 'MyMemory',
    };
  }

  // ---- Wikipedia --------------------------------------------------------------------

  static String _lang(String? l) {
    final s = (l ?? 'en').trim().toLowerCase();
    return RegExp(r'^[a-z]{2,3}(-[a-z]+)?$').hasMatch(s) ? s : 'en';
  }

  Future<Map<String, dynamic>> wikiSearch(String query, {String? language, int limit = 8}) async {
    final lang = _lang(language);
    final j = _m(await _get(
      Uri.https('$lang.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': query.trim(),
        'gsrlimit': '${limit.clamp(1, 20)}',
        'prop': 'pageimages|description|extracts|info',
        'exintro': '1',
        'explaintext': '1',
        'exsentences': '2',
        'exlimit': 'max',
        'piprop': 'thumbnail',
        'pithumbsize': '240',
        'inprop': 'url',
        'format': 'json',
        'formatversion': '2',
      }),
      source: 'Wikipedia',
    ));
    final pages = _l(_m(j['query'])['pages'])..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
    return {
      'language': lang,
      'count': pages.length,
      'results': [
        for (final p in pages)
          {
            'title': p['title'],
            'description': ?_s(p['description']),
            'extract': ?_s(p['extract']),
            'thumbnail': ?_s(_m(p['thumbnail'])['source']),
            'url': p['fullurl'] ?? 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent('${p['title']}'.replaceAll(' ', '_'))}',
          },
      ],
      'source': 'Wikipedia',
    };
  }

  Future<Map<String, dynamic>> wikiSummary(String title, {String? language}) async {
    final lang = _lang(language);
    final t = title.trim().replaceAll(' ', '_');
    if (t.isEmpty) throw const InfoException('Which article?');
    var r = await _get(Uri.parse('https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(t)}?redirect=true'), source: 'Wikipedia', allow404: true, cache: const Duration(hours: 1));
    if (r == null) {
      // Not an exact title: take the best search hit.
      final s = await wikiSearch(title, language: lang, limit: 1);
      final hit = (s['results'] as List).firstOrNull as Map?;
      if (hit == null) throw InfoException('No Wikipedia article for "$title".');
      r = await _get(Uri.parse('https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent('${hit['title']}'.replaceAll(' ', '_'))}'), source: 'Wikipedia', cache: const Duration(hours: 1));
    }
    final j = _m(r);
    final coords = _m(j['coordinates']);
    return {
      'title': j['title'],
      'description': ?_s(j['description']),
      'extract': j['extract'],
      'type': j['type'],
      'thumbnail': ?_s(_m(j['thumbnail'])['source']),
      'image': ?_s(_m(j['originalimage'])['source']),
      if (coords.isNotEmpty) 'latitude': coords['lat'],
      if (coords.isNotEmpty) 'longitude': coords['lon'],
      'updated': ?_s(j['timestamp']),
      'language': lang,
      'url': _m(_m(j['content_urls'])['mobile'])['page'] ?? _m(_m(j['content_urls'])['desktop'])['page'],
      'source': 'Wikipedia',
    };
  }

  Future<Map<String, dynamic>> onThisDay({DateTime? date, String type = 'selected', String? language, int limit = 12}) async {
    final lang = _lang(language);
    final d = date ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0'), dd = d.day.toString().padLeft(2, '0');
    final kind = const {'selected', 'events', 'births', 'deaths', 'holidays', 'all'}.contains(type) ? type : 'selected';
    final j = _m(await _get(
      Uri.parse('https://api.wikimedia.org/feed/v1/wikipedia/$lang/onthisday/$kind/$mm/$dd'),
      source: 'Wikipedia',
      cache: const Duration(hours: 6),
    ));
    List<Map<String, dynamic>> items(Object? v) => [
      for (final e in _l(v).take(limit.clamp(1, 40)))
        () {
          final page = _l(e['pages']).firstOrNull ?? const <String, dynamic>{};
          return {
            'year': ?e['year'],
            'text': e['text'],
            if (page.isNotEmpty) 'article': _s(_m(page['titles'])['normalized']) ?? page['title'],
            'thumbnail': ?_s(_m(page['thumbnail'])['source']),
            if (page.isNotEmpty) 'url': _m(_m(page['content_urls'])['mobile'])['page'] ?? _m(_m(page['content_urls'])['desktop'])['page'],
          };
        }(),
    ];
    final out = <String, dynamic>{
      'date': '$mm-$dd',
      'label': '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][d.month - 1]} ${d.day}',
      'language': lang,
      'type': kind,
      'source': 'Wikipedia',
    };
    for (final k in ['selected', 'events', 'births', 'deaths', 'holidays']) {
      if (j[k] is List) out[k] = items(j[k]);
    }
    return out;
  }
}
