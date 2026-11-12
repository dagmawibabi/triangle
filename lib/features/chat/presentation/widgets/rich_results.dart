import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../telegram/data/telegram_tools.dart';
import '../../domain/chat_models.dart';
import 'app_result_cards.dart';
import 'cloud_result_cards.dart';
import 'workspace_result_cards.dart';
import 'utility_result_cards.dart';
import 'youtube_result_cards.dart';
import 'verify_result_cards.dart';
import 'retro_result_cards.dart';
import 'device_result_cards.dart';
import 'markets_result_cards.dart';
import 'news_result_cards.dart';
import 'bible_result_cards.dart';
import 'finance_result_cards.dart';
import 'call_history_result_cards.dart';
import 'library_result_cards.dart';
import 'explore_result_cards.dart';
import 'pokemon_result_cards.dart';
import 'papers_result_cards.dart';
import 'screen_time_result_cards.dart';
import 'safety_result_cards.dart';
import 'screen_result_cards.dart';
import 'image_result_cards.dart';
import 'reference_result_cards.dart';
import 'world_result_cards.dart';
import 'food_result_cards.dart';
import 'sports_result_cards.dart';

/// Cards for results that are things you'd want to look at: books, YouTube
/// videos and channels, posts and profiles on X, GitHub repos, releases,
/// issues and files, and web pages. Tapping one opens a sheet with all of
/// it and a preview (a cover, a playable video, the live page, the README).
/// Null for every other tool, which keeps its plain card.
Widget? richResultFor(ToolPart part) {
  // A failed sandbox run still has output worth showing (the traceback,
  // stderr), so its card stays; other failures show just the error.
  final failedRun = part.status == ToolStatus.error && (part.name.startsWith('e2b_run') || part.name == 'run_code');
  if ((part.status != ToolStatus.done && !failedRun) || part.result == null) return null;
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(part.result!) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  // Screen time, image tools and the free lookups.
  if (safetyResultFor(part, j) ?? screenResultFor(part, j) ?? screenTimeResultFor(part, j) ?? imageResultFor(part, j) ?? referenceResultFor(part, j) ?? worldResultFor(part, j) ?? foodResultFor(part, j) ?? sportsResultFor(part, j) case final w?) return w;
  return switch (part.name) {
    'search_books' => _Carousel(
      height: 236,
      children: [
        for (final source in const [
          'openlibrary',
          'gutenberg',
          'standardebooks',
          'google',
        ])
          for (final b in list(j[source])) _BookTile(book: b),
      ],
    ),
    'find_free_copy' =>
      list(j['free_copies']).isEmpty
          ? null
          : _Carousel(
              height: 236,
              children: [
                for (final b in list(j['free_copies'])) _BookTile(book: b),
              ],
            ),
    'book_details' => _BookHero(book: j),
    'download_book' => _FileCard(
      icon: Icons.menu_book_rounded,
      title: '${j['name'] ?? 'Book'}',
      subtitle: '${j['size_kb'] ?? '?'} KB · free, legal copy',
      path: '${j['file_path'] ?? ''}',
    ),
    'youtube_search' when j['type'] == null || j['type'] == 'video' => Column(
      children: [for (final v in list(j['results'])) _VideoRow(video: v)],
    ),
    'youtube_video' => _VideoHero(video: j),
    'youtube_channel' => _ChannelCard(channel: j),
    'youtube_playlist' => _Section(
      title: '${j['playlist'] ?? 'Playlist'}',
      subtitle: '${j['by'] ?? ''}',
      icon: Icons.playlist_play_rounded,
      url: j['url'] as String?,
      children: [
        for (final v in list(j['videos']).take(8)) _VideoRow(video: v),
      ],
    ),
    'x_post' => _PostCard(post: j),
    'x_profile' => _ProfileCard(profile: j),
    'github_repo' => _RepoCard(repo: j, big: true),
    'github_search' when list(j['results']).any((r) => r['repo'] != null) =>
      Column(
        children: [
          for (final r in list(j['results']).take(8)) _RepoCard(repo: r),
        ],
      ),
    'github_releases' => Column(
      children: [
        for (final r in list(j['releases']).take(5))
          _ReleaseCard(release: r, repo: '${j['repo']}'),
      ],
    ),
    'github_issues'
        when j['number'] == null &&
            (j['issues'] ?? j['pull_requests']) != null =>
      _Section(
        title: '${j['repo']}',
        subtitle: j['issues'] != null ? 'Issues' : 'Pull requests',
        icon: Icons.bug_report_outlined,
        children: [
          for (final i in list(j['issues'] ?? j['pull_requests']).take(10))
            _IssueRow(issue: i, repo: '${j['repo']}'),
        ],
      ),
    'github_issues' when j['title'] != null => _IssueRow(
      issue: j,
      repo: '',
      full: j,
    ),
    'github_read' when j['text'] != null => _CodeCard(file: j),
    'music_search' => switch (j['type']) {
      'album' => _Carousel(
        height: 206,
        children: [for (final a in list(j['results'])) _AlbumTile(album: a)],
      ),
      'artist' => Column(
        children: [for (final a in list(j['results'])) _ArtistRow(artist: a)],
      ),
      _ => Column(
        children: [for (final t in list(j['results']).take(10)) _SongRow(song: t)],
      ),
    },
    'music_album' => _AlbumHero(album: j),
    'music_artist' => _ArtistHero(artist: j),
    'movie_search' => _Carousel(
      height: 250,
      children: [for (final m in list(j['results'])) _PosterTile(item: m, movie: true)],
    ),
    'movie_details' => _ScreenHero(item: j, movie: true),
    'tv_search' => _Carousel(
      height: 250,
      children: [for (final m in list(j['results'])) _PosterTile(item: m, movie: false)],
    ),
    'tv_show' => _ScreenHero(item: j, movie: false),
    'fetch_url' ||
    'browser_open' ||
    'browser_read' ||
    'web_inspect' when j['url'] is String => _PageCard(page: j),
    'browser_click' when (j['page'] as Map?)?['url'] is String => _PageCard(
      page: Map<String, dynamic>.from(j['page'] as Map),
    ),
    _ => marketsResultFor(part, j) ?? newsResultFor(part, j) ?? bibleResultFor(part, j) ?? financeResultFor(part, j) ?? callHistoryResultFor(part, j) ?? libraryResultFor(part, j) ?? exploreResultFor(part, j) ?? pokemonResultFor(part, j) ?? papersResultFor(part, j) ?? appResultFor(part, j) ?? cloudResultFor(part, j) ?? deviceResultFor(part, j) ?? workspaceResultFor(part, j) ?? utilityResultFor(part, j) ?? youtubeResultFor(part, j) ?? verifyResultFor(part, j) ?? retroResultFor(part, j),
  };
}

// ---- shared pieces --------------------------------------------------------------

Future<void> _open(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

void _copy(BuildContext context, String text, [String what = 'Link']) {
  Clipboard.setData(ClipboardData(text: text));
  showSnack(context, '$what copied');
}

String _compact(Object? n) {
  final v = n is num ? n : num.tryParse('$n'.replaceAll(RegExp(r'[^\d.]'), ''));
  return v == null ? '$n' : NumberFormat.compact().format(v);
}

class _Net extends StatelessWidget {
  const _Net(
    this.url, {
    this.width,
    this.height,
    this.radius = Radii.m,
    this.placeholder = Icons.image_outlined,
  });
  final String? url;
  final double? width, height, radius;
  static const fit = BoxFit.cover;
  final IconData placeholder;

  @override
  Widget build(BuildContext context) => NetImage(
    url,
    width: width,
    height: height,
    fit: fit,
    radius: radius ?? 0,
    placeholder: placeholder,
  );
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Space.m),
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s),
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: padding,
          // Over the content: an edge-to-edge picture can't hide it.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: AppColors.line),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.height, required this.children});
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => children.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.s),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    this.url,
  });
  final String title, subtitle;
  final IconData icon;
  final String? url;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.xs,
          Space.xs,
          Space.xs,
          Space.s,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.text2),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle.isNotEmpty)
                      TextSpan(
                        text: '  $subtitle',
                        style: TextStyle(color: AppColors.text3),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (url != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                onPressed: () => _open(url),
              ),
          ],
        ),
      ),
      ...children,
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.icon, this.color});
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: (color ?? AppColors.text2).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color ?? AppColors.text2),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: color ?? AppColors.text2),
          ),
        ),
      ],
    ),
  );
}

/// A sheet for one thing's full details.
Future<void> _sheet(
  BuildContext context,
  Widget Function(ScrollController) body,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.86,
    minChildSize: 0.4,
    maxChildSize: 1,
    builder: (_, scroll) => body(scroll),
  ),
);

/// Loads a tool's full result for a sheet, so a card from a list opens
/// with everything about that one thing.
class _Loaded extends ConsumerStatefulWidget {
  const _Loaded({
    required this.tool,
    required this.args,
    required this.builder,
    this.initial,
  });
  final String tool;
  final Map<String, dynamic> args;
  final Map<String, dynamic>? initial;
  final Widget Function(Map<String, dynamic> data, bool loading) builder;

