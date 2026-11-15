import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/fullscreen_image.dart';
import '../sections/section_kit.dart' show BottomAudioBar, showFieldsSheet, SheetField;
import 'music_stats_screen.dart';
import '../auth/data/auth_controller.dart';
import '../development/manage/manage_kit.dart' show HeroStat;
import '../media/audio_center.dart';
import '../telegram/presentation/chat_view_screen.dart';
import 'add_tracks_screen.dart';
import 'playlist_sources.dart';
import 'playlist_widgets.dart';
import 'playlists.dart';

/// Every playlist under a header in the colours of what's playing, with
/// stats, quick ways in, and the playlists as covers or as rich rows.
class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlaylistsScreen()));

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = ref.read(playlistsProvider.notifier);
      await store.ready;
      if (!mounted) return;
      for (final p in ref.read(playlistsProvider).playlists) {
        precachePlaylist(context, p);
      }
      unawaited(store.ensureArt());
    });
  }

  Future<void> _new() async {
    final p = await showPlaylistEditor(context, ref);
    if (p != null && mounted) _openPlaylist(context, p);
  }

  Future<void> _import() => importPlaylistFlow(context, ref);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(playlistsProvider);
    final store = ref.read(playlistsProvider.notifier);
    final a = ref.watch(audioCenterProvider);
    final lists = s.sorted;
    final tracks = lists.fold<int>(0, (n, p) => n + p.tracks.length);
    final seconds = lists.fold<int>(0, (n, p) => n + p.seconds);
    final chats = {for (final p in lists) for (final t in p.tracks) if (t.chatId != null) t.chatId};
    final telegram = ref.watch(telegramConnectedProvider);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 900 ? 4 : (width > 600 ? 3 : 2);
    final playingList = a.queueTag == null ? null : lists.where((p) => p.id == a.queueTag).firstOrNull;
    // The header takes the colours of what's playing.
    final base = playingList?.colors ?? const [Color(0xFF6D28D9), Color(0xFF1E1B4B)];
    final header = [Color.lerp(base.first, Colors.black, 0.35)!, Color.lerp(base.last, Colors.black, 0.78)!];
    final custom = s.sort == PlaylistSort.custom;

    return Scaffold(
      bottomNavigationBar: const BottomAudioBar(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 236,
            backgroundColor: header.last,
            foregroundColor: Colors.white,
            titleSpacing: 0,
            title: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    gradient: LinearGradient(colors: [base.first, Color.lerp(base.first, Colors.white, 0.25)!]),
                  ),
                  child: const Icon(Icons.queue_music_rounded, size: 18, color: Colors.white),
                ),
                const SizedBox(width: Space.s),
                const Text('Playlists', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Listening stats',
                icon: const Icon(Icons.insights_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MusicStatsScreen())),
              ),
              IconButton(tooltip: 'Import a playlist file', icon: const Icon(Icons.file_download_outlined), onPressed: _import),
              PopupMenuButton<Object>(
                tooltip: 'Sort and view',
                icon: const Icon(Icons.tune_rounded),
                onSelected: (v) => v is PlaylistSort ? store.setSort(v) : store.setGrid(!s.grid),
                itemBuilder: (_) => [
                  for (final o in PlaylistSort.values) CheckedPopupMenuItem(value: o, checked: s.sort == o, child: Text(o.label)),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(s.grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded, size: 20),
                        const SizedBox(width: Space.m),
                        Text(s.grid ? 'Show as list' : 'Show as grid'),
                      ],
                    ),
                  ),
                ],
              ),
              IconButton(tooltip: 'New playlist', icon: const Icon(Icons.add_rounded), onPressed: _new),
              const SizedBox(width: Space.xs),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              stretchModes: const [StretchMode.zoomBackground],
              background: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: header)),
                child: Stack(
                  children: [
                    Positioned(right: -36, bottom: 10, child: Icon(Icons.graphic_eq_rounded, size: 210, color: Colors.white.withValues(alpha: 0.06))),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Space.l, kToolbarHeight + Space.s, Space.l, 52 + Space.m),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                HeroStat('${lists.length}', lists.length == 1 ? 'playlist' : 'playlists'),
                                const SizedBox(width: Space.s),
                                HeroStat('$tracks', 'tracks'),
                                const SizedBox(width: Space.s),
                                HeroStat(seconds == 0 ? '–' : playlistLength(seconds), 'of audio'),
                                const SizedBox(width: Space.s),
                                HeroStat('${chats.length}', chats.length == 1 ? 'chat' : 'chats'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Quick ways in, kept in reach as the header folds away.
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(Space.l, 6, Space.l, 10),
                  children: [
                    if (telegram) ...[
                      _HeaderChip(icon: Icons.library_music_rounded, label: 'Telegram music', onTap: () => openAddTracks(context)),
                      _HeaderChip(icon: Icons.mic_rounded, label: 'Voice messages', onTap: () => openAddTracks(context, type: TgAudioType.voice)),
                      _HeaderChip(icon: Icons.audio_file_rounded, label: 'Audio files', onTap: () => openAddTracks(context, type: TgAudioType.files)),
                    ],
                    _HeaderChip(icon: Icons.podcasts_rounded, label: 'From Files', onTap: () => openAddTracks(context, files: true)),
                  ],
                ),
              ),
            ),
          ),
          if (lists.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _EmptyLibrary(onNew: _new, onImport: _import))
          else if (s.grid)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.x4),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: Space.l,
                  crossAxisSpacing: Space.l,
                  childAspectRatio: 0.76,
                ),
                itemCount: lists.length + 1,
                itemBuilder: (_, i) => i == lists.length ? _NewCard(onTap: _new) : _PlaylistCard(playlist: lists[i]),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
                child: Text(
                  custom ? 'Your order · drag ⋮⋮ to arrange' : '${s.sort.label} · pick “Your order” to arrange by hand',
                  style: context.text.labelSmall,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.x4),
              sliver: SliverReorderableList(
                itemCount: lists.length,
                onReorderItem: (from, to) => store.movePlaylist(from, to),
                proxyDecorator: (child, _, _) => Material(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l), elevation: 6, child: child),
                itemBuilder: (_, i) => _PlaylistRow(key: ValueKey(lists[i].id), playlist: lists[i], index: custom ? i : null),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A frosted chip on the library header.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: Space.s),
    child: Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.14))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text('+ $label', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Picks a shared playlist file and imports it.
Future<void> importPlaylistFlow(BuildContext context, WidgetRef ref, {String? path}) async {
  var file = path;
  if (file == null) {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    file = picked.singleOrNull?.path;
  }
  if (file == null || !context.mounted) return;
  showSnack(context, 'Importing playlist…', icon: Icons.file_download_outlined);
  try {
    final r = await ref.read(playlistsProvider.notifier).importFile(file);
    if (!context.mounted) return;
    showSnack(
      context,
      'Imported “${r.playlist.name}” · ${r.added} tracks${r.unavailable.isEmpty ? '' : ' · ${r.unavailable.length} not reachable from this account'}',
      icon: Icons.playlist_add_check_rounded,
    );
    _openPlaylist(context, r.playlist);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t import: ${e is FormatException ? e.message : e}', icon: Icons.error_outline_rounded);
  }
}

/// Ways to share a playlist: as a file to a chat (others import it), its
/// songs forwarded to a chat (anyone can listen), or a file in Files.
Future<void> sharePlaylist(BuildContext context, WidgetRef ref, Playlist p) async {
  final telegramTracks = p.tracks.where((t) => t.source == TrackSource.telegram).length;
  final telegram = ref.read(telegramConnectedProvider);
  final v = await showAppSheet<String>(
    context,
    initialSize: 0.5,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: Space.xl),
      children: [
        ListTile(
          leading: PlaylistCover(playlist: p, size: 48, radius: Radii.s),
          title: Text('Share “${p.name}”', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(p.summary, style: context.text.bodySmall),
        ),
        const Divider(),
        if (telegram)
          ListTile(
            leading: lead(const Icon(Icons.send_rounded)),
            title: const Text('Send as a playlist file'),
            subtitle: Text('To any chat. People with Triangle import it with its cover and order.', style: context.text.bodySmall),
            onTap: () => Navigator.pop(context, 'send'),
          ),
        if (telegram && telegramTracks > 0)
          ListTile(
            leading: lead(const Icon(Icons.forward_rounded)),
            title: Text('Forward the $telegramTracks Telegram tracks'),
            subtitle: Text('The songs and voice messages themselves, so anyone can listen.', style: context.text.bodySmall),
            onTap: () => Navigator.pop(context, 'forward'),
          ),
        ListTile(
          leading: lead(const Icon(Icons.save_alt_rounded)),
          title: const Text('Save the file to Files'),
          subtitle: Text('In Files → Exports, to send any way you like.', style: context.text.bodySmall),
          onTap: () => Navigator.pop(context, 'save'),
        ),
      ],
    ),
  );
  if (v == null || !context.mounted) return;
  final store = ref.read(playlistsProvider.notifier);
  try {
    switch (v) {
      case 'send' || 'forward':
        final chat = await pickTelegramChat(context, title: v == 'send' ? 'Send the playlist to…' : 'Forward the tracks to…');
        if (chat == null || !context.mounted) return;
        if (v == 'send') {
          await store.sendFile(p.id, chat);
          if (context.mounted) showSnack(context, 'Playlist sent', icon: Icons.send_rounded);
        } else {
          final n = await store.forwardTracks(p.id, chat);
          if (context.mounted) showSnack(context, 'Forwarded $n tracks', icon: Icons.forward_rounded);
        }
      case 'save':
        final f = await store.exportFile(p.id);
        if (context.mounted) showSnack(context, 'Saved ${f.uri.pathSegments.last} to Files → Exports', icon: Icons.save_alt_rounded);
        await OpenFilex.open(f.path);
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t share: $e', icon: Icons.error_outline_rounded);
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onNew, required this.onImport});
  final VoidCallback onNew;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x4 * 2),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 170,
          height: 150,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 20,
                child: Transform.rotate(angle: -0.18, child: const GradientArtBox(index: 4, emoji: '🎧')),
              ),
              Positioned(
                right: 0,
                top: 20,
                child: Transform.rotate(angle: 0.18, child: const GradientArtBox(index: 2, emoji: '🎙️')),
              ),
              const Positioned(left: 40, top: 0, child: GradientArtBox(index: 0, emoji: '🎵', side: 96)),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        Text('Your music, your way', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        const SizedBox(height: Space.s),
        Text(
          'Gather songs, voice messages and audio from your Telegram chats and channels, plus podcasts and audiobooks from Files, into playlists.',
          style: context.text.bodyMedium?.copyWith(color: AppColors.text2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.xl),
        FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add_rounded), label: const Text('Make a playlist')),
        TextButton.icon(onPressed: onImport, icon: const Icon(Icons.file_download_outlined, size: 18), label: const Text('Import a shared playlist')),
        const SizedBox(height: Space.s),
        Text('Or ask the assistant: “make a playlist of the songs in my Saved Messages”', style: context.text.labelSmall, textAlign: TextAlign.center),
      ],
    ),
  );
}

