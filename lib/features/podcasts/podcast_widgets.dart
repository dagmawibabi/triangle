import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:io';

import '../../app/theme.dart';
import '../sections/section_kit.dart' show TgPicture;
import '../telegram/data/telegram_store.dart' show telegramStoreFamily;
import '../../core/widgets/app_sheet.dart';
import '../media/audio_center.dart';
import '../media/audio_player_ui.dart' show showAudioPlayer;
import '../playlists/playlist_widgets.dart' show EqualizerBars, showAddToPlaylist;
import 'podcast_models.dart';
import 'podcast_show_screen.dart';
import 'podcast_store.dart';
import 'radio_store.dart';

/// The section's colour; the app's own in the monochrome look.
Color get podColor => AppLook.brand(const Color(0xFFEC4899));

String fmtDuration(int seconds) {
  if (seconds <= 0) return '';
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
  return '$m min';
}

String fmtDate(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat.EEEE().format(d);
  return DateFormat(d.year == now.year ? 'd MMM' : 'd MMM y').format(d);
}

String fmtClock(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '$m:${sec.toString().padLeft(2, '0')}';
}

/// Show or station art: the picture, fading in, or a soft gradient with the
/// first letter while there is none.
class PodArt extends StatelessWidget {
  const PodArt(this.url, {super.key, required this.title, this.size, this.radius = 12, this.icon, this.show});
  final String? url;
  final String title;
  final double? size;
  final double radius;
  final IconData? icon;

  /// The show it belongs to: a Telegram channel's (`tg:…`) photo stands in
  /// when there is no picture.
  final String? show;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget fallback() {
      final sh = show;
      if (sh != null && sh.startsWith('tg:')) return TgChatArt(show: sh, title: title);
      final hue = (title.hashCode % 360).abs().toDouble();
      final minimal = AppLook.minimalExplore;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: minimal
                ? [AppColors.surface3, AppColors.surface2]
                : [HSLColor.fromAHSL(1, hue, 0.55, AppColors.isLight ? 0.7 : 0.38).toColor(), HSLColor.fromAHSL(1, (hue + 50) % 360, 0.6, AppColors.isLight ? 0.58 : 0.24).toColor()],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, c) => Center(
            child: icon != null
                ? Icon(icon, size: c.maxWidth * 0.42, color: (minimal ? AppColors.text2 : Colors.white).withValues(alpha: 0.9))
                : Text(
                    title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase(),
                    style: TextStyle(fontSize: c.maxWidth * 0.42, fontWeight: FontWeight.w800, color: (minimal ? AppColors.text2 : Colors.white).withValues(alpha: 0.92)),
                  ),
          ),
        ),
      );
    }

    final u = url;
    final local = u != null && (u.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(u));
    final child = u == null || u.isEmpty
        ? fallback()
        : local
        ? Image.file(File(u), fit: BoxFit.cover, cacheWidth: size == null ? 600 : (size! * dpr).round().clamp(64, 900), gaplessPlayback: true, errorBuilder: (_, _, _) => fallback())
        : Image.network(
            u,
            fit: BoxFit.cover,
            cacheWidth: size == null ? 600 : (size! * dpr).round().clamp(64, 900),
            gaplessPlayback: true,
            frameBuilder: (_, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 220), curve: Curves.easeOut, child: child),
            errorBuilder: (_, _, _) => fallback(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: size == null
          ? AspectRatio(aspectRatio: 1, child: ColoredBox(color: AppColors.surface2, child: child))
          : SizedBox(width: size, height: size, child: ColoredBox(color: AppColors.surface2, child: child)),
    );
  }
}