  @override
  ConsumerState<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends ConsumerState<_Loaded> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(toolRunnerProvider).run(widget.tool, widget.args).then((r) {
      if (!mounted) return;
      setState(
        () => r.json['error'] != null
            ? _error = '${r.json['error']}'
            : _data = r.json,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.initial == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    return widget.builder({
      ...?widget.initial,
      ...?_data,
    }, _data == null && _error == null);
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.m),
    child: Wrap(spacing: Space.s, runSpacing: Space.s, children: children),
  );
}

class _Expandable extends StatefulWidget {
  const _Expandable(this.text);
  final String text;
  static const lines = 6;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText(
        widget.text,
        maxLines: _open ? null : _Expandable.lines,
        style: const TextStyle(height: 1.45),
      ),
      if (widget.text.length > 300)
        TextButton(
          onPressed: () => setState(() => _open = !_open),
          child: Text(_open ? 'Show less' : 'Show more'),
        ),
    ],
  );
}

// ---- books -------------------------------------------------------------------

/// Book providers do not agree on whether a repeated value is encoded as a
/// JSON array or a comma-separated string.  Keep the result cards tolerant of
/// either shape: cards are rendered before their detail request completes.
List<String> _bookStrings(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item != null) '$item',
    ];
  }
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

List<Map> _bookMaps(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map) item,
];

String _authors(Map b) => _bookStrings(b['authors']).join(', ');

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book});
  final Map<String, dynamic> book;

  @override
  Widget build(BuildContext context) {
    final free = '${book['free'] ?? book['source'] ?? ''}';
    final isFree = free.contains('free') || book['source'] != null;
    return SizedBox(
      width: 124,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: () => showBook(context, book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _Net(
                  book['cover'] as String?,
                  width: 124,
                  height: 168,
                  placeholder: Icons.menu_book_rounded,
                ),
                if (isFree)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _Chip('FREE', color: AppColors.success),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${book['title']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            Text(
              _authors(book),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookHero extends StatelessWidget {
  const _BookHero({required this.book});
  final Map<String, dynamic> book;

  @override
  Widget build(BuildContext context) => _Shell(
    onTap: () => showBook(context, book),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Net(
          book['cover'] as String?,
          width: 84,
          height: 124,
          placeholder: Icons.menu_book_rounded,
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${book['title']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium,
              ),
              Text(
                _authors(book),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${book['description'] ?? book['summary'] ?? ''}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: AppColors.text2),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (book['rating'] != null)
                    _Chip(
                      '${book['rating']}',
                      icon: Icons.star_rounded,
                      color: AppColors.warning,
                    ),
                  if ((book['formats'] as List?)?.isNotEmpty == true)
                    _Chip(
                      'Free download',
                      icon: Icons.download_rounded,
                      color: AppColors.success,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

void showBook(BuildContext context, Map<String, dynamic> book) => _sheet(
  context,
  (scroll) => _Loaded(
    tool: 'book_details',
    args: {'book_id': book['book_id']},
    initial: book,
    builder: (b, loading) =>
        _BookSheet(book: b, loading: loading, scroll: scroll),
  ),
);

class _BookSheet extends ConsumerStatefulWidget {
  const _BookSheet({
    required this.book,
    required this.loading,
    required this.scroll,
  });
  final Map<String, dynamic> book;
  final bool loading;
  final ScrollController scroll;

  @override
  ConsumerState<_BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends ConsumerState<_BookSheet> {
  String? _busy;

  Future<void> _download(String format) async {
    final id = '${widget.book['free_copy_id'] ?? widget.book['book_id']}';
    setState(() => _busy = format);
    final r = await ref.read(toolRunnerProvider).run('download_book', {
      'book_id': id,
      'format': format,
    });
    if (!mounted) return;
    setState(() => _busy = null);
    if (r.json['error'] != null) {
      showSnack(
        context,
        '${r.json['error']}',
        icon: Icons.error_outline_rounded,
      );
      return;
    }
    await OpenFilex.open('${r.json['file_path']}');
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    final id = '${b['book_id'] ?? ''}';
    final formats = [
      ..._bookStrings(b['formats']),
      if (id.startsWith('ia:') || b['free_copy_id'] != null) ...['pdf', 'epub'],
    ].toSet().toList();
    final subjects = _bookStrings(b['subjects']);
    final editions = _bookMaps(b['editions']);
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Center(
          child: _Net(
            b['cover'] as String?,
            width: 150,
            height: 222,
            radius: Radii.l,
            placeholder: Icons.menu_book_rounded,
          ),
        ),
        const SizedBox(height: Space.m),
        Text(
          '${b['title']}',
          textAlign: TextAlign.center,
          style: context.text.titleLarge,
        ),
        if (_authors(b).isNotEmpty)
          Text(
            _authors(b),
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: AppColors.text2),
          ),
        const SizedBox(height: Space.s),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            if (b['rating'] != null)
              _Chip(
                '${b['rating']}',
                icon: Icons.star_rounded,
                color: AppColors.warning,
              ),
            if ((b['first_published'] ?? b['published']) != null)
              _Chip(
                '${b['first_published'] ?? b['published']}',
                icon: Icons.event_outlined,
              ),
            if (b['pages'] != null)
              _Chip('${b['pages']} pages', icon: Icons.auto_stories_outlined),
            if (b['editions_total'] != null)
              _Chip(
                '${b['editions_total']} editions',
                icon: Icons.layers_outlined,
              ),
            if (b['downloads_last_month'] != null)
              _Chip(
                '${_compact(b['downloads_last_month'])} downloads/month',
                icon: Icons.trending_up_rounded,
              ),
            if (b['source'] != null)
              _Chip(
                '${b['source']}',
                icon: Icons.verified_outlined,
                color: AppColors.success,
              ),
          ],
        ),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.only(top: Space.m),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        _Buttons([
          for (final f in formats)
            FilledButton.tonalIcon(
              onPressed: _busy == null ? () => _download(f) : null,
              icon: _busy == f
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(switch (f) {
                'kindle' => 'Kindle',
                'txt' => 'Text',
                _ => f.toUpperCase(),
              }),
            ),
          if (b['read_online'] != null)
            OutlinedButton.icon(
              onPressed: () => _open('${b['read_online']}'),
              icon: const Icon(Icons.chrome_reader_mode_outlined),
              label: const Text('Read online'),
            ),
          if ((b['link'] ?? b['preview']) != null)
            OutlinedButton.icon(
              onPressed: () => _open('${b['link'] ?? b['preview']}'),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open page'),
            ),
        ]),
        if ((b['description'] ?? b['summary']) != null) ...[
          Text('About', style: context.text.titleSmall),
          const SizedBox(height: Space.xs),
          _Expandable('${b['description'] ?? b['summary']}'),
        ],
        if (subjects.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text('Subjects', style: context.text.titleSmall),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final s in subjects.take(16)) _Chip(s)],
          ),
        ],
        if (editions.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text('Editions', style: context.text.titleSmall),
          for (final e in editions)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: lead(const Icon(Icons.book_outlined)),
              title: Text('${e['title']}'),
              subtitle: Text(
                [
                  if (_bookStrings(e['publishers']).isNotEmpty)
                    _bookStrings(e['publishers']).join(', '),
                  ?e['published'],
                  if (e['isbn'] != null) 'ISBN ${e['isbn']}',
                  if (e['pages'] != null) '${e['pages']} pp',
                ].join(' · '),
                style: context.text.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
  });
  final IconData icon;
  final String title, subtitle, path;

  @override
  Widget build(BuildContext context) => _Shell(
    onTap: path.isEmpty ? null : () => OpenFilex.open(path),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(Radii.m),
          ),
          child: Icon(icon, color: AppColors.success),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(subtitle, style: context.text.bodySmall),
            ],
          ),
        ),
        Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.text3),
      ],
    ),
  );
}

// ---- YouTube -----------------------------------------------------------------

String? _videoId(Map v) =>
    v['video_id'] as String? ??
    RegExp(r'youtu\.be/([\w-]{11})').firstMatch('${v['url'] ?? ''}')?[1];

class _VideoRow extends StatelessWidget {
  const _VideoRow({required this.video});
  final Map<String, dynamic> video;