/// A small gradient cover for decoration.
class GradientArtBox extends StatelessWidget {
  const GradientArtBox({super.key, required this.index, required this.emoji, this.side = 80});
  final int index;
  final String emoji;
  final double side;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.l),
      boxShadow: [BoxShadow(color: playlistPalettes[index].last.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10))],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(Radii.l),
      child: GradientArt(colors: playlistPalettes[index], emoji: emoji, side: side),
    ),
  );
}

void _openPlaylist(BuildContext context, Playlist p) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: p.id)));

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = playlist;
    final a = ref.watch(audioCenterProvider);
    final live = a.queueTag == p.id;
    return GestureDetector(
      onTap: () => _openPlaylist(context, p),
      onLongPress: () => _playlistMenu(context, ref, p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.l),
                      boxShadow: [BoxShadow(color: p.colors.last.withValues(alpha: AppColors.isLight ? 0.25 : 0.35), blurRadius: 22, offset: const Offset(0, 10))],
                    ),
                    child: Hero(tag: 'playlist-${p.id}', flightShuttleBuilder: coverFlight, child: PlaylistCover(playlist: p)),
                  ),
                ),
                if (p.pinned)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                      child: const Icon(Icons.push_pin_rounded, size: 13, color: Colors.white),
                    ),
                  ),
                if (p.tracks.isNotEmpty)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _RoundPlay(
                      playing: live && a.playing,
                      onTap: () => live ? a.toggle() : ref.read(playlistsProvider.notifier).play(p),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s),
          Row(
            children: [
              if (live) ...[EqualizerBars(playing: a.playing, size: 12), const SizedBox(width: 6)],
              Expanded(
                child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: live ? AppColors.tint : null)),
              ),
            ],
          ),
          Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