/// A Telegram channel's (or group's, or person's) photo, square, for a show
/// made from it.
class TgChatArt extends ConsumerWidget {
  const TgChatArt({super.key, required this.show, required this.title});
  final String show;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = show.split(':');
    final chatId = int.tryParse(parts.last);
    final account = parts.length > 2 ? parts.sublist(1, parts.length - 1).join(':') : '';
    final photo = chatId == null || account.isEmpty ? null : ref.watch(telegramStoreFamily(account)).chat(chatId)?.photo;
    if (photo == null) {
      final hue = (title.hashCode % 360).abs().toDouble();
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [HSLColor.fromAHSL(1, hue, 0.5, 0.4).toColor(), HSLColor.fromAHSL(1, (hue + 50) % 360, 0.55, 0.26).toColor()]),
        ),
        child: const Center(child: Icon(Icons.send_rounded, color: Colors.white70)),
      );
    }
    return TgPicture(file: photo.big, mini: photo.minithumbnail, account: account, cacheWidth: 600, placeholder: TgPicture(file: photo.small, mini: photo.minithumbnail, account: account, cacheWidth: 200));
  }
}

/// A round play button that follows the player for [trackKey].
class PlayButton extends ConsumerWidget {
  const PlayButton({super.key, required this.trackKey, required this.onTap, this.size = 40, this.filled = false});
  final String trackKey;
  final VoidCallback onTap;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (current, playing, loading) = ref.watch(audioCenterProvider.select((a) => (a.current?.key == trackKey, a.playing, a.loading)));
    final on = current && playing;
    final bg = filled || current ? podColor : AppColors.text.withValues(alpha: 0.07);
    final fg = filled || current ? AppLook.onBrand(podColor) : AppColors.text;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: size,
          height: size,
          child: current && loading
              ? Padding(padding: EdgeInsets.all(size * 0.28), child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Icon(on ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(on), color: fg, size: size * 0.56),
                ),
        ),
      ),
    );
  }
}

/// An episode in a list: title, when, how long (or how much is left), its
/// progress, and play.
class EpisodeRow extends ConsumerWidget {
  const EpisodeRow({super.key, required this.episode, this.podcast, this.showShow = false, this.trailing});
  final Episode episode;
  final Podcast? podcast;
  final bool showShow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pods = ref.watch(podcastsProvider);
    final e = episode;
    final key = PodcastStore.trackKey(e);
    final current = ref.watch(audioCenterProvider.select((a) => a.current?.key == key));
    final played = pods.played(e);
    // The one playing shows its progress live; the rest from what was saved.
    final prog = current
        ? ref.watch(audioCenterProvider.select((a) => a.duration.inMilliseconds > 0 ? (a.position.inMilliseconds / a.duration.inMilliseconds).clamp(0.0, 1.0) : 0.0))
        : pods.progressOf(e);
    final dl = pods.downloads[e.guid];
    final meta = [
      fmtDate(e.published),
      if (e.durationMs > 0) prog > 0 && !played ? '${fmtDuration((e.durationMs * (1 - prog) / 1000).round())} left' : fmtDuration(e.durationMs ~/ 1000),
      if (pods.isDownloaded(e)) '⬇ Saved',
      if (pods.queued(e)) 'Queued',
    ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => showEpisodeSheet(context, e, podcast: podcast),
      onLongPress: () => showEpisodeSheet(context, e, podcast: podcast),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showShow) ...[PodArt(e.art, title: e.podcastTitle, size: 54, radius: 10, show: e.feedUrl), const SizedBox(width: Space.m)],
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: played ? 0.5 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showShow) Text(e.podcastTitle.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: podColor)),
                    Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25, color: current ? podColor : AppColors.text)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (played) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check_rounded, size: 14, color: AppColors.text3)),
                        if (pods.isFavorite(e)) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.favorite_rounded, size: 13, color: podColor)),
                        Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.text3))),
                      ],
                    ),
                    if (prog > 0 && !played)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(value: prog, minHeight: 3, color: podColor, backgroundColor: podColor.withValues(alpha: 0.14)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.s),
            if (dl != null)
              InkResponse(
                onTap: () => pods.cancelDownload(e.guid),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, value: dl < 0 ? null : dl, color: podColor)),
                ),
              ),
            ?trailing,
            PlayButton(trackKey: key, onTap: () => pods.play(e)),
          ],
        ),
      ),
    );
  }
}

