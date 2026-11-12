import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../infrastructure/telegram/telegram_client.dart';
import '../chat/presentation/generated_files_screen.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/data/telegram_tools.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'widgets.dart';

/// Telegram's footprint on this phone: what its cached files take, by kind
/// and by chat, with ways to free space; Triangle's own files; and the data
/// used, on mobile and Wi-Fi.
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Storage & data'),
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.sd_storage_outlined, size: 20), text: 'Storage'),
            Tab(icon: Icon(Icons.swap_vert_rounded, size: 20), text: 'Data use'),
          ],
        ),
      ),
      body: const TabBarView(children: [_Storage(), _Data()]),
    ),
  );
}

/// How each kind of file is shown: name, icon, colour.
const _kinds = <String, (String, IconData, Color)>{
  'photos': ('Photos', Icons.photo_outlined, Color(0xFF8AB4FF)),
  'videos': ('Videos', Icons.videocam_outlined, Color(0xFFB69CFF)),
  'files': ('Files', Icons.insert_drive_file_outlined, Color(0xFF6FCF97)),
  'music': ('Music', Icons.music_note_outlined, Color(0xFFF2C46D)),
  'voice': ('Voice messages', Icons.mic_none_rounded, Color(0xFFFF9B85)),
  'video_messages': ('Video messages', Icons.radio_button_checked_rounded, Color(0xFF7FD6E8)),
  'gifs': ('GIFs', Icons.gif_box_outlined, Color(0xFFE88FCF)),
  'stickers': ('Stickers', Icons.emoji_emotions_outlined, Color(0xFFFFC48A)),
  'profile_photos': ('Profile photos', Icons.account_circle_outlined, Color(0xFF9FD8A4)),
  'thumbnails': ('Thumbnails', Icons.image_aspect_ratio_outlined, Color(0xFFB0B6C3)),
  'wallpapers': ('Wallpapers', Icons.wallpaper_outlined, Color(0xFFC9A7FF)),
  'other': ('Other', Icons.category_outlined, Color(0xFF8E939E)),
  'messages': ('Messages', Icons.chat_bubble_outline_rounded, Color(0xFF8AB4FF)),
  'calls': ('Calls', Icons.call_outlined, Color(0xFF6FCF97)),
};

(String, IconData, Color) _kind(String k) => _kinds[k] ?? (k, Icons.category_outlined, const Color(0xFF8E939E));

String _percent(int part, int whole) {
  if (whole <= 0) return '';
  final p = part * 100 / whole;
  return p < 1 ? '<1%' : '${p.round()}%';
}

/// The space Triangle's own files take (generated, sandbox, downloads,
/// exports, screenshots), outside Telegram's cache.
Future<int> _appFilesSize() async {
  final root = (await getApplicationSupportDirectory()).path;
  var total = 0;
  for (final d in ['generated', 'sandbox', 'downloads', 'telegram', 'exports', 'screenshots', 'voice_notes', 'attachments']) {
    final dir = Directory('$root/$d');
    if (!await dir.exists()) continue;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
  }
  return total;
}

class _Storage extends ConsumerStatefulWidget {
  const _Storage();

  @override
  ConsumerState<_Storage> createState() => _StorageState();
}

class _StorageState extends ConsumerState<_Storage> with AutomaticKeepAliveClientMixin {
  late Future<(td.StorageStatisticsFast, td.StorageStatistics)> _stats = ref.read(toolRunnerProvider).storage(chats: 25);
  late Future<int> _appFiles = _appFilesSize();
  bool _cleaning = false;

  @override
  bool get wantKeepAlive => true;

  void _reload() => setState(() {
    _stats = ref.read(toolRunnerProvider).storage(chats: 25);
    _appFiles = _appFilesSize();
  });

  Future<void> _clean({int? olderThanDays, List<String> kinds = const [], List<int> chats = const [], required String what}) async {
    final ok = await confirm(
      context,
      title: 'Clear cached files?',
      body: '$what will be removed from this phone. Nothing is deleted from Telegram: it downloads again when you open it.',
      action: 'Clear',
    );
    if (!ok) return;
    setState(() => _cleaning = true);
    try {
      final freed = await ref.read(toolRunnerProvider).cleanCache(olderThanDays: olderThanDays, kinds: kinds, chatIds: chats);
      if (mounted) showSnack(context, 'Freed ${formatBytes(freed.size)}');
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t clear: $e', icon: Icons.error_outline_rounded);
    }
    if (mounted) setState(() => _cleaning = false);
    _reload();
  }

