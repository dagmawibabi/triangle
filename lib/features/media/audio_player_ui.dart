import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/fullscreen_image.dart';
import '../../core/widgets/glass.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../playlists/music_stats_screen.dart';
import '../playlists/playlist_widgets.dart' show showAddToPlaylist;
import '../playlists/playlists.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/presentation/chat_view_screen.dart';
import 'audio_center.dart';
import 'audio_tags.dart';
import 'lyrics.dart';

/// The bar that floats under a header (or over the bottom of a page)
/// while something plays.
class AudioMiniBar extends ConsumerWidget {
  const AudioMiniBar({super.key, this.margin = const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, 0)});
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioCenterProvider);
    final t = a.current;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: t == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: margin,
              child: Glass(
                radius: Radii.l,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => showAudioPlayer(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(5, 3, 2, 1),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox.square(dimension: 28, child: _SmallArt(track: t)),
                              ),
                              IconButton(
                                visualDensity: _tight,
                                iconSize: 21,
                                icon: a.loading
                                    ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Icon(a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.accent),
                                onPressed: a.toggle,
                              ),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      if (t.subtitle.isNotEmpty) TextSpan(text: ' – ${t.subtitle}', style: TextStyle(color: AppColors.text2)),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.8, color: AppColors.text),
                                ),
                              ),
                              if (a.speed != 1) Text('${a.speed}×', style: TextStyle(fontSize: 11.5, color: AppColors.accent)),
                              if (a.hasNext)
                                IconButton(visualDensity: _tight, iconSize: 20, icon: Icon(Icons.skip_next_rounded, color: AppColors.text2), onPressed: a.next),
                              IconButton(
                                visualDensity: _tight,
                                iconSize: 18,
                                icon: Icon(Icons.close_rounded, color: AppColors.text2),
                                onPressed: a.stop,
                              ),
                            ],
                          ),
                        ),
                        LinearProgressIndicator(
                          value: t.live && a.playing
                              ? null
                              : t.live
                              ? 0
                              : a.duration.inMilliseconds == 0
                              ? 0
                              : (a.position.inMilliseconds / a.duration.inMilliseconds).clamp(0, 1).toDouble(),
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

const _tight = VisualDensity(horizontal: -3, vertical: -3);

class _SmallArt extends StatelessWidget {
  const _SmallArt({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t.artPath != null && File(t.artPath!).existsSync()) {
      return Image(image: ResizeImage(FileImage(File(t.artPath!)), width: 120), fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (t.cover != null) {
      try {
        return Image.memory(base64Decode(t.cover!.data), fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {}
    }
    if (t.artUrl != null) return Image.network(t.artUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox());
    return Container(color: AppColors.surface3, child: Icon(t.voice ? Icons.mic_rounded : Icons.music_note_rounded, size: 18, color: AppColors.text2));
  }
}

/// Opens the full-screen player.
Future<void> showAudioPlayer(BuildContext context) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => const NowPlayingScreen(),
    transitionsBuilder: (_, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);

/// The player on its own page: the cover big over a blurred wash of
/// itself, what's known about the track, the controls, and the queue,
/// lyrics and details a tap away.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  /// The cover the art widget found, shared with the backdrop and viewer.
  ImageProvider? _art;
  String? _artFor;
  AudioTags _tags = AudioTags.empty;
  String? _tagsFrom;
  double? _drag;

  void _readTags(String? path) {
    if (path == null || path == _tagsFrom) return;
    _tagsFrom = path;
    readAudioTags(path).then((t) {
      if (mounted && _tagsFrom == path) setState(() => _tags = t);
    });
  }

  PlaylistTrack _asPlaylistTrack(Track t) => PlaylistTrack.fromTrack(t, ref.read(activeAccountIdProvider));

  Future<void> _like(Track t) async {
    final on = await ref.read(playlistsProvider.notifier).toggleLike(_asPlaylistTrack(t));
    if (mounted) showSnack(context, on ? 'Added to Liked songs' : 'Removed from Liked songs', icon: on ? Icons.favorite_rounded : Icons.heart_broken_outlined);
  }

  void _openArt(Track t) {
    final img = _art;
    if (img == null) return;
    openFullscreenImage(context, img, title: t.title);
  }

  Future<void> _sleep() async {
    final a = ref.read(audioCenterProvider);
    final v = await showAppSheet<Object>(
      context,
      initialSize: 0.5,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          Center(child: Text('Sleep timer', style: context.text.titleMedium)),
          const SizedBox(height: Space.s),
          for (final m in const [5, 10, 15, 30, 45, 60, 90])
            ListTile(leading: lead(const Icon(Icons.bedtime_outlined)), title: Text('$m minutes'), onTap: () => Navigator.pop(context, m)),
          ListTile(leading: lead(const Icon(Icons.last_page_rounded)), title: const Text('End of this track'), onTap: () => Navigator.pop(context, 'end')),
          if (a.sleepAt != null || a.sleepAtEnd)
            ListTile(leading: lead(Icon(Icons.timer_off_outlined, color: AppColors.danger)), title: const Text('Turn off'), onTap: () => Navigator.pop(context, 'off')),
        ],
      ),
    );
    if (v == null) return;
    if (v == 'off') {
      a.setSleep(null);
    } else if (v == 'end') {
      a.setSleep(null, endOfTrack: true);
    } else if (v is int) {
      a.setSleep(Duration(minutes: v));
    }
  }

  Future<void> _menu(Track t, String v) async {
    switch (v) {
      case 'add':
        await showAddToPlaylist(context, ref, [_asPlaylistTrack(t)]);
      case 'chat':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: t.chatId, openAt: t.messageId)));
      case 'sleep':
        await _sleep();
      case 'stats':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MusicStatsScreen()));
      case 'art':
        _openArt(t);
      case 'details':
        _details(t, {..._tags.info, ...t.info});
    }
  }

  void _sheet(String title, Widget Function(BuildContext, ScrollController) body) =>
      showAppSheet<void>(context, initialSize: 0.7, builder: (context, scroll) => Column(
        children: [
          Text(title, style: context.text.titleMedium),
          const SizedBox(height: Space.s),
          Expanded(child: body(context, scroll)),
        ],
      ));

  void _queue() => _sheet('Up next', (context, scroll) => _QueueList(scroll: scroll));

  void _lyrics() => showAppSheet<void>(context, initialSize: 0.85, builder: (context, scroll) => LyricsPanel(scroll: scroll));

  void _details(Track t, Map<String, String> info) => _sheet(
    'About this track',
    (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        _infoRow(context, 'Title', _tags.title ?? t.title),
        if ((_tags.artist ?? t.subtitle).isNotEmpty) _infoRow(context, 'Artist', _tags.artist ?? t.subtitle),
        for (final e in info.entries) _infoRow(context, e.key, e.value),
        if (t.seconds > 0) _infoRow(context, 'Length', formatDuration(t.seconds)),
        if (_tags.comment != null && _tags.comment!.length >= 80) _infoRow(context, 'Comment', _tags.comment!),
      ],
    ),
  );

  Widget _infoRow(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(right: Space.s), child: Icon(_infoIcon(k), size: 16, color: AppColors.text3)),
        SizedBox(width: 100, child: Text(k, style: context.text.bodySmall)),
        Expanded(child: SelectableText(v, style: context.text.bodyMedium)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(audioCenterProvider);
    final t = a.current;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing')),
      );
    }
    if (_artFor != t.key) {
      _artFor = t.key;
      _art = null;
      _tags = AudioTags.empty;
      _tagsFrom = null;
    }
    _readTags(a.currentPath);
    final lists = ref.watch(playlistsProvider);
    final fromList = t.queueTag == null ? null : lists.playlists.where((p) => p.id == t.queueTag).firstOrNull;
    final liked = lists.playlists.where((p) => p.id == PlaylistsStore.likedId).firstOrNull?.tracks.any((x) => x.key == _asPlaylistTrack(t).key) ?? false;
    final total = a.duration.inMilliseconds > 0 ? a.duration : Duration(seconds: t.seconds);
    final pos = a.position > total ? total : a.position;
    final info = <String, String>{..._tags.info, ...t.info};
    final width = MediaQuery.sizeOf(context).width;
    final art = (width - 2 * Space.x4).clamp(180.0, 420.0);
    final title = (_tags.title != null && t.title.toLowerCase().startsWith('audio')) ? _tags.title! : t.title;
    final artist = t.subtitle.isNotEmpty ? t.subtitle : (_tags.artist ?? '');
    const fg = Colors.white;
    const fg2 = Colors.white70;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The cover, blurred, as the backdrop.
            if (_art != null)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Image(image: ResizeImage(_art!, width: 200), fit: BoxFit.cover, gaplessPlayback: true),
              )
            else
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A3550), Color(0xFF0B0E14)]))),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66000000), Color(0x99000000), Color(0xEE000000)]),
              ),
            ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
                children: [
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: fg, size: 30), onPressed: () => Navigator.pop(context)),
                      Expanded(
                        child: Column(
                          children: [
                            Text(fromList != null ? 'PLAYING FROM PLAYLIST' : (t.url != null ? 'STREAMING' : 'NOW PLAYING'), style: const TextStyle(color: fg2, fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                            Text(fromList?.name ?? t.info['From'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: fg, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: fg),
                        onSelected: (v) => _menu(t, v),
                        itemBuilder: (_) => [
                          if (!t.live) const PopupMenuItem(value: 'add', child: Text('Add to playlist…')),
                          if (t.chatId != 0) const PopupMenuItem(value: 'chat', child: Text('Show in chat')),
                          if (_art != null) const PopupMenuItem(value: 'art', child: Text('View cover')),
                          PopupMenuItem(value: 'sleep', child: Text(a.sleepAt != null || a.sleepAtEnd ? 'Sleep timer (on)' : 'Sleep timer')),
                          const PopupMenuItem(value: 'details', child: Text('Details')),
                          const PopupMenuItem(value: 'stats', child: Text('Listening stats')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xl),
                  Center(
                    child: GestureDetector(
                      onTap: () => _openArt(t),
                      onHorizontalDragUpdate: (d) => _drag = (_drag ?? 0) + d.delta.dx,
                      onHorizontalDragEnd: (_) {
                        final d = _drag ?? 0;
                        _drag = null;
                        if (d < -60 && a.hasNext) a.next();
                        if (d > 60) a.previous();
                      },
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 300),
                        scale: a.playing ? 1 : 0.9,
                        child: AudioCoverArt(
                          key: ValueKey(t.key),
                          track: t,
                          path: a.currentPath,
                          size: art,
                          onImage: (img) {
                            if (mounted && _art != img) setState(() => _art = img);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarqueeText(title, style: const TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: fg2, fontSize: 15)),
                          ],
                        ),
                      ),
                      if (!t.live)
                        IconButton(
                          tooltip: liked ? 'Unlike' : 'Like',
                          icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? const Color(0xFFFF4D6D) : fg, size: 28),
                          onPressed: () => _like(t),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.m),
                  if (t.live)
                    Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: Color(0xFFFF4D4D)),
                        const SizedBox(width: 6),
                        Text('LIVE · ${formatDuration(pos.inSeconds)}', style: const TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    )
                  else ...[
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: fg,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: fg,
                        overlayColor: Colors.white12,
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: pos.inMilliseconds.toDouble().clamp(0, total.inMilliseconds.toDouble().clamp(1, double.infinity)),
                        max: total.inMilliseconds.toDouble().clamp(1, double.infinity),
                        onChanged: (v) => a.seek(Duration(milliseconds: v.round())),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m),
                      child: Row(
                        children: [
                          Text(formatDuration(pos.inSeconds), style: const TextStyle(color: fg2, fontSize: 12)),
                          const Spacer(),
                          Text('-${formatDuration((total - pos).inSeconds)}', style: const TextStyle(color: fg2, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.s),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle',
                        icon: Icon(Icons.shuffle_rounded, color: a.shuffle ? AppColors.accent : fg2),
                        onPressed: a.queue.length > 1 ? () => a.setShuffle(!a.shuffle) : null,
                      ),
                      IconButton(iconSize: 36, icon: const Icon(Icons.skip_previous_rounded, color: fg), onPressed: a.previous),
                      Material(
                        color: fg,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: a.toggle,
                          child: SizedBox.square(
                            dimension: 72,
                            child: a.loading
                                ? const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                                : Icon(a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 42, color: Colors.black),
                          ),
                        ),
                      ),
                      IconButton(iconSize: 36, icon: Icon(Icons.skip_next_rounded, color: a.hasNext ? fg : Colors.white24), onPressed: a.hasNext ? a.next : null),
                      IconButton(
                        tooltip: switch (a.repeat) {
                          AudioRepeat.off => 'Repeat off',
                          AudioRepeat.all => 'Repeat all',
                          AudioRepeat.one => 'Repeat this one',
                        },
                        icon: Icon(a.repeat == AudioRepeat.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, color: a.repeat == AudioRepeat.off ? fg2 : AppColors.accent),
                        onPressed: a.cycleRepeat,
                      ),
                    ],
                  ),
                  if (!t.live)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Up next',
                          iconSize: 20,
                          icon: Badge(
                            isLabelVisible: a.upNext.isNotEmpty,
                            label: Text('${a.upNext.length}'),
                            child: const Icon(Icons.queue_music_rounded, color: fg2),
                          ),
                          onPressed: _queue,
                        ),
                        IconButton(icon: const Icon(Icons.replay_10_rounded, color: fg2), onPressed: () => a.skip(-10)),
                        PopupMenuButton<double>(
                          tooltip: 'Speed',
                          onSelected: a.setSpeed,
                          itemBuilder: (_) => [for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]) CheckedPopupMenuItem(value: v, checked: a.speed == v, child: Text('$v×'))],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                            child: Text('${a.speed}×', style: const TextStyle(color: fg, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.forward_10_rounded, color: fg2), onPressed: () => a.skip(10)),
                        IconButton(
                          tooltip: 'Sleep timer',
                          icon: Icon(Icons.bedtime_outlined, color: a.sleepAt != null || a.sleepAtEnd ? AppColors.accent : fg2),
                          onPressed: _sleep,
                        ),
                        IconButton(tooltip: 'Lyrics', iconSize: 20, icon: const Icon(Icons.lyrics_outlined, color: fg2), onPressed: _lyrics),
                      ],
                    ),
                  if (a.sleepAt != null || a.sleepAtEnd)
                    Center(
                      child: Text(
                        a.sleepAtEnd ? 'Stops at the end of this track' : 'Stops in ${a.sleepAt!.difference(DateTime.now()).inMinutes + 1} min',
                        style: const TextStyle(color: fg2, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: Space.l),
                  // Just the quality, quietly; the rest is under Details.
                  if (info['Format'] != null || info['Bitrate'] != null)
                    Center(
                      child: Text(
                        [?info['Codec'] ?? info['Format'], ?info['Bitrate'], ?info['Sample rate']].join(' · '),
                        style: const TextStyle(color: fg2, fontSize: 11.5, letterSpacing: 0.3),
                      ),
                    ),
                  if (a.error != null) ...[
                    const SizedBox(height: Space.m),
                    Text(a.error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A8A))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _infoIcon(String k) => switch (k) {
  'Album' => Icons.album_outlined,
  'Album artist' || 'Artist' => Icons.person_outline_rounded,
  'Composer' => Icons.edit_note_rounded,
  'Year' => Icons.calendar_today_outlined,
  'Genre' => Icons.style_outlined,
  'Track' || 'Disc' => Icons.tag_rounded,
  'Format' || 'Codec' => Icons.audio_file_outlined,
  'Size' => Icons.sd_storage_outlined,
  'Bitrate' || 'Sample rate' || 'Channels' => Icons.graphic_eq_rounded,
  'BPM' => Icons.speed_rounded,
  'From' => Icons.send_rounded,
  'Posted' => Icons.schedule_rounded,
  'Label' => Icons.business_outlined,
  _ => Icons.info_outline_rounded,
};

/// The queue: what plays next, to jump to, reorder or take out.
class _QueueList extends ConsumerWidget {
  const _QueueList({required this.scroll});
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioCenterProvider);
    final q = a.queue;
    if (q.length <= 1) return Center(child: Text('Only this track is queued', style: context.text.bodySmall));
    return ReorderableListView.builder(
      scrollController: scroll,
      itemCount: q.length,
      buildDefaultDragHandles: false,
      onReorder: (from, to) => a.moveInQueue(from, to > from ? to - 1 : to),
      itemBuilder: (context, i) {
        final t = q[i];
        final now = t.key == a.current?.key;
        return ListTile(
          key: ValueKey(t.key),
          leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox.square(dimension: 40, child: _SmallArt(track: t))),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: now ? FontWeight.w800 : FontWeight.w500, color: now ? AppColors.tint : null)),
          subtitle: Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
          onTap: () => a.jumpTo(t),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!now) IconButton(icon: Icon(Icons.remove_circle_outline_rounded, color: AppColors.text3, size: 20), onPressed: () => a.dequeue(t)),
              ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator_rounded, color: AppColors.text3)),
            ],
          ),
        );
      },
    );
  }
}

