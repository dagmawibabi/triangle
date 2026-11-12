import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../pokemon/pokemon_api.dart';
import '../../domain/chat_models.dart';

/// Cards for the Pokémon tools. Null for other tools.
Widget? pokemonResultFor(ToolPart part, Map<String, dynamic> j) {
  final list = [
    for (final x in (j['pokemon'] as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'pokemon_info' when j['id'] != null && j['name'] != null => PokemonCard(p: j),
    'pokemon_search' when list.isNotEmpty => _PokemonGrid(pokemon: list),
    _ => null,
  };
}

const typeColors = {
  'normal': Color(0xFFA8A77A),
  'fire': Color(0xFFEE8130),
  'water': Color(0xFF6390F0),
  'electric': Color(0xFFF7D02C),
  'grass': Color(0xFF7AC74C),
  'ice': Color(0xFF96D9D6),
  'fighting': Color(0xFFC22E28),
  'poison': Color(0xFFA33EA1),
  'ground': Color(0xFFE2BF65),
  'flying': Color(0xFFA98FF3),
  'psychic': Color(0xFFF95587),
  'bug': Color(0xFFA6B91A),
  'rock': Color(0xFFB6A136),
  'ghost': Color(0xFF735797),
  'dragon': Color(0xFF6F35FC),
  'dark': Color(0xFF705746),
  'steel': Color(0xFFB7B7CE),
  'fairy': Color(0xFFD685AD),
};

Color _typeColor(Object? t) => typeColors['$t'] ?? const Color(0xFF8A8A99);

/// Dark text on light type colours (electric, ice…), white on the rest.
Color _on(Color c) => c.computeLuminance() > 0.5 ? const Color(0xFF1B1B1F) : Colors.white;

String _dexNo(Object? id) => '#${'${id ?? 0}'.padLeft(4, '0')}';

List<String> _strings(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

List<Map<String, dynamic>> _maps(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x is Map) Map<String, dynamic>.from(x),
];

AudioPlayer? _cryPlayer;

Future<void> _playCry(String? url) async {
  if (url == null || url.isEmpty) return;
  try {
    final p = _cryPlayer ??= AudioPlayer();
    await p.stop();
    await p.play(UrlSource(url), volume: 0.6);
  } catch (_) {}
}

/// Loads a Pokémon and shows its card in a sheet.
Future<void> showPokemon(BuildContext context, String nameOrId) => showAppSheet<void>(
  context,
  initialSize: 0.92,
  builder: (context, scroll) => FutureBuilder<Map<String, dynamic>>(
    future: PokemonApi.instance.info(nameOrId),
    builder: (context, snap) {
      if (snap.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2)),
          ),
        );
      }
      if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [PokemonCard(p: snap.data!)],
      );
    },
  ),
);

// ---- one Pokémon --------------------------------------------------------------------------

class PokemonCard extends StatefulWidget {
  const PokemonCard({super.key, required this.p});
  final Map<String, dynamic> p;

  @override
  State<PokemonCard> createState() => _PokemonCardState();
}

class _PokemonCardState extends State<PokemonCard> {
  bool _shiny = false;

  Map<String, dynamic> get p => widget.p;

