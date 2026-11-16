import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/fullscreen_image.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../media/audio_center.dart';
import '../playlists/add_tracks_screen.dart' show openAddTracks;
import '../playlists/playlist_sources.dart' show TgAudioType;
import '../playlists/playlist_widgets.dart' show EqualizerBars, PlaylistCover, showPlaylistEditor;
import '../playlists/playlists.dart';
import '../playlists/playlists_screen.dart' show PlaylistScreen;
import '../sections/section_kit.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'podcast_models.dart';
import 'podcast_show_screen.dart';
import 'podcast_store.dart';
import 'podcast_widgets.dart';
import 'radio_store.dart';

import '../sections/skeletons.dart';
import 'podcast_skeletons.dart';
/// Podcasts and live radio: shows from Apple's directory or any RSS feed,
/// Telegram channels as shows, your own podcast playlists, downloads to
/// listen offline, and thousands of live stations. Ported from Alexandria.
class PodcastsScreen extends ConsumerStatefulWidget {
  const PodcastsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  static Future<void> open(BuildContext context, {int tab = 0}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PodcastsScreen(initialTab: tab)));

  @override
  ConsumerState<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends ConsumerState<PodcastsScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(podcastsProvider).refreshAll(quiet: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(ref.read(podcastsProvider).refreshAll(quiet: true));
  }

  @override
  Widget build(BuildContext context) {
    final pods = ref.watch(podcastsProvider);
    final unplayed = pods.latest.length;
    final playlists = ref.watch(playlistsProvider.select((s) => s.playlists.where((p) => p.isPodcast).length));
    return SectionScaffold(
      initialTab: widget.initialTab,
      title: 'Podcasts',
      tabTitles: const [null, null, null, 'Live Radio'],
      icon: Icons.podcasts_rounded,
      color: podColor,
      tabs: const [
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.headphones_rounded, size: 16), SizedBox(width: 6), Text('Listen now')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.explore_outlined, size: 16), SizedBox(width: 6), Text('Discover')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.video_library_outlined, size: 16), SizedBox(width: 6), Text('Library')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.radio_rounded, size: 16), SizedBox(width: 6), Text('Radio')])),
      ],
      actions: [
        IconButton(
          tooltip: 'Up next',
          onPressed: () => showQueueSheet(context),
          icon: Badge(
            isLabelVisible: pods.queue.isNotEmpty,
            label: Text('${pods.queue.length}'),
            backgroundColor: podColor,
            textColor: AppLook.onBrand(podColor),
            child: const Icon(Icons.queue_music_rounded),
          ),
        ),
        IconButton(tooltip: 'Add', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => showAddSheet(context, ref)),
        IconButton(tooltip: 'Settings', icon: const Icon(Icons.tune_rounded), onPressed: () => _settings(context, ref)),
      ],
      hero: SectionHero(
        subtitle: pods.subscriptions.isEmpty ? 'Shows from anywhere, your Telegram channels, and live radio from every country.' : 'Your shows, what\'s new, and live radio',
        stats: [
          ('${pods.subscriptions.length}', pods.subscriptions.length == 1 ? 'show' : 'shows'),
          ('$unplayed', 'new'),
          ('${pods.inProgress.length}', 'in progress'),
          ('$playlists', playlists == 1 ? 'playlist' : 'playlists'),
        ],
      ),
      views: const [_ListenNow(), _Discover(), _Library(), _Radio()],
      bottomBar: const BottomAudioBar(),
    );
  }
}

// ---- adding ---------------------------------------------------------------------------