  Widget _clearButton(String tooltip, VoidCallback onPressed) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    icon: Icon(Icons.cleaning_services_outlined, size: 19, color: AppColors.text2),
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = ref.watch(telegramStoreProvider);
    return FutureBuilder<(td.StorageStatisticsFast, td.StorageStatistics)>(
      future: _stats,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState('Couldn\'t read storage.\n${snap.error}', onRetry: _reload);
        final data = snap.data;
        if (data == null || _cleaning) return LoadingState(_cleaning ? 'Clearing…' : 'Counting files…');
        final (fast, full) = data;
        final byKind = <String, int>{};
        for (final c in full.byChat) {
          for (final t in c.byFileType) {
            byKind.update(MoreTdTools.fileTypeName(t.fileType), (v) => v + t.size, ifAbsent: () => t.size);
          }
        }
        final kinds = byKind.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
        final total = kinds.fold<int>(0, (a, e) => a + e.value);
        final chats = full.byChat.where((c) => c.chatId != 0 && c.size > 0).toList();
        final biggest = chats.isEmpty ? 0 : chats.first.size;
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
                        parts: [for (final e in kinds) (e.value.toDouble(), _kind(e.key).$3)],
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatBytes(fast.filesSize),
                              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
                            ),
                            Text('Telegram cache', style: context.text.labelSmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.l),
                      Expanded(
                        child: kinds.isEmpty
                            ? Text('Nothing cached yet.', style: context.text.bodySmall)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final e in kinds.take(5))
                                    LegendRow(color: _kind(e.key).$3, label: _kind(e.key).$1, value: _percent(e.value, total)),
                                  if (kinds.length > 5)
                                    LegendRow(
                                      color: AppColors.text3,
                                      label: '${kinds.length - 5} more',
                                      value: _percent(kinds.skip(5).fold<int>(0, (a, e) => a + e.value), total),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.l),
                  StatStrip(
                    stats: [
                      (number.format(fast.fileCount), 'files'),
                      (formatBytes(fast.databaseSize), 'database'),
                      (formatBytes(fast.logSize), 'logs'),
                    ],
                  ),
                ],
              ),
              Group(
                label: 'Free up space',
                children: [
                  Tile(
                    leading: const IconBadge(Icons.history_toggle_off_rounded),
                    title: 'Older than a week',
                    subtitle: 'Keeps what you opened recently',
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () => _clean(olderThanDays: 7, what: 'Files you haven\'t opened for a week'),
                  ),
                  Tile(
                    leading: const IconBadge(Icons.calendar_month_outlined),
                    title: 'Older than a month',
                    subtitle: 'The gentle option',
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () => _clean(olderThanDays: 30, what: 'Files you haven\'t opened for a month'),
                  ),
                  Tile(
                    leading: IconBadge(Icons.delete_sweep_outlined, color: AppColors.danger),
                    title: 'Clear the whole cache',
                    titleColor: AppColors.danger,
                    subtitle: '${formatBytes(fast.filesSize)} back; everything downloads again when opened',
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () => _clean(what: 'Every cached file'),
                  ),
                ],
              ),
              Group(
                label: 'By kind',
                children: [
                  if (kinds.isEmpty)
                    const Tile(leading: IconBadge(Icons.inbox_outlined), title: 'Nothing cached yet'),
                  for (final e in kinds)
                    Tile(
                      leading: IconBadge(_kind(e.key).$2, color: _kind(e.key).$3),
                      title: _kind(e.key).$1,
                      below: Meter(value: e.value.toDouble(), max: total.toDouble(), color: _kind(e.key).$3),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Figure(formatBytes(e.value), color: AppColors.text, bold: true),
                              Figure(_percent(e.value, total)),
                            ],
                          ),
                          // The same slot on every row keeps the figures lined up.
                          SizedBox(
                            width: 40,
                            child: MoreTdTools.fileTypesFor(e.key).isEmpty
                                ? null
                                : _clearButton(
                                    'Clear ${_kind(e.key).$1.toLowerCase()}',
                                    () => _clean(kinds: [e.key], what: 'All cached ${_kind(e.key).$1.toLowerCase()}'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (chats.isNotEmpty)
                Group(
                  label: 'Biggest chats',
                  children: [
                    for (final c in chats)
                      Tile(
                        leading: TgAvatar(chatId: c.chatId, title: store.chat(c.chatId)?.title ?? '?', size: 36),
                        title: store.chat(c.chatId)?.title ?? 'Chat ${c.chatId}',
                        below: Meter(value: c.size.toDouble(), max: biggest.toDouble(), color: AppColors.accent),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Figure(formatBytes(c.size), color: AppColors.text, bold: true),
                            SizedBox(
                              width: 40,
                              child: _clearButton(
                                'Clear this chat\'s files',
                                () => _clean(chats: [c.chatId], what: 'Cached files from ${store.chat(c.chatId)?.title ?? 'this chat'}'),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              Group(
                label: 'Triangle\'s own files',
                children: [
                  FutureBuilder<int>(
                    future: _appFiles,
                    builder: (context, s) => Tile(
                      leading: const IconBadge(Icons.folder_copy_outlined, color: Color(0xFF7FD6E8)),
                      title: 'Files',
                      subtitle: 'Generated images and audio, code output, downloads and exports',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Figure(s.data == null ? '…' : formatBytes(s.data!), color: AppColors.text, bold: true),
                          SizedBox(width: 40, child: Icon(Icons.chevron_right_rounded, color: AppColors.text3)),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GeneratedFilesScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              Text(
                'Tip: ask the assistant "free up space from channels I don\'t read" and it will pick what to clear.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---- data use -----------------------------------------------------------------

class _Data extends ConsumerStatefulWidget {
  const _Data();

  @override
  ConsumerState<_Data> createState() => _DataState();
}

class _DataState extends ConsumerState<_Data> with AutomaticKeepAliveClientMixin {
  late Future<td.NetworkStatistics> _stats = ref.read(toolRunnerProvider).networkStats();

  @override
  bool get wantKeepAlive => true;

  static const _nets = <String, (String, IconData, Color)>{
    'mobile': ('Mobile data', Icons.signal_cellular_alt_rounded, Color(0xFFF2C46D)),
    'wifi': ('Wi-Fi', Icons.wifi_rounded, Color(0xFF8AB4FF)),
    'roaming': ('Roaming', Icons.public_rounded, Color(0xFFFF9B85)),
    'other': ('Other', Icons.device_hub_rounded, Color(0xFFB0B6C3)),
  };

  void _reload() => setState(() => _stats = ref.read(toolRunnerProvider).networkStats());

  Future<void> _reset() async {
    final ok = await confirm(context, title: 'Reset the counters?', body: 'Data use starts counting again from now.', action: 'Reset');
    if (!ok) return;
    await ref.read(telegramClientProvider).send<td.Ok>(const td.ResetNetworkStatistics());
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<td.NetworkStatistics>(
      future: _stats,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState('Couldn\'t read data use.\n${snap.error}', onRetry: _reload);
        final s = snap.data;
        if (s == null) return const LoadingState('Reading data use…');
        final table = MoreTdTools.usageTable(s);
        int sent(Map<String, (int, int)> rows) => rows.values.fold<int>(0, (a, b) => a + b.$1);
        int received(Map<String, (int, int)> rows) => rows.values.fold<int>(0, (a, b) => a + b.$2);
        int sum(Map<String, (int, int)> rows) => sent(rows) + received(rows);
        final totals = {for (final e in table.entries) e.key: sum(e.value)};
        final all = totals.values.fold<int>(0, (a, b) => a + b);
        final up = table.values.fold<int>(0, (a, r) => a + sent(r));
        final down = table.values.fold<int>(0, (a, r) => a + received(r));
        final since = DateFormat('d MMM y').format(DateTime.fromMillisecondsSinceEpoch(s.sinceDate * 1000));
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
                        size: 120,
                        stroke: 12,
                        parts: [
                          for (final n in _nets.keys)
                            if ((totals[n] ?? 0) > 0) ((totals[n] ?? 0).toDouble(), _nets[n]!.$3),
                        ],
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatBytes(all),
                              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
                            ),
                            Text('in total', style: context.text.labelSmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.l),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final n in _nets.keys)
                              if ((totals[n] ?? 0) > 0) LegendRow(color: _nets[n]!.$3, label: _nets[n]!.$1, value: formatBytes(totals[n]!)),
                            if (all == 0) Text('Nothing used yet.', style: context.text.bodySmall),
                            const SizedBox(height: Space.xs),
                            Text('Since $since', style: context.text.labelSmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.l),
                  StatStrip(stats: [('↑ ${formatBytes(up)}', 'sent'), ('↓ ${formatBytes(down)}', 'received')]),
                ],
              ),
              for (final n in _nets.keys)
                if (table[n] case final rows? when sum(rows) > 0)
                  Group(
                    label: _nets[n]!.$1,
                    trailing: Text(formatBytes(sum(rows)), style: context.text.labelSmall),
                    children: [
                      // Column headings over the figures.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(64, Space.s, Space.m, 0),
                        child: Row(
                          children: [
                            const Spacer(),
                            Figure('Sent', color: AppColors.text3),
                            Figure('Received', color: AppColors.text3),
                          ],
                        ),
                      ),
                      for (final r in (rows.entries.where((r) => r.value.$1 + r.value.$2 > 0).toList()
                        ..sort((a, b) => (b.value.$1 + b.value.$2).compareTo(a.value.$1 + a.value.$2))))
                        Tile(
                          leading: IconBadge(_kind(r.key).$2, color: _kind(r.key).$3, size: 32),
                          title: _kind(r.key).$1,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [Figure(formatBytes(r.value.$1)), Figure(formatBytes(r.value.$2), color: AppColors.text)],
                          ),
                        ),
                    ],
                  ),
              const SizedBox(height: Space.l),
              Center(
                child: TextButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Reset counters')),
              ),
            ],
          ),
        );
      },
    );
  }
}
