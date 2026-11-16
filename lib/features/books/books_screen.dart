import 'dart:async';
import '../account/account_router.dart' show openChatInAccount;
import 'dart:convert';
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
import '../playlists/add_tracks_screen.dart' show pickTelegramChat;
import '../sections/section_kit.dart';
import '../telegram/data/telegram_tools.dart' show toolRunnerFamily;
import '../telegram/presentation/tg_avatar.dart';
import 'book_parsers.dart';
import 'book_reader.dart';
import 'books.dart';
import 'reading_stats_screen.dart';

import '../sections/skeletons.dart';
/// The section's colour; the app's monochrome one in the minimal look.
Color get booksColor => AppLook.brand(const Color(0xFF8B5CF6));

class BooksScreen extends ConsumerStatefulWidget {
  const BooksScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BooksScreen()));

  @override
  ConsumerState<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends ConsumerState<BooksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(booksProvider.notifier).ready;
      if (mounted) unawaited(ref.read(bookFeedProvider.notifier).loadAll(_mine()));
    });
  }

  List<SourceRef> _mine() => [for (final s in ref.read(booksProvider).sources) if (s.account == ref.read(activeAccountIdProvider)) s];

  Future<void> _sources() async {
    final picked = await pickSources(
      context,
      account: ref.read(activeAccountIdProvider),
      current: ref.read(booksProvider).sources,
      title: 'Book sources',
      hint: 'Channels and groups that post books (EPUB, PDF, Word and more).',
    );
    if (picked == null) return;
    await ref.read(booksProvider.notifier).setSources(picked);
    unawaited(ref.read(bookFeedProvider.notifier).loadAll(_mine()));
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: bookFormats.toList());
    if (!mounted) return;
    var n = 0;
    for (final f in picked) {
      if (f.path == null) continue;
      await ref.read(booksProvider.notifier).importFile(f.path!);
      n++;
    }
    if (mounted) showSnack(context, 'Added $n ${n == 1 ? 'book' : 'books'}', icon: Icons.library_add_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(booksProvider);
    final reading = s.books.where((b) => b.status == ReadStatus.reading).length;
    final finished = s.books.where((b) => b.status == ReadStatus.finished).length;
    return SectionScaffold(
      title: 'Library',
      icon: Icons.auto_stories_rounded,
      color: booksColor,
      tabs: const [
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.explore_outlined, size: 16), SizedBox(width: 6), Text('Discover')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.collections_bookmark_outlined, size: 16), SizedBox(width: 6), Text('Books')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shelves, size: 16), SizedBox(width: 6), Text('Shelves')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.edit_note_rounded, size: 16), SizedBox(width: 6), Text('Notes')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.insights_rounded, size: 16), SizedBox(width: 6), Text('Stats')])),
      ],
      actions: [
        IconButton(tooltip: 'Reading stats', icon: const Icon(Icons.insights_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReadingStatsScreen()))),
        IconButton(tooltip: 'Add from your phone', icon: const Icon(Icons.upload_file_rounded), onPressed: _importFile),
        IconButton(tooltip: 'Book sources', icon: const Icon(Icons.add_link_rounded), onPressed: _sources),
      ],
      hero: SectionHero(
        subtitle: s.books.isEmpty ? 'Books from your channels and your phone, read here.' : 'Today: ${s.todayMinutes} of ${s.goal} min · ${s.streak} day streak',
        stats: [('${s.books.length}', 'books'), ('$reading', 'reading'), ('$finished', 'finished'), ('${s.sources.length}', 'sources')],
      ),
      views: [
        _DiscoverTab(onSources: _sources),
        _LibraryTab(onSources: _sources, onImport: _importFile),
        const _ShelvesTab(),
        const _NotesTab(),
        const _StatsTab(),
      ],
      bottomBar: const BottomAudioBar(),
    );
  }
}