Future<void> showAddSheet(BuildContext context, WidgetRef ref) async {
  final pick = await showFormSheet<String>(
    context,
    builder: (context) {
      Widget row(String v, IconData icon, String title, String sub) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: podColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: podColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub, style: context.text.bodySmall),
        onTap: () => Navigator.pop(context, v),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add', style: context.text.titleMedium),
          const SizedBox(height: Space.s),
          row('playlist', Icons.playlist_add_rounded, 'New podcast playlist', 'Episodes, Telegram audio and your own files, in your order'),
          row('telegram', Icons.send_rounded, 'Telegram channels', 'Their audio and voice posts become episodes'),
          row('rss', Icons.rss_feed_rounded, 'A show by its RSS link', 'Any podcast feed address'),
          row('opml', Icons.file_upload_outlined, 'Import from another app', 'An OPML file of your subscriptions'),
          row('export', Icons.ios_share_rounded, 'Export your shows', 'Save them as an OPML file'),
        ],
      );
    },
  );
  if (pick == null || !context.mounted) return;
  final pods = ref.read(podcastsProvider);
  switch (pick) {
    case 'playlist':
      final p = await showPlaylistEditor(context, ref, shelf: 'podcasts');
      if (p != null && context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: p.id)));
    case 'telegram':
      final current = [
        for (final s in pods.subscriptions.where((s) => s.isTelegram))
          if (s.feedUrl.split(':') case [_, final account, final chat]) SourceRef(account: account, chatId: int.tryParse(chat) ?? 0, title: s.title),
      ];
      final picked = await pickSources(context, account: ref.read(activeAccountIdProvider), current: current, title: 'Podcast channels', hint: 'Channels that post talks, sermons, lectures, shows or audiobooks.');
      if (picked == null) return;
      final keep = {for (final s in picked) PodcastStore.telegramShowId(s.account, s.chatId)};
      for (final s in current) {
        final id = PodcastStore.telegramShowId(s.account, s.chatId);
        if (!keep.contains(id)) pods.unsubscribe(id);
      }
      if (context.mounted) showSnack(context, 'Reading the channels…', icon: Icons.hourglass_top_rounded);
      await pods.addTelegramShows(picked);
    case 'rss':
      final c = TextEditingController();
      final url = await showFormSheet<String>(
        context,
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add by RSS link', style: context.text.titleMedium),
            const SizedBox(height: Space.m),
            TextField(controller: c, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://example.com/feed.xml'), onSubmitted: (v) => Navigator.pop(context, v)),
            const SizedBox(height: Space.l),
            FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Follow')),
          ],
        ),
      );
      if (url == null || url.trim().isEmpty || !context.mounted) return;
      showSnack(context, 'Reading the feed…', icon: Icons.hourglass_top_rounded);
      final pod = await pods.addByUrl(url);
      if (!context.mounted) return;
      showSnack(context, pod == null ? 'That link isn\'t a podcast feed' : 'Following ${pod.title}', icon: pod == null ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded);
    case 'opml':
      final r = await FilePicker.pickFiles(type: FileType.any);
      final path = r.firstOrNull?.path;
      if (path == null) return;
      try {
        final feeds = PodcastStore.parseOpml(await File(path).readAsString());
        if (feeds.isEmpty) {
          if (context.mounted) showSnack(context, 'No shows in that file', icon: Icons.info_outline_rounded);
          return;
        }
        pods.startOpmlImport(feeds);
      } on FormatException catch (e) {
        if (context.mounted) showSnack(context, e.message, icon: Icons.error_outline_rounded);
      }
    case 'export':
      final f = await pods.exportOpml();
      if (!context.mounted) return;
      showSnack(context, 'Saved to Files → Exports', icon: Icons.ios_share_rounded);
      await OpenFilex.open(f.path);
  }
}

Future<void> _settings(BuildContext context, WidgetRef ref) => showAppSheet<void>(
  context,
  initialSize: 0.62,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) {
      final pods = ref.watch(podcastsProvider);
      final audio = ref.watch(audioCenterProvider);
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Text('Podcasts', style: context.text.titleMedium),
          const SizedBox(height: Space.m),
          Text('Default episode order', style: context.text.labelSmall),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in EpisodeSort.values)
                ChoiceChip(label: Text(s.short), selected: pods.episodeSort == s.name, onSelected: (_) => pods.setSettings(sort: s.name)),
            ],
          ),
          const SizedBox(height: Space.l),
          Text('Talk speed (podcasts only; music keeps its own)', style: context.text.labelSmall),
          Slider(
            min: 0.5,
            max: 3,
            divisions: 10,
            value: audio.talkSpeed.clamp(0.5, 3),
            label: '${audio.talkSpeed}×',
            onChanged: (v) {
              audio.talkSpeed = double.parse(v.toStringAsFixed(2));
              if (audio.current?.spoken ?? false) audio.setSpeed(audio.talkSpeed);
              pods.talkSpeed = audio.talkSpeed;
              pods.setSettings();
            },
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Tell me about new episodes'), subtitle: Text('Checked when the app is open, every few hours', style: context.text.bodySmall), value: pods.notifyNew, onChanged: (v) => pods.setSettings(notify: v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Delete downloads once played'), value: pods.deletePlayedDownloads, onChanged: (v) => pods.setSettings(deletePlayed: v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show in the side menu'), value: pods.inDrawer, onChanged: (v) => pods.setSettings(drawer: v)),
          const SizedBox(height: Space.s),
          Text('${pods.downloaded.length} downloads · ${sizeText(pods.downloadedBytes).isEmpty ? '0 KB' : sizeText(pods.downloadedBytes)}', style: context.text.bodySmall),
        ],
      );
    },
  ),
);

