import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../info/info_keys.dart';

// Sports for the assistant: scores, matches, tables, teams and news from
// ESPN's public site API (no key), Formula 1 from Jolpica (the Ergast
// successor, no key), players from TheSportsDB (free key), and top scorers
// from football-data.org (free key the user adds).

class SportsException implements Exception {
  const SportsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A league the ESPN tools know: its id for the assistant, ESPN's sport
/// and league path, and a name.
class League {
  const League(this.id, this.sport, this.slug, this.name, {this.short});
  final String id;
  final String sport;
  final String slug;
  final String name;
  final String? short;
  bool get soccer => sport == 'soccer';
  String get kind => switch (sport) {
    'soccer' => 'soccer',
    'basketball' => 'basketball',
    'football' => 'american_football',
    'baseball' => 'baseball',
    'hockey' => 'hockey',
    _ => sport,
  };
}

const leagues = <League>[
  League('epl', 'soccer', 'eng.1', 'Premier League'),
  League('laliga', 'soccer', 'esp.1', 'LaLiga'),
  League('seriea', 'soccer', 'ita.1', 'Serie A'),
  League('bundesliga', 'soccer', 'ger.1', 'Bundesliga'),
  League('ligue1', 'soccer', 'fra.1', 'Ligue 1'),
  League('ucl', 'soccer', 'uefa.champions', 'Champions League', short: 'UCL'),
  League('uel', 'soccer', 'uefa.europa', 'Europa League', short: 'UEL'),
  League('uecl', 'soccer', 'uefa.europa.conf', 'Conference League', short: 'UECL'),
  League('championship', 'soccer', 'eng.2', 'EFL Championship'),
  League('fa_cup', 'soccer', 'eng.fa', 'FA Cup'),
  League('eredivisie', 'soccer', 'ned.1', 'Eredivisie'),
  League('primeira', 'soccer', 'por.1', 'Primeira Liga'),
  League('saudi', 'soccer', 'ksa.1', 'Saudi Pro League'),
  League('mls', 'soccer', 'usa.1', 'MLS'),
  League('world_cup', 'soccer', 'fifa.world', 'FIFA World Cup'),
  League('afcon', 'soccer', 'caf.nations', 'Africa Cup of Nations', short: 'AFCON'),
  League('nba', 'basketball', 'nba', 'NBA'),
  League('wnba', 'basketball', 'wnba', 'WNBA'),
  League('ncaab', 'basketball', 'mens-college-basketball', 'NCAA Basketball'),
  League('nfl', 'football', 'nfl', 'NFL'),
  League('ncaaf', 'football', 'college-football', 'College Football'),
  League('mlb', 'baseball', 'mlb', 'MLB'),
  League('nhl', 'hockey', 'nhl', 'NHL'),
];

final leagueIds = [for (final l in leagues) l.id];

League leagueOf(String id) {
  final k = id.trim().toLowerCase();
  return leagues.where((l) => l.id == k || l.slug == k || l.name.toLowerCase() == k || l.short?.toLowerCase() == k).firstOrNull ??
      (throw SportsException('Unknown league "$id". Use one of: ${leagueIds.join(', ')}.'));
}

/// football-data.org competition codes for top scorers.
const scorerCompetitions = {
  'epl': ('PL', 'Premier League'),
  'laliga': ('PD', 'LaLiga'),
  'seriea': ('SA', 'Serie A'),
  'bundesliga': ('BL1', 'Bundesliga'),
  'ligue1': ('FL1', 'Ligue 1'),
  'ucl': ('CL', 'Champions League'),
  'championship': ('ELC', 'Championship'),
  'eredivisie': ('DED', 'Eredivisie'),
  'primeira': ('PPL', 'Primeira Liga'),
  'brasileirao': ('BSA', 'Brasileirão'),
  'world_cup': ('WC', 'FIFA World Cup'),
  'euro': ('EC', 'European Championship'),
};

const _ua = 'Triangle/1.0 (assistant app)';

class SportsApi {
  SportsApi._();
  static final instance = SportsApi._();

  final _client = http.Client();
  final _cache = <String, (DateTime, Object?)>{};