// ---- covers --------------------------------------------------------------------

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.width = 110});
  final Book book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final b = book;
    final h = width * 1.5;
    Widget child;
    if (b.coverPath != null && File(b.coverPath!).existsSync()) {
      child = Image(image: ResizeImage(FileImage(File(b.coverPath!)), width: (width * 3).round()), fit: BoxFit.cover, width: width, height: h);
    } else if (b.mini != null) {
      child = Stack(fit: StackFit.expand, children: [Image.memory(base64Decode(b.mini!), fit: BoxFit.cover), _titleOn(b, dark: true)]);
    } else {
      child = _titleOn(b);
    }
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 5))]),
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
    );
  }

  Widget _titleOn(Book b, {bool dark = false}) {
    final hue = (b.title.hashCode % 360).abs().toDouble();
    return Container(
      decoration: BoxDecoration(
        gradient: dark
            ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55000000), Color(0xCC000000)])
            : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [HSLColor.fromAHSL(1, hue, 0.45, 0.35).toColor(), HSLColor.fromAHSL(1, (hue + 50) % 360, 0.5, 0.18).toColor()]),
      ),
      padding: EdgeInsets.all(width * 0.09),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: width * 0.25, height: 2, color: Colors.white54),
          SizedBox(height: width * 0.06),
          Expanded(child: Text(b.title, maxLines: 6, overflow: TextOverflow.fade, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: width * 0.12, height: 1.15, fontFamily: 'serif'))),
          if (b.author.isNotEmpty) Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: width * 0.085)),
          Text(b.format.toUpperCase(), style: TextStyle(color: Colors.white54, fontSize: width * 0.07, fontWeight: FontWeight.w700, letterSpacing: 1)),
        ],
      ),
    );
  }
}

/// Book covers waiting to load.
const _coverSkeleton = Align(alignment: Alignment.topCenter, child: SkeletonGrid(count: 9, maxExtent: 140, childAspectRatio: 0.55, radius: 8));

void openBookDetail(BuildContext context, Book b) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailScreen(bookId: b.id)));

// ---- library -------------------------------------------------------------------

class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab({required this.onSources, required this.onImport});
  final VoidCallback onSources;
  final VoidCallback onImport;

  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String _filter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = ref.watch(booksProvider);
    final store = ref.read(booksProvider.notifier);
    if (s.books.isEmpty && !store.isReady) return const SkeletonPage(child: _coverSkeleton);
    if (s.books.isEmpty) {
      return SingleChildScrollView(
        child: Column(
          children: [
            SectionEmpty(
              icon: Icons.auto_stories_outlined,
              title: 'Your library is empty',
              body: 'Add channels and groups that post books, then pick what to read from Discover. Or add EPUB, PDF, Word, FB2 and text files from your phone.',
              action: 'Add book sources',
              onAction: widget.onSources,
            ),
            TextButton.icon(onPressed: widget.onImport, icon: const Icon(Icons.upload_file_rounded), label: const Text('Add files from this phone')),
          ],
        ),
      );
    }
    final q = _q.toLowerCase();
    final list = [
      for (final b in s.sorted)
        if ((q.isEmpty || '${b.title} ${b.author} ${b.source}'.toLowerCase().contains(q)) &&
            switch (_filter) {
              'reading' => b.status == ReadStatus.reading,
              'want' => b.status == ReadStatus.want,
              'finished' => b.status == ReadStatus.finished,
              'fav' => b.favorite,
              _ => true,
            })
          b,
    ];
    final cont = s.books.where((b) => b.status == ReadStatus.reading && b.openedAt != null).toList()..sort((a, b) => b.openedAt!.compareTo(a.openedAt!));
    final width = MediaQuery.sizeOf(context).width;
    return CustomScrollView(
      slivers: [
        if (cont.isNotEmpty && q.isEmpty && _filter == 'all')
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s), child: Text('Continue reading', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Space.l),
                    itemCount: cont.length,
                    separatorBuilder: (_, _) => const SizedBox(width: Space.m),
                    itemBuilder: (_, i) {
                      final b = cont[i];
                      return GestureDetector(
                        onTap: () => openBook(context, ref, b),
                        onLongPress: () => openBookDetail(context, b),
                        child: Container(
                          width: 290,
                          padding: const EdgeInsets.all(Space.m),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
                          child: Row(
                            children: [
                              BookCover(book: b, width: 80),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    if (b.author.isNotEmpty) Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                                    const SizedBox(height: Space.s),
                                    LinearProgressIndicator(value: b.progress, color: booksColor, minHeight: 4, borderRadius: BorderRadius.circular(9)),
                                    const SizedBox(height: 4),
                                    Text('${(b.progress * 100).round()}%${b.pages > 0 ? ' · page ${b.page}/${b.pages}' : ''}', style: context.text.labelSmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
            child: Row(
              children: [
                Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search your books', isDense: true), onChanged: (v) => setState(() => _q = v))),
                PopupMenuButton<Object>(
                  icon: const Icon(Icons.tune_rounded),
                  onSelected: (v) => v is BookSort ? store.setSort(v) : store.setGrid(!s.grid),
                  itemBuilder: (_) => [
                    for (final o in BookSort.values) CheckedPopupMenuItem(value: o, checked: s.sort == o, child: Text(o.label)),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'view', child: Text(s.grid ? 'Show as list' : 'Show as grid')),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              children: [
                for (final (k, label) in const [('all', 'All'), ('reading', 'Reading'), ('want', 'Want to read'), ('finished', 'Finished'), ('fav', 'Favorites')])
                  Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k))),
              ],
            ),
          ),
        ),
        if (s.grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.x4),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: width > 900 ? 6 : (width > 600 ? 4 : 3), mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: 0.5),
              itemCount: list.length,
              itemBuilder: (_, i) => _GridBook(book: list[i]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.x4),
            sliver: SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => _ListBook(book: list[i])),
          ),
      ],
    );
  }
}