/// Everything about an episode, and every action on it.
Future<void> showEpisodeSheet(BuildContext context, Episode e, {Podcast? podcast}) => showAppSheet<void>(
  context,
  initialSize: 0.72,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) {
      final pods = ref.watch(podcastsProvider);
      final audio = ref.read(audioCenterProvider);
      final key = PodcastStore.trackKey(e);
      final current = ref.watch(audioCenterProvider.select((a) => a.current?.key == key));
      final playing = current && ref.watch(audioCenterProvider.select((a) => a.playing));
      final played = pods.played(e);
      final mark = pods.episodeMark(e);
      final dl = pods.downloads[e.guid];
      final resume = pods.progressOf(e) > 0 && !played;
      Widget row(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: lead(Icon(icon, size: 21, color: color ?? AppColors.text)),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: color ?? AppColors.text)),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      );
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PodArt(e.art, title: e.podcastTitle, size: 76, radius: 14, show: e.feedUrl),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.podcastTitle.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: podColor)),
                    const SizedBox(height: 3),
                    Text(e.title, style: TextStyle(fontSize: 18, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.text)),
                    const SizedBox(height: 4),
                    Text([fmtDate(e.published), if (e.durationMs > 0) fmtDuration(e.durationMs ~/ 1000)].where((s) => s.isNotEmpty).join(' · '), style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: podColor, foregroundColor: AppLook.onBrand(podColor)),
                  onPressed: () async {
                    await pods.play(e);
                    if (!current && context.mounted) {
                      Navigator.pop(context);
                      await showAudioPlayer(context);
                    }
                  },
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(playing ? 'Pause' : (resume ? 'Resume · ${fmtClock(pods.states[e.guid]?.posMs ?? 0)}' : 'Play')),
                ),
              ),
              if (!e.isTelegram) ...[
                const SizedBox(width: Space.s),
                IconButton.filledTonal(
                  iconSize: 24,
                  style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
                  tooltip: dl != null ? 'Cancel download' : (pods.isDownloaded(e) ? 'Remove download' : 'Download'),
                  onPressed: () => dl != null ? pods.cancelDownload(e.guid) : (pods.isDownloaded(e) ? pods.removeDownload(e) : pods.download(e)),
                  icon: dl != null
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, value: dl < 0 ? null : dl))
                      : Icon(pods.isDownloaded(e) ? Icons.download_done_rounded : Icons.download_rounded),
                ),
              ],
              const SizedBox(width: Space.s),
              IconButton.filledTonal(
                iconSize: 24,
                style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
                tooltip: mark.favorite ? 'Unfavourite' : 'Favourite',
                onPressed: () {
                  mark.favorite = !mark.favorite;
                  pods.marksChanged();
                },
                icon: Icon(mark.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: mark.favorite ? podColor : null),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          row(Icons.playlist_play_rounded, 'Play next', () {
            pods.enqueue(e, next: true);
            showSnack(context, 'Plays next', icon: Icons.playlist_play_rounded);
          }),
          row(pods.queued(e) ? Icons.playlist_remove_rounded : Icons.playlist_add_rounded, pods.queued(e) ? 'Remove from Up next' : 'Add to Up next', () => pods.queued(e) ? pods.dequeue(e) : pods.enqueue(e)),
          if (e.tg != null) row(Icons.queue_music_rounded, 'Add to a playlist…', () => showAddToPlaylist(context, ref, [e.tg!])),
          row(played ? Icons.replay_rounded : Icons.check_rounded, played ? 'Mark as unplayed' : 'Mark as played', () => pods.setPlayed(e, !played)),
          if (podcast != null && podcast.episodes.isNotEmpty && podcast.episodes.last.guid != e.guid)
            row(Icons.done_all_rounded, 'Mark older as played', () {
              pods.markOlderPlayed(podcast, e);
              Navigator.pop(context);
            }),
          if (podcast == null)
            row(Icons.podcasts_rounded, 'Go to show', () {
              Navigator.pop(context);
              openShow(context, feedUrl: e.feedUrl);
            }),
          if (current)
            row(Icons.bookmark_add_outlined, 'Bookmark this moment (${fmtClock(audio.position.inMilliseconds)})', () async {
              final at = audio.position.inMilliseconds;
              final text = await _ask(context, 'Bookmark at ${fmtClock(at)}', 'What happens here? (optional)');
              if (text == null) return;
              mark.bookmarks.add(EpisodeNote(ms: at, text: text));
              pods.marksChanged();
            }),
          if (e.link != null) row(Icons.open_in_new_rounded, 'Episode web page', () => launchUrl(Uri.parse(e.link!), mode: LaunchMode.externalApplication)),
          row(Icons.copy_rounded, 'Copy link', () async {
            await Clipboard.setData(ClipboardData(text: e.link ?? (e.audioUrl.isNotEmpty ? e.audioUrl : e.title)));
            if (context.mounted) showSnack(context, 'Copied');
          }),
          const SizedBox(height: Space.s),
          _Stars(value: mark.rating, onChanged: (v) {
            mark.rating = v;
            pods.marksChanged();
          }),
          if (mark.bookmarks.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            Text('BOOKMARKS', style: context.text.labelSmall),
            for (final b in [...mark.bookmarks]..sort((a, b) => a.ms.compareTo(b.ms)))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: podColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                  child: Text(fmtClock(b.ms), style: TextStyle(color: podColor, fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                ),
                title: Text(b.text.isEmpty ? 'Bookmark' : b.text),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    mark.bookmarks.remove(b);
                    pods.marksChanged();
                  },
                ),
                onTap: () async {
                  if (!current) await pods.play(e);
                  await ref.read(audioCenterProvider).seek(Duration(milliseconds: b.ms));
                },
              ),
          ],
          const SizedBox(height: Space.l),
          TextFormField(
            initialValue: mark.note,
            minLines: 1,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Your notes', hintText: 'Ideas, quotes, things to look up'),
            onChanged: (v) {
              mark.note = v;
              pods.marksChanged();
            },
          ),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Text('SHOW NOTES', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            SelectableText(e.description, style: TextStyle(height: 1.55, color: AppColors.text.withValues(alpha: 0.88))),
          ],
        ],
      );
    },
  ),
);