// ---- pieces ------------------------------------------------------------------------------

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.action, this.onAction, this.top = Space.xl});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(Space.l, top, Space.s, Space.s),
    child: Row(
      children: [
        Expanded(child: Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.text))),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(action!, style: TextStyle(color: AppColors.text3)), Icon(Icons.chevron_right_rounded, color: AppColors.text3, size: 20)]),
          ),
      ],
    ),
  );
}

class _ShowTile extends ConsumerWidget {
  const _ShowTile({required this.show, this.width = 118});
  final Podcast show;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pods = ref.watch(podcastsProvider);
    final n = pods.unplayedIn(show);
    final fav = pods.showMark(show.feedUrl).favorite;
    return GestureDetector(
      onTap: () => openShow(context, feedUrl: show.feedUrl),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showMenu(context, ref, show);
      },
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Hero(tag: 'show-${show.feedUrl}', child: PodArt(show.imageUrl, title: show.title, size: width, radius: 14, show: show.feedUrl)),
                if (n > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: podColor, borderRadius: BorderRadius.circular(99)),
                      child: Text('$n', style: TextStyle(color: AppLook.onBrand(podColor), fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ),
                if (fav) const Positioned(left: 6, bottom: 6, child: Icon(Icons.favorite_rounded, color: Colors.white, size: 16, shadows: [Shadow(blurRadius: 8)])),
              ],
            ),
            const SizedBox(height: 6),
            Text(show.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.text)),
          ],
        ),
      ),
    );
  }
}

Future<void> _showMenu(BuildContext context, WidgetRef ref, Podcast show) => showFormSheet<void>(
  context,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      final pods = ref.watch(podcastsProvider);
      final mark = pods.showMark(show.feedUrl);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PodArt(show.imageUrl, title: show.title, size: 54, radius: 12, show: show.feedUrl),
              const SizedBox(width: Space.m),
              Expanded(child: Text(show.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.m),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    mark.rating = mark.rating == i ? 0 : i;
                    pods.marksChanged();
                  },
                  icon: Icon(i <= mark.rating ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= mark.rating ? const Color(0xFFF5B301) : AppColors.text3),
                ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  mark.favorite = !mark.favorite;
                  pods.marksChanged();
                },
                icon: Icon(mark.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: mark.favorite ? podColor : null),
              ),
            ],
          ),
          TextFormField(
            initialValue: mark.note,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes'),
            onChanged: (v) {
              mark.note = v;
              pods.marksChanged();
            },
          ),
          const SizedBox(height: Space.m),
          ListTile(contentPadding: EdgeInsets.zero, leading: lead(const Icon(Icons.done_all_rounded)), title: const Text('Mark all played'), onTap: () => pods.markAllPlayed(show, true)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: lead(Icon(Icons.close_rounded, color: AppColors.danger)),
            title: Text('Unfollow', style: TextStyle(color: AppColors.danger)),
            onTap: () {
              pods.unsubscribe(show.feedUrl);
              Navigator.pop(context);
            },
          ),
        ],
      );
    },
  ),
);

class _OpmlBanner extends ConsumerWidget {
  const _OpmlBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pods = ref.watch(podcastsProvider);
    final job = pods.opml;
    if (job == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: podColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.m)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.running ? 'Importing shows · ${job.done}/${job.total}' : 'Imported ${job.added} shows${job.already > 0 ? ' · ${job.already} already followed' : ''}${job.failed.isNotEmpty ? ' · ${job.failed.length} couldn\'t be read' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(onPressed: job.running ? pods.cancelOpmlImport : pods.dismissOpmlImport, child: Text(job.running ? 'Stop' : 'OK')),
            ],
          ),
          if (job.running) LinearProgressIndicator(value: job.total == 0 ? null : job.done / job.total, color: podColor),
        ],
      ),
    );
  }
}

// ---- listen now ---------------------------------------------------------------------------