class _GridBook extends ConsumerWidget {
  const _GridBook({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = book;
    return GestureDetector(
      onTap: () => openBook(context, ref, b),
      onLongPress: () => openBookDetail(context, b),
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                BookCover(book: b, width: box.maxWidth),
                if (!b.downloaded && b.chatId != null) Positioned(right: 4, top: 4, child: _Badge(icon: Icons.cloud_download_outlined)),
                if (b.favorite) const Positioned(left: 4, top: 4, child: _Badge(icon: Icons.favorite_rounded, color: Color(0xFFFF4D6D))),
                if (b.status == ReadStatus.finished) const Positioned(right: 4, bottom: 4, child: _Badge(icon: Icons.check_rounded, color: Color(0xFF22C55E))),
              ],
            ),
            const SizedBox(height: 6),
            if (b.progress > 0 && b.status != ReadStatus.finished) ...[
              LinearProgressIndicator(value: b.progress, color: booksColor, minHeight: 3, borderRadius: BorderRadius.circular(9)),
              const SizedBox(height: 4),
            ],
            Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
            if (b.author.isNotEmpty) Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, this.color = Colors.white});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
    child: Icon(icon, size: 13, color: color),
  );
}

class _ListBook extends ConsumerWidget {
  const _ListBook({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = book;
    return InkWell(
      onTap: () => openBook(context, ref, b),
      onLongPress: () => openBookDetail(context, b),
      borderRadius: BorderRadius.circular(Radii.m),
      child: Padding(
        padding: const EdgeInsets.all(Space.s),
        child: Row(
          children: [
            BookCover(book: b, width: 56),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text([if (b.author.isNotEmpty) b.author, b.format.toUpperCase(), b.status.label, if (b.minutes > 0) '${b.minutes} min read'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: b.progress, color: booksColor, minHeight: 3, borderRadius: BorderRadius.circular(9)),
                ],
              ),
            ),
            IconButton(icon: Icon(Icons.more_vert_rounded, color: AppColors.text3), onPressed: () => openBookDetail(context, b)),
          ],
        ),
      ),
    );
  }
}

// ---- discover ------------------------------------------------------------------

class _DiscoverTab extends ConsumerStatefulWidget {
  const _DiscoverTab({required this.onSources});
  final VoidCallback onSources;

  @override
  ConsumerState<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<_DiscoverTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String? _source;
  String? _format;
  bool _grid = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _tap(BookPost p, Book? have) async {
    final b = have ?? await ref.read(booksProvider.notifier).addPost(p);
    if (mounted) await openBook(context, ref, b);
  }

  Future<void> _add(BookPost p) async {
    await ref.read(booksProvider.notifier).addPost(p);
    if (mounted) showSnack(context, 'Added “${p.title}”', icon: Icons.library_add_check_rounded);
  }