class _RoundPlay extends StatelessWidget {
  const _RoundPlay({required this.playing, required this.onTap});
  final bool playing;
  final VoidCallback onTap;
  static const double size = 40;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    elevation: 4,
    shadowColor: Colors.black45,
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: size,
        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: size * 0.6),
      ),
    ),
  );
}

class _NewCard extends StatelessWidget {
  const _NewCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface2),
                child: Icon(Icons.add_rounded, size: 28, color: AppColors.text2),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.s),
        Text('New playlist', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        Text('Name it, pick a cover', style: context.text.bodySmall),
      ],
    ),
  );
}

/// A playlist in the list view: cover, name, words, what's in it (songs,
/// voice, episodes), how long, from how many chats, when last played, and
/// a handle to drag it in "Your order".
class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({super.key, required this.playlist, this.index});
  final Playlist playlist;

  /// Its place, when the list can be arranged by hand.
  final int? index;

  static String _ago(DateTime d) {
    final e = DateTime.now().difference(d);
    if (e.inMinutes < 1) return 'just now';
    if (e.inHours < 1) return '${e.inMinutes} min ago';
    if (e.inDays < 1) return '${e.inHours} h ago';
    if (e.inDays < 30) return '${e.inDays} d ago';
    return '${(e.inDays / 30).floor()} mo ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = playlist;
    final a = ref.watch(audioCenterProvider);
    final live = a.queueTag == p.id;
    final kinds = p.kinds;
    final chats = {for (final t in p.tracks) if (t.chatId != null) t.chatId}.length;
    final files = p.tracks.where((t) => t.source == TrackSource.file).length;
    String kindName(TrackKind k, int n) => switch (k) {
      TrackKind.music => '$n ${n == 1 ? 'song' : 'songs'}',
      TrackKind.voice => '$n voice',
      TrackKind.podcast => '$n ${n == 1 ? 'episode' : 'episodes'}',
      TrackKind.audiobook => '$n ${n == 1 ? 'chapter' : 'chapters'}',
      TrackKind.audio => '$n audio',
    };
    final facts = [
      if (chats > 0) (Icons.send_rounded, '$chats ${chats == 1 ? 'chat' : 'chats'}'),
      if (files > 0) (Icons.folder_outlined, '$files from Files'),
      if (p.playedAt != null) (Icons.history_rounded, 'played ${_ago(p.playedAt!)}'),
      if (p.plays > 1) (Icons.repeat_rounded, '${p.plays} plays'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: live ? p.colors.first.withValues(alpha: AppColors.isLight ? 0.10 : 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () => _openPlaylist(context, p),
          onLongPress: () => _playlistMenu(context, ref, p),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.xs, Space.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.m),
                    boxShadow: [BoxShadow(color: p.colors.last.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5))],
                  ),
                  child: Hero(tag: 'playlist-${p.id}', flightShuttleBuilder: coverFlight, child: PlaylistCover(playlist: p, size: 76, radius: Radii.m)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (live) ...[EqualizerBars(playing: a.playing, size: 12), const SizedBox(width: 6)],
                          if (p.pinned) ...[Icon(Icons.push_pin_rounded, size: 13, color: AppColors.text3), const SizedBox(width: 4)],
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 15.5, color: live ? AppColors.tint : null),
                            ),
                          ),
                        ],
                      ),
                      if (p.description.isNotEmpty)
                        Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
                      const SizedBox(height: 3),
                      Text(
                        p.tracks.isEmpty
                            ? 'Empty — tap to add songs'
                            : [
                                for (final k in TrackKind.values)
                                  if (kinds[k] case final n?) kindName(k, n),
                                if (p.seconds > 0) playlistLength(p.seconds),
                              ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.text2),
                      ),
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: Space.m,
                          runSpacing: 2,
                          children: [
                            for (final (icon, label) in facts)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 11.5, color: icon == Icons.send_rounded ? const Color(0xFF2AABEE) : AppColors.text3),
                                  const SizedBox(width: 3),
                                  Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (p.tracks.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: live && a.playing
                            ? Icon(Icons.pause_circle_filled_rounded, size: 34, color: AppColors.tint)
                            : Icon(Icons.play_circle_fill_rounded, size: 34, color: AppColors.tint),
                        onPressed: () => live ? a.toggle() : ref.read(playlistsProvider.notifier).play(p),
                      ),
                    if (index != null)
                      ReorderableDragStartListener(
                        index: index!,
                        child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.drag_indicator_rounded, color: AppColors.text3)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What can be done to a playlist from the library.