class _ListenNow extends ConsumerWidget {
  const _ListenNow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pods = ref.watch(podcastsProvider);
    final going = pods.inProgress.take(12).toList();
    final latest = pods.latest;
    final shows = pods.subscriptions;
    if (shows.isEmpty && going.isEmpty) {
      return CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _OpmlBanner()),
          SliverFillRemaining(
            hasScrollBody: false,
            child: SectionEmpty(
              icon: Icons.podcasts_rounded,
              title: 'Start listening',
              body: 'Follow shows from the Discover tab, add Telegram channels that post talks and lectures, or tune into live radio from anywhere.',
              action: 'Add shows',
              onAction: () => showAddSheet(context, ref),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      color: podColor,
      onRefresh: () => pods.refreshAll(),
      child: CustomScrollView(
        key: const PageStorageKey('listen'),
        slivers: [
          const SliverToBoxAdapter(child: _OpmlBanner()),
          if (going.isNotEmpty) ...[
            const SliverToBoxAdapter(child: _Heading('Continue listening', top: Space.l)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 212,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  itemCount: going.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Space.m),
                  itemBuilder: (context, i) => _ResumeCard(state: going[i]),
                ),
              ),
            ),
          ],
          if (pods.queue.isNotEmpty) ...[
            _Heading('Up next · ${pods.queue.length}', action: 'All', onAction: () => showQueueSheet(context)).toSliver(),
            SliverList.builder(itemCount: pods.queue.take(3).length, itemBuilder: (_, i) => EpisodeRow(episode: pods.queue[i], showShow: true)),
          ],
          if (shows.isNotEmpty) ...[
            const _Heading('Your shows').toSliver(),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 162,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  itemCount: shows.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Space.m),
                  itemBuilder: (_, i) => _ShowTile(show: shows[i]),
                ),
              ),
            ),
          ],
          _Heading(pods.refreshing ? 'New episodes · updating…' : 'New episodes').toSliver(),
          if (latest.isEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(Space.xl), child: Text('All caught up.', textAlign: TextAlign.center, style: context.text.bodySmall)))
          else
            SliverList.builder(itemCount: latest.length, itemBuilder: (_, i) => EpisodeRow(episode: latest[i], showShow: true)),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

extension on Widget {
  Widget toSliver() => SliverToBoxAdapter(child: this);
}

/// A started episode, big, with how far in and how much is left.
class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.state});
  final EpisodeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = state.episode;
    final pods = ref.read(podcastsProvider);
    final p = pods.progressOf(e);
    final left = e.durationMs > 0 ? fmtDuration(((e.durationMs - state.posMs) / 1000).round()) : '';
    return GestureDetector(
      onTap: () => pods.play(e),
      onLongPress: () => showEpisodeSheet(context, e),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                PodArt(e.art, title: e.podcastTitle, size: 150, radius: 16, show: e.feedUrl),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    child: LinearProgressIndicator(value: p, minHeight: 4, color: podColor, backgroundColor: Colors.black38),
                  ),
                ),
                Positioned(right: 8, bottom: 12, child: PlayButton(trackKey: PodcastStore.trackKey(e), size: 38, filled: true, onTap: () => pods.play(e))),
              ],
            ),
            const SizedBox(height: 6),
            Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.text)),
            Text(left.isEmpty ? e.podcastTitle : '$left left', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
          ],
        ),
      ),
    );
  }
}

// ---- discover -------------------------------------------------------------------------------

class _Discover extends ConsumerStatefulWidget {
  const _Discover();

  @override
  ConsumerState<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends ConsumerState<_Discover> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  int? _genre;
  late Future<List<PodcastHit>> _list = _load();
  Future<List<PodcastHit>>? _search;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<List<PodcastHit>> _load({bool force = false}) {
    final pods = ref.read(podcastsProvider);
    if (_genre == null) return pods.top(force: force);
    return pods.search(podcastGenres.firstWhere((g) => g.$2 == _genre).$1, genre: _genre, force: force);
  }

  void _pickGenre(int? g) => setState(() {
    _genre = g;
    _list = _load();
  });