  Widget _thumb(BookPost p) => p.thumb != null || p.mini != null
      ? TgPicture(file: p.thumb, mini: p.mini, cacheWidth: 300, account: p.account)
      : Container(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [booksColor.withValues(alpha: 0.35), booksColor.withValues(alpha: 0.12)])),
          padding: const EdgeInsets.all(Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(p.title, maxLines: 5, overflow: TextOverflow.fade, style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'serif', fontSize: 13))),
              Text(p.format.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: booksColor)),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = ref.watch(booksProvider);
    final feed = ref.watch(bookFeedProvider);
    final account = ref.watch(activeAccountIdProvider);
    if (s.sources.isEmpty && !ref.read(booksProvider.notifier).isReady) return const SkeletonPage(child: _coverSkeleton);
    // Still coming: a source of this account not loaded (or failed) yet.
    final pending = s.sources.any((x) => x.account == account && !feed.bySource.containsKey(x.key) && !feed.errors.containsKey(x.key));
    if (s.sources.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(icon: Icons.explore_outlined, title: 'No book sources', body: 'Pick channels and groups that share books. Their EPUBs, PDFs and documents show up here.', action: 'Add sources', onAction: widget.onSources),
      );
    }
    final sources = [for (final x in s.sources) if (_source == null || x.key == _source) x];
    final q = _q.toLowerCase();
    final all = ref.read(bookFeedProvider.notifier).all(sources);
    final formats = {for (final p in all) p.format};
    final list = [for (final p in all) if ((q.isEmpty || '${p.title} ${p.fileName} ${p.caption}'.toLowerCase().contains(q)) && (_format == null || p.format == _format)) p];
    final more = sources.any((x) => feed.hasMore(x.key));
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 500 && !feed.anyLoading && more) {
          pooled([for (final x in sources) if (feed.hasMore(x.key)) x], 3, (x) => ref.read(bookFeedProvider.notifier).load(x, more: true));
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Row(
                children: [
                  Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Find a book in your sources', isDense: true), onChanged: (v) => setState(() => _q = v))),
                  IconButton(
                    tooltip: _grid ? 'Show as list' : 'Show as grid',
                    icon: Icon(_grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded),
                    onPressed: () => setState(() => _grid = !_grid),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                children: [
                  for (final f in formats)
                    Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: Text(f.toUpperCase()), selected: _format == f, onSelected: (_) => setState(() => _format = _format == f ? null : f))),
                  const SizedBox(width: Space.s),
                  for (final x in s.sources) SourceChip(source: x, selected: _source == x.key, onTap: () => setState(() => _source = _source == x.key ? null : x.key)),
                ],
              ),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: (feed.anyLoading || pending) && all.isEmpty ? _coverSkeleton : Center(child: Text('No books found', style: context.text.bodySmall)),
            )
          else if (_grid)
            SliverPadding(
              padding: const EdgeInsets.all(Space.l),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 140, mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: 0.5),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  final have = s.byPost(p.key);
                  return GestureDetector(
                    onTap: () => _tap(p, have),
                    onLongPress: have == null ? () => _add(p) : () => openBookDetail(context, have),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(borderRadius: BorderRadius.circular(6), child: _thumb(p)),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: have != null
                                    ? const _Badge(icon: Icons.library_add_check_rounded, color: Color(0xFF22C55E))
                                    : GestureDetector(onTap: () => _add(p), child: const _Badge(icon: Icons.add_rounded)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
                        Text([p.format.toUpperCase(), if (p.size > 0) sizeText(p.size)].join(' · '), style: context.text.labelSmall),
                      ],
                    ),
                  );
                },
              ),
            )
          else
            SliverList.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final p = list[i];
                final have = s.byPost(p.key);
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 42,
                      height: 60,
                      child: p.thumb != null || p.mini != null
                          ? TgPicture(file: p.thumb, mini: p.mini, cacheWidth: 150, account: p.account)
                          : Container(color: booksColor.withValues(alpha: 0.15), alignment: Alignment.center, child: Text(p.format.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: booksColor))),
                    ),
                  ),
                  title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([p.format.toUpperCase(), if (p.size > 0) sizeText(p.size), p.source, agoText(p.date)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  trailing: have != null
                      ? TextButton(onPressed: () => openBook(context, ref, have), child: Text(have.downloaded ? 'Read' : 'Open'))
                      : IconButton(
                          tooltip: 'Add to library',
                          icon: Icon(Icons.library_add_rounded, color: booksColor),
                          onPressed: () async {
                            await ref.read(booksProvider.notifier).addPost(p);
                            if (context.mounted) showSnack(context, 'Added “${p.title}”', icon: Icons.library_add_check_rounded);
                          },
                        ),
                  onTap: () async {
                    final b = have ?? await ref.read(booksProvider.notifier).addPost(p);
                    if (context.mounted) await openBook(context, ref, b);
                  },
                );
              },
            ),
          if (feed.anyLoading && list.isNotEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
          const SliverToBoxAdapter(child: SizedBox(height: Space.x4)),
        ],
      ),
    );
  }
}

// ---- shelves -------------------------------------------------------------------

Future<String?> _askName(BuildContext context, {String title = 'New shelf', String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showFormSheet<String>(
    context,
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.shelves, size: 30, color: booksColor),
        const SizedBox(height: Space.s),
        Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: Space.l),
        TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Classics, To study, Summer reads…'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        const SizedBox(height: Space.l),
        FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

class _ShelvesTab extends ConsumerWidget {
  const _ShelvesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(booksProvider);
    final store = ref.read(booksProvider.notifier);
    return ListView(
      padding: const EdgeInsets.only(top: Space.m, bottom: Space.x4),
      children: [
        for (final shelf in s.shelves) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.s),
            child: Row(
              children: [
                Expanded(child: Text(shelf, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Text('${s.books.where((b) => b.shelves.contains(shelf)).length}', style: context.text.labelSmall),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final n = await _askName(context, title: 'Rename shelf', initial: shelf);
                      if (n != null && n.isNotEmpty) await store.renameShelf(shelf, n);
                    }
                    if (v == 'delete' && context.mounted && await confirmDelete(context, title: 'Delete “$shelf”?', message: 'The books stay in your library.')) {
                      await store.deleteShelf(shelf);
                    }
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: Builder(
              builder: (context) {
                final books = s.books.where((b) => b.shelves.contains(shelf)).toList();
                if (books.isEmpty) return Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: Text('Empty — open a book\'s details to shelve it.', style: context.text.bodySmall));
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  itemCount: books.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Space.m),
                  itemBuilder: (_, i) => SizedBox(width: 100, child: _GridBook(book: books[i])),
                );
              },
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(Space.l),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('New shelf'),
            onPressed: () async {
              final n = await _askName(context);
              if (n != null && n.isNotEmpty) await store.addShelf(n);
            },
          ),
        ),
      ],
    );
  }
}