Future<String?> _ask(BuildContext context, String title, String hint) {
  final c = TextEditingController();
  return showFormSheet<String>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.text.titleMedium),
        const SizedBox(height: Space.m),
        TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(context, v.trim())),
        const SizedBox(height: Space.l),
        FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('Your rating', style: context.text.bodySmall),
      const Spacer(),
      for (var i = 1; i <= 5; i++)
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value == i ? 0 : i),
          icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= value ? const Color(0xFFF5B301) : AppColors.text3),
        ),
    ],
  );
}

/// The episodes waiting to play, in order; drag to reorder.
Future<void> showQueueSheet(BuildContext context) => showAppSheet<void>(
  context,
  initialSize: 0.7,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) {
      final pods = ref.watch(podcastsProvider);
      final q = pods.queue;
      final now = pods.nowPlaying;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.s, Space.s),
            child: Row(
              children: [
                Expanded(child: Text('Up next · ${q.length}', style: context.text.titleMedium)),
                if (q.isNotEmpty) TextButton(onPressed: pods.clearQueue, child: const Text('Clear')),
              ],
            ),
          ),
          if (now != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: Container(
                decoration: BoxDecoration(color: podColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(Radii.l)),
                child: EpisodeRow(episode: now, showShow: true),
              ),
            ),
          Expanded(
            child: q.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x4),
                      child: Text('Nothing queued. "Play next" or "Add to Up next" on any episode.', textAlign: TextAlign.center, style: context.text.bodySmall),
                    ),
                  )
                : ReorderableListView.builder(
                    scrollController: scroll,
                    buildDefaultDragHandles: false,
                    itemCount: q.length,
                    onReorder: pods.reorderQueue,
                    itemBuilder: (_, i) => Dismissible(
                      key: ValueKey(q[i].guid),
                      direction: DismissDirection.endToStart,
                      background: Container(color: AppColors.danger.withValues(alpha: 0.15), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: Space.xl), child: Icon(Icons.playlist_remove_rounded, color: AppColors.danger)),
                      onDismissed: (_) => pods.dequeue(q[i]),
                      child: EpisodeRow(
                        episode: q[i],
                        showShow: true,
                        trailing: ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded, color: AppColors.text3))),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  ),
);

// ---- radio --------------------------------------------------------------------------------

