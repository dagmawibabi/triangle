import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../account/storage_screen.dart';
import '../../account/widgets.dart';
import '../../telegram/data/file_loader.dart' show formatBytes;
import '../data/cache_manager.dart';

/// Settings → Cache: what the app keeps only to be quicker or work offline,
/// by kind, with a way to clear each one or all of it.
class CacheScreen extends ConsumerStatefulWidget {
  const CacheScreen({super.key});

  @override
  ConsumerState<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends ConsumerState<CacheScreen> {
  late Future<List<CacheKind>> _kinds = ref.read(appCacheProvider).measure();

  /// The kind being cleared ('all' for everything).
  String? _clearing;

  void _reload() => setState(() => _kinds = ref.read(appCacheProvider).measure());

  String _percent(int part, int whole) {
    if (whole <= 0) return '';
    final p = part * 100 / whole;
    return p < 1 ? '<1%' : '${p.round()}%';
  }

  Future<void> _clear(CacheKind? k, int total) async {
    final ok = await confirm(
      context,
      title: k == null ? 'Clear every cache?' : 'Clear ${k.label.toLowerCase()}?',
      body: k == null
          ? 'About ${formatBytes(total)} is freed. Everything downloads again as you use it, so things may load slower for a while. Your downloads, followed shows, playlists, books and chats aren\'t touched.'
          : '${k.detail}\n\nAbout ${formatBytes(k.bytes)} is freed.',
      action: 'Clear',
      danger: k == null,
    );
    if (!ok || !mounted) return;
    setState(() => _clearing = k?.id ?? 'all');
    try {
      final actions = ref.read(appCacheProvider);
      final freed = k == null ? await actions.clearAll() : await actions.clear(k.id);
      if (mounted) showSnack(context, freed > 0 ? 'Freed ${formatBytes(freed)}' : 'Cleared');
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t clear: $e', icon: Icons.error_outline_rounded);
    }
    if (!mounted) return;
    setState(() => _clearing = null);
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cache'),
      actions: [IconButton(tooltip: 'Count again', onPressed: _clearing == null ? _reload : null, icon: const Icon(Icons.refresh_rounded))],
    ),
    body: FutureBuilder<List<CacheKind>>(
      future: _kinds,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState('Couldn\'t measure the cache.\n${snap.error}', onRetry: _reload);
        final kinds = snap.data;
        if (_clearing == 'all') return const LoadingState('Clearing…');
        if (kinds == null) return const LoadingState('Measuring…');
        final shown = kinds.where((k) => k.bytes > 0).toList();
        final total = kinds.fold<int>(0, (a, k) => a + k.bytes);
        final files = kinds.fold<int>(0, (a, k) => a + k.files);
        final biggest = shown.isEmpty ? 0 : shown.first.bytes;
        final appOnly = kinds.where((k) => k.id != 'telegram').fold<int>(0, (a, k) => a + k.bytes);
        final number = NumberFormat.decimalPattern();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
            children: [
              Group(
                padded: true,
                children: [
                  Row(
                    children: [
                      Ring(
                        size: 128,
                        stroke: 13,
                        parts: [for (final k in shown) (k.bytes.toDouble(), k.color)],
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatBytes(total), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                            Text('cached', style: context.text.labelSmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.l),
                      Expanded(
                        child: shown.isEmpty
                            ? Text('Nothing cached right now.', style: context.text.bodySmall)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final k in shown.take(5)) LegendRow(color: k.color, label: k.label, value: _percent(k.bytes, total)),
                                  if (shown.length > 5)
                                    LegendRow(color: AppColors.text3, label: '${shown.length - 5} more', value: _percent(shown.skip(5).fold<int>(0, (a, k) => a + k.bytes), total)),
                                ],
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.l),
                  // Every kind side by side, to scale.
                  if (total > 0) _Stacked(kinds: shown, total: total),
                  const SizedBox(height: Space.l),
                  StatStrip(
                    stats: [
                      (number.format(files), 'files'),
                      (formatBytes(appOnly), 'Triangle'),
                      (formatBytes(total - appOnly), 'Telegram'),
                    ],
                  ),
                ],
              ),
              Group(
                label: 'Free up space',
                children: [
                  Tile(
                    leading: IconBadge(Icons.delete_sweep_outlined, color: AppColors.danger),
                    title: 'Clear every cache',
                    titleColor: AppColors.danger,
                    subtitle: '${formatBytes(total)} back; things load again as you use them',
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: _clearing != null || total == 0 ? null : () => _clear(null, total),
                  ),
                  Tile(
                    leading: const IconBadge(Icons.storage_rounded),
                    title: 'Telegram storage in detail',
                    subtitle: 'By kind and by chat, or only older files',
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StorageScreen()));
                      if (mounted) _reload();
                    },
                  ),
                ],
              ),
              Group(
                label: 'By kind',
                children: [
                  for (final k in kinds)
                    Tile(
                      leading: IconBadge(k.icon, color: k.color),
                      title: k.label,
                      subtitle: k.detail,
                      below: Meter(value: k.bytes.toDouble(), max: biggest <= 0 ? 1 : biggest.toDouble(), color: k.color),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Figure(formatBytes(k.bytes), color: AppColors.text, bold: true),
                              Figure(k.files > 0 ? '${number.format(k.files)} ${k.id == 'images' ? 'pictures' : 'files'}' : _percent(k.bytes, total)),
                            ],
                          ),
                          // The same slot on every row keeps the figures lined up.
                          SizedBox(
                            width: 40,
                            child: _clearing == k.id
                                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                : IconButton(
                                    tooltip: 'Clear ${k.label.toLowerCase()}',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.cleaning_services_outlined, size: 19, color: k.bytes > 0 ? AppColors.text2 : AppColors.text3.withValues(alpha: 0.4)),
                                    onPressed: _clearing != null || k.bytes == 0 ? null : () => _clear(k, total),
                                  ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.l),
              Text(
                'Clearing the cache never deletes your downloads, followed shows, playlists, books, notes or chats.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// One bar split by kind, each part as wide as its share.
class _Stacked extends StatelessWidget {
  const _Stacked({required this.kinds, required this.total});
  final List<CacheKind> kinds;
  final int total;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: SizedBox(
      height: 10,
      child: Row(
        children: [
          for (final (i, k) in kinds.indexed)
            Expanded(
              // At least a sliver, so tiny kinds still show.
              flex: (k.bytes * 1000 / total).round().clamp(4, 1000),
              child: Container(
                margin: EdgeInsets.only(right: i == kinds.length - 1 ? 0 : 2),
                color: k.color,
              ),
            ),
        ],
      ),
    ),
  );
}