// ---- notes -------------------------------------------------------------------

class _NotesTab extends ConsumerStatefulWidget {
  const _NotesTab();

  @override
  ConsumerState<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<_NotesTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String _kind = 'all';

  @override
  bool get wantKeepAlive => true;

  void _openAt(Book b, {int block = 0, int page = 0}) => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => b.format == 'pdf' ? PdfReaderScreen(bookId: b.id, startPage: page > 0 ? page : null) : BookReaderScreen(bookId: b.id, startBlock: block),
  ));

  Future<void> _highlightMenu(Book b, Highlight h) async {
    final store = ref.read(booksProvider.notifier);
    final v = await showAppSheet<String>(
      context,
      initialSize: 0.55,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
            child: Text('“${h.text}”', maxLines: 4, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontStyle: FontStyle.italic, fontFamily: 'serif')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Row(
              children: [
                for (var i = 0; i < highlightColors.length; i++)
                  GestureDetector(
                    onTap: () => Navigator.pop(context, 'c$i'),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: Space.s),
                      decoration: BoxDecoration(
                        color: Color(highlightColors[i]),
                        shape: BoxShape.circle,
                        border: Border.all(color: h.color == i ? AppColors.text : Colors.transparent, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: Space.xl),
          ListTile(leading: lead(const Icon(Icons.menu_book_rounded)), title: const Text('Open at this spot'), onTap: () => Navigator.pop(context, 'open')),
          ListTile(leading: lead(const Icon(Icons.edit_note_rounded)), title: Text(h.note.isEmpty ? 'Add a note' : 'Edit the note'), onTap: () => Navigator.pop(context, 'note')),
          ListTile(leading: lead(const Icon(Icons.copy_rounded)), title: const Text('Copy the quote'), onTap: () => Navigator.pop(context, 'copy')),
          ListTile(leading: lead(Icon(Icons.delete_outline_rounded, color: AppColors.danger)), title: Text('Delete', style: TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(context, 'delete')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    if (v.startsWith('c')) {
      await store.updateHighlight(h.id, (x) => x.copyWith(color: int.parse(v.substring(1))));
      return;
    }
    switch (v) {
      case 'open':
        _openAt(b, block: h.block);
      case 'note':
        final r = await showFieldsSheet(
          context,
          icon: Icons.edit_note_rounded,
          color: booksColor,
          title: h.note.isEmpty ? 'Add a note' : 'Edit the note',
          subtitle: b.title,
          preview: Text('“${h.text}”', maxLines: 5, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontStyle: FontStyle.italic, fontFamily: 'serif')),
          fields: [SheetField('note', label: 'Your thoughts', initial: h.note, maxLines: 6, suggestions: const ['Important', 'Re-read this', 'Quote', 'Question', 'Disagree'])],
        );
        if (r?['note'] != null) await store.updateHighlight(h.id, (x) => x.copyWith(note: r!['note']));
      case 'copy':
        await Clipboard.setData(ClipboardData(text: '“${h.text}”\n— ${b.title}${b.author.isEmpty ? '' : ', ${b.author}'}'));
        if (mounted) showSnack(context, 'Copied', icon: Icons.copy_rounded);
      case 'delete':
        await store.removeHighlight(h.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = ref.watch(booksProvider);
    final q = _q.toLowerCase().trim();
    bool hit(String text) => q.isEmpty || text.toLowerCase().contains(q);
    final byBook = <String, List<Object>>{};
    for (final h in s.highlights) {
      final isNote = h.note.isNotEmpty;
      if (_kind == 'bookmarks' || (_kind == 'notes' && !isNote) || (_kind == 'highlights' && isNote)) continue;
      if (!hit('${h.text} ${h.note} ${s.byId(h.bookId)?.title ?? ''}')) continue;
      byBook.putIfAbsent(h.bookId, () => []).add(h);
    }
    if (_kind == 'all' || _kind == 'bookmarks') {
      for (final m in s.bookmarks) {
        if (!hit('${m.label} ${m.excerpt} ${s.byId(m.bookId)?.title ?? ''}')) continue;
        byBook.putIfAbsent(m.bookId, () => []).add(m);
      }
    }
    for (final list in byBook.values) {
      list.sort((a, b) {
        int pos(Object x) => x is Highlight ? x.block : (x as Bookmark).block * 1000 + x.page;
        return pos(a).compareTo(pos(b));
      });
    }
    final notes = s.highlights.where((h) => h.note.isNotEmpty).length;
    if (s.highlights.isEmpty && s.bookmarks.isEmpty) {
      return const SingleChildScrollView(
        child: SectionEmpty(icon: Icons.edit_note_rounded, title: 'No notes yet', body: 'While reading, select text to highlight it, write a note, or ask what it means. Bookmarks gather here too.'),
      );
    }
    final books = byBook.keys.map(s.byId).whereType<Book>().toList()..sort((a, b) => (b.openedAt ?? b.addedAt).compareTo(a.openedAt ?? a.addedAt));
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
      children: [
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search your highlights and notes', isDense: true), onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: Space.s),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (k, label) in [
                ('all', 'All'),
                ('highlights', 'Highlights · ${s.highlights.length - notes}'),
                ('notes', 'Notes · $notes'),
                ('bookmarks', 'Bookmarks · ${s.bookmarks.length}'),
              ])
                Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k))),
            ],
          ),
        ),
        if (books.isEmpty) Padding(padding: const EdgeInsets.all(Space.x4), child: Center(child: Text('Nothing matches', style: context.text.bodySmall))),
        for (final b in books) ...[
          const SizedBox(height: Space.l),
          // The book.
          InkWell(
            borderRadius: BorderRadius.circular(Radii.l),
            onTap: () => openBookDetail(context, b),
            child: Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.l),
                gradient: LinearGradient(colors: [booksColor.withValues(alpha: 0.16), booksColor.withValues(alpha: 0.03)]),
              ),
              child: Row(
                children: [
                  BookCover(book: b, width: 44),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFamily: 'serif')),
                        if (b.author.isNotEmpty) Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                        Text(
                          [
                            '${byBook[b.id]!.whereType<Highlight>().length} highlights',
                            if (byBook[b.id]!.whereType<Bookmark>().isNotEmpty) '${byBook[b.id]!.whereType<Bookmark>().length} bookmarks',
                            '${(b.progress * 100).round()}% read',
                          ].join(' · '),
                          style: context.text.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(tooltip: 'Continue reading', icon: const Icon(Icons.menu_book_rounded), onPressed: () => openBook(context, ref, b)),
                ],
              ),
            ),
          ),
          for (final n in byBook[b.id]!)
            if (n is Highlight)
              Padding(
                padding: const EdgeInsets.only(top: Space.s, left: Space.s),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.m),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.m),
                    onTap: () => _openAt(b, block: n.block),
                    onLongPress: () => _highlightMenu(b, n),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xs, Space.s),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.m),
                        border: Border(left: BorderSide(color: Color(highlightColors[n.color % highlightColors.length]), width: 4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    text: n.text,
                                    style: TextStyle(backgroundColor: Color(highlightColors[n.color % highlightColors.length]).withValues(alpha: AppColors.isLight ? 0.45 : 0.28)),
                                  ),
                                  style: context.text.bodyMedium?.copyWith(fontFamily: 'serif', height: 1.55),
                                ),
                              ),
                              IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.more_vert_rounded, size: 18, color: AppColors.text3), onPressed: () => _highlightMenu(b, n)),
                            ],
                          ),
                          if (n.note.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: Space.s, right: Space.s),
                              padding: const EdgeInsets.all(Space.s),
                              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.edit_note_rounded, size: 16, color: AppColors.text3),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(n.note, style: context.text.bodySmall?.copyWith(color: AppColors.text))),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(agoText(n.at), style: context.text.labelSmall),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else if (n is Bookmark)
              Padding(
                padding: const EdgeInsets.only(top: Space.s, left: Space.s),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.m),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
                    leading: Icon(Icons.bookmark_rounded, color: booksColor),
                    title: Text(n.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([if (n.excerpt.isNotEmpty) n.excerpt, agoText(n.at)].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(icon: Icon(Icons.close_rounded, size: 18, color: AppColors.text3), onPressed: () => ref.read(booksProvider.notifier).removeBookmark(n.id)),
                    onTap: () => _openAt(b, block: n.block, page: n.page),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

// ---- stats -------------------------------------------------------------------

class _StatsTab extends ConsumerWidget {
  const _StatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(booksProvider);
    final now = DateTime.now();
    final days = [for (var i = 13; i >= 0; i--) (now.subtract(Duration(days: i)), s.days[BooksState.dayKey(now.subtract(Duration(days: i)))] ?? 0)];
    final maxDay = days.fold<int>(s.goal, (m, d) => d.$2 > m ? d.$2 : m);
    final total = s.days.values.fold<int>(0, (a, b) => a + b);
    final finished = s.books.where((b) => b.status == ReadStatus.finished).toList();
    final thisYear = finished.where((b) => b.finishedAt?.year == now.year).length;
    final top = [...s.books]..sort((a, b) => b.minutes.compareTo(a.minutes));
    final goalDone = (s.todayMinutes / s.goal).clamp(0.0, 1.0);
    Widget tile(String v, String l) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w900)), Text(l, style: context.text.labelSmall)]),
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReadingStatsScreen())),
            icon: const Icon(Icons.insights_rounded, size: 18),
            label: const Text('Full reading stats'),
          ),
        ),
        Row(
          children: [
            SizedBox.square(
              dimension: 110,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(value: goalDone, strokeWidth: 10, color: booksColor, backgroundColor: AppColors.surface3, strokeCap: StrokeCap.round),
                  Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('${s.todayMinutes}', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w900)), Text('of ${s.goal} min', style: context.text.labelSmall)])),
                ],
              ),
            ),
            const SizedBox(width: Space.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goalDone >= 1 ? 'Goal reached today 🎉' : 'Today\'s reading', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${s.streak} day streak', style: context.text.bodySmall),
                  const SizedBox(height: Space.s),
                  Row(
                    children: [
                      Text('Daily goal', style: context.text.bodySmall),
                      Expanded(
                        child: Slider(
                          value: s.goal.toDouble().clamp(5, 120),
                          min: 5,
                          max: 120,
                          divisions: 23,
                          label: '${s.goal} min',
                          onChanged: (v) => ref.read(booksProvider.notifier).setGoal(v.round()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.l),
        Row(children: [tile('${(total / 60).toStringAsFixed(1)}h', 'read in all'), const SizedBox(width: Space.s), tile('${finished.length}', 'books finished'), const SizedBox(width: Space.s), tile('$thisYear', 'this year')]),
        const SizedBox(height: Space.l),
        Text('Last 14 days', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Space.s),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (d, m) in days)
                Expanded(
                  child: Tooltip(
                    message: '${d.day}/${d.month}: $m min',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: m == 0 ? 3 : 4 + 90 * m / maxDay,
                            decoration: BoxDecoration(color: m >= s.goal ? booksColor : booksColor.withValues(alpha: m == 0 ? 0.15 : 0.5), borderRadius: BorderRadius.circular(4)),
                          ),
                          const SizedBox(height: 4),
                          Text('${d.day}', style: TextStyle(fontSize: 9.5, color: AppColors.text3)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        if (top.isNotEmpty && top.first.minutes > 0) ...[
          Text('Most read', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          for (final b in top.where((b) => b.minutes > 0).take(8))
            ListTile(contentPadding: EdgeInsets.zero, leading: BookCover(book: b, width: 34), title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Text('${b.minutes} min'), onTap: () => openBookDetail(context, b)),
        ],
      ],
    );
  }
}

// ---- one book ------------------------------------------------------------------

class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(booksProvider);
    final b = s.byId(bookId);
    if (b == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This book was removed')));
    final store = ref.read(booksProvider.notifier);
    final hl = s.highlights.where((h) => h.bookId == b.id).length;
    final dl = store.downloadProgress(b.id);
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  final t = await _askName(context, title: 'Title', initial: b.title);
                  if (t != null && t.isNotEmpty) await store.update(b.id, (x) => x.copyWith(title: t));
                  if (!context.mounted) return;
                  final a = await _askName(context, title: 'Author', initial: b.author);
                  if (a != null) await store.update(b.id, (x) => x.copyWith(author: a));
                case 'post':
                  await openChatInAccount(context, b.chatId!, hint: b.account, openAt: b.messageId);
                case 'share':
                  final chat = await pickTelegramChat(context, title: 'Share to…');
                  if (chat != null) await ref.read(toolRunnerFamily(b.account!)).forwardTo(chat, b.chatId!, [b.messageId!]);
                case 'other':
                  await OpenFilex.open(b.path!);
                case 'remove':
                  if (await confirmDelete(context, title: 'Remove “${b.title}”?', message: 'The book, its file on this phone, highlights and bookmarks go. It stays in its chat.')) {
                    await store.remove(b.id);
                    if (context.mounted) Navigator.pop(context);
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit title and author')),
              if (b.chatId != null) const PopupMenuItem(value: 'post', child: Text('Open the post')),
              if (b.chatId != null) const PopupMenuItem(value: 'share', child: Text('Share to a chat')),
              if (b.downloaded) const PopupMenuItem(value: 'other', child: Text('Open in another app')),
              PopupMenuItem(value: 'remove', child: Text('Remove from library', style: TextStyle(color: AppColors.danger))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Center(
            child: GestureDetector(
              onTap: b.coverPath != null ? () => openFullscreenFile(context, b.coverPath!, title: b.title) : null,
              child: BookCover(book: b, width: 160),
            ),
          ),
          const SizedBox(height: Space.l),
          Text(b.title, textAlign: TextAlign.center, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFamily: 'serif')),
          if (b.author.isNotEmpty) Text(b.author, textAlign: TextAlign.center, style: context.text.titleSmall?.copyWith(color: AppColors.text2)),
          const SizedBox(height: Space.s),
          Text(
            [b.format.toUpperCase(), if (b.size > 0) sizeText(b.size), if (b.year.isNotEmpty) b.year, if (b.words > 0) '${(b.words / 1000).round()}k words · ~${(b.words / 230 / 60).toStringAsFixed(1)}h', if (b.pages > 0) '${b.pages} pages'].join(' · '),
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.m),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(i <= b.rating ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFFFB400)),
                  onPressed: () => store.setRating(b.id, b.rating == i ? 0 : i),
                ),
              IconButton(
                icon: Icon(b.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: b.favorite ? const Color(0xFFFF4D6D) : null),
                onPressed: () => store.setFavorite(b.id, !b.favorite),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          if (dl != null)
            ValueListenableBuilder<double>(
              valueListenable: dl,
              builder: (_, p, _) => Row(
                children: [
                  Expanded(child: LinearProgressIndicator(value: p > 0 ? p : null, minHeight: 6, borderRadius: BorderRadius.circular(9))),
                  const SizedBox(width: Space.s),
                  Text('${(p * 100).round()}%', style: context.text.labelMedium),
                  IconButton(tooltip: 'Pause', icon: const Icon(Icons.pause_rounded), onPressed: () => store.pauseDownload(b.id)),
                  IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close_rounded), onPressed: () => store.cancelDownload(b.id)),
                ],
              ),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: booksColor, foregroundColor: AppLook.onBrand(booksColor)),
              icon: Icon(b.downloaded ? Icons.menu_book_rounded : Icons.download_rounded),
              label: Text(b.progress > 0 && b.status != ReadStatus.finished ? 'Continue · ${(b.progress * 100).round()}%' : (b.downloaded ? 'Read' : (store.paused.value.contains(b.id) ? 'Resume download' : 'Download and read'))),
              onPressed: () => openBook(context, ref, b),
            ),
          const SizedBox(height: Space.l),
          SegmentedButton<ReadStatus>(
            showSelectedIcon: false,
            segments: [for (final st in ReadStatus.values) ButtonSegment(value: st, label: Text(st.label, style: const TextStyle(fontSize: 12)))],
            selected: {b.status},
            onSelectionChanged: (v) => store.setStatus(b.id, v.first),
          ),
          const SizedBox(height: Space.l),
          Text('Shelves', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 6,
            children: [
              for (final shelf in s.shelves)
                FilterChip(
                  label: Text(shelf),
                  selected: b.shelves.contains(shelf),
                  onSelected: (v) => store.setShelves(b.id, v ? [...b.shelves, shelf] : [for (final x in b.shelves) if (x != shelf) x]),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: const Text('New shelf'),
                onPressed: () async {
                  final n = await _askName(context);
                  if (n != null && n.isNotEmpty) await store.setShelves(b.id, [...b.shelves, n]);
                },
              ),
            ],
          ),
          if (b.description.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            Text('About', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(b.description, style: context.text.bodyMedium?.copyWith(height: 1.5)),
          ],
          const SizedBox(height: Space.l),
          TextFormField(
            initialValue: b.notes,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Your notes on this book'),
            onChanged: (v) => store.update(b.id, (x) => x.copyWith(notes: v)),
          ),
          const SizedBox(height: Space.l),
          Text(
            [
              if (b.source.isNotEmpty) 'From ${b.source}',
              'Added ${agoText(b.addedAt)}',
              if (b.minutes > 0) '${b.minutes} min read',
              if (hl > 0) '$hl highlights',
              if (b.finishedAt != null) 'Finished ${agoText(b.finishedAt!)}',
            ].join(' · '),
            style: context.text.bodySmall,
          ),
          if (b.chatId != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: TgAvatar(chatId: b.chatId, title: b.source, size: 32, accountId: b.account),
              title: Text(b.source),
              subtitle: Text('Where it was posted', style: context.text.bodySmall),
            ),
        ],
      ),
    );
  }
}