  Future<void> _country() async {
    final pods = ref.read(podcastsProvider);
    final picked = await showAppSheet<String>(
      context,
      initialSize: 0.7,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s), child: Text('Charts from', style: context.text.titleMedium)),
          for (final (code, name) in chartCountries)
            ListTile(
              leading: Text(flagOf(code), style: const TextStyle(fontSize: 22)),
              title: Text(name),
              trailing: pods.chartCountry == code ? Icon(Icons.check_rounded, color: podColor) : null,
              onTap: () => Navigator.pop(context, code),
            ),
        ],
      ),
    );
    if (picked == null) return;
    pods.setSettings(country: picked);
    setState(() => _list = _load());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pods = ref.watch(podcastsProvider);
    final country = chartCountries.where((c) => c.$1 == pods.chartCountry).firstOrNull;
    return RefreshIndicator(
      color: podColor,
      onRefresh: () async {
        setState(() {
          _list = _load(force: true);
          if (_search != null) _search = ref.read(podcastsProvider).search(_q.text.trim(), force: true);
        });
        await (_search ?? _list);
      },
      child: CustomScrollView(
        key: const PageStorageKey('discover'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onChanged: (v) {
                  if (v.trim().isEmpty) setState(() => _search = null);
                },
                onSubmitted: (v) => setState(() => _search = v.trim().isEmpty ? null : pods.search(v.trim())),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search every podcast',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: AppColors.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: AppColors.line)),
                  suffixIcon: _q.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _q.clear();
                            _search = null;
                          }),
                        ),
                ),
              ),
            ),
          ),
          if (_search != null)
            FutureBuilder<List<PodcastHit>>(
              future: _search,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SliverToBoxAdapter(child: PodcastHitSkeleton());
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(padding: const EdgeInsets.all(Space.x4), child: Text(pods.unreachable ? 'The podcast directory isn\'t answering. Check your connection.' : 'No shows found.', textAlign: TextAlign.center, style: context.text.bodySmall)),
                  );
                }
                return SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => _HitRow(hit: list[i]));
              },
            )
          else ...[
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 4),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                        avatar: Text(flagOf(pods.chartCountry)),
                        label: Text(country?.$2 ?? pods.chartCountry.toUpperCase()),
                        onPressed: _country,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                        label: const Text('Top charts'),
                        selected: _genre == null,
                        selectedColor: podColor,
                        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _genre == null ? AppLook.onBrand(podColor) : AppColors.text),
                        onSelected: (_) => _pickGenre(null),
                      ),
                    ),
                    for (final (name, id) in podcastGenres)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                          label: Text(name),
                          selected: _genre == id,
                          selectedColor: podColor,
                          labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _genre == id ? AppLook.onBrand(podColor) : AppColors.text),
                          onSelected: (_) => _pickGenre(id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            FutureBuilder<List<PodcastHit>>(
              future: _list,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return SliverToBoxAdapter(child: PodcastGridSkeleton(ranked: _genre == null));
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x4),
                      child: Column(
                        children: [
                          Text(pods.unreachable ? 'Couldn\'t reach the podcast directory.' : 'Nothing here right now.', style: context.text.bodySmall),
                          TextButton(onPressed: () => setState(() => _list = _load(force: true)), child: const Text('Try again')),
                        ],
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 120),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: 0.66),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final h = list[i];
                      final subbed = h.feedUrl != null && pods.subscribed(h.feedUrl!);
                      return GestureDetector(
                        onTap: () => openShow(context, hit: h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                PodArt(h.artwork, title: h.title, radius: 14),
                                if (_genre == null)
                                  Positioned(
                                    left: 6,
                                    top: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                                    ),
                                  ),
                                if (subbed) Positioned(right: 6, top: 6, child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 18, shadows: const [Shadow(blurRadius: 8)])),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(h.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.text)),
                            Text(h.genre.isNotEmpty && _genre == null ? h.genre : h.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.text3)),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _HitRow extends ConsumerWidget {
  const _HitRow({required this.hit});
  final PodcastHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pods = ref.watch(podcastsProvider);
    final subbed = hit.feedUrl != null && pods.subscribed(hit.feedUrl!);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 4),
      leading: PodArt(hit.artwork, title: hit.title, size: 56, radius: 12),
      title: Text(hit.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([hit.author, if (hit.genre.isNotEmpty) hit.genre, if (hit.episodes > 0) '${hit.episodes} episodes'].where((s) => s.isNotEmpty).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
      trailing: subbed ? Icon(Icons.check_circle_rounded, color: podColor) : const Icon(Icons.chevron_right_rounded),
      onTap: () => openShow(context, hit: hit),
    );
  }
}

// ---- library ---------------------------------------------------------------------------------

enum _Shelf {
  shows('Shows', Icons.grid_view_rounded),
  telegram('Telegram', Icons.send_rounded),
  playlists('Playlists', Icons.queue_music_rounded),
  downloads('Downloads', Icons.download_done_rounded),
  saved('Saved', Icons.favorite_border_rounded),
  history('History', Icons.history_rounded);