  @override
  Widget build(BuildContext context) {
    final id = _videoId(video);
    return _Shell(
      padding: const EdgeInsets.all(Space.s),
      onTap: id == null ? null : () => showVideo(context, id, video),
      child: Row(
        children: [
          Stack(
            children: [
              _Net(
                video['thumbnail'] as String? ??
                    (id == null
                        ? null
                        : 'https://i.ytimg.com/vi/$id/hqdefault.jpg'),
                width: 132,
                height: 74,
                placeholder: Icons.smart_display_outlined,
              ),
              if (video['length'] != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${video['length']}',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${video['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (video['channel'] != null) '${video['channel']}',
                    if (video['views'] != null)
                      '${video['views']}'.contains('view')
                          ? '${video['views']}'
                          : '${_compact(video['views'])} views',
                    if ((video['published'] ?? '').toString().isNotEmpty)
                      '${video['published']}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoHero extends StatelessWidget {
  const _VideoHero({required this.video});
  final Map<String, dynamic> video;

  @override
  Widget build(BuildContext context) {
    final id = _videoId(video);
    return _Shell(
      padding: EdgeInsets.zero,
      onTap: id == null ? null : () => showVideo(context, id, video),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Net(
                  video['thumbnail'] as String?,
                  radius: 0,
                  placeholder: Icons.smart_display_outlined,
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
                if (video['length'] != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${video['length']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
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
                Text(
                  '${video['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${video['channel']}',
                    if (video['views'] != null)
                      '${_compact(video['views'])} views',
                    if (video['published'] != null)
                      '${video['published']}'.split('T').first,
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel});
  final Map<String, dynamic> channel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Shell(
        onTap: () => _open(channel['url'] as String?),
        child: Row(
          children: [
            _Net(
              channel['avatar'] as String?,
              width: 52,
              height: 52,
              radius: 26,
              placeholder: Icons.smart_display_outlined,
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${channel['channel']}',
                    style: context.text.titleMedium,
                  ),
                  Text(
                    [?channel['subscribers'], ?channel['videos']].join(' · '),
                    style: context.text.bodySmall,
                  ),
                  if (channel['description'] != null)
                    Text(
                      '${channel['description']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.text2,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      for (final v in [
        for (final x in (channel['latest'] as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ].take(5))
        _VideoRow(video: v),
    ],
  );
}

void showVideo(BuildContext context, String id, Map<String, dynamic> initial) =>
    _sheet(
      context,
      (scroll) => _Loaded(
        tool: 'youtube_video',
        args: {'video': id},
        initial: initial,
        builder: (v, loading) =>
            _VideoSheet(id: id, video: v, loading: loading, scroll: scroll),
      ),
    );

class _VideoSheet extends StatefulWidget {
  const _VideoSheet({
    required this.id,
    required this.video,
    required this.loading,
    required this.scroll,
  });
  final String id;
  final Map<String, dynamic> video;
  final bool loading;
  final ScrollController scroll;

  @override
  State<_VideoSheet> createState() => _VideoSheetState();
}

class _VideoSheetState extends State<_VideoSheet> {
  // YouTube's own embedded player, so the video plays right here.
  late final WebViewController _player = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(
      Uri.parse(
        'https://www.youtube.com/embed/${widget.id}?playsinline=1&rel=0&modestbranding=1',
      ),
    );

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final chapters = [
      for (final c in (v['chapters'] as List? ?? const [])) '$c',
    ];
    final tags = [for (final t in (v['tags'] as List? ?? const [])) '$t'];
    final url = 'https://youtu.be/${widget.id}';
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.l),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: WebViewWidget(controller: _player),
          ),
        ),
        const SizedBox(height: Space.m),
        Text('${v['title'] ?? ''}', style: context.text.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${v['channel'] ?? ''}',
          style: context.text.bodyMedium?.copyWith(color: AppColors.text2),
        ),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (v['views'] != null)
              _Chip(
                '${_compact(v['views'])} views',
                icon: Icons.visibility_outlined,
              ),
            if (v['likes'] != null)
              _Chip(
                '${_compact(v['likes'])} likes',
                icon: Icons.thumb_up_alt_outlined,
              ),
            if (v['length'] != null)
              _Chip('${v['length']}', icon: Icons.schedule_rounded),
            if (v['published'] != null)
              _Chip(
                '${v['published']}'.split('T').first,
                icon: Icons.event_outlined,
              ),
            if (v['category'] != null)
              _Chip('${v['category']}', icon: Icons.category_outlined),
          ],
        ),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.only(top: Space.m),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        _Buttons([
          FilledButton.tonalIcon(
            onPressed: () => _open(url),
            icon: const Icon(Icons.smart_display_outlined),
            label: const Text('Open in YouTube'),
          ),
          OutlinedButton.icon(
            onPressed: () => _copy(context, url),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Copy link'),
          ),
        ]),
        if (chapters.isNotEmpty) ...[
          Text('Chapters', style: context.text.titleSmall),
          for (final c in chapters)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: lead(const Icon(Icons.bookmark_border_rounded, size: 18)),
              title: Text(c),
              onTap: () {
                final t = RegExp(r'^((?:\d+:)?\d{1,2}):(\d{2})').firstMatch(c);
                if (t == null) return;
                final parts = t[1]!.split(':').map(int.parse).toList();
                final secs =
                    (parts.length == 2
                        ? parts[0] * 3600 + parts[1] * 60
                        : parts[0] * 60) +
                    int.parse(t[2]!);
                _player.loadRequest(
                  Uri.parse(
                    'https://www.youtube.com/embed/${widget.id}?playsinline=1&rel=0&autoplay=1&start=$secs',
                  ),
                );
              },
            ),
        ],
        if ((v['description'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Text('Description', style: context.text.titleSmall),
          const SizedBox(height: Space.xs),
          _Expandable('${v['description']}'),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in tags.take(20)) _Chip('#$t')],
          ),
        ],
      ],
    );
  }
}

// ---- X -----------------------------------------------------------------------

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, this.inSheet = false});
  final Map<String, dynamic> post;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final photos = [
      for (final p in (post['photos'] as List? ?? const [])) '$p',
    ];
    final quoted = post['quotes'] as Map?;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Net(
              post['avatar'] as String?,
              width: 40,
              height: 40,
              radius: 20,
              placeholder: Icons.person_outline_rounded,
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${post['name'] ?? post['author'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (post['handle'] != null)
                    Text('@${post['handle']}', style: context.text.bodySmall),
                ],
              ),
            ),
            const Text(
              '𝕏',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: Space.s),
        SelectableText(
          '${post['text'] ?? ''}',
          maxLines: inSheet ? null : 8,
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          if (inSheet)
            for (final p in photos)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: GestureDetector(
                  onTap: () => _open(p),
                  child: _Net(p, radius: Radii.l),
                ),
              )
          else
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  for (final (i, p) in photos.take(2).indexed) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(child: _Net(p, height: 180, radius: Radii.m)),
                  ],
                ],
              ),
            ),
        ] else if (post['video_thumbnail'] != null) ...[
          const SizedBox(height: Space.s),
          GestureDetector(
            onTap: () => _open('${post['url']}'),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Net('${post['video_thumbnail']}', radius: Radii.m),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (quoted != null) ...[
          const SizedBox(height: Space.s),
          Container(
            padding: const EdgeInsets.all(Space.s),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.m),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${quoted['author']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${quoted['text']}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.text2),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.s),
        DefaultTextStyle(
          style: context.text.bodySmall ?? const TextStyle(),
          child: Wrap(
            spacing: Space.m,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (icon, key) in const [
                (Icons.chat_bubble_outline_rounded, 'replies'),
                (Icons.repeat_rounded, 'reposts'),
                (Icons.favorite_border_rounded, 'likes'),
                (Icons.bar_chart_rounded, 'views'),
              ])
                if (post[key] != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: AppColors.text3),
                      const SizedBox(width: 3),
                      Text(_compact(post[key])),
                    ],
                  ),
              if (post['date'] != null) Text(_xDate('${post['date']}')),
            ],
          ),
        ),
      ],
    );
    if (inSheet) return body;
    return _Shell(onTap: () => showPost(context, post), child: body);
  }
}

String _xDate(String raw) {
  final d = DateTime.tryParse(raw) ?? _parseTwitterDate(raw);
  return d == null ? raw : DateFormat('d MMM y, HH:mm').format(d.toLocal());
}

/// X's "Wed Oct 26 18:45:58 +0000 2022".
DateTime? _parseTwitterDate(String s) {
  final m = RegExp(
    r'^\w{3} (\w{3}) (\d{1,2}) (\d{2}):(\d{2}):(\d{2}) [+-]\d{4} (\d{4})$',
  ).firstMatch(s);
  if (m == null) return null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return DateTime.utc(
    int.parse(m[6]!),
    months.indexOf(m[1]!) + 1,
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
  );
}