/// A track's cover, the best one there is: saved album art, Telegram's
/// full-size album cover, the picture inside the file, then the blurry
/// preview, a cover link, or a gradient with an icon. Tapping it is the
/// caller's (the player opens it full screen).
class AudioCoverArt extends ConsumerStatefulWidget {
  const AudioCoverArt({super.key, required this.track, this.path, this.size = 200, this.onImage});
  final Track track;

  /// The playing file, for the picture embedded in it.
  final String? path;
  final double size;

  /// Told the full-size picture once it's found.
  final ValueChanged<ImageProvider>? onImage;

  @override
  ConsumerState<AudioCoverArt> createState() => _AudioCoverArtState();
}

class _AudioCoverArtState extends ConsumerState<AudioCoverArt> {
  ImageProvider? _image;
  String? _triedPath;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void didUpdateWidget(AudioCoverArt old) {
    super.didUpdateWidget(old);
    if (_image == null && widget.path != _triedPath) _find();
  }

  Future<void> _find() async {
    final t = widget.track;
    ImageProvider? found;
    if (t.artPath != null && File(t.artPath!).existsSync()) {
      found = FileImage(File(t.artPath!));
    } else if (t.artFile != null) {
      final p = await ref.read(fileLoaderProvider).download(t.artFile!, priority: 8);
      if (p != null) found = FileImage(File(p));
    }
    final path = widget.path;
    _triedPath = path;
    if (found == null && path != null) {
      final tags = await readAudioTags(path);
      if (tags.picture != null) found = MemoryImage(tags.picture!);
    }
    if (found == null && t.artUrl != null) found = NetworkImage(t.artUrl!);
    if (found != null && mounted) {
      setState(() => _image = found);
      widget.onImage?.call(found);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final side = widget.size;
    Widget fallback() {
      if (t.cover != null) {
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Image.memory(base64Decode(t.cover!.data), fit: BoxFit.cover, width: side, height: side),
        );
      }
      return _gradient();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        boxShadow: const [BoxShadow(color: Color(0x77000000), blurRadius: 40, offset: Offset(0, 18))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.xl),
        child: SizedBox.square(
          dimension: side,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _image == null
                ? KeyedSubtree(key: const ValueKey('fallback'), child: fallback())
                : Image(
                    key: const ValueKey('art'),
                    image: ResizeImage(_image!, width: 800, policy: ResizeImagePolicy.fit),
                    fit: BoxFit.cover,
                    width: side,
                    height: side,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => fallback(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _gradient() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2A3550), Color(0xFF151A26)]),
    ),
    child: Icon(
      widget.track.live ? Icons.radio_rounded : (widget.track.voice ? Icons.mic_rounded : Icons.music_note_rounded),
      size: widget.size * 0.36,
      color: AppColors.accent,
    ),
  );
}
