import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/files/download_progress.dart' show formatBytes;
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../retro/retro_games.dart';
import '../../../web/web_fetch.dart';
import '../../domain/chat_models.dart';

/// Cards for retro game search, details and downloads, and the game sheet.
Widget? retroResultFor(ToolPart part, Map<String, dynamic> j) {
  if (!part.name.startsWith('retro_') || j['error'] != null) return null;
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'retro_games_search' => _SearchCard(data: j, games: list(j['games'])),
    'retro_game_details' => _GameHero(game: j),
    'retro_game_download' when j['file_path'] != null => _DownloadedCard(data: j),
    _ => null,
  };
}

/// Each system's colour, as the consoles were known.
Color _systemColor(String? s) => switch (s) {
  'gb' => const Color(0xFF8BAC0F),
  'gbc' => const Color(0xFF00B5AD),
  'gba' => const Color(0xFF6C5CE7),
  'nes' => const Color(0xFFE17055),
  'snes' => const Color(0xFF8E7CC3),
  'genesis' => const Color(0xFF0984E3),
  'sms' => const Color(0xFF636E72),
  'gg' => const Color(0xFF00897B),
  'doom' => const Color(0xFFD63031),
  _ => const Color(0xFF9CA3AF),
};

String _short(String? s) => switch (s) {
  'gb' => 'GB',
  'gbc' => 'GBC',
  'gba' => 'GBA',
  'nes' => 'NES',
  'sms' => 'SMS',
  'gg' => 'GG',
  'doom' => 'DOOM',
  _ => (s ?? '').toUpperCase(),
};

class _SystemPill extends StatelessWidget {
  const _SystemPill(this.system, {this.label});
  final String? system;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = _systemColor(system);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5)),
      child: Text(label ?? _short(system), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
    );
  }
}

