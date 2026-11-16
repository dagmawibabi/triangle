import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../../core/widgets/app_sheet.dart' show confirmDelete;
import '../sections/ai_run.dart';
import '../sections/section_kit.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'gallery.dart';
import 'gallery_screen.dart';
import 'gallery_search.dart';

enum _When {
  any('Any time'),
  week('This week'),
  month('This month'),
  year('This year'),
  older('Over a year ago');

  const _When(this.label);
  final String label;
}

/// Search the gallery: words in captions and sources at once, older posts
/// through Telegram, and what the pictures show once they're indexed.
class GallerySearchScreen extends ConsumerStatefulWidget {
  const GallerySearchScreen({super.key, this.initial = ''});
  final String initial;

  static Future<void> open(BuildContext context, {String query = ''}) =>
      Navigator.of(context).push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => GallerySearchScreen(initial: query),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
        ),
      ));

  @override
  ConsumerState<GallerySearchScreen> createState() => _GallerySearchScreenState();
}

class _GallerySearchScreenState extends ConsumerState<GallerySearchScreen> {
  static const _historyKey = 'gallery_search_history';
  late final _q = TextEditingController(text: widget.initial);
  final _focus = FocusNode();
  final _debounce = Debounce();
  String _query = '';
  bool? _videos;
  _When _when = _When.any;
  PhotoShape? _shape;
  bool _favorites = false;
  String? _source;
  bool _deep = false;
  int? _deepAdded;
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _query = widget.initial;
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _history = p.getStringList(_historyKey) ?? const []);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(galleryProvider.notifier).ready;
      if (!mounted) return;
      unawaited(ref.read(galleryFeedProvider.notifier).loadAll(_mine()));
      if (widget.initial.isEmpty) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce.cancel();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<SourceRef> _mine() => [for (final s in ref.read(galleryProvider).sources) if (s.account == ref.read(activeAccountIdProvider)) s];

  void _set(String v) {
    _q.text = v;
    _q.selection = TextSelection.collapsed(offset: v.length);
    setState(() {
      _query = v;
      _deepAdded = null;
    });
    _remember(v);
  }

  Future<void> _remember(String v) async {
    final q = v.trim();
    if (q.length < 2) return;
    final next = [q, for (final h in _history) if (h.toLowerCase() != q.toLowerCase()) h].take(12).toList();
    setState(() => _history = next);
    await (await SharedPreferences.getInstance()).setStringList(_historyKey, next);
  }

  Future<void> _searchTelegram() async {
    setState(() => _deep = true);
    try {
      final n = await deepSearchGallery(ref.read, _mine(), _query);
      if (mounted) setState(() => _deepAdded = n);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t search Telegram: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _deep = false);
    }
  }

  Future<void> _index(List<GalleryItem> items) async {
    final idx = ref.read(galleryIndexProvider.notifier);
    final n = await idx.run(items, limit: 200);
    if (!mounted) return;
    final err = ref.read(galleryIndexProvider).error;
    showSnack(context, err ?? 'Understood $n more photos', icon: err == null ? Icons.auto_awesome_rounded : Icons.error_outline_rounded);
  }

  (DateTime?, DateTime?) get _range {
    final now = DateTime.now();
    return switch (_when) {
      _When.any => (null, null),
      _When.week => (now.subtract(Duration(days: now.weekday - 1)), null),
      _When.month => (DateTime(now.year, now.month), null),
      _When.year => (DateTime(now.year), null),
      _When.older => (null, DateTime(now.year - 1, now.month, now.day)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(galleryProvider);
    final feed = ref.watch(galleryFeedProvider);
    final index = ref.watch(galleryIndexProvider);
    final all = galleryItems(g, feed);
    final (since, until) = _range;
    final filtering = _videos != null || _when != _When.any || _shape != null || _favorites || _source != null;
    final hits = (_query.trim().isEmpty && !filtering)
        ? const <GalleryHit>[]
        : searchGallery(g, all, index.notes, query: _query, videos: _videos, since: since, until: until, sourceKey: _source, shape: _shape, favorites: _favorites);
    final photos = all.where((i) => !i.video).toList();
    final indexed = photos.where((i) => index.notes.containsKey(i.key)).length;
    // The words the pictures are most often about, as suggestions.
    final tagCounts = <String, int>{};
    for (final n in index.notes.values) {
      for (final t in n.tags) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
    final topTags = (tagCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(14).map((e) => e.key).toList();
    final where = <String>{for (final h in hits) ...h.seen.split(', ').where((s) => s.isNotEmpty)};
    final accent = galleryColor;

    Widget chip(String label, bool on, VoidCallback tap, {IconData? icon}) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
        showCheckmark: false,
        avatar: icon == null ? null : Icon(icon, size: 15, color: on ? AppLook.onBrand(accent) : AppColors.text2),
        label: Text(label),
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: on ? AppLook.onBrand(accent) : AppColors.text),
        selectedColor: accent,
        selected: on,
        onSelected: (_) => tap(),
      ),
    );

    final header = <Widget>[
      SliverToBoxAdapter(
        child: SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 4),
            children: [
              chip('Photos', _videos == false, () => setState(() => _videos = _videos == false ? null : false), icon: Icons.photo_outlined),
              chip('Videos', _videos == true, () => setState(() => _videos = _videos == true ? null : true), icon: Icons.videocam_outlined),
              chip('Favorites', _favorites, () => setState(() => _favorites = !_favorites), icon: Icons.favorite_border_rounded),
              PopupMenuButton<_When>(
                tooltip: 'When',
                initialValue: _when,
                onSelected: (v) => setState(() => _when = v),
                itemBuilder: (_) => [for (final w in _When.values) CheckedPopupMenuItem(value: w, checked: _when == w, child: Text(w.label))],
                child: IgnorePointer(child: chip(_when == _When.any ? 'When' : _when.label, _when != _When.any, () {}, icon: Icons.calendar_month_outlined)),
              ),
              PopupMenuButton<PhotoShape?>(
                tooltip: 'Shape',
                onSelected: (v) => setState(() => _shape = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('Any shape')),
                  for (final s in PhotoShape.values) CheckedPopupMenuItem(value: s, checked: _shape == s, child: Text(s.name[0].toUpperCase() + s.name.substring(1))),
                ],
                child: IgnorePointer(child: chip(_shape == null ? 'Shape' : _shape!.name[0].toUpperCase() + _shape!.name.substring(1), _shape != null, () {}, icon: Icons.crop_rounded)),
              ),
              for (final s in g.sources)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                    showCheckmark: false,
                    avatar: TgAvatar(chatId: s.chatId, title: s.title, size: 20, accountId: s.account),
                    label: Text(s.title, overflow: TextOverflow.ellipsis),
                    selectedColor: accent,
                    labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _source == s.key ? AppLook.onBrand(accent) : AppColors.text),
                    selected: _source == s.key,
                    onSelected: (_) => setState(() => _source = _source == s.key ? null : s.key),
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: GestureDetector(
          onTap: () => SmartSearchScreen.open(context),
          child: _SmartCard(indexed: indexed, photos: photos.length, state: index, onRun: () => _index(photos), onStop: ref.read(galleryIndexProvider.notifier).stop),
        ),
      ),
      if (_query.trim().isEmpty && !filtering)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_history.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(child: Text('RECENT', style: context.text.labelSmall)),
                      TextButton(
                        onPressed: () async {
                          setState(() => _history = const []);
                          await (await SharedPreferences.getInstance()).remove(_historyKey);
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final h in _history) ActionChip(avatar: const Icon(Icons.history_rounded, size: 16), label: Text(h), onPressed: () => _set(h))]),
                  const SizedBox(height: Space.l),
                ],
                Text(topTags.isEmpty ? 'TRY' : 'IN YOUR PICTURES', style: context.text.labelSmall),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in topTags.isEmpty ? const ['screenshot', 'receipt', 'document', 'food', 'selfie', 'people', 'sunset', 'car'] : topTags)
                      ActionChip(avatar: Icon(Icons.search_rounded, size: 16, color: accent), label: Text(t), onPressed: () => _set(t)),
                  ],
                ),
                if (topTags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s),
                    child: Text('Words in captions work now. Words for what\'s in a picture work once smart search has looked at it.', style: context.text.bodySmall),
                  ),
              ],
            ),
          ),
        )
      else
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${hits.length} ${hits.length == 1 ? 'result' : 'results'}${where.isEmpty ? '' : ' · matched in ${where.join(', ')}'}',
                    style: context.text.labelMedium?.copyWith(color: AppColors.text2),
                  ),
                ),
                if (_query.trim().isNotEmpty)
                  TextButton.icon(
                    onPressed: _deep ? null : _searchTelegram,
                    icon: _deep ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore_rounded, size: 18),
                    label: Text(_deepAdded == null ? 'Older posts' : '+$_deepAdded found'),
                  ),
              ],
            ),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: (v) => _debounce(const Duration(milliseconds: 180), () {
            if (mounted) {
              setState(() {
                _query = v;
                _deepAdded = null;
              });
            }
          }),
          onSubmitted: (v) {
            setState(() => _query = v);
            _remember(v);
          },
          style: TextStyle(fontSize: 17, color: AppColors.text),
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintText: 'Search photos and videos',
            suffixIcon: _q.text.isEmpty ? null : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => _set('')),
          ),
        ),
      ),
      body: GalleryGrid(
        items: [for (final h in hits) h.item],
        header: header,
        loading: feed.anyLoading && hits.isEmpty && (_query.isNotEmpty || filtering),
        empty: (_query.trim().isEmpty && !filtering)
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_search_rounded, size: 44, color: AppColors.text3),
                    const SizedBox(height: Space.m),
                    Text(
                      indexed < photos.length && _query.trim().isNotEmpty
                          ? 'Nothing yet. Smart search has looked at $indexed of ${photos.length} photos; let it look at the rest, or search older posts.'
                          : 'No matches. Try other words or fewer filters.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// How much of the gallery smart search understands, and the button that
/// teaches it the rest.
class _SmartCard extends StatelessWidget {
  const _SmartCard({required this.indexed, required this.photos, required this.state, required this.onRun, required this.onStop});
  final int indexed;
  final int photos;
  final GalleryIndexState state;
  final VoidCallback onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (photos == 0) return const SizedBox.shrink();
    final c = galleryColor;
    final share = photos == 0 ? 0.0 : indexed / photos;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.m),
      decoration: BoxDecoration(
        gradient: AppLook.minimalExplore ? null : LinearGradient(colors: [c.withValues(alpha: 0.14), c.withValues(alpha: 0.04)]),
        color: AppLook.minimalExplore ? AppColors.surface : null,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppLook.minimalExplore ? AppColors.line : c.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: state.running ? (state.total == 0 ? null : state.done / state.total) : share,
                  strokeWidth: 3,
                  color: c,
                  backgroundColor: c.withValues(alpha: 0.15),
                  strokeCap: StrokeCap.round,
                ),
                Icon(Icons.auto_awesome_rounded, size: 17, color: c),
              ],
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Smart search', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text)),
                Text(
                  state.running
                      ? 'Looking at photos · ${state.done}/${state.total}'
                      : state.error != null
                      ? state.error!
                      : indexed >= photos
                      ? 'Knows what\'s in all $photos loaded photos'
                      : 'Knows what\'s in $indexed of $photos photos. Search by what they show: "receipt", "cat", "whiteboard".',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: state.error != null && !state.running ? AppColors.warning : null),
                ),
              ],
            ),
          ),
          if (state.running)
            TextButton(onPressed: onStop, child: const Text('Stop'))
          else if (indexed < photos)
            TextButton(onPressed: onRun, child: Text(indexed == 0 ? 'Start' : 'Look at more')),
          Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.text3),
        ],
      ),
    );
  }
}


