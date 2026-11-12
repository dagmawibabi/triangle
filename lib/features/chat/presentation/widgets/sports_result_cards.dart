import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../sports/sports_api.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';
import 'tile_map.dart';

/// Cards for the sports tools. Null for other tools.
Widget? sportsResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'sports_scores' when maps(j['events']).length == 1 => _MatchHeroCard(m: maps(j['events']).first),
  'sports_scores' when j['events'] != null => _ScoreboardCard(s: j),
  'sports_match' when j['home'] != null => _MatchHeroCard(m: j, full: j),
  'sports_standings' when maps(j['groups']).isNotEmpty => _StandingsCard(s: j),
  'sports_team' when j['name'] != null => _TeamCard(t: j),
  'sports_player' when j['name'] != null => _PlayerCard(p: j),
  'sports_news' when maps(j['articles']).isNotEmpty => _NewsCard(n: j),
  'sports_top_scorers' when maps(j['scorers']).isNotEmpty => _ScorersCard(s: j),
  'formula1' when j['view'] == 'next' => _F1NextCard(r: j),
  'formula1' when j['view'] == 'standings' => _F1TableCard(t: j, drivers: true),
  'formula1' when j['view'] == 'constructors' => _F1TableCard(t: j, drivers: false),
  'formula1' when j['view'] == 'last_race' => _F1ResultCard(r: j),
  'formula1' when j['view'] == 'calendar' => _F1CalendarCard(c: j),
  _ => null,
};

// ---- shared -----------------------------------------------------------------------

const _live = Color(0xFFE5484D);
const _win = Color(0xFF2FB45A);
const _draw = Color(0xFF8A8F98);

Color teamColor(Object? hex, [Color fallback = const Color(0xFF3A3F47)]) {
  final s = '${hex ?? ''}'.replaceAll('#', '');
  final v = int.tryParse(s, radix: 16);
  if (s.length != 6 || v == null) return fallback;
  final c = Color(0xFF000000 | v);
  // Near-white kits read badly as a background.
  return c.computeLuminance() > 0.85 ? fallback : c;
}

class Crest extends StatelessWidget {
  const Crest(this.url, {super.key, this.size = 28, this.label});
  final Object? url;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final u = textOf(url);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
      child: Text((label ?? '?').characters.take(3).toString(), style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w800, color: AppColors.text2)),
    );
    if (u == null) return fallback;
    return SizedBox(width: size, height: size, child: NetImage(u, width: size, height: size, fit: BoxFit.contain, errorWidget: fallback));
  }
}

String _kick(Object? iso, {bool withDay = true}) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final hm = DateFormat.Hm().format(t);
  if (!withDay) return hm;
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today $hm';
  if (diff == 1) return 'Tomorrow $hm';
  if (diff == -1) return 'Yesterday $hm';
  return '${DateFormat('EEE d MMM').format(t)} · $hm';
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge(this.text);
  final String text;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: _live, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(opacity: _c, child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
        const SizedBox(width: 4),
        Text(widget.text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
      ],
    ),
  );
}

class _FormDots extends StatelessWidget {
  const _FormDots(this.form, {this.size = 18});
  final String form;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final ch in form.split(''))
        Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(right: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: switch (ch) {
              'W' => _win,
              'L' => _live,
              _ => _draw,
            },
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(ch, style: TextStyle(color: Colors.white, fontSize: size * 0.55, fontWeight: FontWeight.w800)),
        ),
    ],
  );
}

// ---- scoreboard -------------------------------------------------------------------

class _ScoreboardCard extends StatelessWidget {
  const _ScoreboardCard({required this.s});
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final events = maps(s['events']);
    final live = (numOf(s['live']) ?? 0).toInt();
    return InfoFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
            child: Row(
              children: [
                Crest(s['logo'], size: 22, label: '${s['league_name']}'),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    '${s['league_name']}${s['date'] == null ? '' : ' · ${DateFormat('EEE d MMM').format(DateTime.tryParse('${s['date']}') ?? DateTime.now())}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (live > 0) _LiveBadge('$live LIVE'),
              ],
            ),
          ),
          if (events.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: Text('${s['note'] ?? 'No games.'}', style: context.text.bodySmall)),
          for (final (i, e) in events.take(12).indexed) ...[
            if (i > 0) Divider(height: 1, color: AppColors.line, indent: Space.m, endIndent: Space.m),
            _GameRow(e: e),
          ],
          if (events.length > 12)
            TextButton(onPressed: () => showInfoSheet(context, (c) => [SheetTitle('${s['league_name']}', subtitle: '${events.length} games'), for (final e in events) _GameRow(e: e)]), child: Text('All ${events.length} games')),
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.e});
  final Map<String, dynamic> e;

  @override
  Widget build(BuildContext context) {
    final home = mapOf(e['home']), away = mapOf(e['away']);
    final st = mapOf(e['status']);
    final state = '${st['state']}';
    final started = state != 'pre';
    final moments = maps(e['moments']);
    Widget side(Map<String, dynamic> t, {required bool right}) {
      final lost = state == 'post' && t['winner'] != true && (home['winner'] == true || away['winner'] == true);
      final name = Text(
        '${t['short'] ?? t['name']}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: right ? TextAlign.left : TextAlign.right,
        style: TextStyle(fontWeight: t['winner'] == true ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5, color: lost ? AppColors.text2 : AppColors.text),
      );
      return Expanded(
        child: Row(
          mainAxisAlignment: right ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: right
              ? [Crest(t['logo'], label: '${t['abbr']}'), const SizedBox(width: Space.s), Flexible(child: name)]
              : [Flexible(child: name), const SizedBox(width: Space.s), Crest(t['logo'], label: '${t['abbr']}')],
        ),
      );
    }

    return InkWell(
      onTap: () => showMatch(context, '${e['league']}', '${e['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                side(home, right: false),
                SizedBox(
                  width: 78,
                  child: Column(
                    children: [
                      if (started)
                        Text(
                          '${home['score'] ?? '-'}  ${away['score'] ?? '-'}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: state == 'in' ? _live : AppColors.text, fontFeatures: tabularFigures),
                        )
                      else
                        Text(_kick(e['date'], withDay: false), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                      const SizedBox(height: 2),
                      state == 'in'
                          ? _LiveBadge(textOf(st['clock']) ?? 'LIVE')
                          : Text(state == 'post' ? '${st['detail'] ?? 'FT'}' : _dayOnly(e['date']), style: TextStyle(fontSize: 10.5, color: AppColors.text3)),
                    ],
                  ),
                ),
                side(away, right: true),
              ],
            ),
            if (moments.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _MomentList(moments.where((m) => m['home'] == true).toList(), right: false)),
                  const SizedBox(width: 78),
                  Expanded(child: _MomentList(moments.where((m) => m['home'] != true).toList(), right: true)),
                ],
              ),
            ],
            if (moments.isEmpty && maps(e['leaders']).isNotEmpty && started) ...[
              const SizedBox(height: 4),
              Text(
                maps(e['leaders']).map((l) => '${l['player']} ${l['value']} ${'${l['stat'] ?? ''}'.toLowerCase()}').join('  ·  '),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.text3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _dayOnly(Object? iso) {
    final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (t == null) return '';
    final k = _kick(iso);
    return k.startsWith('Today') ? 'Today' : (k.startsWith('Tomorrow') ? 'Tomorrow' : DateFormat('d MMM').format(t));
  }
}

class _MomentList extends StatelessWidget {
  const _MomentList(this.moments, {required this.right});
  final List<Map<String, dynamic>> moments;
  final bool right;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: right ? CrossAxisAlignment.start : CrossAxisAlignment.end,
    children: [
      for (final m in moments.take(5))
        Text(
          '${m['type'] == 'red_card' ? '🟥' : '⚽'} ${m['player'] ?? ''} ${m['minute'] ?? ''}${m['type'] == 'penalty' ? ' (P)' : m['type'] == 'own_goal' ? ' (OG)' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: AppColors.text2),
        ),
    ],
  );
}