void showPost(BuildContext context, Map<String, dynamic> post) => _sheet(
  context,
  (scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: [
      _PostCard(post: post, inSheet: true),
      _Buttons([
        FilledButton.tonalIcon(
          onPressed: () => _open('${post['url']}'),
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Open on X'),
        ),
        OutlinedButton.icon(
          onPressed: () => _copy(context, '${post['url']}'),
          icon: const Icon(Icons.link_rounded),
          label: const Text('Copy link'),
        ),
        for (final m in [
          for (final x in (post['media'] as List? ?? const []))
            if (x is Map && x['type'] != 'photo') x,
        ])
          OutlinedButton.icon(
            onPressed: () => _open('${m['url']}'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play video'),
          ),
      ]),
    ],
  ),
);

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) => _Shell(
    padding: EdgeInsets.zero,
    onTap: () => _sheet(
      context,
      (scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          _ProfileBody(profile: profile, full: true),
          _Buttons([
            FilledButton.tonalIcon(
              onPressed: () => _open('${profile['url']}'),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open on X'),
            ),
            if (profile['website'] != null)
              OutlinedButton.icon(
                onPressed: () => _open('${profile['website']}'),
                icon: const Icon(Icons.language_rounded),
                label: const Text('Website'),
              ),
            OutlinedButton.icon(
              onPressed: () => _copy(context, '${profile['url']}'),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Copy link'),
            ),
          ]),
        ],
      ),
    ),
    child: _ProfileBody(profile: profile),
  );
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile, this.full = false});
  final Map<String, dynamic> profile;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 118,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                bottom: 30,
                child: _Net(
                  p['banner'] as String?,
                  radius: full ? Radii.l : 0,
                  placeholder: Icons.landscape_outlined,
                ),
              ),
              Positioned(
                left: Space.m,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 3),
                  ),
                  child: _Net(
                    p['avatar'] as String?,
                    width: 64,
                    height: 64,
                    radius: 32,
                    placeholder: Icons.person_outline_rounded,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            full ? 0 : Space.m,
            Space.s,
            full ? 0 : Space.m,
            Space.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${p['name']}',
                      style: context.text.titleMedium,
                    ),
                  ),
                  if (p['verified'] == true)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.verified_rounded,
                        size: 16,
                        color: Color(0xFF1D9BF0),
                      ),
                    ),
                ],
              ),
              Text('${p['username']}', style: context.text.bodySmall),
              if (p['bio'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${p['bio']}',
                  maxLines: full ? null : 3,
                  overflow: full ? null : TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: Space.m,
                runSpacing: 4,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _compact(p['following']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: ' following',
                          style: TextStyle(color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _compact(p['followers']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: ' followers',
                          style: TextStyle(color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                  if (full && p['posts'] != null)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _compact(p['posts']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: ' posts',
                            style: TextStyle(color: AppColors.text3),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (full) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (p['location'] != null)
                      _Chip('${p['location']}', icon: Icons.place_outlined),
                    if (p['joined'] != null)
                      _Chip(
                        'Joined ${_xDate('${p['joined']}').split(',').first}',
                        icon: Icons.event_outlined,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---- GitHub ------------------------------------------------------------------

const _langColors = {
  'Dart': Color(0xFF00B4AB),
  'Python': Color(0xFF3572A5),
  'JavaScript': Color(0xFFF1E05A),
  'TypeScript': Color(0xFF3178C6),
  'Go': Color(0xFF00ADD8),
  'Rust': Color(0xFFDEA584),
  'Java': Color(0xFFB07219),
  'Kotlin': Color(0xFFA97BFF),
  'Swift': Color(0xFFF05138),
  'C++': Color(0xFFF34B7D),
  'C': Color(0xFF555555),
  'C#': Color(0xFF178600),
  'Ruby': Color(0xFF701516),
  'PHP': Color(0xFF4F5D95),
  'HTML': Color(0xFFE34C26),
  'CSS': Color(0xFF563D7C),
  'Shell': Color(0xFF89E051),
};

class _RepoCard extends StatelessWidget {
  const _RepoCard({required this.repo, this.big = false});
  final Map<String, dynamic> repo;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final r = repo;
    final name = '${r['repo']}';
    final topics = [for (final t in (r['topics'] as List? ?? const [])) '$t'];
    final lang = r['language'] as String?;
    return _Shell(
      onTap: () => showRepo(context, name, r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Net(
                r['owner_avatar'] as String? ??
                    'https://github.com/${name.split('/').first}.png?size=80',
                width: 32,
                height: 32,
                radius: 8,
                placeholder: Icons.code_rounded,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${name.split('/').first}/',
                        style: TextStyle(color: AppColors.text2),
                      ),
                      TextSpan(
                        text: name.split('/').last,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (r['archived'] == true)
                _Chip('Archived', color: AppColors.warning),
            ],
          ),
          if (r['description'] != null) ...[
            const SizedBox(height: 6),
            Text(
              '${r['description']}',
              maxLines: big ? 4 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.text2),
            ),
          ],
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.m,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (lang != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 5,
                      backgroundColor: _langColors[lang] ?? AppColors.text3,
                    ),
                    const SizedBox(width: 4),
                    Text(lang, style: context.text.bodySmall),
                  ],
                ),
              if (r['stars'] != null)
                _stat(context, Icons.star_border_rounded, r['stars']),
              if (r['forks'] != null)
                _stat(context, Icons.call_split_rounded, r['forks']),
              if (r['open_issues'] != null)
                _stat(context, Icons.adjust_rounded, r['open_issues']),
              if (r['license'] != null)
                Text('${r['license']}', style: context.text.bodySmall),
              if ((r['updated'] ?? r['last_push']) != null)
                Text(
                  'Updated ${r['updated'] ?? r['last_push']}',
                  style: context.text.bodySmall,
                ),
            ],
          ),
          if (big && topics.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in topics.take(8))
                  _Chip(t, color: const Color(0xFF58A6FF)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Widget _stat(BuildContext context, IconData icon, Object? n) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.text3),
      const SizedBox(width: 2),
      Text(_compact(n), style: context.text.bodySmall),
    ],
  );
}

void showRepo(
  BuildContext context,
  String repo,
  Map<String, dynamic> initial,
) => _sheet(
  context,
  (scroll) => _Loaded(
    tool: 'github_repo',
    args: {'repo': repo, 'readme_chars': 30000},
    initial: initial,
    builder: (r, loading) =>
        _RepoSheet(repo: r, loading: loading, scroll: scroll),
  ),
);

MarkdownStyleSheet _md(BuildContext context) =>
    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(fontSize: 14, height: 1.45, color: AppColors.text),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12.5,
        backgroundColor: AppColors.surface3,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.m),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.line, width: 3)),
      ),
    );

/// Resolves README assets against GitHub's raw-content host. Markdown parsers
/// pass a relative image URI straight to [imageBuilder], which has no page URL
/// to resolve it against on its own.
String _githubReadmeUrl(Map<String, dynamic> repo, Uri uri) {
  if (uri.hasScheme) {
    if (uri.host == 'github.com' &&
        uri.pathSegments.length >= 5 &&
        (uri.pathSegments[2] == 'blob' || uri.pathSegments[2] == 'raw')) {
      final path = uri.pathSegments;
      return Uri.https(
        'raw.githubusercontent.com',
        [...path.take(2), ...path.skip(3)].join('/'),
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      ).toString();
    }
    return uri.toString();
  }

  final name = '${repo['repo'] ?? ''}';
  final branch = '${repo['default_branch'] ?? 'main'}';
  final readmePath = '${repo['readme_path'] ?? 'README.md'}';
  final base = Uri.parse(
    'https://raw.githubusercontent.com/$name/$branch/$readmePath',
  );
  // A leading slash is repo-root-relative, not host-root-relative.
  final relative = uri.path.startsWith('/')
      ? uri.replace(path: uri.path.substring(1))
      : uri;
  return base.resolveUri(relative).toString();
}

class _RepoSheet extends ConsumerStatefulWidget {
  const _RepoSheet({
    required this.repo,
    required this.loading,
    required this.scroll,
  });
  final Map<String, dynamic> repo;
  final bool loading;
  final ScrollController scroll;

  @override
  ConsumerState<_RepoSheet> createState() => _RepoSheetState();
}

class _RepoSheetState extends ConsumerState<_RepoSheet> {
  bool _zipping = false;