Future<void> _playlistMenu(BuildContext context, WidgetRef ref, Playlist p) async {
  final store = ref.read(playlistsProvider.notifier);
  final v = await showAppSheet<String>(
    context,
    initialSize: 0.5,
    builder: (context, scroll) => ListView(
      controller: scroll,
      children: [
        ListTile(
          leading: PlaylistCover(playlist: p, size: 48, radius: Radii.s),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(p.summary, style: context.text.bodySmall),
        ),
        const Divider(),
        if (p.tracks.isNotEmpty) ...[
          ListTile(leading: lead(const Icon(Icons.play_arrow_rounded)), title: const Text('Play'), onTap: () => Navigator.pop(context, 'play')),
          ListTile(leading: lead(const Icon(Icons.shuffle_rounded)), title: const Text('Shuffle'), onTap: () => Navigator.pop(context, 'shuffle')),
        ],
        ListTile(leading: lead(const Icon(Icons.edit_outlined)), title: const Text('Edit name and cover'), onTap: () => Navigator.pop(context, 'edit')),
        ListTile(
          leading: lead(Icon(p.pinned ? Icons.push_pin : Icons.push_pin_outlined)),
          title: Text(p.pinned ? 'Unpin' : 'Pin to top'),
          onTap: () => Navigator.pop(context, 'pin'),
        ),
        ListTile(leading: lead(const Icon(Icons.ios_share_rounded)), title: const Text('Share'), onTap: () => Navigator.pop(context, 'share')),
        ListTile(leading: lead(const Icon(Icons.copy_all_rounded)), title: const Text('Duplicate'), onTap: () => Navigator.pop(context, 'copy')),
        ListTile(
          leading: lead(Icon(Icons.delete_outline_rounded, color: AppColors.danger)),
          title: Text('Delete', style: TextStyle(color: AppColors.danger)),
          onTap: () => Navigator.pop(context, 'delete'),
        ),
      ],
    ),
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'play':
      await store.play(p);
    case 'shuffle':
      await store.play(p, shuffle: true);
    case 'edit':
      await showPlaylistEditor(context, ref, playlist: p);
    case 'pin':
      await store.setPinned(p.id, !p.pinned);
    case 'share':
      await sharePlaylist(context, ref, p);
    case 'copy':
      final c = await store.duplicate(p.id);
      if (c != null && context.mounted) showSnack(context, 'Made “${c.name}”', icon: Icons.copy_all_rounded);
    case 'delete':
      await _confirmDelete(context, ref, p);
  }
}