// ---- one match --------------------------------------------------------------------

Future<void> showMatch(BuildContext context, String league, String id) =>
    showLoadingSheet(context, () => SportsApi.instance.match(league, id), (context, m) => _matchBody(context, m), initialSize: 0.94);

class _MatchHeroCard extends StatelessWidget {
  const _MatchHeroCard({required this.m, this.full});
  final Map<String, dynamic> m;
  final Map<String, dynamic>? full;

  @override
  Widget build(BuildContext context) {
    final stats = maps(m['stats']);
    final goals = maps(m['events']).where((e) => e['scoring'] == true).toList();
    final moments = maps(m['moments']);
    return InfoFrame(
      onTap: () => full != null
          ? showInfoSheet(context, initialSize: 0.94, (c) => _matchBody(c, full!))
          : showMatch(context, '${m['league']}', '${m['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MatchHero(m: m),
          if (goals.isNotEmpty || moments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MomentList(
                      goals.isNotEmpty
                          ? [for (final g in goals.where((g) => g['home'] == true)) {'player': g['player'], 'minute': g['minute'], 'type': '${g['type']}'.contains('own') ? 'own_goal' : '${g['type']}'.contains('penalty') ? 'penalty' : 'goal'}]
                          : moments.where((x) => x['home'] == true).toList(),
                      right: false,
                    ),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: _MomentList(
                      goals.isNotEmpty
                          ? [for (final g in goals.where((g) => g['home'] != true)) {'player': g['player'], 'minute': g['minute'], 'type': '${g['type']}'.contains('own') ? 'own_goal' : '${g['type']}'.contains('penalty') ? 'penalty' : 'goal'}]
                          : moments.where((x) => x['home'] != true).toList(),
                      right: true,
                    ),
                  ),
                ],
              ),
            ),
          if (stats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 0),
              child: Column(children: [for (final s in stats.take(4)) _StatBar(s: s, home: teamColor(mapOf(m['home'])['color']), away: teamColor(mapOf(m['away'])['color'], const Color(0xFF7A808A)))]),
            ),
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Text(
              [m['venue'], m['city'], if (m['attendance'] != null) '${NumberFormat.decimalPattern().format(m['attendance'])} fans'].whereType<Object>().join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.text3),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchHero extends StatelessWidget {
  const _MatchHero({required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final home = mapOf(m['home']), away = mapOf(m['away']);
    final st = mapOf(m['status']);
    final state = '${st['state']}';
    final hc = teamColor(home['color']), ac = teamColor(away['color'], const Color(0xFF2B2F36));
    Widget side(Map<String, dynamic> t) => Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), shape: BoxShape.circle),
            child: Crest(t['logo'], size: 46, label: '${t['abbr']}'),
          ),
          const SizedBox(height: 6),
          Text('${t['short'] ?? t['name']}', maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.15)),
          if (t['form'] != null) ...[const SizedBox(height: 4), _FormDots('${t['form']}', size: 13)],
          if (t['form'] == null && t['record'] != null) Text('${t['record']}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.l),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color.lerp(hc, Colors.black, 0.35)!, Color.lerp(ac, Colors.black, 0.35)!], begin: Alignment.centerLeft, end: Alignment.centerRight),
      ),
      child: Column(
        children: [
          Text('${m['league_name'] ?? ''}'.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: Space.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side(home),
              SizedBox(
                width: 110,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: state == 'pre'
                          ? Text(_kick(m['date'], withDay: false), maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, fontFeatures: tabularFigures))
                          : Text('${home['score'] ?? 0} – ${away['score'] ?? 0}', maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, fontFeatures: tabularFigures)),
                    ),
                    const SizedBox(height: 4),
                    if (state == 'in')
                      _LiveBadge(textOf(st['clock']) ?? 'LIVE')
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(99)),
                        child: Text(state == 'pre' ? _kick(m['date']).split(' · ').first : '${st['detail'] ?? 'FT'}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
              side(away),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({required this.s, required this.home, required this.away});
  final Map<String, dynamic> s;
  final Color home;
  final Color away;

  static num _v(Object? x) => num.tryParse('${x ?? ''}'.replaceAll('%', '').split('-').first.split('/').first) ?? 0;

  @override
  Widget build(BuildContext context) {
    final a = _v(s['home']), b = _v(s['away']);
    final total = a + b;
    final f = total == 0 ? 0.5 : a / total;
    final pct = '${s['label']}' == 'Possession';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Text('${s['home']}${pct ? '%' : ''}', style: TextStyle(fontWeight: a >= b ? FontWeight.w800 : FontWeight.w500, fontSize: 13, fontFeatures: tabularFigures)),
              Expanded(child: Text('${s['label']}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.text2))),
              Text('${s['away']}${pct ? '%' : ''}', style: TextStyle(fontWeight: b >= a ? FontWeight.w800 : FontWeight.w500, fontSize: 13, fontFeatures: tabularFigures)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(flex: (f * 1000).round().clamp(1, 999), child: Container(color: a >= b ? home : home.withValues(alpha: 0.4))),
                  const SizedBox(width: 2),
                  Expanded(flex: ((1 - f) * 1000).round().clamp(1, 999), child: Container(color: b >= a ? away : away.withValues(alpha: 0.4))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _matchBody(BuildContext context, Map<String, dynamic> m) {
  final home = mapOf(m['home']), away = mapOf(m['away']);
  final hc = teamColor(home['color']), ac = teamColor(away['color'], const Color(0xFF7A808A));
  final events = maps(m['events']);
  final lineups = maps(m['lineups']);
  final leaders = maps(m['leaders']);
  return [
    ClipRRect(borderRadius: BorderRadius.circular(Radii.l), child: _MatchHero(m: m)),
    if (m['headline'] != null) ...[
      const SizedBox(height: Space.m),
      Text('${m['headline']}', style: context.text.titleMedium),
      if (m['recap'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${m['recap']}', style: context.text.bodySmall?.copyWith(height: 1.4))),
    ],
    if (events.isNotEmpty) ...[
      const SectionLabel('Timeline'),
      for (final e in events) _TimelineRow(e: e, homeColor: hc, awayColor: ac),
    ],
    if (maps(m['stats']).isNotEmpty) ...[
      const SectionLabel('Match stats'),
      Row(children: [Crest(home['logo'], size: 20), const Spacer(), Crest(away['logo'], size: 20)]),
      for (final s in maps(m['stats'])) _StatBar(s: s, home: hc, away: ac),
    ],
    if (lineups.isNotEmpty) ...[
      const SectionLabel('Lineups'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, l) in lineups.indexed) ...[
            if (i > 0) const SizedBox(width: Space.m),
            Expanded(child: _Lineup(l: l, color: l['home'] == true ? hc : ac)),
          ],
        ],
      ),
    ],
    if (leaders.isNotEmpty) ...[
      const SectionLabel('Top performers'),
      for (final t in leaders) ...[
        Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text('${t['team'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800))),
        for (final c in maps(t['categories']))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                ClipOval(child: Container(color: AppColors.surface2, child: NetImage(textOf(c['headshot']), width: 36, height: 36, fit: BoxFit.cover, placeholder: Icons.person_rounded))),
                const SizedBox(width: Space.m),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${c['player']}', style: const TextStyle(fontWeight: FontWeight.w600)), Text('${c['stat']}', style: context.text.bodySmall)])),
                Text('${c['value']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
      ],
    ],
    const SectionLabel('Match info'),
    KeyValueRow('Kick-off', _kick(m['date'])),
    if (m['venue'] != null) KeyValueRow('Venue', [m['venue'], m['city']].whereType<Object>().join(', ')),
    if (m['attendance'] != null) KeyValueRow('Attendance', NumberFormat.decimalPattern().format(m['attendance'])),
    KeyValueRow('Competition', '${m['league_name']}'),
    sheetButtons([linkButton('ESPN', textOf(m['url']), filled: true)]),
  ];
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.e, required this.homeColor, required this.awayColor});
  final Map<String, dynamic> e;
  final Color homeColor;
  final Color awayColor;

  @override
  Widget build(BuildContext context) {
    final type = '${e['type'] ?? ''}';
    final (IconData icon, Color c) = switch (type) {
      _ when e['scoring'] == true => (Icons.sports_soccer_rounded, _win),
      'yellow-card' => (Icons.style_rounded, const Color(0xFFF2C94C)),
      'red-card' || 'yellow-red-card' => (Icons.style_rounded, _live),
      'substitution' => (Icons.swap_vert_rounded, AppColors.text3),
      _ => (Icons.circle, AppColors.text3),
    };
    final home = e['home'] == true;
    final body = Column(
      crossAxisAlignment: home ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text('${e['player'] ?? e['label'] ?? ''}', textAlign: home ? TextAlign.right : TextAlign.left, style: TextStyle(fontWeight: e['scoring'] == true ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
        if (type == 'substitution' && e['assist'] != null)
          Text('for ${e['assist']}', style: TextStyle(fontSize: 11, color: AppColors.text3))
        else if (e['scoring'] == true && e['assist'] != null)
          Text('assist ${e['assist']}', style: TextStyle(fontSize: 11, color: AppColors.text3))
        else if (e['scoring'] != true && type != 'substitution')
          Text('${e['label'] ?? ''}', style: TextStyle(fontSize: 11, color: AppColors.text3)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: home ? body : const SizedBox()),
          const SizedBox(width: Space.s),
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99), border: Border.all(color: (home ? homeColor : awayColor).withValues(alpha: 0.6))),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: c), const SizedBox(width: 2), Text('${e['minute'] ?? ''}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700))]),
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(child: home ? const SizedBox() : body),
        ],
      ),
    );
  }
}

class _Lineup extends StatelessWidget {
  const _Lineup({required this.l, required this.color});
  final Map<String, dynamic> l;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(Radii.s)),
        child: Text('${l['team']}${l['formation'] == null ? '' : '  ${l['formation']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
      ),
      const SizedBox(height: 4),
      for (final p in maps(l['starters']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text('${p['number'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              if (p['subbed_out'] == true) Icon(Icons.south_rounded, size: 12, color: _live),
            ],
          ),
        ),
      if (maps(l['bench']).any((p) => p['subbed_in'] == true)) ...[
        const SizedBox(height: 4),
        Text('ON', style: context.text.labelSmall),
        for (final p in maps(l['bench']).where((p) => p['subbed_in'] == true))
          Row(children: [Icon(Icons.north_rounded, size: 12, color: _win), const SizedBox(width: 4), Expanded(child: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.text2)))]),
      ],
    ],
  );
}