  const _Shelf(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _Library extends ConsumerStatefulWidget {
  const _Library();

  @override
  ConsumerState<_Library> createState() => _LibraryState();
}

class _LibraryState extends ConsumerState<_Library> with AutomaticKeepAliveClientMixin {
  _Shelf _shelf = _Shelf.shows;
  bool _favOnly = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pods = ref.watch(podcastsProvider);
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 4),
            children: [
              for (final s in _Shelf.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                    avatar: Icon(s.icon, size: 16, color: _shelf == s ? AppLook.onBrand(podColor) : AppColors.text2),
                    showCheckmark: false,
                    label: Text(s.label),
                    selected: _shelf == s,
                    selectedColor: podColor,
                    labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _shelf == s ? AppLook.onBrand(podColor) : AppColors.text),
                    onSelected: (_) => setState(() => _shelf = s),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
    switch (_shelf) {
      case _Shelf.shows:
        final shows = [for (final s in pods.subscriptions) if (!s.isTelegram && (!_favOnly || pods.showMark(s.feedUrl).favorite)) s];
        slivers.addAll([
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, 0),
              child: Row(
                children: [
                  Expanded(child: Text('${shows.length} ${shows.length == 1 ? 'show' : 'shows'}${pods.refreshing ? ' · updating…' : ''}', style: context.text.labelMedium?.copyWith(color: AppColors.text2))),
                  FilterChip(
                    visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                    label: const Text('Favourites'),
                    selected: _favOnly,
                    onSelected: (v) => setState(() => _favOnly = v),
                  ),
                ],
              ),
            ),
          ),
          if (shows.isEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(Space.x4), child: Text(_favOnly ? 'No favourites yet. Hold a show to favourite it.' : 'Follow shows from Discover.', textAlign: TextAlign.center, style: context.text.bodySmall)))
          else
            SliverPadding(
              padding: const EdgeInsets.all(Space.l),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: 0.72),
                itemCount: shows.length,
                itemBuilder: (context, i) => LayoutBuilder(builder: (context, c) => _ShowTile(show: shows[i], width: c.maxWidth)),
              ),
            ),
        ]);
      case _Shelf.telegram:
        final shows = [for (final s in pods.subscriptions) if (s.isTelegram) s];
        slivers.addAll([
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
              child: Text('Channels whose audio, voice posts and audio files you follow as shows.', style: context.text.bodySmall),
            ),
          ),
          for (final s in shows)
            SliverToBoxAdapter(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                leading: TgAvatar(chatId: int.tryParse(s.feedUrl.split(':').last), title: s.title, size: 48),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${s.episodes.length} episodes${pods.unplayedIn(s) > 0 ? ' · ${pods.unplayedIn(s)} new' : ''}', style: context.text.bodySmall),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openShow(context, feedUrl: s.feedUrl),
                onLongPress: () => _showMenu(context, ref, s),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: OutlinedButton.icon(onPressed: () => showAddSheet(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('Add Telegram channels')),
            ),
          ),
        ]);
      case _Shelf.playlists:
        final lists = [for (final p in ref.watch(playlistsProvider).sorted) if (p.isPodcast) p];
        slivers.addAll([
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
              child: Text('Your own podcast playlists: episodes from Telegram channels, audio files and voice notes, in the order you want.', style: context.text.bodySmall),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: 0.78),
              itemCount: lists.length + 1,
              itemBuilder: (context, i) {
                if (i == lists.length) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(Radii.l),
                    onTap: () async {
                      final p = await showPlaylistEditor(context, ref, shelf: 'podcasts');
                      if (p != null && context.mounted) await openAddTracks(context, playlistId: p.id, type: TgAudioType.voice);
                    },
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line, width: 1.5), color: AppColors.surface),
                            child: Icon(Icons.add_rounded, size: 40, color: podColor),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('New playlist', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                      ],
                    ),
                  );
                }
                final p = lists[i];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: p.id))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          AspectRatio(aspectRatio: 1, child: PlaylistCover(playlist: p)),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: podColor,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: p.tracks.isEmpty ? null : () => ref.read(playlistsProvider.notifier).play(p),
                                child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.play_arrow_rounded, color: AppLook.onBrand(podColor))),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                      Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
                    ],
                  ),
                );
              },
            ),
          ),
        ]);
      case _Shelf.downloads:
        final list = pods.downloaded;
        slivers.addAll([
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, 0),
              child: Row(
                children: [
                  Expanded(child: Text('${list.length} saved · ${sizeText(pods.downloadedBytes).isEmpty ? '0 KB' : sizeText(pods.downloadedBytes)}', style: context.text.labelMedium?.copyWith(color: AppColors.text2))),
                  if (list.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        if (!await confirmDelete(context, title: 'Remove every download?', message: 'The episodes stay in their shows; only the saved copies go.', action: 'Remove')) return;
                        for (final s in [...list]) {
                          await pods.removeDownload(s.episode);
                        }
                      },
                      child: const Text('Remove all'),
                    ),
                ],
              ),
            ),
          ),
          if (list.isEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(Space.x4), child: Text('Download episodes to listen without a connection.', textAlign: TextAlign.center, style: context.text.bodySmall)))
          else
            SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => EpisodeRow(episode: list[i].episode, showShow: true)),
        ]);
      case _Shelf.saved:
        final list = pods.bookmarked;
        slivers.add(
          list.isEmpty
              ? SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(Space.x4), child: Text('Favourite episodes, bookmarks and notes collect here.', textAlign: TextAlign.center, style: context.text.bodySmall)))
              : SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => EpisodeRow(episode: list[i].episode, showShow: true)),
        );
      case _Shelf.history:
        final list = pods.history.take(100).toList();
        slivers.add(
          list.isEmpty
              ? SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(Space.x4), child: Text('Episodes you listen to show up here.', textAlign: TextAlign.center, style: context.text.bodySmall)))
              : SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => EpisodeRow(episode: list[i].episode, showShow: true)),
        );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 120)));
    return CustomScrollView(key: const PageStorageKey('library'), slivers: slivers);
  }
}