Future<bool> _confirmDelete(BuildContext context, WidgetRef ref, Playlist p) async {
  final ok = await confirmDelete(
    context,
    title: 'Delete “${p.name}”?',
    message: 'The playlist goes; the songs and voice messages stay in Telegram and Files.',
  );
  if (!ok) return false;
  final a = ref.read(audioCenterProvider);
  if (a.queueTag == p.id) await a.stop();
  await ref.read(playlistsProvider.notifier).delete(p.id);
  return true;
}

// ---- one playlist ----------------------------------------------------------------

enum _TrackSort { custom, title, added, length }

/// A playlist: its cover over a wash of its colours, play and shuffle, and
/// its tracks to reorder, filter and search.
class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(playlistsProvider.notifier).ensureArt(widget.playlistId));
  }

  TrackKind? _kind;
  String _q = '';
  bool _searching = false;
  _TrackSort _sort = _TrackSort.custom;

  List<PlaylistTrack> _visible(Playlist p) {
    final q = _q.toLowerCase();
    final list = [
      for (final t in p.tracks)
        if ((_kind == null || t.kind == _kind) && (q.isEmpty || '${t.title} ${t.artist} ${t.chatTitle ?? ''}'.toLowerCase().contains(q))) t,
    ];
    switch (_sort) {
      case _TrackSort.custom:
        break;
      case _TrackSort.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _TrackSort.added:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case _TrackSort.length:
        list.sort((a, b) => b.seconds.compareTo(a.seconds));
    }
    return list;
  }

  Future<void> _playFrom(Playlist p, List<PlaylistTrack> visible, int i) async {
    final store = ref.read(playlistsProvider.notifier);
    final a = ref.read(audioCenterProvider);
    final t = visible[i];
    if (a.current?.key == t.key) {
      await a.toggle();
      return;
    }
    await a.play(store.trackFor(t, tag: p.id), playlist: [for (final x in visible) store.trackFor(x, tag: p.id)]);
    await store.markPlayed(p.id);
  }

  Future<void> _remove(Playlist p, PlaylistTrack t) async {
    final store = ref.read(playlistsProvider.notifier);
    final before = p.tracks;
    await store.removeTracks(p.id, [t.id]);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Removed “${t.title}”', maxLines: 1, overflow: TextOverflow.ellipsis),
          action: SnackBarAction(label: 'Undo', onPressed: () => store.setTracks(p.id, before)),
        ),
      );
  }

  Future<void> _trackMenu(Playlist p, PlaylistTrack t) async {
    final store = ref.read(playlistsProvider.notifier);
    final v = await showAppSheet<String>(
      context,
      initialSize: 0.55,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          ListTile(
            leading: TrackArt(track: t),
            title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: trackSourceLine(context, t, maxLines: 2),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in {
                  ...t.info,
                  if (t.seconds > 0) 'Length': playlistLength(t.seconds),
                  'Type': t.kind.label,
                  'Added': '${t.addedAt.day}/${t.addedAt.month}/${t.addedAt.year}',
                }.entries)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(99)),
                    child: Text('${e.key}: ${e.value}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
                  ),
              ],
            ),
          ),
          const Divider(),
          ListTile(leading: lead(const Icon(Icons.play_arrow_rounded)), title: const Text('Play'), onTap: () => Navigator.pop(context, 'play')),
          if (ref.read(audioCenterProvider).current != null) ...[
            ListTile(leading: lead(const Icon(Icons.queue_play_next_rounded)), title: const Text('Play next'), onTap: () => Navigator.pop(context, 'next')),
            ListTile(leading: lead(const Icon(Icons.add_to_queue_rounded)), title: const Text('Add to queue'), onTap: () => Navigator.pop(context, 'queue')),
          ],
          ListTile(
            leading: lead(Icon(store.isLiked(t.key) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: store.isLiked(t.key) ? const Color(0xFFFF4D6D) : null)),
            title: Text(store.isLiked(t.key) ? 'Unlike' : 'Like'),
            onTap: () => Navigator.pop(context, 'like'),
          ),
          if (t.artPath != null && fileExists(t.artPath!))
            ListTile(leading: lead(const Icon(Icons.image_outlined)), title: const Text('View album art'), onTap: () => Navigator.pop(context, 'art')),
          if (t.source == TrackSource.telegram && t.chatId != null)
            ListTile(
              leading: lead(const Icon(Icons.forum_outlined)),
              title: const Text('Show in chat'),
              subtitle: t.chatTitle == null ? null : Text(t.chatTitle!, style: context.text.bodySmall),
              onTap: () => Navigator.pop(context, 'chat'),
            ),
          ListTile(leading: lead(const Icon(Icons.playlist_add_rounded)), title: const Text('Add to another playlist'), onTap: () => Navigator.pop(context, 'add')),
          ListTile(leading: lead(const Icon(Icons.drive_file_rename_outline_rounded)), title: const Text('Rename'), onTap: () => Navigator.pop(context, 'rename')),
          ListTile(
            leading: lead(const Icon(Icons.vertical_align_top_rounded)),
            title: const Text('Move to top'),
            onTap: () => Navigator.pop(context, 'top'),
          ),
          ListTile(
            leading: lead(Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger)),
            title: Text('Remove from playlist', style: TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.pop(context, 'remove'),
          ),
        ],
      ),
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'play':
        final vis = _visible(p);
        final i = vis.indexWhere((x) => x.id == t.id);
        if (i >= 0) await _playFrom(p, vis, i);
      case 'next':
        ref.read(audioCenterProvider).playNext(store.trackFor(t, tag: p.id));
        showSnack(context, 'Plays next', icon: Icons.queue_play_next_rounded);
      case 'queue':
        ref.read(audioCenterProvider).enqueue(store.trackFor(t, tag: p.id));
        showSnack(context, 'Added to the queue', icon: Icons.add_to_queue_rounded);
      case 'like':
        await store.toggleLike(t);
      case 'art':
        await openFullscreenFile(context, t.artPath!, title: t.title);
      case 'chat':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: t.chatId!, openAt: t.messageId)));
      case 'add':
        await showAddToPlaylist(context, ref, [t]);
      case 'rename':
        final v = await showFieldsSheet(
          context,
          icon: Icons.drive_file_rename_outline_rounded,
          color: p.colors.first,
          title: 'Rename track',
          subtitle: 'Only in “${p.name}”; the message or file keeps its name.',
          preview: Row(children: [TrackArt(track: t, size: 52), const SizedBox(width: Space.m), Expanded(child: trackSourceLine(context, t, maxLines: 2))]),
          fields: [
            SheetField(
              'title',
              label: 'Title',
              initial: t.title,
              suggestions: [
                if (t.fileName != null) t.fileName!.replaceAll(RegExp(r'\.[a-z0-9]+$', caseSensitive: false), '').replaceAll('_', ' '),
                if (t.artist.isNotEmpty) '${t.artist} - ${t.title}',
              ],
            ),
          ],
        );
        final name = v?['title'];
        if (name != null && name.isNotEmpty) await store.renameTrack(p.id, t.id, name);
      case 'top':
        await store.moveTrack(p.id, p.tracks.indexWhere((x) => x.id == t.id), 0);
      case 'remove':
        await _remove(p, t);
    }
  }

  Future<void> _menu(Playlist p, String v) async {
    final store = ref.read(playlistsProvider.notifier);
    switch (v) {
      case 'edit':
        await showPlaylistEditor(context, ref, playlist: p);
      case 'pin':
        await store.setPinned(p.id, !p.pinned);
      case 'share':
        await sharePlaylist(context, ref, p);
      case 'reverse':
        await store.sortTracks(p.id, 'reverse');
      case 'copy':
        final c = await store.duplicate(p.id);
        if (c != null && mounted) showSnack(context, 'Made “${c.name}”', icon: Icons.copy_all_rounded);
      case 'clear':
        if (await confirmDelete(context, title: 'Empty “${p.name}”?', message: 'Every track is taken out. The audio stays where it is.', action: 'Empty')) {
          await store.setTracks(p.id, const []);
        }
      case 'delete':
        if (await _confirmDelete(context, ref, p) && mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(playlistsProvider.select((s) => s.playlists.where((x) => x.id == widget.playlistId).firstOrNull));
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This playlist was deleted')));
    final a = ref.watch(audioCenterProvider);
    final live = a.queueTag == p.id;
    final visible = _visible(p);
    final reorderable = _sort == _TrackSort.custom && _kind == null && _q.isEmpty;
    final kinds = {for (final t in p.tracks) t.kind};
    final chats = {for (final t in p.tracks) if (t.chatId != null) t.chatId};
    final topColor = p.colors.first;
    final store = ref.read(playlistsProvider.notifier);

    Widget row(int i) {
      final t = visible[i];
      return Dismissible(
        key: ValueKey('t-${t.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: Space.xl),
          decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(Radii.m)),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
        ),
        onDismissed: (_) => _remove(p, t),
        child: TrackRow(
          track: t,
          index: i,
          onTap: () => _playFrom(p, visible, i),
          onLongPress: () => _trackMenu(p, t),
          trailing: reorderable
              ? ReorderableDragStartListener(
                  index: i,
                  child: Padding(padding: const EdgeInsets.only(left: Space.xs), child: Icon(Icons.drag_indicator_rounded, color: AppColors.text3)),
                )
              : IconButton(icon: Icon(Icons.more_vert_rounded, color: AppColors.text3, size: 20), onPressed: () => _trackMenu(p, t)),
        ),
      );
    }

    return Scaffold(
      bottomNavigationBar: const BottomAudioBar(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 330,
            backgroundColor: Color.lerp(AppColors.bg, topColor, 0.25),
            foregroundColor: Colors.white,
            title: Text(p.name),
            actions: [
              IconButton(
                tooltip: 'Search',
                icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _q = '';
                }),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(p, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit name and cover')),
                  PopupMenuItem(value: 'pin', child: Text(p.pinned ? 'Unpin' : 'Pin to top')),
                  const PopupMenuItem(value: 'share', child: Text('Share…')),
                  const PopupMenuItem(value: 'copy', child: Text('Duplicate')),
                  if (p.tracks.length > 1) const PopupMenuItem(value: 'reverse', child: Text('Reverse the order')),
                  if (p.tracks.isNotEmpty) const PopupMenuItem(value: 'clear', child: Text('Empty playlist')),
                  PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
              collapseMode: CollapseMode.parallax,
              background: _Header(
                playlist: p,
                onCover: () {
                  final cover = p.coverPath != null && fileExists(p.coverPath!) ? p.coverPath : null;
                  final arts = p.collage ? p.arts : const <String>[];
                  if (cover != null) {
                    openFullscreenFile(context, cover, title: p.name);
                  } else if (arts.isNotEmpty) {
                    openFullscreenFile(context, arts.first, title: p.name);
                  } else {
                    showPlaylistEditor(context, ref, playlist: p);
                  }
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(AppColors.bg, topColor, 0.12)!, AppColors.bg],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: Space.xs),
                    Text(p.description, style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
                  ],
                  const SizedBox(height: Space.xs),
                  Text(
                    [p.summary, if (chats.isNotEmpty) 'from ${chats.length} ${chats.length == 1 ? 'chat' : 'chats'}'].join(' · '),
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: Space.m),
                  Row(
                    children: [
                      _Pill(icon: Icons.add_rounded, label: 'Add', onTap: () => openAddTracks(context, playlistId: p.id)),
                      const SizedBox(width: Space.s),
                      if (p.tracks.isNotEmpty)
                        _Pill(
                          icon: Icons.shuffle_rounded,
                          label: 'Shuffle',
                          active: live && a.shuffle,
                          onTap: () => store.play(p, shuffle: true),
                        ),
                      const Spacer(),
                      if (p.tracks.isNotEmpty)
                        Material(
                          color: AppColors.tint,
                          shape: const CircleBorder(),
                          elevation: 6,
                          shadowColor: topColor.withValues(alpha: 0.6),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => live ? a.toggle() : store.play(p),
                            child: SizedBox.square(
                              dimension: 58,
                              child: live && a.loading
                                  ? Padding(padding: const EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.isLight ? Colors.white : AppColors.bg))
                                  : Icon(live && a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34, color: AppColors.isLight ? Colors.white : AppColors.bg),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_searching) ...[
                    const SizedBox(height: Space.m),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Find in this playlist'),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ],
                  if (p.tracks.length > 1) ...[
                    const SizedBox(height: Space.m),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (kinds.length > 1) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(label: const Text('All'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
                            ),
                            for (final k in TrackKind.values)
                              if (kinds.contains(k))
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(avatar: Icon(k.icon, size: 15), label: Text(k.label), selected: _kind == k, onSelected: (_) => setState(() => _kind = _kind == k ? null : k)),
                                ),
                            const SizedBox(width: Space.s),
                          ],
                          PopupMenuButton<_TrackSort>(
                            tooltip: 'Sort',
                            onSelected: (v) => setState(() => _sort = v),
                            itemBuilder: (_) => [
                              for (final (v, label) in const [
                                (_TrackSort.custom, 'Your order'),
                                (_TrackSort.title, 'Title'),
                                (_TrackSort.added, 'Recently added'),
                                (_TrackSort.length, 'Longest first'),
                              ])
                                CheckedPopupMenuItem(value: v, checked: _sort == v, child: Text(label)),
                            ],
                            child: Chip(
                              avatar: Icon(Icons.swap_vert_rounded, size: 16, color: AppColors.text2),
                              label: Text(switch (_sort) {
                                _TrackSort.custom => 'Your order',
                                _TrackSort.title => 'Title',
                                _TrackSort.added => 'Recently added',
                                _TrackSort.length => 'Longest first',
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (p.tracks.isEmpty)
            SliverToBoxAdapter(child: _EmptyPlaylist(playlist: p))
          else if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Center(child: Text('Nothing matches', style: context.text.bodySmall)),
              ),
            )
          else if (reorderable)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              sliver: SliverReorderableList(
                itemCount: visible.length,
                onReorderItem: (from, to) => store.moveTrack(p.id, from, to),
                proxyDecorator: (child, _, _) => Material(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), elevation: 6, child: child),
                itemBuilder: (_, i) => KeyedSubtree(key: ValueKey(visible[i].id), child: row(i)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              sliver: SliverList.builder(itemCount: visible.length, itemBuilder: (_, i) => row(i)),
            ),
          if (p.tracks.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.x4 * 2),
                child: Text(
                  reorderable ? 'Drag ⋮⋮ to reorder · swipe left to remove · long-press for more' : 'Swipe left to remove · long-press for more',
                  textAlign: TextAlign.center,
                  style: context.text.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The top of a playlist: its cover big over a blurred wash of itself.
class _Header extends StatelessWidget {
  const _Header({required this.playlist, required this.onCover});
  final Playlist playlist;
  final VoidCallback onCover;

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    final cover = p.coverPath != null && File(p.coverPath!).existsSync() ? p.coverPath : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Image.file(File(cover), fit: BoxFit.cover, cacheWidth: 200),
          )
        else
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p.colors))),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.25), Colors.transparent, Color.lerp(AppColors.bg, p.colors.first, 0.12)!],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 36),
              child: GestureDetector(
                onTap: onCover,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.xl),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 36, offset: Offset(0, 16))],
                  ),
                  child: Hero(tag: 'playlist-${p.id}', flightShuttleBuilder: coverFlight, child: PlaylistCover(playlist: p, size: 210, radius: Radii.xl)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? AppColors.tint.withValues(alpha: 0.18) : AppColors.surface2,
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? AppColors.tint : AppColors.text),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: active ? AppColors.tint : AppColors.text)),
          ],
        ),
      ),
    ),
  );
}