  Future<void> _zip() async {
    setState(() => _zipping = true);
    final r = await ref.read(toolRunnerProvider).run('github_download', {
      'repo': '${widget.repo['repo']}',
      'what': 'zip',
    });
    if (!mounted) return;
    setState(() => _zipping = false);
    showSnack(
      context,
      r.json['error'] != null
          ? '${r.json['error']}'
          : 'Saved ${r.json['name']} (${r.json['size_kb']} KB)',
      icon: r.json['error'] != null
          ? Icons.error_outline_rounded
          : Icons.check_circle_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.repo;
    final langs = (r['languages'] as Map?)?.cast<String, dynamic>() ?? const {};
    final url = '${r['url'] ?? 'https://github.com/${r['repo']}'}';
    String readmeUri(Uri uri) => _githubReadmeUrl(r, uri);
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        _RepoCard(repo: r, big: true),
        if (langs.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final e in langs.entries)
                    Expanded(
                      flex:
                          ((double.tryParse('${e.value}'.replaceAll('%', '')) ??
                                      1) *
                                  10)
                              .round()
                              .clamp(1, 1000),
                      child: ColoredBox(
                        color: _langColors[e.key] ?? AppColors.text3,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: Space.m,
            runSpacing: 4,
            children: [
              for (final e in langs.entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: _langColors[e.key] ?? AppColors.text3,
                    ),
                    const SizedBox(width: 4),
                    Text('${e.key} ${e.value}', style: context.text.bodySmall),
                  ],
                ),
            ],
          ),
        ],
        _Buttons([
          FilledButton.tonalIcon(
            onPressed: () => _open(url),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open on GitHub'),
          ),
          OutlinedButton.icon(
            onPressed: _zipping ? null : _zip,
            icon: _zipping
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_zip_outlined),
            label: const Text('Download zip'),
          ),
          OutlinedButton.icon(
            onPressed: () => _copy(context, '$url.git', 'Clone URL'),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Clone URL'),
          ),
          if (r['homepage'] != null)
            OutlinedButton.icon(
              onPressed: () => _open('${r['homepage']}'),
              icon: const Icon(Icons.language_rounded),
              label: const Text('Website'),
            ),
        ]),
        if (widget.loading) const LinearProgressIndicator(minHeight: 2),
        if (r['readme'] != null)
          Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('README', style: context.text.labelSmall),
                  ],
                ),
                const Divider(),
                MarkdownBody(
                  data: '${r['readme']}',
                  selectable: true,
                  styleSheet: _md(context),
                  onTapLink: (_, href, _) => href == null
                      ? null
                      : _open(
                          href.startsWith('http')
                              ? href
                              : '$url/blob/${r['default_branch'] ?? 'main'}/$href',
                        ),
                  // Flutter's standard image provider cannot rasterize SVGs.
                  imageBuilder: (uri, _, _) => uri.path.endsWith('.svg')
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _Net(readmeUri(uri), radius: Radii.s),
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.repo});
  final Map<String, dynamic> release;
  final String repo;

  @override
  Widget build(BuildContext context) {
    final r = release;
    final assets = [
      for (final a in (r['assets'] as List? ?? const []))
        if (a is Map) a,
    ];
    return _Shell(
      onTap: () => _sheet(
        context,
        (scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
          children: [
            Text('${r['name'] ?? r['tag']}', style: context.text.titleLarge),
            Text(
              '$repo · ${r['tag']} · ${r['date']}',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Space.m),
            if (assets.isNotEmpty) ...[
              Text('Downloads', style: context.text.titleSmall),
              for (final a in assets) _AssetRow(asset: a, repo: repo),
              const SizedBox(height: Space.m),
            ],
            if (r['notes'] != null)
              MarkdownBody(
                data: '${r['notes']}',
                selectable: true,
                styleSheet: _md(context),
                onTapLink: (_, href, _) => _open(href),
              ),
            _Buttons([
              FilledButton.tonalIcon(
                onPressed: () =>
                    _open('https://github.com/$repo/releases/tag/${r['tag']}'),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open on GitHub'),
              ),
            ]),
          ],
        ),
      ),
      child: Row(
        children: [
          const _Badge(icon: Icons.new_releases_outlined),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${r['name'] ?? r['tag']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (r['prerelease'] == true)
                      Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: _Chip('Pre-release', color: AppColors.warning),
                      ),
                  ],
                ),
                Text(
                  '${r['tag']} · ${r['date']} · ${assets.length} file${assets.length == 1 ? '' : 's'}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.text3),
        ],
      ),
    );
  }
}

class _AssetRow extends ConsumerStatefulWidget {
  const _AssetRow({required this.asset, required this.repo});
  final Map asset;
  final String repo;

  @override
  ConsumerState<_AssetRow> createState() => _AssetRowState();
}

class _AssetRowState extends ConsumerState<_AssetRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: lead(const Icon(Icons.inventory_2_outlined)),
      title: Text('${a['name']}'),
      subtitle: Text(
        '${a['size_mb']} MB · ${_compact(a['downloads'])} downloads',
        style: context.text.bodySmall,
      ),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () async {
                setState(() => _busy = true);
                final r = await ref.read(toolRunnerProvider).run(
                  'github_download',
                  {
                    'repo': widget.repo,
                    'what': 'asset',
                    'asset_url': '${a['asset_url']}',
                  },
                );
                if (!mounted) return;
                setState(() => _busy = false);
                if (r.json['error'] != null) {
                  showSnack(
                    context,
                    '${r.json['error']}',
                    icon: Icons.error_outline_rounded,
                  );
                } else {
                  await OpenFilex.open('${r.json['file_path']}');
                }
              },
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(Radii.m),
    ),
    child: Icon(icon, size: 20, color: AppColors.accent),
  );
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.repo, this.full});
  final Map<String, dynamic> issue;
  final String repo;

  /// Already loaded with its comments.
  final Map<String, dynamic>? full;

  @override
  Widget build(BuildContext context) {
    final i = issue;
    final open = '${i['state']}' == 'open';
    final pr = '${i['kind'] ?? ''}'.contains('pull');
    return _Shell(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.m,
        vertical: Space.s,
      ),
      onTap: () => _sheet(
        context,
        (scroll) => full != null
            ? _IssueSheet(issue: full!, scroll: scroll)
            : _Loaded(
                tool: 'github_issues',
                args: {'repo': repo, 'number': i['number']},
                initial: i,
                builder: (d, _) => _IssueSheet(issue: d, scroll: scroll),
              ),
      ),
      child: Row(
        children: [
          Icon(
            pr
                ? Icons.merge_type_rounded
                : (open
                      ? Icons.adjust_rounded
                      : Icons.check_circle_outline_rounded),
            size: 18,
            color: open ? AppColors.success : const Color(0xFFA371F7),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    if (i['number'] != null) '#${i['number']}',
                    if (i['by'] != null) 'by ${i['by']}',
                    ?(i['updated'] ?? i['opened']),
                    if (i['comments'] is num) '${i['comments']} comments',
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueSheet extends StatelessWidget {
  const _IssueSheet({required this.issue, required this.scroll});
  final Map<String, dynamic> issue;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final i = issue;
    final comments = [
      for (final c
          in (i['comments'] is List ? i['comments'] as List : const []))
        if (c is Map) c,
    ];
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Text('${i['title']}', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(
              '${i['state']}',
              color: '${i['state']}' == 'open'
                  ? AppColors.success
                  : const Color(0xFFA371F7),
            ),
            if (i['by'] != null)
              _Chip('${i['by']}', icon: Icons.person_outline_rounded),
            if (i['opened'] != null)
              _Chip('${i['opened']}', icon: Icons.event_outlined),
            for (final l in (i['labels'] as List? ?? const []))
              _Chip('$l', color: const Color(0xFF58A6FF)),
          ],
        ),
        const SizedBox(height: Space.m),
        if (i['body'] != null)
          MarkdownBody(
            data: '${i['body']}',
            selectable: true,
            styleSheet: _md(context),
            onTapLink: (_, href, _) => _open(href),
          ),
        for (final c in comments) ...[
          const Divider(height: Space.xl),
          Text('${c['by']} · ${c['date']}', style: context.text.labelSmall),
          const SizedBox(height: 4),
          MarkdownBody(
            data: '${c['text'] ?? ''}',
            selectable: true,
            styleSheet: _md(context),
            onTapLink: (_, href, _) => _open(href),
          ),
        ],
        if (i['url'] != null)
          _Buttons([
            FilledButton.tonalIcon(
              onPressed: () => _open('${i['url']}'),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open on GitHub'),
            ),
          ]),
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.file});
  final Map<String, dynamic> file;

  @override
  Widget build(BuildContext context) {
    final f = file;
    final text = '${f['text']}';
    final lines = text.split('\n');
    return _Shell(
      padding: EdgeInsets.zero,
      onTap: () => _sheet(
        context,
        (scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
          children: [
            Text(
              '${f['path']}',
              style: context.text.titleMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            Text(
              '${f['repo']} · ${f['ref']} · ${lines.length} lines',
              style: context.text.bodySmall,
            ),
            _Buttons([
              OutlinedButton.icon(
                onPressed: () => _copy(context, text, 'Code'),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _open(
                  'https://github.com/${f['repo']}/blob/${f['ref']}/${f['path']}',
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open on GitHub'),
              ),
            ]),
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.m),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      for (final (n, l) in lines.indexed) ...[
                        TextSpan(
                          text: '${'${n + 1}'.padLeft(4)}  ',
                          style: TextStyle(color: AppColors.text3),
                        ),
                        TextSpan(text: '$l\n'),
                      ],
                    ],
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 4),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: AppColors.text2,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${f['path']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                Text('${lines.length} lines', style: context.text.bodySmall),
              ],
            ),
          ),
          Container(
            color: AppColors.surface2,
            padding: const EdgeInsets.all(Space.s),
            child: Text(
              lines.take(8).join('\n'),
              maxLines: 8,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: AppColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- web pages -----------------------------------------------------------------

/// Details of a fetched page for its card and sheet.
class _PageInfo {
  _PageInfo(this.p)
    : url = '${p['url']}',
      host = (Uri.tryParse('${p['url']}')?.host ?? '${p['url']}').replaceFirst(RegExp(r'^www\.'), '');
  final Map<String, dynamic> p;
  final String url;
  final String host;

  String get title => '${p['title'] ?? ''}'.trim().isEmpty ? host : '${p['title']}'.trim();
  String get site => '${p['site_name'] ?? ''}'.trim().isEmpty ? host : '${p['site_name']}'.trim();
  String? get image => p['image'] as String?;
  String get icon => '${p['icon'] ?? ''}'.isNotEmpty ? '${p['icon']}' : 'https://www.google.com/s2/favicons?domain=$host&sz=128';
  String get summary => '${p['description'] ?? p['text'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
  int get links => (p['links'] as List?)?.length ?? 0;

  /// About 1,100 characters a minute of reading.
  int? get minutes {
    final n = (p['length'] as num?)?.toInt() ?? '${p['text'] ?? ''}'.length;
    return n < 600 ? null : (n / 1100).ceil();
  }

  String? get date {
    final d = DateTime.tryParse('${p['published'] ?? ''}');
    return d == null ? null : DateFormat(d.year == DateTime.now().year ? 'd MMM' : 'd MMM y').format(d.toLocal());
  }

  Color? get tint {
    final s = '${p['theme_color'] ?? ''}'.replaceAll('#', '');
    final v = int.tryParse(s.length == 6 ? 'FF$s' : '', radix: 16);
    return v == null ? null : Color(v);
  }
}

/// A link preview: the page's share image (or its icon on its colour), the
/// site and date, title, description, reading time, and ways in.
class _PageCard extends StatelessWidget {
  const _PageCard({required this.page});
  final Map<String, dynamic> page;

  @override
  Widget build(BuildContext context) {
    final i = _PageInfo(page);
    final tint = i.tint ?? AppColors.surface3;
    void read() => _sheet(context, (scroll) => _PageSheet(page: page, scroll: scroll));
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: read,
          child: Container(
            // Drawn over the preview, so the picture can't cover the edge.
            foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1.91,
                  child: i.image != null
                      ? NetImage(
                          i.image,
                          fit: BoxFit.cover,
                          // The image didn't load: a live look at the page instead.
                          errorWidget: _LivePreview(url: i.url, fallback: _TintHeader(info: i, tint: tint)),
                        )
                      : _LivePreview(url: i.url, fallback: _TintHeader(info: i, tint: tint)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.m + 2, Space.m, Space.m + 2, Space.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          NetImage(i.icon, width: 16, height: 16, radius: 4, placeholder: Icons.language_rounded),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(i.site, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: AppColors.text2, fontWeight: FontWeight.w600)),
                          ),
                          if (i.date != null) Text('  ·  ${i.date}', style: context.text.labelMedium?.copyWith(color: AppColors.text3)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
                      if (i.summary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(i.summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.4)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.xs, Space.xs),
                  child: Row(
                    children: [
                      if (i.minutes != null) _Meta(Icons.schedule_rounded, '${i.minutes} min read'),
                      if (i.links > 0) _Meta(Icons.link_rounded, '${i.links} links'),
                      if (page['author'] != null && i.minutes == null) Flexible(child: _Meta(Icons.person_outline_rounded, '${page['author']}')),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text),
                        onPressed: read,
                        icon: const Icon(Icons.chrome_reader_mode_outlined, size: 17),
                        label: const Text('Read'),
                      ),
                      IconButton(
                        tooltip: 'Open in browser',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _open(i.url),
                        icon: Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.text2),
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

/// The page itself, small and still: rendered on the phone (no outside
/// screenshot service sees the link), a skeleton until it has drawn, and
/// [fallback] where web views aren't available.
class _LivePreview extends StatefulWidget {
  const _LivePreview({required this.url, required this.fallback});
  final String url;
  final Widget fallback;

  @override
  State<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<_LivePreview> {
  static final bool _supported = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  WebViewController? _web;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    if (!_supported || uri == null || !uri.hasScheme) return;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Stay on the page: a preview never follows redirects to apps or
          // pop-ups.
          onNavigationRequest: (r) => r.isMainFrame && r.url.startsWith('http') ? NavigationDecision.navigate : NavigationDecision.prevent,
          onPageFinished: (_) => Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted) setState(() => _ready = true);
          }),
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) setState(() => _web = null);
          },
        ),
      )
      ..loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    if (web == null) return widget.fallback;
    return Stack(
      fit: StackFit.expand,
      children: [
        // A wider page than the card, scaled down: closer to how the site looks.
        IgnorePointer(
          child: LayoutBuilder(
            builder: (context, c) => FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              child: SizedBox(width: c.maxWidth * 1.6, height: c.maxHeight * 1.6, child: WebViewWidget(controller: web)),
            ),
          ),
        ),
        // Fades the page into the card below it.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, AppColors.surface.withValues(alpha: 0.55)],
                stops: const [0.6, 1],
              ),
            ),
          ),
        ),
        AnimatedOpacity(opacity: _ready ? 0 : 1, duration: const Duration(milliseconds: 300), child: IgnorePointer(ignoring: _ready, child: const Skeleton())),
      ],
    );
  }
}