  @override
  Widget build(BuildContext context) {
    final types = _strings(p['types']);
    final c1 = _typeColor(types.firstOrNull);
    final c2 = types.length > 1 ? _typeColor(types[1]) : Color.lerp(c1, Colors.black, 0.28)!;
    final stats = Map<String, dynamic>.from(p['stats'] as Map? ?? const {});
    final evolution = _maps(p['evolution']);
    final weak = _maps(p['weaknesses']);
    final resist = _maps(p['resistances']);
    final immune = _strings(p['immunities']);
    final abilities = _maps(p['abilities']);

    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(p: p, types: types, c1: c1, c2: c2, shiny: _shiny, onShiny: () => setState(() => _shiny = !_shiny)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ('${p['description'] ?? ''}'.isNotEmpty) ...[
                  Text(
                    '${p['description']}',
                    style: TextStyle(color: AppColors.text2, fontSize: 13.5, height: 1.45, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: Space.l),
                ],
                Row(
                  children: [
                    Expanded(child: _Fact('Height', '${p['height_m'] ?? '—'} m')),
                    const SizedBox(width: Space.s),
                    Expanded(child: _Fact('Weight', '${p['weight_kg'] ?? '—'} kg')),
                    const SizedBox(width: Space.s),
                    Expanded(child: _Fact('Gender', '${p['gender'] ?? '—'}')),
                  ],
                ),
                if (abilities.isNotEmpty) ...[
                  const SizedBox(height: Space.m),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in abilities)
                        _Chip(
                          a['hidden'] == true ? '${a['name']} · hidden' : '${a['name']}',
                          color: a['hidden'] == true ? AppColors.surface2 : c1.withValues(alpha: 0.16),
                          fg: AppColors.text,
                          border: a['hidden'] == true ? AppColors.line : c1.withValues(alpha: 0.45),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.xl),
                _SectionTitle('Base stats', trailing: 'Total ${p['total'] ?? ''}'),
                const SizedBox(height: Space.s),
                for (final s in const [
                  ('hp', 'HP'),
                  ('attack', 'Attack'),
                  ('defense', 'Defense'),
                  ('special_attack', 'Sp. Atk'),
                  ('special_defense', 'Sp. Def'),
                  ('speed', 'Speed'),
                ])
                  _StatRow(label: s.$2, value: (stats[s.$1] as num?)?.toInt() ?? 0, color: c1),
                if (weak.isNotEmpty) ...[
                  const SizedBox(height: Space.l),
                  const _SectionTitle('Weak to'),
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final w in weak) _TypeChip('${w['type']}', suffix: '×${_x(w['x'])}')],
                  ),
                ],
                if (resist.isNotEmpty || immune.isNotEmpty) ...[
                  const SizedBox(height: Space.m),
                  const _SectionTitle('Resists'),
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in immune) _TypeChip(t, suffix: '×0', faded: true),
                      for (final r in resist) _TypeChip('${r['type']}', suffix: '×${_x(r['x'])}', faded: true),
                    ],
                  ),
                ],
                if (evolution.length > 1) ...[
                  const SizedBox(height: Space.xl),
                  const _SectionTitle('Evolution'),
                  const SizedBox(height: Space.s),
                  _Evolution(chain: evolution, current: '${p['slug']}', dex: p['dex'], color: c1),
                ],
                const SizedBox(height: Space.l),
                Text(
                  [
                    'Gen ${p['generation']} · ${p['region']}',
                    if (p['habitat'] != null) p['habitat'],
                    if ((p['egg_groups'] as List?)?.isNotEmpty ?? false) 'Egg: ${_strings(p['egg_groups']).join(', ')}',
                    if (_strings(p['forms']).isNotEmpty) '${_strings(p['forms']).length} other form${_strings(p['forms']).length == 1 ? '' : 's'}',
                  ].join('  ·  '),
                  style: TextStyle(color: AppColors.text3, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _x(Object? v) {
    final d = (v as num?)?.toDouble() ?? 1;
    return d == 0.25 ? '¼' : d == 0.5 ? '½' : d.toStringAsFixed(0);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.p, required this.types, required this.c1, required this.c2, required this.shiny, required this.onShiny});
  final Map<String, dynamic> p;
  final List<String> types;
  final Color c1, c2;
  final bool shiny;
  final VoidCallback onShiny;

  @override
  Widget build(BuildContext context) {
    final fg = _on(c1);
    final art = shiny ? '${p['shiny_artwork'] ?? ''}' : '${p['artwork'] ?? ''}';
    final badge = p['mythical'] == true
        ? 'Mythical'
        : p['legendary'] == true
        ? 'Legendary'
        : p['baby'] == true
        ? 'Baby'
        : null;
    return SizedBox(
      height: 218,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(c1, Colors.white, 0.12)!, c1, c2],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
          // A big faint ball behind the artwork.
          Positioned(
            right: -46,
            top: -30,
            child: Icon(Icons.catching_pokemon, size: 250, color: Colors.white.withValues(alpha: 0.16)),
          ),
          Positioned(
            top: Space.m,
            right: Space.l,
            child: Text(
              _dexNo(p['dex'] ?? p['id']),
              style: TextStyle(color: fg.withValues(alpha: 0.55), fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.2),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child)),
              child: NetImage(
                art,
                key: ValueKey(art),
                width: 178,
                height: 178,
                fit: BoxFit.contain,
                errorWidget: const SizedBox(width: 178, height: 178),
              ),
            ),
          ),
          Positioned(
            left: Space.l,
            top: Space.l,
            bottom: Space.m,
            right: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      badge.toUpperCase(),
                      style: const TextStyle(color: Color(0xFFFFE08A), fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                  ),
                Text(
                  '${p['name']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 25, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -0.3),
                ),
                if (p['genus'] != null) ...[
                  const SizedBox(height: 3),
                  Text('${p['genus']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: 0.78), fontSize: 12.5)),
                ],
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final t in types)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: _typeColor(t),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
                        ),
                        child: Text(
                          t.toUpperCase(),
                          style: TextStyle(color: _on(_typeColor(t)), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    _RoundButton(icon: Icons.auto_awesome_rounded, fg: fg, active: shiny, tooltip: shiny ? 'Normal colours' : 'Shiny', onTap: onShiny),
                    if ('${p['cry'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(width: Space.s),
                      _RoundButton(icon: Icons.volume_up_rounded, fg: fg, tooltip: 'Play its cry', onTap: () => unawaited(_playCry('${p['cry']}'))),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.fg, required this.tooltip, required this.onTap, this.active = false});
  final IconData icon;
  final Color fg;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: active ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 17, color: active ? const Color(0xFFE0A100) : fg),
        ),
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: Column(
      children: [
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 1),
        Text(label, style: TextStyle(color: AppColors.text3, fontSize: 11)),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(text.toUpperCase(), style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const Spacer(),
      if (trailing != null) Text(trailing!, style: TextStyle(color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w700)),
    ],
  );
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3.5),
    child: Row(
      children: [
        SizedBox(width: 58, child: Text(label, style: TextStyle(color: AppColors.text2, fontSize: 12))),
        SizedBox(
          width: 32,
          child: Text('$value', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 7,
              color: AppColors.surface3,
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (value / 180).clamp(0.02, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, f, _) => FractionallySizedBox(
                  widthFactor: f,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(colors: [color.withValues(alpha: 0.75), color]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.color, required this.fg, required this.border});
  final String text;
  final Color color, fg, border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99), border: Border.all(color: border)),
    child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(this.type, {this.suffix, this.faded = false});
  final String type;
  final String? suffix;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final c = _typeColor(type);
    final fg = faded ? AppColors.text : _on(c);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 3, 4, 3),
      decoration: BoxDecoration(
        color: faded ? c.withValues(alpha: 0.14) : c,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: faded ? c.withValues(alpha: 0.5) : c),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titleCase(type), style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
          if (suffix != null) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: faded ? c.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(suffix!, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The evolution line as columns of stages, with how each one evolves.
class _Evolution extends StatelessWidget {
  const _Evolution({required this.chain, required this.current, required this.dex, required this.color});
  final List<Map<String, dynamic>> chain;
  final String current;
  final Object? dex;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final stages = <int, List<Map<String, dynamic>>>{};
    for (final e in chain) {
      (stages[(e['stage'] as num?)?.toInt() ?? 1] ??= []).add(e);
    }
    final keys = stages.keys.toList()..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final (i, k) in keys.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.text3, size: 20),
              ),
            // Many branches (Eevee) wrap three across instead of one tall column.
            if (stages[k]!.length > 3)
              SizedBox(width: 92 * 3, child: Wrap(children: [for (final e in stages[k]!) _evoMember(context, e)]))
            else
              Column(mainAxisSize: MainAxisSize.min, children: [for (final e in stages[k]!) _evoMember(context, e)]),
          ],
        ],
      ),
    );
  }

  Widget _evoMember(BuildContext context, Map<String, dynamic> e) {
    final me = e['slug'] == current || e['id'] == dex;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.m),
      onTap: me ? null : () => showPokemon(context, '${e['slug']}'),
      child: SizedBox(
        width: 92,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: me ? color.withValues(alpha: 0.18) : AppColors.surface2,
                  border: Border.all(color: me ? color : AppColors.line, width: me ? 2 : 1),
                ),
                child: NetImage('${e['artwork']}', fit: BoxFit.contain, errorWidget: const SizedBox.shrink()),
              ),
              const SizedBox(height: 4),
              Text(
                '${e['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: me ? FontWeight.w800 : FontWeight.w600),
              ),
              if ('${e['how'] ?? ''}'.isNotEmpty)
                Text(
                  '${e['how']}',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppColors.text3, height: 1.2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- search results -----------------------------------------------------------------------

class _PokemonGrid extends StatelessWidget {
  const _PokemonGrid({required this.pokemon});
  final List<Map<String, dynamic>> pokemon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s),
    child: LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 520 ? 4 : 3;
        const gap = Space.s;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final p in pokemon) SizedBox(width: w, child: _PokemonTile(p: p))],
        );
      },
    ),
  );
}

class _PokemonTile extends StatelessWidget {
  const _PokemonTile({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final types = _strings(p['types']);
    final c1 = _typeColor(types.firstOrNull);
    final c2 = types.length > 1 ? _typeColor(types[1]) : Color.lerp(c1, Colors.black, 0.25)!;
    final fg = _on(c1);
    return Material(
      borderRadius: BorderRadius.circular(Radii.l),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showPokemon(context, '${p['slug'] ?? p['id']}'),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
          ),
          child: AspectRatio(
            aspectRatio: 0.8,
            child: Stack(
              children: [
                Positioned(
                  right: -22,
                  top: -14,
                  child: Icon(Icons.catching_pokemon, size: 96, color: Colors.white.withValues(alpha: 0.16)),
                ),
                Positioned(
                  left: 8,
                  top: 6,
                  child: Text(
                    _dexNo(p['id']),
                    style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                  ),
                ),
                Positioned.fill(
                  top: 18,
                  bottom: 34,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: NetImage('${p['artwork']}', fit: BoxFit.contain, errorWidget: const SizedBox.shrink()),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          for (final t in types)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: _typeColor(t),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              types.map(titleCase).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 9.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