class _EmptyPlaylist extends ConsumerWidget {
  const _EmptyPlaylist({required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telegram = ref.watch(telegramConnectedProvider);
    Widget option(IconData icon, Color color, String title, String body, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(Radii.m)),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                      Text(body, style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.text3),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Let\'s fill it up', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: Space.xs),
          Text('Pick from your chats and channels, or from what you\'ve downloaded.', style: context.text.bodySmall),
          const SizedBox(height: Space.l),
          if (telegram) ...[
            option(Icons.library_music_rounded, const Color(0xFF2AABEE), 'Songs from Telegram', 'Music shared in any chat or channel', () => openAddTracks(context, playlistId: playlist.id)),
            option(Icons.mic_rounded, const Color(0xFF7F5AF0), 'Voice messages', 'Sermons, lectures, notes from friends', () => openAddTracks(context, playlistId: playlist.id, type: TgAudioType.voice)),
            option(Icons.audio_file_rounded, const Color(0xFF00B894), 'Audio files', 'MP3s and recordings posted as files', () => openAddTracks(context, playlistId: playlist.id, type: TgAudioType.files)),
          ],
          option(Icons.podcasts_rounded, const Color(0xFFFF8A3D), 'From Files', 'Podcasts, audiobooks and saved audio', () => openAddTracks(context, playlistId: playlist.id, files: true)),
        ],
      ),
    );
  }
}