class _TintHeader extends StatelessWidget {
  const _TintHeader({required this.info, required this.tint});
  final _PageInfo info;
  final Color tint;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tint.withValues(alpha: 0.55), Color.lerp(tint, AppColors.surface, 0.75)!],
      ),
    ),
    child: Center(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10)]),
        child: NetImage(info.icon, width: 30, height: 30, radius: 6, placeholder: Icons.language_rounded),
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: Space.m),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.text3),
        const SizedBox(width: 4),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3))),
      ],
    ),
  );
}

/// The page, live or as clean text, with what the assistant read.
class _PageSheet extends StatefulWidget {
  const _PageSheet({required this.page, required this.scroll});
  final Map<String, dynamic> page;
  final ScrollController scroll;

  @override
  State<_PageSheet> createState() => _PageSheetState();
}

class _PageSheetState extends State<_PageSheet> {
  late final _PageInfo _i = _PageInfo(widget.page);
  WebViewController? _web;
  late bool _reader = '${widget.page['text'] ?? ''}'.trim().length > 200;
  bool _loading = true;

  WebViewController get _webView => _web ??= WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
      if (mounted) setState(() => _loading = false);
    }))
    ..loadRequest(Uri.parse(_i.url));

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    final links = [
      for (final l in (p['links'] as List? ?? const []))
        if (l is Map && '${l['url'] ?? ''}'.startsWith('http')) l,
    ];
    final paragraphs = '${p['text'] ?? p['description'] ?? ''}'.split(RegExp(r'\n\s*\n|\n')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NetImage(_i.image ?? _i.icon, width: 56, height: 56, radius: Radii.m, placeholder: Icons.language_rounded),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                        const SizedBox(height: 3),
                        Text(
                          [_i.site, p['author'], _i.date, if (_i.minutes != null) '${_i.minutes} min read'].whereType<Object>().where((x) => '$x'.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: true, icon: Icon(Icons.chrome_reader_mode_outlined, size: 17), label: Text('Reader')),
                        ButtonSegment(value: false, icon: Icon(Icons.public_rounded, size: 17), label: Text('Page')),
                      ],
                      selected: {_reader},
                      onSelectionChanged: (s) => setState(() => _reader = s.first),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  IconButton(tooltip: 'Copy link', onPressed: () => _copy(context, _i.url), icon: const Icon(Icons.link_rounded)),
                  IconButton(tooltip: 'Open in browser', onPressed: () => _open(_i.url), icon: const Icon(Icons.open_in_new_rounded)),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.line),
        Expanded(
          child: _reader
              ? ListView(
                  controller: widget.scroll,
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.x4),
                  children: [
                    if (paragraphs.isEmpty) Text('No text was read from this page. Switch to Page to see it.', style: context.text.bodyMedium?.copyWith(color: AppColors.text3)),
                    for (final para in paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.m),
                        child: SelectableText(para, style: context.text.bodyLarge?.copyWith(height: 1.6, fontSize: 15.5)),
                      ),
                    if (p['more_text'] != null) Text('The assistant read the start of the page; the rest is on the page itself.', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                    if (links.isNotEmpty) ...[
                      const SizedBox(height: Space.l),
                      Text('LINKS ON THIS PAGE', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
                      const SizedBox(height: Space.s),
                      for (final l in links.take(40))
                        InkWell(
                          borderRadius: BorderRadius.circular(Radii.m),
                          onTap: () => _open('${l['url']}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                NetImage('https://www.google.com/s2/favicons?domain=${Uri.tryParse('${l['url']}')?.host ?? ''}&sz=64', width: 18, height: 18, radius: 4, placeholder: Icons.link_rounded),
                                const SizedBox(width: Space.m),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${l['text'] ?? ''}'.trim().isEmpty ? '${l['url']}' : '${l['text']}'.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                                      Text('${Uri.tryParse('${l['url']}')?.host ?? ''}${Uri.tryParse('${l['url']}')?.path ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                )
              : Stack(
                  children: [
                    WebViewWidget(controller: _webView),
                    if (_loading) const LinearProgressIndicator(minHeight: 2),
                  ],
                ),
        ),
      ],
    );
  }
}


// ---- music ---------------------------------------------------------------------

/// One 30-second preview at a time, app-wide.
final _preview = AudioPlayer();
final _previewing = ValueNotifier<String?>(null);
bool _previewHooked = false;

Future<void> _togglePreview(String url) async {
  if (!_previewHooked) {
    _previewHooked = true;
    _preview.onPlayerComplete.listen((_) => _previewing.value = null);
  }
  if (_previewing.value == url) {
    await _preview.stop();
    _previewing.value = null;
    return;
  }
  _previewing.value = url;
  try {
    await _preview.stop();
    await _preview.play(UrlSource(url));
  } catch (_) {
    _previewing.value = null;
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton(this.url);
  final String? url;
  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return SizedBox(width: size);
    return ValueListenableBuilder<String?>(
      valueListenable: _previewing,
      builder: (_, playing, _) => IconButton(
        tooltip: playing == u ? 'Stop preview' : 'Play a 30-second preview',
        iconSize: size * 0.62,
        constraints: BoxConstraints.tight(Size.square(size)),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: playing == u ? AppColors.accent : AppColors.surface3,
          foregroundColor: playing == u ? AppColors.bg : AppColors.text,
        ),
        icon: Icon(playing == u ? Icons.stop_rounded : Icons.play_arrow_rounded),
        onPressed: () => _togglePreview(u),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.song, this.showArt = true});
  final Map<String, dynamic> song;
  final bool showArt;

  @override
  Widget build(BuildContext context) => _Shell(
    padding: const EdgeInsets.all(Space.s),
    onTap: song['album_id'] == null
        ? () => _open(_listenUrl('youtube', '${song['title']} ${song['artist'] ?? ''}'))
        : () => showAlbum(context, song),
    child: Row(
      children: [
        if (showArt)
          _Net(song['artwork'] as String?, width: 52, height: 52, placeholder: Icons.music_note_rounded)
        else
          SizedBox(
            width: 28,
            child: Text('${song['track'] ?? ''}', textAlign: TextAlign.center, style: context.text.labelSmall),
          ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${song['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                [
                  if (showArt) song['artist'],
                  if (showArt && song['album'] != null) song['album'],
                  if (song['length'] != null) song['length'],
                ].whereType<Object>().join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        if (song['explicit'] == true) const Padding(padding: EdgeInsets.only(right: 6), child: _Chip('E')),
        _PreviewButton(song['preview'] as String?),
      ],
    ),
  );
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album});
  final Map<String, dynamic> album;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 148,
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.m),
      onTap: () => showAlbum(context, album),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Net(album['artwork'] as String?, width: 148, height: 148, placeholder: Icons.album_outlined),
          const SizedBox(height: 6),
          Text(
            '${album['title']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(
            [album['artist'], album['year']].whereType<Object>().join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist});
  final Map<String, dynamic> artist;

  @override
  Widget build(BuildContext context) => _Shell(
    padding: const EdgeInsets.all(Space.s),
    onTap: () => showArtist(context, artist),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
          child: Icon(Icons.mic_external_on_outlined, color: AppColors.text2),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${artist['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (artist['genre'] != null) Text('${artist['genre']}', style: context.text.bodySmall),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: AppColors.text3),
      ],
    ),
  );
}

