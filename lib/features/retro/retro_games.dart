import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Free, legal retro games: homebrew and community releases from the same
/// stores Nostalgia browses. Homebrew Hub (Game Boy, GBC, GBA, NES), SMS
/// Power (Master System, Game Gear), the idgames archive (Doom maps and
/// megawads) and hand-picked homebrew. PDRoms turns automated readers
/// away, so it is only linked.
class RetroGames {
  RetroGames({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const hub = 'https://hh3.gbdev.io';
  static const smsPower = 'https://www.smspower.org';
  static const idgamesMirrors = ['https://youfailit.net/pub/idgames', 'https://ftpmirror1.infania.net/pub/idgames'];
  static const _ua = {'user-agent': 'Triangle (retro game search)'};

  static const stores = {
    'homebrew_hub': 'Homebrew Hub: Game Boy, Game Boy Color, GBA and NES homebrew',
    'smspower': 'SMS Power: Master System and Game Gear homebrew',
    'idgames': 'idgames: the Doom community archive of maps and megawads',
    'picks': 'Staff picks: hand-picked homebrew from each author\'s own release',
    'pdroms': 'PDRoms: homebrew for many consoles (opened in the browser)',
  };

  static const systems = {
    'gb': 'Game Boy',
    'gbc': 'Game Boy Color',
    'gba': 'Game Boy Advance',
    'nes': 'NES',
    'snes': 'SNES',
    'genesis': 'Genesis / Mega Drive',
    'sms': 'Master System',
    'gg': 'Game Gear',
    'doom': 'Doom engine',
    'a2600': 'Atari 2600',
    'a7800': 'Atari 7800',
    'n64': 'Nintendo 64',
    'nds': 'Nintendo DS',
    'vb': 'Virtual Boy',
  };

  /// The emulators that play each system, to say how to play a download.
  static const playWith = {
    'gb': 'any Game Boy emulator (mGBA, Nostalgia, RetroArch)',
    'gbc': 'any Game Boy Color emulator (mGBA, Nostalgia, RetroArch)',
    'gba': 'a GBA emulator (mGBA, Pizza Boy, Nostalgia)',
    'nes': 'a NES emulator (Nostalgia, RetroArch FCEUmm)',
    'sms': 'a Master System emulator (Nostalgia, RetroArch Genesis Plus GX)',
    'gg': 'a Game Gear emulator (Nostalgia, RetroArch Genesis Plus GX)',
    'doom': 'a Doom source port (Delta Touch, GZDoom, Nostalgia) with Freedoom or Doom as the base game',
  };

  Future<String?> _text(String url, {Duration timeout = const Duration(seconds: 25)}) async {
    try {
      final r = await _http.get(Uri.parse(url), headers: _ua).timeout(timeout);
      if (r.statusCode >= 400) return null;
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static String _plain(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', '\'')
      .replaceAll('&#8217;', '’')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'&#\d+;'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();

  // ---- search ---------------------------------------------------------------------

  /// Games matching [query] (all of a store's newest or best when empty),
  /// from [store] or every store, on [system] when given.
  Future<Map<String, dynamic>> search({String query = '', String store = 'all', String? system, int limit = 20}) async {
    final q = query.trim().toLowerCase();
    final want = store == 'all' ? const ['homebrew_hub', 'smspower', 'idgames', 'picks'] : [store];
    final out = <Map<String, dynamic>>[];
    final failed = <String>[];
    await Future.wait([
      for (final s in want)
        () async {
          try {
            final items = switch (s) {
              'homebrew_hub' => await _hubSearch(q, system),
              'smspower' => await _smsSearch(q, system),
              'idgames' => (system == null || system == 'doom') ? await _idgamesSearch(q) : <Map<String, dynamic>>[],
              'picks' => _picks.where((p) => (q.isEmpty || '${p['title']} ${p['author']} ${p['about']}'.toLowerCase().contains(q)) && (system == null || p['system'] == system)).toList(),
              _ => <Map<String, dynamic>>[],
            };
            out.addAll(items);
          } catch (_) {
            failed.add(s);
          }
        }(),
    ]);
    // Exact and starting matches first, then the rest as found.
    int rank(Map<String, dynamic> g) {
      final t = '${g['title']}'.toLowerCase();
      if (q.isEmpty) return 1;
      if (t == q) return 0;
      if (t.startsWith(q)) return 1;
      if (t.contains(q)) return 2;
      return 3;
    }

    // Within each rank, take the stores in turn so one big store can't
    // crowd out the others.
    final byRank = <int, Map<String, List<Map<String, dynamic>>>>{};
    for (final g in out) {
      byRank.putIfAbsent(rank(g), () => {}).putIfAbsent('${g['store']}', () => []).add(g);
    }
    final mixed = <Map<String, dynamic>>[];
    for (final r in byRank.keys.toList()..sort()) {
      final lists = byRank[r]!.values.toList();
      for (var i = 0; lists.any((l) => i < l.length); i++) {
        for (final l in lists) {
          if (i < l.length) mixed.add(l[i]);
        }
      }
    }
    out
      ..clear()
      ..addAll(mixed);
    return {
      'query': query,
      'store': store,
      'system': ?system,
      'total': out.length,
      'games': out.take(limit).toList(),
      if (failed.isNotEmpty) 'unreachable': failed,
      'pdroms': 'https://pdroms.de/?s=${Uri.encodeComponent(query)}',
    };
  }

  static String _hubSystem(String platform, List files) => switch (platform) {
    'GBA' => 'gba',
    'GBC' => 'gbc',
    'NES' => 'nes',
    _ => files.any((f) => '${(f as Map)['filename']}'.toLowerCase().endsWith('.gbc')) ? 'gbc' : 'gb',
  };

  static String _hubDeveloper(Object? d) {
    if (d is List) return d.map((x) => x is Map ? '${x['name'] ?? ''}' : '$x').where((s) => s.isNotEmpty).join(', ');
    return '${d ?? ''}';
  }

  Map<String, dynamic> _hubItem(Map e) {
    final slug = '${e['slug']}';
    final base = '${e['basepath'] ?? 'database-gb'}';
    final shots = [for (final s in (e['screenshots'] as List? ?? const [])) '$hub/static/$base/entries/$slug/$s'];
    final files = (e['files'] as List? ?? const []);
    final system = _hubSystem('${e['platform'] ?? 'GB'}', files);
    final tags = [for (final t in (e['tags'] as List? ?? const [])) '$t'];
    return {
      'store': 'homebrew_hub',
      'store_name': 'Homebrew Hub',
      'id': slug,
      'title': '${e['title'] ?? slug}',
      'author': _hubDeveloper(e['developer']),
      'system': system,
      'system_name': systems[system],
      'image': ?shots.firstOrNull,
      if (tags.isNotEmpty) 'tags': tags.take(4).toList(),
      if (e['license'] != null) 'license': e['license'] is List ? (e['license'] as List).join(', ') : '${e['license']}',
      if (e['date'] != null) 'date': '${e['date']}',
      'page': '$hub/entry/$slug',
    };
  }

  Future<List<Map<String, dynamic>>> _hubSearch(String q, String? system) async {
    final platform = switch (system) {
      'gba' => 'GBA',
      'gbc' => 'GBC',
      'nes' => 'NES',
      'gb' => 'GB',
      null => '',
      _ => '-',
    };
    if (platform == '-') return const [];
    final params = {
      'results': '24',
      'typetag': 'game',
      if (q.isNotEmpty) 'q': q,
      if (platform.isNotEmpty) 'platform': platform,
      'sort': 'firstadded_date',
      'order': 'desc',
    };
    final text = await _text(Uri.parse('$hub/api/search').replace(queryParameters: params).toString());
    if (text == null) throw const HttpException('Homebrew Hub is unreachable');
    final j = jsonDecode(text) as Map;
    return [for (final e in (j['entries'] as List? ?? const [])) _hubItem(e as Map)];
  }

  List<Map<String, dynamic>>? _sms;

  Future<List<Map<String, dynamic>>> _smsAll() async {
    if (_sms != null) return _sms!;
    final html = await _text('$smsPower/Homebrew/Index?q=order=name', timeout: const Duration(seconds: 35));
    if (html == null) throw const HttpException('SMS Power is unreachable');
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    final slugRe = RegExp(r"href='//www\.smspower\.org/Homebrew/([A-Za-z0-9_]+)-(SMS|GG)'");
    final imgRe = RegExp(r"<img[^>]*src='([^']+)'");
    final titleRe = RegExp(r"<span[^>]*>\s*<a[^>]*>(.*?)</a>\s*</span>", dotAll: true);
    for (final cell in html.split("<td valign='top'").skip(1)) {
      final m = slugRe.firstMatch(cell);
      final t = titleRe.firstMatch(cell);
      if (m == null || t == null) continue;
      final slug = '${m.group(1)}-${m.group(2)}';
      if (!seen.add(slug) || slug.toLowerCase().contains('port')) continue;
      final rest = cell.substring(t.end).split('<br />').map(_plain).where((x) => x.isNotEmpty).toList();
      final line = rest.isNotEmpty ? rest.first : '';
      final by = line.indexOf(' by ');
      final img = imgRe.firstMatch(cell)?.group(1);
      final system = m.group(2) == 'GG' ? 'gg' : 'sms';
      out.add({
        'store': 'smspower',
        'store_name': 'SMS Power',
        'id': slug,
        'title': _plain(t.group(1)!),
        'author': by < 0 ? '' : line.substring(by + 4).trim(),
        'system': system,
        'system_name': systems[system],
        'image': ?(img == null ? null : (img.startsWith('//') ? 'https:$img' : img)),
        'kind': by < 0 ? line : line.substring(0, by).trim(),
        if (rest.length > 1) 'date': rest[1],
        'page': '$smsPower/Homebrew/$slug',
      });
    }
    return _sms = out;
  }

  Future<List<Map<String, dynamic>>> _smsSearch(String q, String? system) async {
    if (system != null && system != 'sms' && system != 'gg') return const [];
    var list = await _smsAll();
    list = list.where((e) => '${e['kind']}'.toLowerCase().contains('game')).toList();
    if (system != null) list = list.where((e) => e['system'] == system).toList();
    if (q.isNotEmpty) list = list.where((e) => '${e['title']} ${e['author']}'.toLowerCase().contains(q)).toList();
    return list.take(24).toList();
  }

  // ---- idgames ---------------------------------------------------------------------

  static const _classics = [
    ('levels/doom2/Ports/megawads', 'eviternity', 'Eviternity', 'Six chapters of gorgeous modern maps; widely called one of the best megawads ever.'),
    ('levels/doom2/megawads', 'scythe', 'Scythe', 'Fast, compact, endlessly replayable. 32 maps that ramp from breezy to brutal.'),
    ('levels/doom2/Ports/megawads', 'scythe2', 'Scythe 2', 'The sequel: bigger maps, wilder ideas, same flow.'),
    ('levels/doom2/megawads', 'av', 'Alien Vendetta', 'A 2001 classic: huge, detailed maps that redefined what Doom levels could be.'),
    ('levels/doom2/megawads', 'requiem', 'Requiem', 'A community megawad from 1997 with a wide range of styles.'),
    ('levels/doom2/Ports/megawads', 'valiant', 'Valiant', 'Tough and stylish, with new monsters and weapon tweaks.'),
    ('levels/doom2/Ports/megawads', 'sunlust', 'Sunlust', 'Famously hard, puzzle-like slaughter maps for experts.'),
    ('levels/doom2/megawads', 'btsx_e1', 'Back to Saturn X · Ep 1', 'A sci-fi journey with its own textures and soundtrack.'),
    ('levels/doom2/Ports/megawads', 'aaliens', 'Ancient Aliens', 'Bright, alien worlds, a cult favourite.'),
    ('levels/doom2/megawads', 'pl2', 'Plutonia 2', 'A sequel to Final Doom: Plutonia, as nasty as the original.'),
    ('levels/doom2/Ports/megawads', 'gd', 'Going Down', '32 short, punchy maps set in an office tower, by Cyriak.'),
    ('levels/doom/megawads', 'dtwid', 'Doom the Way id Did', 'A new episode set in the original game\'s exact style.'),
  ];

  static List<(String, String, int, String)>? _index;

  /// Every Doom and Doom II map pack: (folder, name, bytes, date), from the
  /// archive's directory listing (about 400 KB, kept for the session).
  Future<List<(String, String, int, String)>> _idIndex() async {
    if (_index != null) return _index!;
    for (final m in idgamesMirrors) {
      try {
        final r = await _http.get(Uri.parse('$m/ls-laR.gz'), headers: _ua).timeout(const Duration(seconds: 40));
        if (r.statusCode >= 400) continue;
        final b = r.bodyBytes;
        final text = latin1.decode(b.length > 2 && b[0] == 0x1f && b[1] == 0x8b ? gzip.decode(b) : b);
        if (!text.contains('levels/doom2')) continue;
        final out = <(String, String, int, String)>[];
        var dir = '';
        final line = RegExp(r'^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\w{3}\s+\d+\s+[\d:]+)\s+(\S+)\.zip$');
        for (final l in const LineSplitter().convert(text)) {
          if (l.endsWith(':')) {
            dir = l.substring(0, l.length - 1).replaceFirst('./', '');
            continue;
          }
          if (!dir.startsWith('levels/doom') || dir.contains('deathmatch')) continue;
          final x = line.firstMatch(l);
          if (x != null) out.add((dir, x.group(3)!, int.parse(x.group(1)!), x.group(2)!));
        }
        return _index = out;
      } catch (_) {}
    }
    throw const HttpException('idgames is unreachable');
  }

  static String _size(int b) => b >= 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).round()} KB';

  Map<String, dynamic> _idItem((String, String, int, String) e, {String? title, String? about}) {
    final doom2 = e.$1.startsWith('levels/doom2');
    return {
      'store': 'idgames',
      'store_name': 'idgames',
      'id': '${e.$1}/${e.$2}',
      'title': title ?? e.$2,
      'system': 'doom',
      'system_name': doom2 ? 'Doom II' : 'Doom',
      'size': _size(e.$3),
      'date': e.$4,
      'kind': [
        if (e.$1.contains('megawads')) 'Megawad' else 'Map pack',
        if (e.$1.contains('/Ports')) 'needs a modern engine',
      ].join(' · '),
      'about': ?about,
      'page': '${idgamesMirrors.first}/${e.$1}/${e.$2}.txt',
    };
  }

  Future<List<Map<String, dynamic>>> _idgamesSearch(String q) async {
    final index = await _idIndex();
    if (q.isEmpty) {
      return [
        for (final c in _classics)
          for (final e in index.where((e) => e.$1 == c.$1 && e.$2 == c.$2).take(1)) _idItem(e, title: c.$3, about: c.$4),
      ];
    }
    final named = [for (final c in _classics) if (c.$3.toLowerCase().contains(q)) c];
    return [
      for (final c in named)
        for (final e in index.where((e) => e.$1 == c.$1 && e.$2 == c.$2).take(1)) _idItem(e, title: c.$3, about: c.$4),
      for (final e in index.where((e) => e.$2.toLowerCase().contains(q) && !named.any((c) => c.$2 == e.$2)).take(20)) _idItem(e),
    ];
  }

  // ---- staff picks -----------------------------------------------------------------

  static const _picks = <Map<String, dynamic>>[
    {
      'store': 'picks', 'store_name': 'Staff picks', 'id': 'ucity', 'title': 'µCity', 'author': 'Antonio Niño Díaz', 'system': 'gbc', 'system_name': 'Game Boy Color',
      'url': 'https://github.com/AntonioND/ucity/releases/download/v1.3/ucity.gbc', 'size': '128 KB', 'license': 'GPL-3.0',
      'about': 'A full city-building sim: zone land, build power and roads, handle disasters and grow a metropolis. Open source.', 'page': 'https://github.com/AntonioND/ucity',
    },
    {
      'store': 'picks', 'store_name': 'Staff picks', 'id': 'ucity-advance', 'title': 'µCity Advance', 'author': 'Antonio Niño Díaz', 'system': 'gba', 'system_name': 'Game Boy Advance',
      'url': 'https://github.com/AntonioND/ucity-advance/releases/download/v1.0.3/ucity-advance-v1.0.3.gba', 'size': '1.9 MB', 'license': 'GPL-3.0 / MIT',
      'about': 'The city builder rebuilt for the GBA, with bigger maps, more detail and smoother controls.', 'page': 'https://github.com/AntonioND/ucity-advance',
    },
    {
      'store': 'picks', 'store_name': 'Staff picks', 'id': 'celeste-classic', 'title': 'Celeste Classic', 'author': 'JeffRuLz (port) · Maddy Thorson & Noel Berry', 'system': 'gba', 'system_name': 'Game Boy Advance',
      'url': 'https://github.com/JeffRuLz/Celeste-Classic-GBA/releases/download/v1.2/Celeste.Classic.v1.2.Homebrew.gba', 'size': '5.2 MB', 'license': 'Free homebrew',
      'about': 'The original PICO-8 Celeste: a tight, tough mountain-climbing platformer, ported to the Game Boy Advance.', 'page': 'https://github.com/JeffRuLz/Celeste-Classic-GBA',
      'image': 'https://hh3.gbdev.io/static/database-gba/entries/celeste-classic-gba/screen1.png',
    },
    {
      'store': 'picks', 'store_name': 'Staff picks', 'id': 'libbet', 'title': 'Libbet and the Magic Floor', 'author': 'Damian Yerrick (PinoBatch)', 'system': 'gb', 'system_name': 'Game Boy',
      'url': 'https://github.com/pinobatch/libbet/releases/download/v0.08/libbet.gb', 'size': '32 KB', 'license': 'zlib',
      'about': 'A puzzle game about rolling across a basement floor, painting every tile exactly once. Fits in 32 KB.', 'page': 'https://github.com/pinobatch/libbet',
    },
    {
      'store': 'picks', 'store_name': 'Staff picks', 'id': 'gb240p', 'title': '240p Test Suite', 'author': 'Damian Yerrick · Artemio Urbina', 'system': 'gb', 'system_name': 'Game Boy',
      'url': 'https://github.com/pinobatch/240p-test-mini/releases/download/v0.23/gb240p.gb', 'size': '32 KB', 'license': 'GPL-2.0',
      'about': 'Display and controller test patterns used by retro collectors. Handy for trying out palettes and LCD filters.', 'page': 'https://github.com/pinobatch/240p-test-mini',
    },
  ];

  // ---- details ---------------------------------------------------------------------

  /// Everything about one game, and where its download is.
  Future<Map<String, dynamic>> details(String store, String id) async {
    switch (store) {
      case 'homebrew_hub':
        final text = await _text('$hub/api/entry/$id.json');
        if (text == null) throw const HttpException('Homebrew Hub has no such entry, or is unreachable');
        final e = jsonDecode(text) as Map;
        e['slug'] ??= id;
        final item = _hubItem(e);
        final base = '${e['basepath'] ?? 'database-gb'}';
        final files = [for (final f in (e['files'] as List? ?? const [])) if (f is Map) f];
        Map? pick;
        for (final f in files) {
          if (f['playable'] == false) continue;
          if (pick == null || f['default'] == true) pick = f;
        }
        final links = <String>{
          for (final k in const ['website', 'repository'])
            if (e[k] is List) ...[for (final x in e[k] as List) '$x'] else if (e[k] != null) '${e[k]}',
        }.where((l) => l.startsWith('http')).toList();
        final description = '${e['description'] is List ? (e['description'] as List).join('\n') : e['description'] ?? ''}';
        return {
          ...item,
          'description': _plain(description),
          'screenshots': [for (final s in (e['screenshots'] as List? ?? const [])) '$hub/static/$base/entries/$id/$s'],
          if (pick != null) 'download': '$hub/static/$base/entries/$id/${pick['filename']}',
          if (pick != null) 'file': pick['filename'],
          'links': links,
          'facts': {
            'System': item['system_name'],
            'Developer': item['author'],
            if (item['license'] != null) 'License': item['license'],
            if (e['typetag'] != null) 'Type': '${e['typetag']}',
            if (e['date'] != null) 'Released': '${e['date']}',
            if (item['tags'] != null) 'Tags': (item['tags'] as List).join(', '),
          },
          if (pick == null) 'note': links.any((l) => l.contains('github.com')) ? 'No file on Homebrew Hub; the download is in the project\'s GitHub releases.' : 'Homebrew Hub has no download for this entry.',
        };
      case 'smspower':
        final list = await _smsAll();
        final item = list.where((e) => e['id'] == id).firstOrNull ?? {'store': 'smspower', 'store_name': 'SMS Power', 'id': id, 'title': id, 'page': '$smsPower/Homebrew/$id'};
        final html = await _text('$smsPower/Homebrew/$id') ?? '';
        final shots = <String>{
          for (final m in RegExp('uploads/Homebrew/${RegExp.escape(id)}-[^\'" >]+\\.(?:png|gif|jpg)').allMatches(html)) '$smsPower/${m.group(0)}',
        }.toList();
        final paras = [
          for (final m in RegExp(r'<p>(.*?)</p>', dotAll: true).allMatches(html))
            // The site's own menus come out as paragraphs too; skip them.
            if (_plain(m.group(1)!).length > 50 &&
                !m.group(1)!.contains('forumuserlink') &&
                !RegExp(r'Home - Forums|Mark III / Game Gear|SG-1000 / SC-3000').hasMatch(_plain(m.group(1)!)))
              _plain(m.group(1)!),
        ];
        final zips = {for (final m in RegExp('uploads/Homebrew/${RegExp.escape(id)}[^\'" >]*\\.zip').allMatches(html)) m.group(0)!}.toList()..sort();
        return {
          ...item,
          'description': paras.take(4).join('\n\n'),
          'screenshots': shots,
          if (zips.isNotEmpty) 'download': '$smsPower/${zips.last}',
          if (zips.isNotEmpty) 'file': zips.last.split('/').last,
          'facts': {
            'System': item['system_name'] ?? '',
            if ('${item['kind'] ?? ''}'.isNotEmpty) 'Type': item['kind'],
            if ('${item['author'] ?? ''}'.isNotEmpty) 'Author': item['author'],
            if (item['date'] != null) 'Updated': item['date'],
          },
        };
      case 'idgames':
        final index = await _idIndex();
        final at = id.lastIndexOf('/');
        final dir = id.substring(0, at), name = id.substring(at + 1);
        final e = index.where((e) => e.$1 == dir && e.$2 == name).firstOrNull;
        final classic = _classics.where((c) => c.$1 == dir && c.$2 == name).firstOrNull;
        final item = e == null ? {'store': 'idgames', 'store_name': 'idgames', 'id': id, 'title': name, 'system': 'doom', 'system_name': 'Doom'} : _idItem(e, title: classic?.$3, about: classic?.$4);
        Map<String, String> readme = const {};
        for (final m in idgamesMirrors) {
          final t = await _text('$m/$dir/$name.txt');
          if (t != null) {
            readme = _readme(t);
            break;
          }
        }
        final engine = readme['Advanced engine needed'] ?? readme['Source port'] ?? '';
        return {
          ...item,
          if (readme['Title'] != null) 'title': classic?.$3 ?? readme['Title'],
          if (readme['Author'] != null) 'author': readme['Author'],
          'description': readme['Description'] ?? classic?.$4 ?? '',
          'screenshots': const <String>[],
          'download': '${idgamesMirrors.first}/$dir/$name.zip',
          'file': '$name.zip',
          'facts': {
            'Game': dir.startsWith('levels/doom2') ? 'Doom II (plays on Freedoom 2)' : 'Doom (plays on Freedoom)',
            if (readme['Author'] != null) 'Author': readme['Author']!,
            if (readme['Release date'] != null) 'Released': readme['Release date']!,
            if (engine.isNotEmpty) 'Engine': engine,
            if (readme['Maps'] != null) 'Maps': readme['Maps']!,
            if (readme['Difficulty Settings'] != null) 'Difficulty': readme['Difficulty Settings']!,
            'Size': '${item['size'] ?? ''}',
          },
        };
      case 'picks':
        final p = _picks.where((p) => p['id'] == id).firstOrNull;
        if (p == null) throw ArgumentError('No staff pick "$id".');
        return {
          ...p,
          'description': p['about'],
          'screenshots': [?p['image']],
          'download': p['url'],
          'file': '${p['url']}'.split('/').last,
          'facts': {'System': p['system_name'], 'Author': p['author'], 'License': p['license'], 'Size': p['size'], 'Source': p['page']},
        };
    }
    throw ArgumentError('Unknown store "$store".');
  }

  /// An idgames readme ("Title : …", "Description : …").
  static Map<String, String> _readme(String text) {
    final out = <String, String>{};
    String? key;
    for (final raw in const LineSplitter().convert(text)) {
      final m = RegExp(r'^([A-Za-z][A-Za-z .\-/()]*?)\s*:\s?(.*)$').firstMatch(raw);
      if (m != null && raw.indexOf(':') < 32) {
        key = m.group(1)!.trim();
        out[key] = m.group(2)!.trim();
      } else if (key != null && raw.trim().isNotEmpty && raw.startsWith(' ')) {
        out[key] = '${out[key]} ${raw.trim()}'.trim();
      } else if (raw.trim().isEmpty) {
        key = null;
      }
    }
    return out;
  }
}