// ---- radio --------------------------------------------------------------------------------------

class _Radio extends ConsumerStatefulWidget {
  const _Radio();

  @override
  ConsumerState<_Radio> createState() => _RadioState();
}

class _RadioState extends ConsumerState<_Radio> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();

  /// 'top', 'fav', 'recent' or a genre tag.
  String _view = 'top';
  List<Station> _results = const [];
  bool _loading = true;
  bool _more = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(radioProvider).ready;
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool get _local => _view == 'fav' || _view == 'recent';

  /// A new list (genre, search, country) shows the skeleton; pulling to
  /// refresh ([force]) keeps the current one up while the directory is
  /// asked again.
  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      if (!force) _results = const [];
    });
    final r = await ref.read(radioProvider).browse(name: _q.text, tag: _local || _view == 'top' ? null : _view, force: force);
    if (!mounted) return;
    setState(() {
      _results = r;
      _more = r.length >= RadioStore.pageSize ~/ 2;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    final more = await ref.read(radioProvider).browse(name: _q.text, tag: _local || _view == 'top' ? null : _view, offset: _results.length);
    if (!mounted) return;
    final have = {for (final s in _results) s.name.toLowerCase()};
    final fresh = more.where((s) => have.add(s.name.toLowerCase())).toList();
    setState(() {
      _results = [..._results, ...fresh];
      _more = fresh.isNotEmpty;
    });
  }

  void _pick(String v) {
    setState(() => _view = v);
    if (!_local) _load();
  }

  Future<void> _country() async {
    final radio = ref.read(radioProvider);
    final picked = await showAppSheet<RadioCountry?>(context, initialSize: 0.85, builder: (context, scroll) => _CountryPicker(scroll: scroll));
    if (picked == null) return;
    picked.code.isEmpty ? radio.setCountry('', '') : radio.setCountry(picked.code, picked.name);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final radio = ref.watch(radioProvider);
    final shown = _view == 'fav' ? radio.favorites : (_view == 'recent' ? radio.recents : _results);
    final now = radio.nowPlaying;
    final flag = countryFlag(radio.country, radio.countryName);
    return RefreshIndicator(
      color: podColor,
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        key: const PageStorageKey('radio'),
        slivers: [
          if (now != null) SliverToBoxAdapter(child: _OnAir(station: now)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _q,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) {
                        if (_local) setState(() => _view = 'top');
                        _load();
                      },
                      onChanged: (v) {
                        if (v.isEmpty) _load();
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        hintText: radio.country.isEmpty ? 'Search stations worldwide' : 'Search in ${radio.countryName}',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: AppColors.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: AppColors.line)),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Material(
                    color: AppColors.surface,
                    shape: StadiumBorder(side: BorderSide(color: AppColors.line)),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: _country,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            flag.isEmpty ? Icon(Icons.public_rounded, size: 18, color: podColor) : Text(flag, style: const TextStyle(fontSize: 17)),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 90),
                              child: Text(radio.country.isEmpty ? 'World' : radio.countryName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            const Icon(Icons.expand_more_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 4),
                children: [
                  for (final (id, name, icon) in [('top', 'Top', Icons.trending_up_rounded), ('fav', 'Favourites', Icons.favorite_border_rounded), ('recent', 'Recent', Icons.history_rounded)])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                        showCheckmark: false,
                        avatar: Icon(icon, size: 15, color: _view == id ? AppLook.onBrand(podColor) : AppColors.text2),
                        label: Text(name),
                        selected: _view == id,
                        selectedColor: podColor,
                        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _view == id ? AppLook.onBrand(podColor) : AppColors.text),
                        onSelected: (_) => _pick(id),
                      ),
                    ),
                  for (final (tag, name) in RadioStore.genres)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                        label: Text(name),
                        selected: _view == tag,
                        selectedColor: podColor,
                        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _view == tag ? AppLook.onBrand(podColor) : AppColors.text),
                        onSelected: (_) => _pick(tag),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_local && !_loading && radio.usingFallback && shown.isNotEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0), child: Text('Radio Browser is down, so this list is from TuneIn.', style: context.text.bodySmall))),
          if (!_local && _loading && _results.isEmpty)
            const SliverToBoxAdapter(child: StationSkeleton())
          else if (shown.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  children: [
                    Icon(Icons.radio_rounded, size: 40, color: AppColors.text3),
                    const SizedBox(height: Space.m),
                    Text(
                      _view == 'fav'
                          ? 'No favourite stations yet. Tap a heart to keep one here.'
                          : _view == 'recent'
                          ? 'Stations you play show up here.'
                          : radio.unreachable
                          ? 'The radio directory isn\'t answering. Its servers are sometimes down; try again in a little while.'
                          : 'No stations found. Try fewer words, another genre or another country.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall,
                    ),
                    if (!_local) TextButton(onPressed: () => _load(force: true), child: const Text('Try again')),
                  ],
                ),
              ),
            )
          else ...[
            SliverList.builder(itemCount: shown.length, itemBuilder: (_, i) => StationRow(station: shown[i], around: shown)),
            if (!_local && _more)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(Space.l), child: OutlinedButton(onPressed: _loadMore, child: const Text('Load more')))),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