/// A game's picture, scaled without smoothing so pixel art stays crisp;
/// Doom packs, which come without pictures, get a title card.
class _Art extends StatelessWidget {
  const _Art({required this.game, this.url, this.fit = BoxFit.cover});
  final Map<String, dynamic> game;
  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final src = url ?? game['image'] as String?;
    final c = _systemColor(game['system'] as String?);
    final fallback = Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withValues(alpha: 0.85), Colors.black])),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Space.s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(game['system'] == 'doom' ? Icons.local_fire_department_rounded : Icons.videogame_asset_rounded, color: Colors.white.withValues(alpha: 0.9), size: 26),
          const SizedBox(height: 4),
          Text(
            '${game['title'] ?? ''}',
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, height: 1.15),
          ),
        ],
      ),
    );
    if (src == null || src.isEmpty) return fallback;
    return Container(
      color: Colors.black,
      child: Image.network(
        src,
        fit: fit,
        filterQuality: FilterQuality.none,
        gaplessPlayback: true,
        loadingBuilder: (context, child, p) => p == null ? child : const Skeleton(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

void _openGame(BuildContext context, Map<String, dynamic> game) => showAppSheet<void>(
  context,
  initialSize: 0.92,
  builder: (context, scroll) => _GameSheet(game: game, scroll: scroll),
);

// ---- search -------------------------------------------------------------------------

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.data, required this.games});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> games;

  @override
  Widget build(BuildContext context) {
    final q = '${data['query'] ?? ''}'.trim();
    final stores = {for (final g in games) '${g['store_name']}'};
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(Radii.s + 2)),
                  child: Icon(Icons.sports_esports_rounded, size: 18, color: AppColors.bg),
                ),
                const SizedBox(width: Space.s + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.isEmpty ? 'Retro games to play' : 'Retro games for "$q"', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${data['total']} free · ${stores.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (games.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              child: Text('Nothing matches in these stores.', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: _Grid(games: games.take(6).toList()),
            ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            padding: const EdgeInsets.fromLTRB(Space.s, 2, 0, 2),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(alignment: Alignment.centerLeft, visualDensity: VisualDensity.compact, foregroundColor: AppColors.text2),
                    onPressed: data['pdroms'] == null ? null : () => launchUrl(Uri.parse('${data['pdroms']}'), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.travel_explore_rounded, size: 15),
                    label: const Text('Also on PDRoms'),
                  ),
                ),
                if (games.length > 6)
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text),
                    onPressed: () => showAppSheet<void>(
                      context,
                      initialSize: 0.92,
                      builder: (context, scroll) => ListView(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
                        children: [
                          Text(q.isEmpty ? 'Retro games' : '"$q"', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: Space.m),
                          _Grid(games: games),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.grid_view_rounded, size: 16),
                    label: Text('All ${games.length}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.games});
  final List<Map<String, dynamic>> games;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, mainAxisSpacing: Space.s, crossAxisSpacing: Space.s, childAspectRatio: 0.74),
    itemCount: games.length,
    itemBuilder: (context, i) => _Tile(game: games[i]),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.game});
  final Map<String, dynamic> game;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m), side: BorderSide(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _openGame(context, game),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Art(game: game),
                Positioned(left: 6, top: 6, child: _SystemPill(game['system'] as String?)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, 6, Space.s, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${game['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  ['${game['author'] ?? ''}', '${game['store_name'] ?? ''}'].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ---- details --------------------------------------------------------------------------

class _GameHero extends StatelessWidget {
  const _GameHero({required this.game});
  final Map<String, dynamic> game;

  @override
  Widget build(BuildContext context) {
    final shots = [for (final s in (game['screenshots'] as List? ?? const [])) '$s'];
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l), side: BorderSide(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openGame(context, game),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Art(game: game, url: shots.firstOrNull, fit: BoxFit.contain),
                  Positioned(left: Space.s, top: Space.s, child: _SystemPill(game['system'] as String?, label: game['system_name'] as String?)),
                  if (shots.length > 1)
                    Positioned(
                      right: Space.s,
                      bottom: Space.s,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(20)),
                        child: Text('${shots.length} screenshots', style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${game['title']}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(['${game['author'] ?? ''}', '${game['store_name'] ?? ''}'].where((s) => s.isNotEmpty).join(' · '), style: context.text.labelMedium?.copyWith(color: AppColors.text3)),
                  if ('${game['description'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: Space.s),
                    Text('${game['description']}', maxLines: 4, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.4)),
                  ],
                  const SizedBox(height: Space.s),
                  _FactPills(facts: Map<String, dynamic>.from((game['facts'] as Map?) ?? const {})),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              padding: const EdgeInsets.fromLTRB(Space.s, 2, 0, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: Space.s),
                      child: Text(game['download'] == null ? 'No direct download' : 'Free download · ${game['file'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text),
                    onPressed: () => _openGame(context, game),
                    icon: const Icon(Icons.info_outline_rounded, size: 16),
                    label: const Text('Details'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactPills extends StatelessWidget {
  const _FactPills({required this.facts});
  final Map<String, dynamic> facts;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final k in const ['Released', 'License', 'Type', 'Size', 'Engine'])
        if ('${facts[k] ?? ''}'.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
            child: Text('${facts[k]}'.length > 28 ? '${'${facts[k]}'.substring(0, 28)}…' : '${facts[k]}', style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
    ],
  );
}

class _DownloadedCard extends StatelessWidget {
  const _DownloadedCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final path = '${data['file_path']}';
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(Radii.m), child: SizedBox(width: 64, height: 64, child: _Art(game: data))),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _SystemPill(data['system'] as String?),
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded, size: 15, color: AppColors.success),
                          const SizedBox(width: 3),
                          Text('Downloaded', style: context.text.labelSmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${data['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text('${data['name']} · ${data['size']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (data['play_with'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: Text('Play it with ${data['play_with']}.', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
            ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            padding: const EdgeInsets.fromLTRB(Space.s, 2, 0, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: path));
                    showSnack(context, 'Path copied');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy path'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text),
                  onPressed: File(path).existsSync() ? () => OpenFilex.open(path) : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Open'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- the sheet ------------------------------------------------------------------------

/// Everything about one game: its screenshots full width (tap for full
/// screen), who made it and where it's from, every fact, the description,
/// links, and a download that runs right here.
class _GameSheet extends StatefulWidget {
  const _GameSheet({required this.game, required this.scroll});
  final Map<String, dynamic> game;
  final ScrollController scroll;

  @override
  State<_GameSheet> createState() => _GameSheetState();
}

class _GameSheetState extends State<_GameSheet> {
  late Map<String, dynamic> _g = widget.game;
  bool _loading = false;
  String? _error;
  int _shot = 0;
  double? _progress;
  String? _saved;

  @override
  void initState() {
    super.initState();
    if (_g['facts'] == null) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await RetroGames().details('${_g['store']}', '${_g['id']}');
      if (mounted) setState(() => _g = {..._g, ...d});
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final url = _g['download'] as String?;
    if (url == null) return;
    setState(() => _progress = 0);
    try {
      final file = await WebFetcher().download(Uri.parse(url), name: '${_g['file'] ?? url.split('/').last}');
      if (mounted) {
        setState(() {
          _saved = file.path;
          _progress = null;
        });
        showSnack(context, 'Saved to Files: ${formatBytes(await file.length())}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _progress = null);
        showSnack(context, 'Download failed: $e');
      }
    }
  }

  void _fullScreen(List<String> shots, int at) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text('${_g['title']}')),
        body: PageView(
          controller: PageController(initialPage: at),
          children: [
            for (final s in shots) InteractiveViewer(maxScale: 8, child: Center(child: Image.network(s, filterQuality: FilterQuality.none, fit: BoxFit.contain, width: double.infinity))),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final shots = [for (final s in (g['screenshots'] as List? ?? const [])) '$s'];
    if (shots.isEmpty && g['image'] != null) shots.add('${g['image']}');
    final facts = Map<String, dynamic>.from((g['facts'] as Map?) ?? const {});
    final links = [for (final l in (g['links'] as List? ?? const [])) '$l'];
    final system = g['system'] as String?;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        // Screenshots, edge to edge, swiped through.
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (shots.isEmpty)
                _Art(game: g)
              else
                PageView.builder(
                  itemCount: shots.length,
                  onPageChanged: (i) => setState(() => _shot = i),
                  itemBuilder: (context, i) => GestureDetector(onTap: () => _fullScreen(shots, i), child: _Art(game: g, url: shots[i], fit: BoxFit.contain)),
                ),
              if (shots.length > 1)
                Positioned(
                  bottom: Space.s,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < shots.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _shot ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == _shot ? 0.95 : 0.45), borderRadius: BorderRadius.circular(3)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _SystemPill(system, label: g['system_name'] as String?),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(5), border: Border.all(color: AppColors.line)),
                    child: Text('${g['store_name'] ?? ''}', style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if ('${g['kind'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(child: Text('${g['kind']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3))),
                  ],
                ],
              ),
              const SizedBox(height: Space.s),
              Text('${g['title']}', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w900, height: 1.15)),
              if ('${g['author'] ?? ''}'.isNotEmpty) Text('by ${g['author']}', style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
              const SizedBox(height: Space.l),
              // The main action: get the game.
              if (_loading)
                const LinearProgressIndicator(minHeight: 2)
              else if (_saved != null)
                FilledButton.icon(onPressed: () => OpenFilex.open(_saved!), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Open the download'))
              else if (_progress != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const LinearProgressIndicator(minHeight: 6),
                    const SizedBox(height: 4),
                    Text('Downloading ${g['file'] ?? ''}…', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                  ],
                )
              else if (g['download'] != null)
                FilledButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download_rounded),
                  label: Text('Download free${'${facts['Size'] ?? g['size'] ?? ''}'.isEmpty ? '' : ' · ${facts['Size'] ?? g['size']}'}'),
                )
              else if (_error == null)
                Text('${g['note'] ?? 'No direct download. Ask the assistant to download it, or open its page.'}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
              if (_error != null) Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
              if (RetroGames.playWith[system] != null) ...[
                const SizedBox(height: Space.s),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.gamepad_outlined, size: 16, color: AppColors.text3),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Plays in ${RetroGames.playWith[system]}', style: context.text.bodySmall?.copyWith(color: AppColors.text3, height: 1.35))),
                  ],
                ),
              ],
              if ('${g['description'] ?? g['about'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: Space.xl),
                Text('ABOUT', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
                const SizedBox(height: Space.s),
                SelectableText('${g['description'] ?? g['about']}', style: context.text.bodyMedium?.copyWith(height: 1.5)),
              ],
              if (g['tags'] is List && (g['tags'] as List).isNotEmpty) ...[
                const SizedBox(height: Space.m),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final t in g['tags'] as List) Chip(label: Text('$t'), visualDensity: VisualDensity.compact)]),
              ],
              if (facts.isNotEmpty) ...[
                const SizedBox(height: Space.xl),
                Text('DETAILS', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
                const SizedBox(height: Space.s),
                Container(
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
                  child: Column(
                    children: [
                      for (final (i, e) in facts.entries.where((e) => '${e.value}'.isNotEmpty).indexed) ...[
                        if (i > 0) Divider(height: 1, indent: Space.l, endIndent: Space.l, color: AppColors.line),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s + 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 100, child: Text(e.key, style: context.text.bodySmall?.copyWith(color: AppColors.text3))),
                              Expanded(child: Text('${e.value}', style: context.text.bodyMedium)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Space.l),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  if (g['page'] != null)
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse('${g['page']}'), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text('Open on ${g['store_name'] ?? 'the store'}'),
                    ),
                  for (final l in links.take(3))
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(l), mode: LaunchMode.externalApplication),
                      icon: Icon(l.contains('github.com') ? Icons.code_rounded : Icons.link_rounded, size: 16),
                      label: Text(Uri.tryParse(l)?.host.replaceFirst('www.', '') ?? l),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