/// A station in a list: tap to play, hold for details.
class StationRow extends ConsumerWidget {
  const StationRow({super.key, required this.station, this.around});
  final Station station;

  /// The list it's in, so next and previous in the player move through it.
  final List<Station>? around;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.watch(radioProvider);
    final s = station;
    final key = RadioStore.trackKey(s.id);
    final (current, playing) = ref.watch(audioCenterProvider.select((a) => (a.current?.key == key, a.playing)));
    final fav = radio.isFavorite(s.id);
    final facts = [if (s.bitrate > 0) '${s.bitrate} kbps', if (s.codec.isNotEmpty) s.codec].join(' · ');
    return InkWell(
      onTap: () => radio.play(s, around: around),
      onLongPress: () => showStationSheet(context, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 9),
        child: Row(
          children: [
            Stack(
              children: [
                PodArt(s.favicon, title: s.name, size: 52, radius: 12, icon: Icons.radio_rounded),
                if (current)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(color: Colors.black45, child: Center(child: EqualizerBars(playing: playing, color: Colors.white, size: 20))),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: current ? podColor : AppColors.text)),
                  if (s.subtitle.isNotEmpty) Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
                  if (facts.isNotEmpty) Text(facts, maxLines: 1, style: TextStyle(fontSize: 11, color: AppColors.text3)),
                ],
              ),
            ),
            IconButton(
              tooltip: fav ? 'Unfavourite' : 'Favourite',
              onPressed: () {
                HapticFeedback.selectionClick();
                radio.toggleFavorite(s);
              },
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, key: ValueKey(fav), color: fav ? podColor : AppColors.text3, size: 22),
              ),
            ),
            PlayButton(trackKey: key, onTap: () => radio.play(s, around: around)),
          ],
        ),
      ),
    );
  }
}

Future<void> showStationSheet(BuildContext context, Station s) => showAppSheet<void>(
  context,
  initialSize: 0.62,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) {
      final radio = ref.watch(radioProvider);
      final key = RadioStore.trackKey(s.id);
      final (current, playing) = ref.watch(audioCenterProvider.select((a) => (a.current?.key == key, a.playing)));
      final mark = radio.markOf(s.id);
      final facts = [if (s.language.isNotEmpty) s.language, if (s.bitrate > 0) '${s.bitrate} kbps', if (s.codec.isNotEmpty) s.codec].join(' · ');
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
        children: [
          Row(
            children: [
              PodArt(s.favicon, title: s.name, size: 84, radius: 16, icon: Icons.radio_rounded),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(4)),
                          child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        ),
                        if (s.country.isNotEmpty) ...[const SizedBox(width: 8), Flexible(child: Text('${s.flag} ${s.country}'.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall))],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
                    if (facts.isNotEmpty) Text(facts, style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (s.tags.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final t in s.tags.take(8)) Chip(label: Text(t), visualDensity: VisualDensity.compact)]),
          ],
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: podColor, foregroundColor: AppLook.onBrand(podColor)),
                  onPressed: () => radio.play(s),
                  icon: Icon(current && playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(current && playing ? 'Pause' : 'Listen live'),
                ),
              ),
              const SizedBox(width: Space.s),
              IconButton.filledTonal(
                style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
                onPressed: () => radio.toggleFavorite(s),
                icon: Icon(mark.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: mark.favorite ? podColor : null),
              ),
              if (s.homepage != null) ...[
                const SizedBox(width: Space.s),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
                  tooltip: 'Website',
                  onPressed: () => launchUrl(Uri.parse(s.homepage!), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.public_rounded),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.m),
          _Stars(value: mark.rating, onChanged: (v) {
            mark.rating = v;
            radio.changed(s);
          }),
          const SizedBox(height: Space.s),
          TextFormField(
            initialValue: mark.note,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Your notes', hintText: 'Best shows, times, presenters'),
            onChanged: (v) {
              mark.note = v;
              radio.changed(s);
            },
          ),
          const SizedBox(height: Space.m),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: s.homepage ?? s.url));
              if (context.mounted) showSnack(context, 'Copied');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy link'),
          ),
        ],
      );
    },
  ),
);