// ---- standings --------------------------------------------------------------------

class _StandingsCard extends StatelessWidget {
  const _StandingsCard({required this.s});
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final groups = maps(s['groups']);
    final soccer = s['sport'] == 'soccer';
    return InfoFrame(
      onTap: () => _showStandings(context, s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.leaderboard_rounded, '${s['league_name']} · ${s['season'] ?? ''}'),
          for (final g in groups.take(2)) ...[
            if (groups.length > 1) Padding(padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 2), child: Text('${g['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            _TableHead(soccer: soccer),
            for (final r in maps(g['rows']).take(groups.length > 1 ? 5 : 8)) _TableRow(r: r, soccer: soccer, league: '${s['league']}'),
          ],
          Padding(padding: const EdgeInsets.all(Space.s), child: Text('Tap for the full table', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
        ],
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead({required this.soccer});
  final bool soccer;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 10.5, color: AppColors.text3, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, 4, Space.m, 4),
      child: Row(
        children: [
          const SizedBox(width: 30),
          Expanded(child: Text('TEAM', style: style)),
          for (final h in soccer ? const ['P', 'W', 'D', 'L', 'GD'] : const ['W', 'L', 'PCT', 'GB']) SizedBox(width: h == 'PCT' ? 40 : 28, child: Text(h, textAlign: TextAlign.center, style: style)),
          SizedBox(width: 34, child: Text(soccer ? 'PTS' : 'STRK', textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.r, required this.soccer, required this.league});
  final Map<String, dynamic> r;
  final bool soccer;
  final String league;

  String _i(Object? v) => v is num ? '${v.toInt()}' : '${v ?? '–'}';

  @override
  Widget build(BuildContext context) {
    final zone = r['zone_color'] == null ? null : teamColor(r['zone_color'], Colors.transparent);
    final cell = const TextStyle(fontSize: 12.5, fontFeatures: tabularFigures);
    return InkWell(
      onTap: () => showTeam(context, league, '${r['name']}'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 5, Space.m, 5),
        child: Row(
          children: [
            Container(width: 3, height: 22, color: zone ?? Colors.transparent),
            SizedBox(width: Space.m - 3 + 18, child: Text('${r['position']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            Crest(r['logo'], size: 18, label: '${r['abbr']}'),
            const SizedBox(width: 6),
            Expanded(child: Text('${r['short'] ?? r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            if (soccer)
              for (final v in [r['played'], r['won'], r['drawn'], r['lost'], r['gd']]) SizedBox(width: 28, child: Text(_i(v), textAlign: TextAlign.center, style: cell))
            else ...[
              SizedBox(width: 28, child: Text(_i(r['won']), textAlign: TextAlign.center, style: cell)),
              SizedBox(width: 28, child: Text(_i(r['lost']), textAlign: TextAlign.center, style: cell)),
              SizedBox(width: 40, child: Text(_i(r['pct']), textAlign: TextAlign.center, style: cell)),
              SizedBox(width: 28, child: Text(_i(r['games_behind']), textAlign: TextAlign.center, style: cell)),
            ],
            SizedBox(
              width: 34,
              child: Text(
                soccer ? _i(r['points']) : _i(r['streak']),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, fontFeatures: tabularFigures, color: !soccer && '${r['streak']}'.startsWith('W') ? _win : (!soccer && '${r['streak']}'.startsWith('L') ? _live : null)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showStandings(BuildContext context, Map<String, dynamic> s) {
  final soccer = s['sport'] == 'soccer';
  showInfoSheet(
    context,
    initialSize: 0.94,
    (context) => [
      SheetTitle('${s['league_name']}', subtitle: '${s['season'] ?? ''}'),
      for (final g in maps(s['groups'])) ...[
        if (maps(s['groups']).length > 1) SectionLabel('${g['name']}') else const SizedBox(height: Space.m),
        Container(
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(Radii.m)),
          child: Column(children: [_TableHead(soccer: soccer), for (final r in maps(g['rows'])) _TableRow(r: r, soccer: soccer, league: '${s['league']}')]),
        ),
      ],
      if (maps(s['zones']).isNotEmpty) ...[
        const SizedBox(height: Space.m),
        Wrap(
          spacing: Space.m,
          runSpacing: 6,
          children: [
            for (final z in maps(s['zones']))
              Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: teamColor(z['color']), borderRadius: BorderRadius.circular(2))), const SizedBox(width: 4), Text('${z['label']}', style: const TextStyle(fontSize: 12))]),
          ],
        ),
      ],
      Padding(padding: const EdgeInsets.only(top: Space.m), child: Text('Tap a team for its form and fixtures. Source: ESPN.', style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
    ],
  );
}

// ---- team -------------------------------------------------------------------------

Future<void> showTeam(BuildContext context, String league, String name) =>
    showLoadingSheet(context, () => SportsApi.instance.team(league, name), (context, t) => _teamBody(context, t), initialSize: 0.9);

class _TeamHero extends StatelessWidget {
  const _TeamHero({required this.t});
  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final c = teamColor(t['color']);
    final alt = teamColor(t['alt_color'], Color.lerp(c, Colors.black, 0.5)!);
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [c, Color.lerp(alt, Colors.black, 0.3)!], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), shape: BoxShape.circle), child: Crest(t['logo'], size: 56, label: '${t['abbr']}')),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t['name']}', style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.1)),
                if (t['nickname'] != null && t['nickname'] != t['name']) Text('"${t['nickname']}"', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text([t['standing'], t['record']].whereType<Object>().join(' · '), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.t});
  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final next = maps(t['next']).firstOrNull;
    return InfoFrame(
      onTap: () => showInfoSheet(context, initialSize: 0.9, (c) => _teamBody(c, t)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TeamHero(t: t),
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ('${t['form'] ?? ''}'.isNotEmpty) Row(children: [Text('FORM  ', style: context.text.labelSmall), _FormDots('${t['form']}')]),
                if (next != null) ...[
                  const SizedBox(height: Space.m),
                  Row(
                    children: [
                      Text('NEXT  ', style: context.text.labelSmall),
                      Crest(next['opponent_logo'], size: 20),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${next['home'] == true ? 'vs' : 'at'} ${next['opponent']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(_kick(next['date']), style: TextStyle(fontSize: 12, color: AppColors.text2)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _teamBody(BuildContext context, Map<String, dynamic> t) {
  final rs = mapOf(t['record_stats']);
  return [
    ClipRRect(borderRadius: BorderRadius.circular(Radii.l), child: _TeamHero(t: t)),
    const SizedBox(height: Space.l),
    infoGrid(columns: 3, [
      for (final (k, label) in const [('gamesPlayed', 'Played'), ('wins', 'Won'), ('ties', 'Drawn'), ('losses', 'Lost'), ('pointsFor', 'Scored'), ('pointsAgainst', 'Conceded'), ('points', 'Points'), ('homeWins', 'Home wins'), ('awayWins', 'Away wins')])
        if (rs[k] != null && !(k == 'ties' && t['sport'] != 'soccer') && !(k == 'points' && t['sport'] != 'soccer')) InfoStat(label, '${(numOf(rs[k]) ?? 0) % 1 == 0 ? (numOf(rs[k]) ?? 0).toInt() : rs[k]}'),
    ]),
    if ('${t['form'] ?? ''}'.isNotEmpty) ...[const SectionLabel('Form, oldest to newest'), _FormDots('${t['form']}', size: 24)],
    if (maps(t['next']).isNotEmpty) ...[
      const SectionLabel('Next up'),
      for (final g in maps(t['next'])) _TeamGameRow(g: g, league: '${t['league']}'),
    ],
    if (maps(t['recent']).isNotEmpty) ...[
      const SectionLabel('Recent results'),
      for (final g in maps(t['recent'])) _TeamGameRow(g: g, league: '${t['league']}'),
    ],
    sheetButtons([
      FilledButton.icon(onPressed: () => showLoadingSheet(context, () => SportsApi.instance.standings('${t['league']}'), (c, s) => [_StandingsCard(s: s)]), icon: const Icon(Icons.leaderboard_rounded, size: 18), label: const Text('Table')),
      linkButton('ESPN', textOf(t['url'])),
    ]),
  ];
}

class _TeamGameRow extends StatelessWidget {
  const _TeamGameRow({required this.g, required this.league});
  final Map<String, dynamic> g;
  final String league;

  @override
  Widget build(BuildContext context) {
    final r = '${g['result'] ?? ''}';
    return InkWell(
      onTap: () => showMatch(context, league, '${g['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            if (r.isNotEmpty) _FormDots(r, size: 22) else Icon(Icons.event_rounded, size: 20, color: AppColors.text3),
            const SizedBox(width: Space.s),
            Crest(g['opponent_logo'], size: 22),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${g['home'] == true ? 'vs' : 'at'} ${g['opponent']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  Text(_kick(g['date']), style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
                ],
              ),
            ),
            if (g['score'] != null) Text('${g['score']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, fontFeatures: tabularFigures)),
          ],
        ),
      ),
    );
  }
}

// ---- players ----------------------------------------------------------------------

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) => InfoFrame(
    onTap: () => _showPlayer(context, p),
    child: _PlayerHero(p: p, height: 190),
  );
}

class _PlayerHero extends StatelessWidget {
  const _PlayerHero({required this.p, this.height = 220});
  final Map<String, dynamic> p;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (p['banner'] != null) NetImage('${p['banner']}', fit: BoxFit.cover, errorWidget: const ColoredBox(color: Color(0xFF1B1F24))) else const ColoredBox(color: Color(0xFF1B1F24)),
        DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.black.withValues(alpha: 0.88), Colors.black.withValues(alpha: 0.35)])),
        ),
        Positioned(right: 0, bottom: 0, top: 8, width: height * 0.85, child: NetImage(textOf(p['photo']), fit: BoxFit.contain, alignment: Alignment.bottomCenter, errorWidget: const SizedBox.shrink())),
        Positioned(
          left: Space.l,
          top: Space.l,
          bottom: Space.l,
          right: height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (p['number'] != null) Text('#${p['number']}', style: const TextStyle(color: Colors.white38, fontSize: 30, fontWeight: FontWeight.w900, height: 1)),
              Text('${p['name']}', maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
              const SizedBox(height: 4),
              Text([p['position'], p['team']].whereType<Object>().join(' · '), maxLines: 2, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (p['nationality'] != null) _chip('${p['nationality']}'),
                if (p['age'] != null) _chip('${p['age']} yrs'),
                if (p['status'] != null && p['status'] != 'Active') _chip('${p['status']}'),
              ]),
            ],
          ),
        ),
      ],
    ),
  );

  static Widget _chip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
    child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

void _showPlayer(BuildContext context, Map<String, dynamic> p) => showInfoSheet(
  context,
  initialSize: 0.92,
  (context) => [
    ClipRRect(borderRadius: BorderRadius.circular(Radii.l), child: _PlayerHero(p: p, height: 240)),
    const SizedBox(height: Space.l),
    infoGrid([
      InfoStat('Team', '${p['team'] ?? '—'}', icon: Icons.shield_outlined),
      if (p['national_team'] != null) InfoStat('National team', '${p['national_team']}', icon: Icons.flag_outlined),
      InfoStat('Position', '${p['position'] ?? '—'}', icon: Icons.sports_rounded),
      InfoStat('Born', [p['born'], if (p['age'] != null) '(${p['age']})'].whereType<Object>().join(' '), icon: Icons.cake_outlined),
      if (p['birthplace'] != null) InfoStat('Birthplace', '${p['birthplace']}', icon: Icons.place_outlined),
      if (p['height'] != null) InfoStat('Height', '${p['height']}', icon: Icons.height_rounded),
      if (p['weight'] != null) InfoStat('Weight', '${p['weight']}', icon: Icons.monitor_weight_outlined),
      if (p['side'] != null) InfoStat('Foot / side', '${p['side']}', icon: Icons.directions_walk_rounded),
      if (p['signed'] != null) InfoStat('Signed', '${p['signed']}', icon: Icons.edit_note_rounded),
    ]),
    if (p['description'] != null) ...[const SectionLabel('Biography'), SelectableText('${p['description']}', style: context.text.bodyMedium?.copyWith(height: 1.5))],
    if (maps(p['others']).isNotEmpty) ...[
      const SectionLabel('Did you mean'),
      for (final o in maps(p['others']))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ClipOval(child: NetImage(textOf(o['thumb']), width: 36, height: 36, placeholder: Icons.person_rounded)),
          title: Text('${o['name']}'),
          subtitle: Text([o['team'], o['sport']].whereType<Object>().join(' · ')),
          onTap: () => showLoadingSheet(context, () => SportsApi.instance.player('${o['name']}'), (c, x) => [_PlayerCard(p: x)]),
        ),
    ],
    sheetButtons([linkButton('Instagram', textOf(p['instagram']), icon: Icons.camera_alt_outlined), linkButton('X / Twitter', textOf(p['twitter']), icon: Icons.alternate_email_rounded)]),
    Padding(padding: const EdgeInsets.only(top: Space.l), child: Text('From TheSportsDB (community-edited).', style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
  ],
);

// ---- news -------------------------------------------------------------------------

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.n});
  final Map<String, dynamic> n;

  @override
  Widget build(BuildContext context) {
    final list = maps(n['articles']);
    final lead = list.first;
    return InfoFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => openLink(textOf(lead['url'])),
            child: Stack(
              children: [
                AspectRatio(aspectRatio: 16 / 9, child: NetImage(textOf(lead['image']), fit: BoxFit.cover, errorWidget: ColoredBox(color: AppColors.surface2))),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)])))),
                Positioned(
                  left: Space.m,
                  right: Space.m,
                  bottom: Space.m,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${n['league_name']} · ESPN'.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                      Text('${lead['headline']}', maxLines: 3, style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final a in list.skip(1).take(6))
            InkWell(
              onTap: () => openLink(textOf(a['url'])),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(Radii.s), child: NetImage(textOf(a['image']), width: 76, height: 48, fit: BoxFit.cover, errorWidget: Container(width: 76, height: 48, color: AppColors.surface2))),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${a['headline']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.25)),
                          Text(_ago(a['published']), style: TextStyle(fontSize: 11, color: AppColors.text3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }

  static String _ago(Object? iso) {
    final t = DateTime.tryParse('${iso ?? ''}');
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

// ---- top scorers ------------------------------------------------------------------

class _ScorersCard extends StatelessWidget {
  const _ScorersCard({required this.s});
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final list = maps(s['scorers']);
    final top = numOf(list.first['goals']) ?? 1;
    Widget row(Map<String, dynamic> x) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 22, child: Text('${x['rank']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
          Crest(x['crest'], size: 24, label: '${x['team']}'),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${x['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                ShareBar(((numOf(x['goals']) ?? 0) / top).toDouble(), color: _win, height: 4),
              ],
            ),
          ),
          const SizedBox(width: Space.m),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${x['goals'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, fontFeatures: tabularFigures)),
              Text('${x['assists'] ?? 0} ast · ${x['played'] ?? '?'} gp', style: TextStyle(fontSize: 10.5, color: AppColors.text3)),
            ],
          ),
        ],
      ),
    );
    return InfoFrame(
      onTap: () => showInfoSheet(context, (c) => [
        SheetTitle('${s['competition']} top scorers', subtitle: 'Season ${s['season']}${s['matchday'] == null ? '' : ' · matchday ${s['matchday']}'}', leading: Crest(s['emblem'], size: 40)),
        const SizedBox(height: Space.m),
        for (final x in list) ...[row(x), if (x['penalties'] != null && (numOf(x['penalties']) ?? 0) > 0) Padding(padding: const EdgeInsets.only(left: 64), child: Text('${x['penalties']} penalties · ${x['nationality'] ?? ''}', style: TextStyle(fontSize: 11, color: AppColors.text3)))],
        Padding(padding: const EdgeInsets.only(top: Space.l), child: Text('Source: football-data.org.', style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
            child: Row(children: [Crest(s['emblem'], size: 22), const SizedBox(width: Space.s), Expanded(child: Text('${s['competition']} · top scorers', style: const TextStyle(fontWeight: FontWeight.w800))), Text('${s['season']}', style: TextStyle(fontSize: 11.5, color: AppColors.text3))]),
          ),
          for (final x in list.take(8)) row(x),
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}

// ---- Formula 1 --------------------------------------------------------------------

const _f1Red = Color(0xFFE10600);

Color _f1Team(Object? id) => teamColor(f1TeamColors['$id'], const Color(0xFF8A8F98));

class _Countdown extends StatefulWidget {
  const _Countdown(this.to);
  final DateTime to;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.to.difference(DateTime.now());
    if (d.isNegative) return const Text('LIGHTS OUT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20));
    Widget unit(int v, String l) => Column(
      children: [
        Container(
          width: 54,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
          child: Text(v.toString().padLeft(2, '0'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, fontFeatures: tabularFigures)),
        ),
        const SizedBox(height: 3),
        Text(l, style: const TextStyle(color: Colors.white60, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [unit(d.inDays, 'DAYS'), unit(d.inHours % 24, 'HRS'), unit(d.inMinutes % 60, 'MIN'), unit(d.inSeconds % 60, 'SEC')],
    );
  }
}

class _F1NextCard extends StatelessWidget {
  const _F1NextCard({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse('${r['start']}')?.toLocal();
    final leader = mapOf(r['leader']);
    return InfoFrame(
      color: const Color(0xFF15151E),
      onTap: () => _showF1Race(context, r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: _f1Red),
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _f1Red, borderRadius: BorderRadius.circular(4)),
                      child: Text('ROUND ${r['round']}', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                    ),
                    const SizedBox(width: Space.s),
                    if (r['sprint_weekend'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(4)),
                        child: const Text('SPRINT', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ),
                    const Spacer(),
                    const Icon(Icons.sports_motorsports_rounded, color: Colors.white54, size: 18),
                  ],
                ),
                const SizedBox(height: Space.m),
                Text('${r['name']}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
                Text('${r['circuit']} · ${r['locality']}, ${r['country']}', style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                const SizedBox(height: Space.l),
                if (start != null) _Countdown(start),
                const SizedBox(height: Space.m),
                if (start != null)
                  Text('Race: ${DateFormat('EEE d MMM · HH:mm').format(start)} your time', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (leader.isNotEmpty) ...[
                  const SizedBox(height: Space.m),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Container(width: 3, height: 26, color: _f1Team(leader['team_id'])),
                        const SizedBox(width: Space.s),
                        const Text('LEADER  ', style: TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.w800)),
                        Expanded(child: Text('${leader['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                        Text('${leader['points']} pts', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showF1Race(BuildContext context, Map<String, dynamic> r) {
  final sessions = mapOf(r['sessions']);
  final lat = numOf(r['latitude'])?.toDouble(), lon = numOf(r['longitude'])?.toDouble();
  showInfoSheet(
    context,
    (context) => [
      SheetTitle('${r['name']}', subtitle: 'Round ${r['round']} · ${r['season']}'),
      const SizedBox(height: Space.m),
      if (lat != null && lon != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.l),
          child: TileMap(lat: lat, lon: lon, zoom: 12.5, height: 170, markers: [MapMarker(lat, lon, size: 34, child: const PulseDot(color: _f1Red, pulse: true))]),
        ),
      const SizedBox(height: Space.s),
      Text('${r['circuit']} · ${r['locality']}, ${r['country']}', style: context.text.bodySmall),
      const SectionLabel('Weekend schedule', trailing: 'your time'),
      for (final e in sessions.entries)
        () {
          final t = DateTime.tryParse('${e.value}')?.toLocal();
          final done = t != null && t.isBefore(DateTime.now());
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(done ? Icons.check_circle_rounded : (e.key == 'Race' ? Icons.flag_rounded : Icons.timer_outlined), size: 18, color: done ? AppColors.text3 : (e.key == 'Race' ? _f1Red : AppColors.text2)),
                const SizedBox(width: Space.m),
                Expanded(child: Text(e.key, style: TextStyle(fontWeight: e.key == 'Race' ? FontWeight.w800 : FontWeight.w500, color: done ? AppColors.text3 : null))),
                Text(t == null ? '—' : DateFormat('EEE d MMM · HH:mm').format(t), style: TextStyle(fontFeatures: tabularFigures, color: done ? AppColors.text3 : null)),
              ],
            ),
          );
        }(),
      sheetButtons([
        FilledButton.icon(onPressed: () => showLoadingSheet(context, () => SportsApi.instance.f1('standings'), (c, t) => [_F1TableCard(t: t, drivers: true)]), icon: const Icon(Icons.leaderboard_rounded, size: 18), label: const Text('Standings')),
        linkButton('Wikipedia', textOf(r['url'])),
      ]),
    ],
  );
}

class _F1TableCard extends StatelessWidget {
  const _F1TableCard({required this.t, required this.drivers});
  final Map<String, dynamic> t;
  final bool drivers;

  @override
  Widget build(BuildContext context) {
    final rows = maps(drivers ? t['drivers'] : t['teams']);
    final top = numOf(rows.firstOrNull?['points']) ?? 1;
    Widget row(Map<String, dynamic> x) {
      final c = _f1Team(x['team_id']);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 5),
        child: Row(
          children: [
            SizedBox(width: 24, child: Text('${x['position']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
            Container(width: 4, height: 30, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(drivers ? '${x['name']}' : '${x['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                      if (drivers && x['code'] != null) Text('  ${x['code']}', style: TextStyle(fontSize: 11, color: AppColors.text3, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  ShareBar(((numOf(x['points']) ?? 0) / top).toDouble(), color: c, height: 4),
                ],
              ),
            ),
            const SizedBox(width: Space.m),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${x['points']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, fontFeatures: tabularFigures)),
                Text(drivers ? '${x['team'] ?? ''}' : '${x['wins']} wins', style: TextStyle(fontSize: 10.5, color: AppColors.text3)),
              ],
            ),
          ],
        ),
      );
    }

    return InfoFrame(
      onTap: () => showInfoSheet(context, (c) => [
        SheetTitle(drivers ? 'Drivers\' championship' : 'Constructors\' championship', subtitle: '${t['season']} · after round ${t['round']}'),
        const SizedBox(height: Space.m),
        for (final x in rows) row(x),
        Padding(padding: const EdgeInsets.only(top: Space.l), child: Text('Source: Jolpica (Ergast).', style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: _f1Red),
          InfoHeader(Icons.sports_motorsports_rounded, '${drivers ? 'Drivers' : 'Constructors'} · ${t['season']} · round ${t['round']}', color: _f1Red),
          for (final x in rows.take(drivers ? 10 : 10)) row(x),
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}

class _F1ResultCard extends StatelessWidget {
  const _F1ResultCard({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final res = maps(r['results']);
    final podium = res.take(3).toList();
    Widget step(Map<String, dynamic>? x, int place, double h) => Expanded(
      child: x == null
          ? const SizedBox()
          : Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${x['code'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                Text('${x['name']}'.split(' ').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.text2)),
                const SizedBox(height: 4),
                Container(
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_f1Team(x['team_id']), _f1Team(x['team_id']).withValues(alpha: 0.35)]),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Text('$place', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
    );
    return InfoFrame(
      onTap: () => _showF1Results(context, r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: _f1Red),
          InfoHeader(Icons.flag_rounded, '${r['name']} · results', color: _f1Red),
          SizedBox(
            height: 150,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [step(podium.elementAtOrNull(1), 2, 64), step(podium.elementAtOrNull(0), 1, 88), step(podium.elementAtOrNull(2), 3, 48)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Text(
              [
                if (podium.isNotEmpty) 'Winner ${podium.first['name']} (${podium.first['team']})${podium.first['time'] == null ? '' : ' in ${podium.first['time']}'}',
                if (res.any((x) => x['fastest_lap'] == true)) 'Fastest lap ${res.firstWhere((x) => x['fastest_lap'] == true)['name']}',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}

void _showF1Results(BuildContext context, Map<String, dynamic> r) => showInfoSheet(
  context,
  initialSize: 0.92,
  (context) => [
    SheetTitle('${r['name']}', subtitle: 'Round ${r['round']} · ${r['circuit']}'),
    const SectionLabel('Classification'),
    for (final x in maps(r['results']))
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(width: 26, child: Text('${x['position_text'] ?? x['position']}', style: const TextStyle(fontWeight: FontWeight.w900))),
            Container(width: 4, height: 28, color: _f1Team(x['team_id'])),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${x['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  Text('${x['team']} · grid ${x['grid']}${(numOf(x['grid']) ?? 0) > 0 && numOf(x['position']) != null ? ' (${_gained(x)})' : ''}', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                ],
              ),
            ),
            if (x['fastest_lap'] == true) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.timer_rounded, size: 16, color: Color(0xFFB04CE8))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${x['time'] ?? x['status'] ?? ''}', style: const TextStyle(fontSize: 12, fontFeatures: tabularFigures)),
                if ((numOf(x['points']) ?? 0) > 0) Text('+${x['points']} pts', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _win)),
              ],
            ),
          ],
        ),
      ),
    sheetButtons([linkButton('Wikipedia', textOf(r['url']))]),
  ],
);

String _gained(Map<String, dynamic> x) {
  final d = (numOf(x['grid']) ?? 0) - (numOf(x['position']) ?? 0);
  return d == 0 ? '±0' : (d > 0 ? '+${d.toInt()}' : '${d.toInt()}');
}

class _F1CalendarCard extends StatelessWidget {
  const _F1CalendarCard({required this.c});
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    final races = maps(c['races']);
    final nextIdx = races.indexWhere((r) => r['done'] != true);
    Widget row(Map<String, dynamic> r, bool isNext) {
      final t = DateTime.tryParse('${r['start']}')?.toLocal();
      final done = r['done'] == true;
      return InkWell(
        onTap: () => _showF1Race(context, r),
        child: Container(
          color: isNext ? _f1Red.withValues(alpha: 0.1) : null,
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 7),
          child: Row(
            children: [
              SizedBox(width: 26, child: Text('${r['round']}', style: TextStyle(fontWeight: FontWeight.w900, color: done ? AppColors.text3 : (isNext ? _f1Red : null)))),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['name']}'.replaceAll(' Grand Prix', ' GP'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: done ? AppColors.text3 : null)),
                    Text('${r['locality']}, ${r['country']}', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                  ],
                ),
              ),
              if (r['sprint_weekend'] == true) const Padding(padding: EdgeInsets.only(right: 6), child: InfoPill('Sprint')),
              Text(t == null ? '' : DateFormat('d MMM').format(t), style: TextStyle(fontWeight: FontWeight.w600, color: done ? AppColors.text3 : null)),
              if (done) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.check_rounded, size: 16, color: AppColors.text3)),
            ],
          ),
        ),
      );
    }

    final shown = nextIdx < 0 ? races.reversed.take(6).toList().reversed.toList() : races.skip((nextIdx - 2).clamp(0, races.length)).take(6).toList();
    return InfoFrame(
      onTap: () => showInfoSheet(context, (ctx) => [
        SheetTitle('${c['season']} Formula 1 calendar', subtitle: '${races.length} rounds · ${races.where((r) => r['done'] == true).length} done'),
        const SizedBox(height: Space.m),
        for (final (i, r) in races.indexed) row(r, i == nextIdx),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: _f1Red),
          InfoHeader(Icons.calendar_month_rounded, '${c['season']} calendar · ${races.length} rounds', color: _f1Red),
          for (final r in shown) row(r, races.indexOf(r) == nextIdx),
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}