  Future<Object?> _get(Uri url, {String source = 'ESPN', Duration cache = const Duration(seconds: 45), Map<String, String> headers = const {}}) async {
    final key = url.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < cache) return hit.$2;
    final http.Response r;
    try {
      r = await _client.get(url, headers: {'User-Agent': _ua, 'Accept': 'application/json', ...headers}).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw SportsException('$source took too long to answer; try again.');
    } on SocketException {
      throw SportsException('Couldn\'t reach $source; check the connection.');
    }
    if (r.statusCode == 404) throw SportsException('$source has nothing for that.');
    if (r.statusCode == 429) throw SportsException('$source is rate-limiting requests; wait a minute.');
    if (r.statusCode == 403 || r.statusCode == 401) throw SportsException('$source refused the request (check the key in Settings → More apps → Sports).');
    if (r.statusCode >= 400) throw SportsException('$source answered ${r.statusCode}.');
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    } on FormatException {
      throw SportsException('$source sent something unexpected.');
    }
    _cache[key] = (DateTime.now(), j);
    if (_cache.length > 200) _cache.remove(_cache.keys.first);
    return j;
  }

  static Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
  static num? _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
  static String? _s(Object? v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static String? _hex(Object? v) {
    final s = _s(v)?.replaceAll('#', '');
    return s != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s) ? s : null;
  }

  Uri _espn(League l, String path, [Map<String, String>? q]) => Uri.https('site.api.espn.com', '/apis/site/v2/sports/${l.sport}/${l.slug}/$path', q);

  static String? _logo(Map<String, dynamic> team) =>
      _s(team['logo']) ?? _l(team['logos']).map((x) => _s(x['href'])).whereType<String>().firstOrNull;

  Map<String, dynamic> _team(Map<String, dynamic> t) => {
    'id': t['id'],
    'name': _s(t['displayName']) ?? _s(t['name']),
    'short': _s(t['shortDisplayName']) ?? _s(t['abbreviation']),
    'abbr': _s(t['abbreviation']),
    'logo': _logo(t),
    'color': _hex(t['color']),
    'alt_color': _hex(t['alternateColor']),
  };

  Map<String, dynamic> _status(Map<String, dynamic> st) {
    final type = _m(st['type']);
    return {
      'state': type['state'], // pre, in, post
      'completed': type['completed'] == true,
      'detail': _s(type['shortDetail']) ?? _s(type['detail']) ?? _s(type['description']),
      'description': _s(type['description']),
      'clock': _s(st['displayClock']),
      'period': st['period'],
    };
  }

  Map<String, dynamic> _side(Map<String, dynamic> c) => {
    ..._team(_m(c['team'])),
    'home': c['homeAway'] == 'home',
    'score': _s(c['score'] is Map ? _m(c['score'])['displayValue'] : c['score']),
    'winner': c['winner'] == true,
    'form': ?_s(c['form']),
    'record': _l(c['records']).map((r) => _s(r['summary'])).whereType<String>().firstOrNull,
    if (_l(c['linescores']).isNotEmpty) 'periods': [for (final x in _l(c['linescores'])) _s(x['displayValue']) ?? '${x['value'] ?? ''}'],
  };

  // ---- scoreboard ---------------------------------------------------------------------

  Map<String, dynamic> _event(Map<String, dynamic> e, League l) {
    final c = _l(e['competitions']).firstOrNull ?? const <String, dynamic>{};
    final sides = [for (final x in _l(c['competitors'])) _side(x)];
    final home = sides.where((s) => s['home'] == true).firstOrNull ?? sides.firstOrNull;
    final away = sides.where((s) => s['home'] != true).firstOrNull ?? sides.elementAtOrNull(1);
    final teamNames = {for (final x in _l(c['competitors'])) '${_m(x['team'])['id']}': _s(_m(x['team'])['shortDisplayName']) ?? ''};
    final moments = [
      for (final d in _l(c['details']))
        if (d['scoringPlay'] == true || d['redCard'] == true)
          {
            'minute': _s(_m(d['clock'])['displayValue']),
            'type': d['redCard'] == true ? 'red_card' : (d['ownGoal'] == true ? 'own_goal' : (d['penaltyKick'] == true ? 'penalty' : 'goal')),
            'player': _l(d['athletesInvolved']).map((a) => _s(a['shortName']) ?? _s(a['displayName'])).whereType<String>().firstOrNull,
            'team': teamNames['${_m(d['team'])['id']}'],
            'home': '${_m(d['team'])['id']}' == '${home?['id']}',
          },
    ];
    final leaders = <Map<String, dynamic>>[];
    for (final x in _l(c['competitors'])) {
      for (final cat in _l(x['leaders']).take(1)) {
        final top = _l(cat['leaders']).firstOrNull;
        if (top == null) continue;
        final a = _m(top['athlete']);
        leaders.add({'team': _s(_m(x['team'])['abbreviation']), 'stat': _s(cat['shortDisplayName']) ?? _s(cat['displayName']), 'value': _s(top['displayValue']), 'player': _s(a['shortName']) ?? _s(a['displayName']), 'headshot': _s(a['headshot'])});
      }
    }
    final venue = _m(c['venue']).isNotEmpty ? _m(c['venue']) : _m(e['venue']);
    return {
      'id': '${e['id']}',
      'league': l.id,
      'league_name': l.name,
      'name': _s(e['shortName']) ?? _s(e['name']),
      'date': _s(e['date']),
      'status': _status(_m(e['status'])),
      'home': home,
      'away': away,
      if (moments.isNotEmpty) 'moments': moments,
      if (leaders.isNotEmpty) 'leaders': leaders,
      'venue': ?_s(venue['fullName']),
      'city': ?_s(_m(venue['address'])['city']),
      'broadcast': _l(c['broadcasts']).expand((b) => (b['names'] as List? ?? const [])).map((x) => '$x').take(3).join(', ').trim().isEmpty
          ? null
          : _l(c['broadcasts']).expand((b) => (b['names'] as List? ?? const [])).map((x) => '$x').take(3).join(', '),
      'note': _l(c['notes']).map((n) => _s(n['headline'])).whereType<String>().firstOrNull,
    };
  }

  Future<Map<String, dynamic>> scores(String league, {String? date, String? team}) async {
    final l = leagueOf(league);
    final d = (date ?? '').replaceAll('-', '').trim();
    final j = _m(await _get(_espn(l, 'scoreboard', {if (RegExp(r'^\d{8}$').hasMatch(d)) 'dates': d, 'limit': '100'})));
    var events = [for (final e in _l(j['events'])) _event(e, l)];
    final t = (team ?? '').trim().toLowerCase();
    if (t.isNotEmpty) {
      events = events.where((e) => [e['home'], e['away']].any((s) => s is Map && '${s['name']} ${s['abbr']} ${s['short']}'.toLowerCase().contains(t))).toList();
    }
    final lg = _l(j['leagues']).firstOrNull ?? const <String, dynamic>{};
    return {
      'league': l.id,
      'league_name': l.name,
      'sport': l.kind,
      'logo': _l(lg['logos']).map((x) => _s(x['href'])).whereType<String>().firstOrNull,
      'season': _s(_m(lg['season'])['displayName']),
      'date': _s(_m(j['day'])['date']) ?? (d.length == 8 ? '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6)}' : null),
      'count': events.length,
      'live': events.where((e) => _m(e['status'])['state'] == 'in').length,
      'events': events,
      if (events.isEmpty) 'note': 'No games${t.isEmpty ? '' : ' for "$team"'} on that day. Try another date.',
      'source': 'ESPN',
    };
  }

  // ---- one match ----------------------------------------------------------------------

  Future<Map<String, dynamic>> match(String league, String eventId) async {
    final l = leagueOf(league);
    final j = _m(await _get(_espn(l, 'summary', {'event': eventId.trim()})));
    final header = _m(j['header']);
    final comp = _l(header['competitions']).firstOrNull ?? const <String, dynamic>{};
    final sides = [for (final x in _l(comp['competitors'])) _side(x)];
    final home = sides.where((s) => s['home'] == true).firstOrNull ?? sides.firstOrNull;
    final away = sides.where((s) => s['home'] != true).firstOrNull ?? sides.elementAtOrNull(1);
    if (home == null) throw SportsException('No match $eventId in ${l.name}.');

    // Team stats side by side.
    final box = _l(_m(j['boxscore'])['teams']);
    Map<String, String> statsOf(Map<String, dynamic>? side) {
      final t = box.where((b) => '${_m(b['team'])['id']}' == '${side?['id']}').firstOrNull;
      return {for (final s in _l(t?['statistics'])) if (_s(s['label']) != null && _s(s['displayValue']) != null) '${s['label']}': '${s['displayValue']}'};
    }

    final hs = statsOf(home), as = statsOf(away);
    const keep = [
      'Possession', 'SHOTS', 'ON GOAL', 'Corner Kicks', 'Fouls', 'Yellow Cards', 'Red Cards', 'Offsides', 'Saves', 'Passes', 'Accurate Passes', //
      'FG', 'Field Goal %', '3PT', 'Three Point %', 'FT', 'Rebounds', 'Assists', 'Steals', 'Blocks', 'Turnovers', 'Fast Break Points', 'Points in Paint',
      'Total Yards', 'Passing', 'Rushing', '1st Downs', 'Turnovers', 'Possession', 'Penalties', 'Third Down Efficiency',
      'Hits', 'Errors', 'Shots', 'Power Play Goals', 'Faceoffs Won', 'Hits',
    ];
    final labels = <String>{for (final k in keep) if (hs.containsKey(k) && as.containsKey(k)) k};
    for (final k in hs.keys) {
      if (labels.length >= 14) break;
      if (as.containsKey(k) && !k.contains('%') && !k.startsWith('Penalty')) labels.add(k);
    }
    final stats = [
      for (final k in labels.take(14))
        {'label': _statLabel(k), 'home': hs[k], 'away': as[k]},
    ];

    // Goals, cards, substitutions (soccer) in order.
    final events = [
      for (final e in _l(j['keyEvents']))
        if (_s(_m(e['type'])['type']) != null && !const {'kickoff', 'halftime', 'end-regular-time', 'start-2nd-half', 'end-extra-time'}.contains(_m(e['type'])['type']))
          {
            'minute': _s(_m(e['clock'])['displayValue']),
            'type': _m(e['type'])['type'],
            'label': _s(_m(e['type'])['text']),
            'text': _s(e['shortText']) ?? _s(e['text']),
            'player': _l(e['participants']).map((p) => _s(_m(p['athlete'])['displayName'])).whereType<String>().firstOrNull,
            'assist': _l(e['participants']).skip(1).map((p) => _s(_m(p['athlete'])['displayName'])).whereType<String>().firstOrNull,
            'home': '${_m(e['team'])['id']}' == '${home['id']}',
            'scoring': e['scoringPlay'] == true,
          },
    ];

    // Lineups.
    final lineups = [
      for (final r in _l(j['rosters']))
        {
          'team': _s(_m(r['team'])['displayName']),
          'home': r['homeAway'] == 'home',
          'formation': _s(r['formation']),
          'starters': [
            for (final p in _l(r['roster']).where((p) => p['starter'] == true))
              {'name': _s(_m(p['athlete'])['displayName']), 'number': _s(p['jersey']), 'position': _s(_m(p['position'])['abbreviation']), 'subbed_out': p['subbedOut'] == true, 'place': p['formationPlace']},
          ],
          'bench': [
            for (final p in _l(r['roster']).where((p) => p['starter'] != true))
              {'name': _s(_m(p['athlete'])['displayName']), 'number': _s(p['jersey']), 'position': _s(_m(p['position'])['abbreviation']), 'subbed_in': p['subbedIn'] == true},
          ],
        },
    ];

    // Top players (basketball, football…): the leaders by category.
    final leaders = [
      for (final t in _l(j['leaders']))
        {
          'team': _s(_m(t['team'])['abbreviation']),
          'home': '${_m(t['team'])['id']}' == '${home['id']}',
          'categories': [
            for (final c in _l(t['leaders']).take(4))
              if (_l(c['leaders']).isNotEmpty)
                {
                  'stat': _s(c['displayName']),
                  'player': _s(_m(_l(c['leaders']).first['athlete'])['displayName']),
                  'headshot': _s(_m(_m(_l(c['leaders']).first['athlete'])['headshot'])['href']),
                  'value': _s(_l(c['leaders']).first['displayValue']),
                },
          ],
        },
    ];

    final info = _m(j['gameInfo']);
    final venue = _m(info['venue']);
    final article = _m(j['article']);
    return {
      'id': eventId,
      'league': l.id,
      'league_name': l.name,
      'sport': l.kind,
      'date': _s(comp['date']),
      'status': _status(_m(comp['status'])),
      'home': home,
      'away': away,
      'stats': stats,
      if (events.isNotEmpty) 'events': events,
      if (lineups.any((x) => (x['starters'] as List).isNotEmpty)) 'lineups': lineups,
      if (leaders.any((x) => (x['categories'] as List).isNotEmpty)) 'leaders': leaders,
      'venue': ?_s(venue['fullName']),
      'city': ?_s(_m(venue['address'])['city']),
      if (_n(info['attendance']) != null && _n(info['attendance'])! > 0) 'attendance': _n(info['attendance']),
      'headline': ?_s(article['headline']),
      'recap': ?_s(article['description']),
      'url': _l(header['links']).map((x) => _s(x['href'])).whereType<String>().firstOrNull,
      'source': 'ESPN',
    };
  }

  static String _statLabel(String k) => switch (k) {
    'SHOTS' => 'Shots',
    'ON GOAL' => 'Shots on target',
    'Corner Kicks' => 'Corners',
    _ => k,
  };

  // ---- standings ----------------------------------------------------------------------

  Future<Map<String, dynamic>> standings(String league) async {
    final l = leagueOf(league);
    final j = _m(await _get(Uri.https('site.api.espn.com', '/apis/v2/sports/${l.sport}/${l.slug}/standings'), cache: const Duration(minutes: 10)));
    List<Map<String, dynamic>> groupsOf(Map<String, dynamic> node) {
      final out = <Map<String, dynamic>>[];
      final st = _m(node['standings']);
      if (_l(st['entries']).isNotEmpty) out.add({'name': _s(node['name']) ?? l.name, 'entries': _l(st['entries'])});
      for (final c in _l(node['children'])) {
        out.addAll(groupsOf(c));
      }
      return out;
    }

    final groups = groupsOf(j);
    if (groups.isEmpty) throw SportsException('${l.name} has no table right now (it may be a knockout stage).');
    final zones = <String, String>{};
    final out = [
      for (final g in groups)
        () {
          final rows = [
            for (final e in g['entries'] as List<Map<String, dynamic>>)
              () {
                final s = {for (final x in _l(e['stats'])) '${x['name']}': x};
                String? v(String k) => _s(_m(s[k])['displayValue']);
                num? n(String k) => _n(_m(s[k])['value']);
                final note = _m(e['note']);
                if (_s(note['description']) != null && _hex(note['color']) != null) zones[_hex(note['color'])!] = _s(note['description'])!;
                return <String, dynamic>{
                  ..._team(_m(e['team'])),
                  'rank': n('rank') ?? n('playoffSeed'),
                  'played': n('gamesPlayed'),
                  'won': n('wins'),
                  if (l.soccer || l.sport == 'hockey') 'drawn': n('ties') ?? n('otLosses'),
                  'lost': n('losses'),
                  if (l.soccer) 'gd': v('pointDifferential'),
                  if (l.soccer) 'for': n('pointsFor'),
                  if (l.soccer) 'against': n('pointsAgainst'),
                  if (l.soccer || l.sport == 'hockey') 'points': n('points'),
                  if (!l.soccer) 'pct': v('winPercent'),
                  if (!l.soccer) 'games_behind': v('gamesBehind'),
                  if (!l.soccer) 'streak': v('streak'),
                  if (!l.soccer) 'last_ten': v('Last Ten Games') ?? v('L10'),
                  'zone': _s(note['description']),
                  'zone_color': _hex(note['color']),
                };
              }(),
          ];
          rows.sort((a, b) {
            final ra = a['rank'] as num?, rb = b['rank'] as num?;
            if (ra != null && rb != null && ra != rb) return ra.compareTo(rb);
            if (!l.soccer) return (num.tryParse('${b['pct'] ?? 0}') ?? 0).compareTo(num.tryParse('${a['pct'] ?? 0}') ?? 0);
            return ((b['points'] as num?) ?? 0).compareTo((a['points'] as num?) ?? 0);
          });
          for (var i = 0; i < rows.length; i++) {
            rows[i]['position'] = i + 1;
          }
          return {'name': g['name'], 'rows': rows};
        }(),
    ];
    return {
      'league': l.id,
      'league_name': l.name,
      'sport': l.kind,
      'season': _s(_m(_l(j['children']).firstOrNull?['standings'])['seasonDisplayName']) ?? _s(_l(j['children']).firstOrNull?['name']),
      'groups': out,
      'zones': [for (final e in zones.entries) {'color': e.key, 'label': e.value}],
      'source': 'ESPN',
    };
  }

  // ---- teams --------------------------------------------------------------------------

  Future<Map<String, dynamic>> team(String league, String name) async {
    final l = leagueOf(league);
    final want = name.trim().toLowerCase();
    if (want.isEmpty) throw const SportsException('Which team?');
    final list = _m(await _get(_espn(l, 'teams', {'limit': '400'}), cache: const Duration(hours: 12)));
    final teams = [
      for (final lg in _l(_m(_l(list['sports']).firstOrNull)['leagues']))
        for (final t in _l(lg['teams'])) _m(t['team']),
    ];
    Map<String, dynamic>? pick;
    for (final test in <bool Function(Map<String, dynamic>)>[
      (t) => '${t['displayName']}'.toLowerCase() == want || '${t['abbreviation']}'.toLowerCase() == want || '${t['shortDisplayName']}'.toLowerCase() == want,
      (t) => '${t['displayName']} ${t['shortDisplayName']} ${t['nickname'] ?? ''} ${t['location'] ?? ''}'.toLowerCase().contains(want),
      (t) => want.split(' ').every((w) => '${t['displayName']} ${t['nickname'] ?? ''}'.toLowerCase().contains(w)),
    ]) {
      pick = teams.where(test).firstOrNull;
      if (pick != null) break;
    }
    if (pick == null) throw SportsException('No team "$name" in ${l.name}.');
    final id = '${pick['id']}';
    final results = await Future.wait([
      _get(_espn(l, 'teams/$id'), cache: const Duration(minutes: 10)),
      _get(_espn(l, 'teams/$id/schedule'), cache: const Duration(minutes: 10)).catchError((_) => null),
    ]);
    final t = _m(_m(results[0])['team']);
    final sched = _m(results[1]);
    final record = _l(_m(t['record'])['items']).firstOrNull;
    final recStats = {for (final s in _l(record?['stats'])) '${s['name']}': _n(s['value'])};

    Map<String, dynamic> game(Map<String, dynamic> e) {
      final c = _l(e['competitions']).firstOrNull ?? const <String, dynamic>{};
      final sides = _l(c['competitors']);
      bool mine(Map<String, dynamic> x) => '${x['id']}' == id || '${_m(x['team'])['id']}' == id;
      final me = sides.where(mine).firstOrNull ?? const <String, dynamic>{};
      final them = sides.where((x) => !mine(x)).firstOrNull ?? const <String, dynamic>{};
      String? score(Map<String, dynamic> x) => _s(x['score'] is Map ? _m(x['score'])['displayValue'] : x['score']);
      final st = _status(_m(c['status']).isNotEmpty ? _m(c['status']) : _m(e['status']));
      final a = score(me), b = score(them);
      String? result;
      if (st['completed'] == true && a != null && b != null) {
        final x = num.tryParse(a) ?? 0, y = num.tryParse(b) ?? 0;
        result = x > y ? 'W' : (x < y ? 'L' : 'D');
        if (me['winner'] == true) result = 'W';
      }
      return {
        'id': '${e['id']}',
        'date': _s(e['date']),
        'home': me['homeAway'] == 'home',
        'opponent': _s(_m(them['team'])['displayName']) ?? _s(_m(them['team'])['shortDisplayName']),
        'opponent_logo': _logo(_m(them['team'])),
        'score': a == null || b == null ? null : '$a–$b',
        'result': result,
        'status': st['detail'],
        'competition': _s(_m(e['seasonType'])['abbreviation']) ?? _s(_m(e['league'])['abbreviation']),
      };
    }

    // Oldest first, whatever order ESPN sends.
    final past = [for (final e in _l(sched['events'])) game(e)].where((g) => g['result'] != null).toList()
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final next = _l(t['nextEvent']).map(game).toList();
    return {
      'league': l.id,
      'league_name': l.name,
      'sport': l.kind,
      ..._team(t),
      'nickname': ?_s(t['nickname']),
      'location': ?_s(t['location']),
      'standing': ?_s(t['standingSummary']),
      'record': _s(record?['summary']),
      'record_stats': {
        for (final k in ['wins', 'losses', 'ties', 'points', 'pointsFor', 'pointsAgainst', 'gamesPlayed', 'winPercent', 'streak', 'homeWins', 'awayWins'])
          if (recStats[k] != null) k: recStats[k],
      },
      'form': [for (final g in past.reversed.take(5).toList().reversed) g['result']].join(),
      'recent': past.reversed.take(10).toList(),
      'next': next.take(3).toList(),
      'url': _l(t['links']).map((x) => _s(x['href'])).whereType<String>().firstOrNull,
      'source': 'ESPN',
    };
  }

  // ---- news ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> news(String league, {int limit = 10}) async {
    final l = leagueOf(league);
    final j = _m(await _get(_espn(l, 'news', {'limit': '${limit.clamp(1, 25)}'}), cache: const Duration(minutes: 10)));
    return {
      'league': l.id,
      'league_name': l.name,
      'articles': [
        for (final a in _l(j['articles']))
          {
            'headline': _s(a['headline']),
            'description': _s(a['description']),
            'published': _s(a['published']),
            'image': _l(a['images']).map((i) => _s(i['url'])).whereType<String>().firstOrNull,
            'byline': _s(a['byline']),
            'type': _s(a['type']),
            'url': _s(_m(_m(a['links'])['web'])['href']) ?? _s(_m(_m(_m(a['links'])['mobile']))['href']),
          },
      ],
      'source': 'ESPN',
    };
  }

  // ---- players (TheSportsDB) ----------------------------------------------------------

  String get _dbKey {
    final k = InfoKeysNotifier.current.sportsDbKey.trim();
    return k.isEmpty ? '123' : k;
  }

  Future<Map<String, dynamic>> player(String name) async {
    final q = name.trim();
    if (q.isEmpty) throw const SportsException('Which player?');
    final s = _m(await _get(Uri.parse('https://www.thesportsdb.com/api/v1/json/$_dbKey/searchplayers.php?p=${Uri.encodeQueryComponent(q)}'), source: 'TheSportsDB', cache: const Duration(hours: 6)));
    final hits = _l(s['player']);
    if (hits.isEmpty) throw SportsException('No player "$q" on TheSportsDB.');
    // Prefer active players and the best match.
    hits.sort((a, b) => (_n(b['relevance']) ?? 0).compareTo(_n(a['relevance']) ?? 0));
    final first = hits.first;
    Map<String, dynamic> p = first;
    try {
      final full = _l(_m(await _get(Uri.parse('https://www.thesportsdb.com/api/v1/json/$_dbKey/lookupplayer.php?id=${first['idPlayer']}'), source: 'TheSportsDB', cache: const Duration(hours: 6)))['players']).firstOrNull;
      if (full != null) p = {...first, ...full};
    } catch (_) {}
    final born = DateTime.tryParse('${p['dateBorn'] ?? ''}');
    var age = born == null ? null : DateTime.now().year - born.year;
    if (born != null && age != null && (DateTime.now().month < born.month || (DateTime.now().month == born.month && DateTime.now().day < born.day))) age--;
    String? social(Object? v) {
      final s = _s(v);
      if (s == null) return null;
      return s.startsWith('http') ? s : 'https://$s';
    }

    return {
      'id': p['idPlayer'],
      'name': _s(p['strPlayer']),
      'team': _s(p['strTeam']),
      'national_team': _s(p['strTeam2']),
      'sport': _s(p['strSport']),
      'position': _s(p['strPosition']),
      'number': _s(p['strNumber']),
      'nationality': _s(p['strNationality']),
      'born': _s(p['dateBorn']),
      'age': age,
      'birthplace': _s(p['strBirthLocation']),
      'height': _s(p['strHeight']),
      'weight': _s(p['strWeight']),
      'status': _s(p['strStatus']),
      'signed': _s(p['dateSigned']),
      'side': _s(p['strSide']),
      'photo': _s(p['strCutout']) ?? _s(p['strRender']) ?? _s(p['strThumb']),
      'thumb': _s(p['strThumb']),
      'banner': _s(p['strFanart1']) ?? _s(p['strBanner']),
      'description': _s(p['strDescriptionEN']),
      'instagram': social(p['strInstagram']),
      'twitter': social(p['strTwitter']),
      'others': [
        for (final h in hits.skip(1).take(4)) {'name': _s(h['strPlayer']), 'team': _s(h['strTeam']), 'sport': _s(h['strSport']), 'thumb': _s(h['strThumb'])},
      ],
      'source': 'TheSportsDB',
    };
  }

  // ---- top scorers (football-data.org) ------------------------------------------------

  Future<Map<String, dynamic>> topScorers(String competition, {int limit = 15}) async {
    final key = InfoKeysNotifier.current.footballDataKey.trim();
    if (key.isEmpty) throw const SportsException('Top scorers need a free football-data.org key: the user can add it in Settings → More apps → Sports.');
    final c = scorerCompetitions[competition.trim().toLowerCase()] ??
        scorerCompetitions.values.where((v) => v.$1.toLowerCase() == competition.trim().toLowerCase()).firstOrNull ??
        (throw SportsException('Top scorers cover: ${scorerCompetitions.keys.join(', ')}.'));
    final j = _m(await _get(
      Uri.https('api.football-data.org', '/v4/competitions/${c.$1}/scorers', {'limit': '${limit.clamp(1, 30)}'}),
      source: 'football-data.org',
      cache: const Duration(minutes: 30),
      headers: {'X-Auth-Token': key},
    ));
    final comp = _m(j['competition']);
    return {
      'competition': c.$2,
      'code': c.$1,
      'emblem': _s(comp['emblem']),
      'season': '${_s(_m(j['season'])['startDate'])?.substring(0, 4) ?? ''}/${_s(_m(j['season'])['endDate'])?.substring(2, 4) ?? ''}',
      'matchday': _m(j['season'])['currentMatchday'],
      'scorers': [
        for (final (i, s) in _l(j['scorers']).indexed)
          {
            'rank': i + 1,
            'name': _s(_m(s['player'])['name']),
            'nationality': _s(_m(s['player'])['nationality']),
            'position': _s(_m(s['player'])['section']) ?? _s(_m(s['player'])['position']),
            'team': _s(_m(s['team'])['shortName']) ?? _s(_m(s['team'])['name']),
            'crest': _s(_m(s['team'])['crest']),
            'goals': _n(s['goals']),
            'assists': _n(s['assists']),
            'penalties': _n(s['penalties']),
            'played': _n(s['playedMatches']),
          },
      ],
      'source': 'football-data.org',
    };
  }

  // ---- Formula 1 (Jolpica) ------------------------------------------------------------

  Future<Map<String, dynamic>> _f1(String path) async => _m(_m(await _get(Uri.parse('https://api.jolpi.ca/ergast/f1/$path.json'), source: 'Jolpica F1', cache: const Duration(minutes: 10)))['MRData']);

  static Map<String, dynamic> _driver(Map<String, dynamic> d) => {
    'id': d['driverId'],
    'name': '${d['givenName'] ?? ''} ${d['familyName'] ?? ''}'.trim(),
    'code': _s(d['code']),
    'number': _s(d['permanentNumber']),
    'nationality': _s(d['nationality']),
    'url': _s(d['url']),
  };

  static Map<String, dynamic> _race(Map<String, dynamic> r) {
    String? at(Object? s) {
      final m = _m(s);
      final d = _s(m['date']);
      if (d == null) return null;
      return '${d}T${_s(m['time']) ?? '00:00:00Z'}';
    }

    final c = _m(r['Circuit']);
    final loc = _m(c['Location']);
    return {
      'round': _n(r['round']),
      'season': _s(r['season']),
      'name': _s(r['raceName']),
      'circuit': _s(c['circuitName']),
      'locality': _s(loc['locality']),
      'country': _s(loc['country']),
      'latitude': _n(loc['lat']),
      'longitude': _n(loc['long']),
      'start': at(r),
      'sessions': {
        'Practice 1': ?at(r['FirstPractice']),
        'Practice 2': ?at(r['SecondPractice']),
        'Practice 3': ?at(r['ThirdPractice']),
        'Sprint qualifying': ?at(r['SprintQualifying'] ?? r['SprintShootout']),
        'Sprint': ?at(r['Sprint']),
        'Qualifying': ?at(r['Qualifying']),
        'Race': ?at(r),
      },
      'sprint_weekend': r['Sprint'] != null,
      'url': _s(r['url']),
    };
  }

  Future<Map<String, dynamic>> f1(String view, {String season = 'current'}) async {
    final s = season.trim().isEmpty ? 'current' : season.trim();
    switch (view) {
      case 'standings':
        final j = _f1('$s/driverStandings');
        final list = _m((_l(_m((await j)['StandingsTable'])['StandingsLists'])).firstOrNull);
        return {
          'view': 'standings',
          'season': _s(list['season']),
          'round': _n(list['round']),
          'drivers': [
            for (final d in _l(list['DriverStandings']))
              {
                'position': _n(d['position']),
                ..._driver(_m(d['Driver'])),
                'team': _s(_m(_l(d['Constructors']).lastOrNull)['name']),
                'team_id': _s(_m(_l(d['Constructors']).lastOrNull)['constructorId']),
                'points': _n(d['points']),
                'wins': _n(d['wins']),
              },
          ],
          'source': 'Jolpica (Ergast)',
        };
      case 'constructors':
        final list = _m(_l(_m((await _f1('$s/constructorStandings'))['StandingsTable'])['StandingsLists']).firstOrNull);
        return {
          'view': 'constructors',
          'season': _s(list['season']),
          'round': _n(list['round']),
          'teams': [
            for (final d in _l(list['ConstructorStandings']))
              {
                'position': _n(d['position']),
                'name': _s(_m(d['Constructor'])['name']),
                'team_id': _s(_m(d['Constructor'])['constructorId']),
                'nationality': _s(_m(d['Constructor'])['nationality']),
                'points': _n(d['points']),
                'wins': _n(d['wins']),
              },
          ],
          'source': 'Jolpica (Ergast)',
        };
      case 'last_race':
        final r = _l(_m((await _f1('$s/last/results'))['RaceTable'])['Races']).firstOrNull;
        if (r == null) throw const SportsException('No race results yet this season.');
        return {
          'view': 'last_race',
          ..._race(r),
          'results': [
            for (final x in _l(r['Results']))
              {
                'position': _n(x['position']),
                'position_text': _s(x['positionText']),
                ..._driver(_m(x['Driver'])),
                'team': _s(_m(x['Constructor'])['name']),
                'team_id': _s(_m(x['Constructor'])['constructorId']),
                'grid': _n(x['grid']),
                'laps': _n(x['laps']),
                'status': _s(x['status']),
                'time': _s(_m(x['Time'])['time']),
                'points': _n(x['points']),
                'fastest_lap': _m(x['FastestLap'])['rank'] == '1',
                'fastest_lap_time': _s(_m(_m(x['FastestLap'])['Time'])['time']),
              },
          ],
          'source': 'Jolpica (Ergast)',
        };
      case 'calendar':
        final races = [for (final r in _l(_m((await _f1(s))['RaceTable'])['Races'])) _race(r)];
        final now = DateTime.now().toUtc();
        return {
          'view': 'calendar',
          'season': races.firstOrNull?['season'],
          'races': [
            for (final r in races) {...r, 'done': (DateTime.tryParse('${r['start']}') ?? now).isBefore(now)},
          ],
          'source': 'Jolpica (Ergast)',
        };
      default: // next
        final r = _l(_m((await _f1('$s/next'))['RaceTable'])['Races']).firstOrNull;
        if (r == null) throw const SportsException('No upcoming race: the season may be over.');
        Map<String, dynamic>? leader;
        try {
          final st = await f1('standings', season: s);
          leader = (st['drivers'] as List).isEmpty ? null : Map<String, dynamic>.from((st['drivers'] as List).first as Map);
        } catch (_) {}
        return {'view': 'next', ..._race(r), 'leader': ?leader, 'source': 'Jolpica (Ergast)'};
    }
  }
}

/// Team colours for F1 cards.
const f1TeamColors = {
  'mercedes': '27F4D2',
  'ferrari': 'E8002D',
  'red_bull': '3671C6',
  'mclaren': 'FF8000',
  'aston_martin': '229971',
  'alpine': 'FF87BC',
  'williams': '64C4FF',
  'rb': '6692FF',
  'sauber': '52E252',
  'audi': 'B6BABD',
  'haas': 'B6BABD',
  'cadillac': 'C9A86A',
};