/// Smart search at work: the pictures it's looking at, the model's
/// thinking and answer as they stream, what it saw in each picture, and
/// the controls — the same page as the other AI runs.
class SmartSearchScreen extends ConsumerStatefulWidget {
  const SmartSearchScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SmartSearchScreen()));

  @override
  ConsumerState<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends ConsumerState<SmartSearchScreen> {
  late final _view = ValueNotifier<AiRunView>(_viewOf(ref.read(galleryIndexProvider)));

  @override
  void initState() {
    super.initState();
    ref.listenManual(galleryIndexProvider, (_, s) => _view.value = _viewOf(s));
    ref.listenManual(galleryFeedProvider, (_, _) => _view.value = _viewOf(ref.read(galleryIndexProvider)));
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  List<GalleryItem> get _photos => galleryItems(ref.read(galleryProvider), ref.read(galleryFeedProvider)).where((i) => !i.video).toList();

  AiRunView _viewOf(GalleryIndexState s) {
    final photos = _photos;
    final known = photos.where((i) => s.notes.containsKey(i.key)).length;
    final feed = ref.read(galleryFeedProvider.notifier);
    final autoload = ref.read(galleryProvider).autoDownload;
    return AiRunView(
      status: s.running ? AiRunStatus.running : (s.stopped ? AiRunStatus.stopped : (s.total > 0 ? AiRunStatus.done : AiRunStatus.idle)),
      model: s.model,
      total: s.total,
      done: s.done,
      failed: s.failed,
      current: s.current,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
      lastError: s.error,
      summary: 'Knows what’s in $known of ${photos.length} loaded photos. Search them by what they show: “receipt”, “cat”, “whiteboard”.',
      entries: [
        for (final l in s.log)
          if ((s.items[l.key] ?? feed.byKey(l.key)) case final item?)
            AiRunEntry(
              title: s.notes[l.key]?.description ?? (item.caption.isNotEmpty ? item.caption : item.source),
              subtitle: [
                if (s.notes[l.key]?.tags.isNotEmpty ?? false) s.notes[l.key]!.tags.take(6).join(', '),
                if (s.notes[l.key]?.text.isNotEmpty ?? false) '“${s.notes[l.key]!.text}”',
              ].join('  ·  '),
              error: l.error,
              at: l.at,
              leading: TgPicture(file: item.thumb, mini: item.mini, cacheWidth: 160, autoload: autoload, account: item.account),
              onTap: () => openGalleryViewer(context, [item], 0, hero: 'smart'),
            ),
      ],
    );
  }

  Future<void> _run() async {
    final photos = _photos;
    final n = await ref.read(galleryIndexProvider.notifier).run(photos, limit: 200);
    if (!mounted) return;
    final err = ref.read(galleryIndexProvider).error;
    if (err != null || n > 0) showSnack(context, err ?? 'Understood $n more photos', icon: err == null ? Icons.auto_awesome_rounded : Icons.error_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.read(galleryIndexProvider.notifier);
    final s = ref.watch(galleryIndexProvider);
    final model = s.model;
    return AiRunPage(
      title: 'Smart search',
      icon: Icons.image_search_rounded,
      color: galleryColor,
      view: _view,
      live: idx.live,
      runLabel: 'Look at more photos',
      about: 'A vision model looks at each photo once and notes what’s in it, so you can search by what pictures show. Notes stay on this phone.',
      onRun: _run,
      onStop: idx.stop,
      onPause: idx.stop,
      onResume: _run,
      onClear: idx.clearLog,
      settings: [
        ListTile(
          leading: lead(const Icon(Icons.memory_rounded)),
          title: const Text('Model'),
          subtitle: Text('${model.isEmpty ? 'Chosen when it runs' : 'Last run: ${model.split(':').last}'} · your chat model when it can see pictures, else the cheapest one that can', style: context.text.bodySmall),
        ),
        ListTile(
          leading: lead(const Icon(Icons.photo_library_outlined)),
          title: const Text('What it looks at'),
          subtitle: Text('The small preview of each loaded photo (and video thumbnails), four to a model call, up to 200 per run.', style: context.text.bodySmall),
        ),
        ListTile(
          leading: lead(Icon(Icons.restart_alt_rounded, color: AppColors.danger)),
          title: const Text('Forget what it learned'),
          subtitle: Text('${s.notes.length} photos described so far', style: context.text.bodySmall),
          onTap: () async {
            if (await confirmDelete(context, title: 'Forget photo notes?', message: 'Smart search forgets what it saw; it can look again later.', action: 'Forget')) await idx.forget();
          },
        ),
      ],
    );
  }
}