class _AlbumHero extends StatelessWidget {
  const _AlbumHero({required this.album});
  final Map<String, dynamic> album;

  @override
  Widget build(BuildContext context) {
    final tracks = [for (final t in (album['track_list'] as List? ?? const [])) if (t is Map) Map<String, dynamic>.from(t)];
    return _Shell(
      onTap: () => showAlbum(context, album),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Net(album['artwork'] as String?, width: 88, height: 88, placeholder: Icons.album_outlined),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${album['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                    Text('${album['artist'] ?? ''}', style: context.text.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (album['year'] != null) _Chip('${album['year']}', icon: Icons.event_outlined),
                        if (album['genre'] != null) _Chip('${album['genre']}'),
                        if (album['tracks'] != null) _Chip('${album['tracks']} tracks', icon: Icons.queue_music_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (tracks.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            for (final t in tracks.take(4)) _SongRow(song: t, showArt: false),
            if (tracks.length > 4)
              Text('+ ${tracks.length - 4} more · tap for all', textAlign: TextAlign.center, style: context.text.labelSmall),
          ],
        ],
      ),
    );
  }
}

void showAlbum(BuildContext context, Map<String, dynamic> item) => _sheet(
  context,
  (scroll) => _Loaded(
    tool: 'music_album',
    args: {'album_id': item['album_id']},
    initial: {
      'title': item['album'] ?? item['title'],
      'artist': item['artist'],
      'artwork': item['artwork'],
      'album_id': item['album_id'],
    },
    builder: (a, loading) {
      final tracks = [for (final t in (a['track_list'] as List? ?? const [])) if (t is Map) Map<String, dynamic>.from(t)];
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Center(child: _Net(a['artwork'] as String?, width: 220, height: 220, radius: Radii.l, placeholder: Icons.album_outlined)),
          const SizedBox(height: Space.m),
          Text('${a['title'] ?? ''}', textAlign: TextAlign.center, style: context.text.titleLarge),
          InkWell(
            onTap: a['artist_id'] == null ? null : () => showArtist(context, {'artist_id': a['artist_id'], 'name': a['artist']}),
            child: Text(
              '${a['artist'] ?? ''}',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: AppColors.accent),
            ),
          ),
          const SizedBox(height: Space.s),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (a['released'] != null) _Chip('${a['released']}', icon: Icons.event_outlined),
              if (a['genre'] != null) _Chip('${a['genre']}'),
              if (tracks.isNotEmpty) _Chip('${tracks.length} tracks', icon: Icons.queue_music_rounded),
              if (a['explicit'] == true) const _Chip('Explicit'),
            ],
          ),
          if (loading) const Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          const SizedBox(height: Space.m),
          for (final t in tracks) _SongRow(song: t, showArt: false),
          if (a['label'] != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text('${a['label']}', textAlign: TextAlign.center, style: context.text.labelSmall),
            ),
          _ListenOn(query: '${a['title'] ?? ''} ${a['artist'] ?? ''}', apple: a['url'] as String?),
        ],
      );
    },
  ),
);

class _ArtistHero extends StatelessWidget {
  const _ArtistHero({required this.artist});
  final Map<String, dynamic> artist;

  @override
  Widget build(BuildContext context) => _Shell(
    onTap: () => showArtist(context, artist),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(child: _Net((artist['image'] ?? artist['artwork']) as String?, width: 72, height: 72, radius: 0, placeholder: Icons.person_outline_rounded)),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${artist['name']}', style: context.text.titleMedium),
              Text(
                [artist['kind'], artist['from'], artist['genre']].whereType<Object>().join(' · '),
                style: context.text.bodySmall,
              ),
              if (artist['summary'] != null) ...[
                const SizedBox(height: 6),
                Text('${artist['summary']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.text2)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

void showArtist(BuildContext context, Map<String, dynamic> item) => _sheet(
  context,
  (scroll) => _Loaded(
    tool: 'music_artist',
    args: {if (item['artist_id'] != null) 'artist_id': item['artist_id'] else 'name': item['name']},
    initial: {'name': item['name'], 'genre': item['genre']},
    builder: (a, loading) {
      final albums = [for (final x in (a['albums'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      final tags = [for (final t in (a['tags'] as List? ?? const [])) '$t'];
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Center(
            child: ClipOval(
              child: _Net((a['image'] ?? a['artwork']) as String?, width: 140, height: 140, radius: 0, placeholder: Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: Space.m),
          Text('${a['name'] ?? ''}', textAlign: TextAlign.center, style: context.text.titleLarge),
          if (a['known_as'] != null) Text('${a['known_as']}', textAlign: TextAlign.center, style: context.text.bodySmall),
          const SizedBox(height: Space.s),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (a['kind'] != null) _Chip('${a['kind']}', icon: Icons.groups_2_outlined),
              if ((a['origin'] ?? a['from']) != null) _Chip('${a['origin'] ?? a['from']}', icon: Icons.place_outlined),
              if (a['active_since'] != null)
                _Chip('${_yearOf(a['active_since'])}–${a['until'] == null ? 'now' : _yearOf(a['until'])}', icon: Icons.timeline_rounded),
              if (a['genre'] != null) _Chip('${a['genre']}'),
              for (final t in tags.take(4)) _Chip(t, color: AppColors.accent),
            ],
          ),
          if (loading) const Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          if (a['summary'] != null) ...[
            const SizedBox(height: Space.m),
            _Expandable('${a['summary']}'),
          ],
          if (albums.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            Text('ALBUMS · ${albums.length}', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            _Carousel(height: 206, children: [for (final al in albums) _AlbumTile(album: al)]),
          ],
          _ListenOn(query: '${a['name'] ?? ''}', apple: a['url'] as String?),
          _Buttons([
            if (a['wikipedia'] != null)
              OutlinedButton.icon(
                onPressed: () => _open(a['wikipedia'] as String?),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Wikipedia'),
              ),
          ]),
        ],
      );
    },
  ),
);

/// A search for [query] on a music service; Android opens its app when it's
/// installed, else the website.
String _listenUrl(String service, String query) {
  final q = Uri.encodeComponent(query.trim());
  return switch (service) {
    'spotify' => 'https://open.spotify.com/search/$q',
    _ => 'https://music.youtube.com/search?q=$q',
  };
}

/// Where to listen: YouTube Music and Spotify first (what Android phones
/// have), Apple Music last, for those who use it.
class _ListenOn extends StatelessWidget {
  const _ListenOn({required this.query, this.apple});
  final String query;
  final String? apple;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.m),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LISTEN ON', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _open(_listenUrl('youtube', query)),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: const Text('YouTube Music'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _open(_listenUrl('spotify', query)),
              icon: const Icon(Icons.graphic_eq_rounded, size: 18),
              label: const Text('Spotify'),
            ),
            if (apple != null)
              OutlinedButton.icon(
                onPressed: () => _open(apple),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Apple Music'),
              ),
          ],
        ),
      ],
    ),
  );
}