/// The station playing, large, with its controls.
class _OnAir extends ConsumerWidget {
  const _OnAir({required this.station});
  final Station station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = station;
    final (playing, loading) = ref.watch(audioCenterProvider.select((a) => (a.playing, a.loading)));
    final radio = ref.read(radioProvider);
    final c = podColor;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        gradient: AppLook.minimalExplore ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0.06)]),
        color: AppLook.minimalExplore ? AppColors.surface : null,
        border: Border.all(color: AppLook.minimalExplore ? AppColors.line : c.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: s.favicon == null || s.favicon!.isEmpty ? null : () => openFullscreenUrl(context, s.favicon!, title: s.name),
            child: PodArt(s.favicon, title: s.name, size: 64, radius: 14, icon: Icons.radio_rounded),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(4)),
                      child: const Text('ON AIR', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                    const SizedBox(width: 8),
                    EqualizerBars(playing: playing && !loading, color: c, size: 14),
                  ],
                ),
                const SizedBox(height: 4),
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text)),
                if (s.subtitle.isNotEmpty) Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              ],
            ),
          ),
          IconButton(onPressed: () => showStationSheet(context, s), icon: const Icon(Icons.more_horiz_rounded)),
          PlayButton(trackKey: RadioStore.trackKey(s.id), size: 48, filled: true, onTap: () => radio.play(s)),
        ],
      ),
    );
  }
}

class _CountryPicker extends ConsumerStatefulWidget {
  const _CountryPicker({required this.scroll});
  final ScrollController scroll;

  @override
  ConsumerState<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends ConsumerState<_CountryPicker> {
  late final Future<List<RadioCountry>> _all = ref.read(radioProvider).countries();
  String _q = '';

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: TextField(
          autofocus: false,
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search countries'),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<RadioCountry>>(
          future: _all,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const SingleChildScrollView(child: SkeletonRows(count: 14, art: 28, artRadius: 6, lines: 1));
            final list = (snap.data ?? const <RadioCountry>[]).where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q) || c.code.toLowerCase() == _q).toList();
            return ListView.builder(
              controller: widget.scroll,
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ListTile(leading: Icon(Icons.public_rounded, color: podColor), title: const Text('Every country'), onTap: () => Navigator.pop(context, const RadioCountry('', '', 0)));
                }
                final c = list[i - 1];
                return ListTile(
                  leading: SizedBox(width: 30, child: c.flag.isEmpty ? const Icon(Icons.flag_outlined) : Text(c.flag, style: const TextStyle(fontSize: 22))),
                  title: Text(c.name),
                  trailing: c.count > 0 ? Text('${c.count}', style: context.text.bodySmall) : null,
                  onTap: () => Navigator.pop(context, c),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}