String _yearOf(Object? date) => '$date'.length >= 4 ? '$date'.substring(0, 4) : '$date';

// ---- movies and TV -------------------------------------------------------------

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.item, required this.movie});
  final Map<String, dynamic> item;
  final bool movie;

  @override
  Widget build(BuildContext context) {
    final year = movie ? item['year'] : _yearOf(item['premiered'] ?? '');
    final rating = movie ? item['runtime'] : item['rating'];
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: () => showScreen(context, item, movie: movie),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _Net(item['poster'] as String?, width: 132, height: 192, placeholder: movie ? Icons.movie_outlined : Icons.live_tv_rounded),
                if (rating != null)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _Chip(
                      '$rating',
                      icon: movie ? null : Icons.star_rounded,
                      color: movie ? AppColors.text : AppColors.warning,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${item['title']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
            ),
            Text(
              [if ('$year'.isNotEmpty) year, movie ? item['genre'] : item['network']].whereType<Object>().join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenHero extends StatelessWidget {
  const _ScreenHero({required this.item, required this.movie});
  final Map<String, dynamic> item;
  final bool movie;

  @override
  Widget build(BuildContext context) => _Shell(
    onTap: () => showScreen(context, item, movie: movie),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Net(item['poster'] as String?, width: 88, height: 130, placeholder: movie ? Icons.movie_outlined : Icons.live_tv_rounded),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
              Text(
                movie
                    ? [item['year'], item['director'], item['runtime']].whereType<Object>().join(' · ')
                    : [item['network'], item['status']].whereType<Object>().join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${item['synopsis'] ?? item['summary'] ?? ''}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: AppColors.text2),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

void showScreen(BuildContext context, Map<String, dynamic> item, {required bool movie}) => _sheet(
  context,
  (scroll) => _Loaded(
    tool: movie ? 'movie_details' : 'tv_show',
    args: movie ? {'movie_id': item['movie_id']} : {'show_id': item['show_id']},
    initial: item,
    builder: (m, loading) => movie ? _MovieSheet(m: m, loading: loading, scroll: scroll) : _ShowSheet(s: m, loading: loading, scroll: scroll),
  ),
);

class _MovieSheet extends StatelessWidget {
  const _MovieSheet({required this.m, required this.loading, required this.scroll});
  final Map<String, dynamic> m;
  final bool loading;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: [
      Center(child: _Net(m['poster'] as String?, width: 170, height: 252, radius: Radii.l, placeholder: Icons.movie_outlined)),
      const SizedBox(height: Space.m),
      Text('${m['title']}', textAlign: TextAlign.center, style: context.text.titleLarge),
      if (m['director'] != null)
        Text('Directed by ${m['director']}', textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
      const SizedBox(height: Space.s),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          if (m['released'] != null) _Chip('${m['released']}', icon: Icons.event_outlined),
          if (m['runtime'] != null) _Chip('${m['runtime']}', icon: Icons.schedule_rounded),
          if (m['genre'] != null) _Chip('${m['genre']}'),
          if (m['rated'] != null) _Chip('Rated ${m['rated']}', icon: Icons.shield_outlined),
        ],
      ),
      if (loading) const Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      _Buttons([
        if (m['trailer'] != null)
          FilledButton.icon(
            onPressed: () => _open(m['trailer'] as String?),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('Watch the trailer'),
          ),
        if (m['imdb'] != null)
          OutlinedButton.icon(
            onPressed: () => _open(m['imdb'] as String?),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('IMDb'),
          ),
        if (m['wikipedia'] != null)
          OutlinedButton.icon(
            onPressed: () => _open(m['wikipedia'] as String?),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Wikipedia'),
          ),
      ]),
      if (m['synopsis'] != null) ...[
        Text('SYNOPSIS', style: context.text.labelSmall),
        const SizedBox(height: Space.xs),
        _Expandable('${m['synopsis']}'),
      ],
      if ((m['cast'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: Space.m),
        Text('CAST', style: context.text.labelSmall),
        const SizedBox(height: Space.xs),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final c in m['cast'] as List) _Chip('$c', icon: Icons.person_outline_rounded)]),
      ],
      const SizedBox(height: Space.m),
      for (final (label, key) in const [
        ('Written by', 'writers'),
        ('Country', 'country'),
        ('Language', 'language'),
        ('Budget', 'budget'),
        ('Box office', 'box_office'),
      ])
        if (m[key] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 96, child: Text(label, style: context.text.bodySmall)),
                Expanded(child: Text('${m[key]}', style: const TextStyle(fontSize: 13.5))),
              ],
            ),
          ),
    ],
  );
}

class _ShowSheet extends StatelessWidget {
  const _ShowSheet({required this.s, required this.loading, required this.scroll});
  final Map<String, dynamic> s;
  final bool loading;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final seasons = [for (final x in (s['seasons'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final cast = [for (final x in (s['cast'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final next = s['next_episode'] is Map ? Map<String, dynamic>.from(s['next_episode'] as Map) : null;
    final genres = [for (final g in (s['genres'] as List? ?? const [])) '$g'];
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Center(child: _Net(s['poster'] as String?, width: 170, height: 250, radius: Radii.l, placeholder: Icons.live_tv_rounded)),
        const SizedBox(height: Space.m),
        Text('${s['title']}', textAlign: TextAlign.center, style: context.text.titleLarge),
        Text(
          [s['network'], '${_yearOf(s['premiered'] ?? '')}${s['ended'] != null ? '–${_yearOf(s['ended'])}' : (s['status'] == 'Running' ? '–now' : '')}']
              .whereType<Object>()
              .where((x) => '$x'.isNotEmpty)
              .join(' · '),
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: AppColors.text2),
        ),
        const SizedBox(height: Space.s),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            if (s['rating'] != null) _Chip('${s['rating']}', icon: Icons.star_rounded, color: AppColors.warning),
            if (s['status'] != null) _Chip('${s['status']}', color: s['status'] == 'Running' ? AppColors.success : null),
            if (s['episode_length'] != null) _Chip('${s['episode_length']}', icon: Icons.schedule_rounded),
            for (final g in genres) _Chip(g),
          ],
        ),
        if (loading) const Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        if (next != null)
          Container(
            margin: const EdgeInsets.only(top: Space.m),
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.m),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.upcoming_outlined, color: AppColors.success),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    'Next: S${next['season']}E${next['episode']} “${next['title']}”${next['airs'] != null ? ' · ${next['airs']}' : ''}',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        if (s['summary'] != null) ...[
          const SizedBox(height: Space.m),
          _Expandable('${s['summary']}'),
        ],
        if (cast.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text('CAST', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.m),
              itemBuilder: (_, i) => SizedBox(
                width: 76,
                child: Column(
                  children: [
                    ClipOval(child: _Net(cast[i]['photo'] as String?, width: 64, height: 64, radius: 0, placeholder: Icons.person_outline_rounded)),
                    const SizedBox(height: 4),
                    Text('${cast[i]['actor'] ?? ''}', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    Text('${cast[i]['as'] ?? ''}', maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (seasons.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text('SEASONS · ${seasons.length}', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          for (final x in seasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  _Net(x['poster'] as String?, width: 36, height: 52, radius: Radii.s, placeholder: Icons.live_tv_rounded),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text('Season ${x['season']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(
                    [
                      if (x['episodes'] != null) '${x['episodes']} episodes',
                      if (x['from'] != null) _yearOf(x['from']),
                    ].join(' · '),
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
        ],
        _Buttons([
          if (s['url'] != null)
            OutlinedButton.icon(
              onPressed: () => _open(s['url'] as String?),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('TVmaze'),
            ),
          if (s['official_site'] != null)
            OutlinedButton.icon(
              onPressed: () => _open(s['official_site'] as String?),
              icon: const Icon(Icons.public_rounded, size: 18),
              label: const Text('Official site'),
            ),
        ]),
      ],
    );
  }
}
