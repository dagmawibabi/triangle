import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/math_text.dart';
import '../../../papers/papers_api.dart';
import '../../../settings/data/settings.dart';
import '../../domain/chat_models.dart';

/// Cards for the ScholarXIV paper tools: paper lists, one paper, an author
/// and a venue. Tapping a paper opens a sheet with its abstract, links,
/// ids, authors (each opens their profile), similar papers and its venue.
/// Null for other tools.
Widget? papersResultFor(ToolPart part, Map<String, dynamic> j) {
  if (!part.name.startsWith('paper_')) return null;
  // The model got clipped abstracts; the full answer is kept for the card.
  var d = j;
  if (part.full case final f?) {
    try {
      d = Map<String, dynamic>.from(jsonDecode(f) as Map);
    } catch (_) {}
  }
  final papers = _maps(d['papers']);
  return switch (part.name) {
    'paper_search' when papers.isNotEmpty => PaperList(title: 'arXiv', query: '${d['query'] ?? ''}', papers: papers, hasMore: d['has_more'] == true),
    'paper_search_everywhere' when papers.isNotEmpty => PaperList(
      title: 'Papers',
      query: '${d['query'] ?? ''}',
      papers: papers,
      bySource: Map<String, dynamic>.from(d['by_source'] as Map? ?? const {}),
      hasMore: d['has_more'] == true,
    ),
    'paper_recommendations' when papers.isNotEmpty => PaperList(title: 'Related papers', query: '', papers: papers),
    'paper_details' when d['paper'] is Map => _PaperHero(paper: Map<String, dynamic>.from(d['paper'] as Map)),
    'paper_author' when d['name'] != null => _Card(child: _AuthorBody(a: d)),
    'paper_venue' when d['name'] != null => _Card(child: _VenueBody(v: d)),
    _ => null,
  };
}

// ---- helpers ----------------------------------------------------------------------------

List<Map<String, dynamic>> _maps(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x is Map) Map<String, dynamic>.from(x),
];

List<String> _strings(Object? v) => [
  for (final x in (v as List? ?? const []))
    if ('$x'.trim().isNotEmpty && x != null) '$x',
];

String? _str(Object? v) {
  final s = v == null ? '' : '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

String _n(Object? v) => v is num ? NumberFormat.compact().format(v) : '—';

String _exact(Object? v) => v is num ? NumberFormat.decimalPattern().format(v) : '—';

Future<void> _open(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

void _copy(BuildContext context, String text, String what) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$what copied'), duration: const Duration(seconds: 2)));
}

PapersApi _api(BuildContext context) => PapersApi(ProviderScope.containerOf(context, listen: false).read(settingsProvider).scholarxivKey);

const _sourceColors = {
  'arxiv': Color(0xFFB31B1B),
  'openalex': Color(0xFFE0673B),
  'semantic_scholar': Color(0xFF1857B6),
  'pubmed': Color(0xFF326599),
  'europepmc': Color(0xFF2A7AB0),
  'crossref': Color(0xFF3EB1C8),
  'biorxiv': Color(0xFFB21E2D),
  'medrxiv': Color(0xFF0E5C8C),
  'chemrxiv': Color(0xFF6B4FA0),
  'chinarxiv': Color(0xFFC8102E),
  'clinicaltrials': Color(0xFF20744A),
};

Color _sourceColor(String? s) => _sourceColors[s] ?? AppColors.text2;

/// "Ada Lovelace, Alan Turing, Grace Hopper +4"
String _authorLine(List<String> authors, {int shown = 3}) {
  if (authors.isEmpty) return 'Unknown authors';
  if (authors.length <= shown) return authors.join(', ');
  return '${authors.take(shown).join(', ')} +${authors.length - shown}';
}

/// A short reference to paste anywhere: "Vaswani A. et al. (2017). Title. Venue. https://doi.org/…"
String _citation(Map<String, dynamic> p) {
  final authors = _strings(p['authors']);
  String short(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    return '${parts.last} ${parts.first.characters.first}.';
  }

  final who = authors.isEmpty
      ? ''
      : authors.length == 1
      ? short(authors.first)
      : authors.length == 2
      ? '${short(authors[0])} & ${short(authors[1])}'
      : '${short(authors.first)} et al.';
  final link = p['doi'] != null ? 'https://doi.org/${p['doi']}' : (p['url'] ?? '');
  final where = _str(p['venue']) ?? _str(p['journal_ref']) ?? (p['arxiv_id'] != null ? 'arXiv:${p['arxiv_id']}' : null);
  return [
    if (who.isNotEmpty) '$who (${p['year'] ?? 'n.d.'}).',
    '${p['title']}.',
    if (where != null) '$where.',
    if ('$link'.isNotEmpty) '$link',
  ].join(' ');
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    padding: const EdgeInsets.all(Space.l),
    decoration: _frame(),
    child: child,
  );
}

BoxDecoration _frame() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(Radii.l),
  border: Border.all(color: AppColors.line),
);

/// A small rounded pill; with [dot] a coloured dot leads the label (sources).
class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.color, this.icon, this.dot = false});
  final String text;
  final Color? color;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: AppColors.isLight ? 0.09 : 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: 0.22), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[Icon(icon, size: 11, color: c), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dot ? AppColors.text : c, height: 1.2, letterSpacing: 0.1)),
        ],
      ),
    );
  }
}

/// A row of figures in one tinted strip, split by hairlines.
Widget _stats(List<(String, String)> items) => Builder(
  builder: (context) => Container(
    padding: const EdgeInsets.symmetric(vertical: Space.m),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: IntrinsicHeight(
      child: Row(
        children: [
          for (final (i, (label, value)) in items.indexed) ...[
            if (i > 0) VerticalDivider(width: 1, thickness: 1, indent: 4, endIndent: 4, color: AppColors.line),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures, height: 1.1)),
                  const SizedBox(height: 3),
                  Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  ),
);

Widget _section(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.only(top: Space.xxl, bottom: Space.s),
  child: Row(
    children: [
      Text(title.toUpperCase(), style: context.text.labelSmall?.copyWith(letterSpacing: 0.8)),
      const SizedBox(width: Space.s),
      Expanded(child: Divider(height: 1, color: AppColors.line)),
    ],
  ),
);

/// A tappable figure with an icon, for a row's footer.
class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.text2),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.text2, fontFeatures: tabularFigures)),
        ],
      ),
    );
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(99),
      child: onTap == null ? body : InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: body),
    );
  }
}

Widget _chips(List<String> items, {void Function(String)? onTap}) => Wrap(
  spacing: 6,
  runSpacing: 6,
  children: [
    for (final t in items)
      ActionChip(
        label: Text(t, style: const TextStyle(fontSize: 12.5)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: onTap == null ? null : () => onTap(t),
      ),
  ],
);

/// A sheet that loads something from ScholarXIV, then shows it.
Future<void> _loadingSheet<T>(BuildContext context, Future<T> Function() load, Widget Function(BuildContext, T) body) => showAppSheet<void>(
  context,
  initialSize: 0.9,
  builder: (context, scroll) => FutureBuilder<T>(
    future: load(),
    builder: (context, snap) {
      if (snap.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: AppColors.text3),
                const SizedBox(height: Space.s),
                Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2)),
              ],
            ),
          ),
        );
      }
      if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4), children: [body(context, snap.data as T)]);
    },
  ),
);

/// ---- a list of papers -------------------------------------------------------------------

class PaperList extends StatefulWidget {
  const PaperList({super.key, required this.title, required this.query, required this.papers, this.bySource = const {}, this.hasMore = false});
  final String title;
  final String query;
  final List<Map<String, dynamic>> papers;
  final Map<String, dynamic> bySource;
  final bool hasMore;

  @override
  State<PaperList> createState() => _PaperListState();
}

class _PaperListState extends State<PaperList> {
  static const _first = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final shown = _all ? widget.papers : widget.papers.take(_first).toList();
    final sources = widget.bySource.entries.where((e) => e.value is num && (e.value as num) > 0).toList();
    final count = widget.papers.length;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      decoration: _frame(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
                  child: Icon(Icons.auto_stories_outlined, size: 18, color: AppColors.text),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (widget.query.isNotEmpty)
                        Text('“${widget.query}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    '$count${widget.hasMore ? '+' : ''} ${count == 1 ? 'paper' : 'papers'}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.text2, fontFeatures: tabularFigures),
                  ),
                ),
              ],
            ),
          ),
          if (sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [for (final e in sources) _Badge('${PapersApi.sourceLabel(e.key)} · ${e.value}', color: _sourceColor(e.key), dot: true)],
              ),
            ),
          Divider(height: 1, color: AppColors.line),
          for (final (i, p) in shown.indexed) ...[
            if (i > 0) Divider(height: 1, indent: Space.m, endIndent: Space.m, color: AppColors.line),
            PaperRow(paper: p),
          ],
          if (count > _first) ...[
            Divider(height: 1, color: AppColors.line),
            InkWell(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.m),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_all ? 'Show fewer' : 'Show all $count', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text)),
                    const SizedBox(width: 4),
                    Icon(_all ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: AppColors.text2),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PaperRow extends StatelessWidget {
  const PaperRow({super.key, required this.paper});
  final Map<String, dynamic> paper;

  @override
  Widget build(BuildContext context) {
    final p = paper;
    final source = _str(p['source']);
    final where = _str(p['venue']) ?? _str(p['category']);
    final blurb = _str(p['tldr']) ?? _str(p['summary']);
    final pdf = _str(p['pdf']);
    final meta = [if (p['year'] != null) '${p['year']}', ?where];
    return InkWell(
      onTap: () => showPaperSheet(context, p),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (source != null) ...[_Badge(PapersApi.sourceLabel(source), color: _sourceColor(source), dot: true), const SizedBox(width: Space.s)],
                Expanded(
                  child: Text(meta.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.text3, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            MathText('${p['title']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, height: 1.3, fontSize: 15, color: AppColors.text)),
            const SizedBox(height: 4),
            Text(_authorLine(_strings(p['authors'])), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
            if (blurb != null) ...[
              const SizedBox(height: Space.s),
              MathText(blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.text3, height: 1.4)),
            ],
            if (p['citations'] != null || pdf != null) ...[
              const SizedBox(height: Space.s),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (p['citations'] != null) _Meta(Icons.format_quote_rounded, '${_n(p['citations'])} cited'),
                  if (pdf != null) _Meta(Icons.picture_as_pdf_outlined, 'PDF', onTap: () => _open(pdf)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- one paper ---------------------------------------------------------------------------

/// paper_details: the paper's head and TLDR inline; the rest in its sheet.
class _PaperHero extends StatelessWidget {
  const _PaperHero({required this.paper});
  final Map<String, dynamic> paper;

  @override
  Widget build(BuildContext context) {
    final p = paper;
    final tldr = _str(p['tldr']);
    final blurb = tldr ?? _str(p['summary']);
    final tint = _sourceColor(_str(p['source']) ?? _strings(p['sources']).firstOrNull);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      decoration: _frame(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showPaperSheet(context, p),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tint.withValues(alpha: AppColors.isLight ? 0.08 : 0.14), tint.withValues(alpha: 0)],
                  ),
                ),
                child: _PaperHead(p: p),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _stats([
                      ('Citations', _n(p['citations'])),
                      ('Year', '${p['year'] ?? '—'}'),
                      ('Authors', '${_strings(p['authors']).length}'),
                    ]),
                    if (blurb != null) ...[
                      const SizedBox(height: Space.m),
                      _Callout(
                        label: tldr != null ? 'TL;DR' : 'Abstract',
                        child: MathText(blurb, maxLines: 5, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: AppColors.text, height: 1.45)),
                      ),
                    ],
                    const SizedBox(height: Space.m),
                    Row(
                      children: [
                        if (p['pdf'] != null) ...[
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _open(p['pdf'] as String?),
                              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                              label: const Text('Read PDF'),
                            ),
                          ),
                          const SizedBox(width: Space.s),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => showPaperSheet(context, p),
                            icon: const Icon(Icons.subject_rounded, size: 18),
                            label: const Text('Details'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled block with an accent rule down its left edge.
class _Callout extends StatelessWidget {
  const _Callout({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.m),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(Radii.m),
      border: Border(left: BorderSide(color: AppColors.accent.withValues(alpha: 0.8), width: 3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(color: AppColors.text2, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

/// Badges, title, authors and where it was published.
class _PaperHead extends StatelessWidget {
  const _PaperHead({required this.p, this.large = false});
  final Map<String, dynamic> p;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final sources = {..._strings(p['sources']), ?_str(p['source'])}.toList();
    final where = [
      ?_str(p['published']) ?? (p['year'] != null ? '${p['year']}' : null),
      ?_str(p['venue']) ?? _str(p['journal_ref']),
      if (_str(p['venue']) == null && _str(p['journal_ref']) == null) ?_str(p['category']),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final s in sources) _Badge(PapersApi.sourceLabel(s), color: _sourceColor(s), dot: true),
            if (_str(p['type']) case final t?) _Badge(t),
            if (p['pdf'] != null) _Badge('Open access', color: AppColors.success, icon: Icons.lock_open_rounded),
          ],
        ),
        SizedBox(height: large ? Space.m : Space.s),
        large
            ? MathText('${p['title']}', selectable: true, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.28, fontSize: 22))
            : MathText('${p['title']}', maxLines: 4, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.28, fontSize: 17)),
        if (!large) ...[
          const SizedBox(height: 6),
          Text(_authorLine(_strings(p['authors']), shown: 4), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.text2)),
        ],
        if (where.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.event_note_outlined, size: 13, color: AppColors.text3),
              const SizedBox(width: 5),
              Expanded(child: Text(where.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.text3))),
            ],
          ),
        ],
      ],
    );
  }
}

// Everything about one paper, in a sheet.
Future<void> showPaperSheet(BuildContext context, Map<String, dynamic> paper) => showAppSheet<void>(
  context,
  initialSize: 0.92,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: [_PaperDetails(p: paper)],
  ),
);

class _PaperDetails extends StatefulWidget {
  const _PaperDetails({required this.p});
  final Map<String, dynamic> p;

  @override
  State<_PaperDetails> createState() => _PaperDetailsState();
}

class _PaperDetailsState extends State<_PaperDetails> {
  bool _allAuthors = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final authors = _strings(p['authors']);
    final shownAuthors = _allAuthors ? authors : authors.take(12).toList();
    final id = _str(p['id']);
    final page = _str(p['url']);
    final ids = <(String, String, String?)>[
      if (_str(p['arxiv_id']) case final a?) ('arXiv', a, 'https://arxiv.org/abs/$a'),
      if (_str(p['doi']) case final d?) ('DOI', d, 'https://doi.org/$d'),
      if (_str(p['s2_id']) case final s?) ('Semantic Scholar', s, 'https://www.semanticscholar.org/paper/$s'),
      if (_str(p['openalex_id']) case final o?) ('OpenAlex', o, 'https://openalex.org/$o'),
      if (_str(p['pmid']) case final m?) ('PubMed', m, 'https://pubmed.ncbi.nlm.nih.gov/$m'),
      if (_str(p['pmcid']) case final m?) ('PMC', m, 'https://www.ncbi.nlm.nih.gov/pmc/articles/$m'),
      for (final i in _strings(p['issn'])) ('ISSN', i, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaperHead(p: p, large: true),
        if (authors.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, name) in shownAuthors.indexed)
                _AuthorChip(
                  name: name,
                  onTap: id == null && (p['s2_author_ids'] as List?)?.elementAtOrNull(i) == null ? null : () => showPaperAuthorSheet(context, p, i),
                ),
              if (authors.length > 12)
                _AuthorChip(name: _allAuthors ? 'Fewer' : '+${authors.length - 12} more', plain: true, onTap: () => setState(() => _allAuthors = !_allAuthors)),
            ],
          ),
        ],
        const SizedBox(height: Space.l),
        _stats([
          ('Citations', p['citations'] != null ? _exact(p['citations']) : '—'),
          ('Year', '${p['year'] ?? '—'}'),
          ('Authors', '${authors.length}'),
        ]),
        const SizedBox(height: Space.m),
        Row(
          children: [
            for (final (i, a) in [
              if (p['pdf'] != null) (Icons.picture_as_pdf_outlined, 'PDF', () => _open(p['pdf'] as String?)),
              if (page != null) (Icons.open_in_new_rounded, 'Page', () => _open(page)),
              if (_str(p['scholarxiv_url']) case final sx?) (Icons.auto_stories_outlined, 'ScholarXIV', () => _open(sx)),
              (Icons.format_quote_rounded, 'Cite', () => _copy(context, _citation(p), 'Citation')),
            ].indexed) ...[
              if (i > 0) const SizedBox(width: Space.s),
              Expanded(child: _ActionTile(icon: a.$1, label: a.$2, onTap: a.$3, primary: i == 0 && p['pdf'] != null)),
            ],
          ],
        ),
        if (_str(p['tldr']) case final t?) ...[
          const SizedBox(height: Space.l),
          _Callout(label: 'TL;DR', child: MathText(t, selectable: true, style: context.text.bodyMedium?.copyWith(height: 1.5, color: AppColors.text))),
        ],
        if (_str(p['summary']) case final abs?) ...[
          _section(context, 'Abstract'),
          MathText(abs, selectable: true, style: context.text.bodyMedium?.copyWith(height: 1.65, fontSize: 15, color: AppColors.text)),
        ],
        if (_str(p['comment']) case final c?) ...[
          _section(context, 'Comments'),
          MathText(c, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45)),
        ],
        if (_strings(p['categories']).isNotEmpty) ...[
          _section(context, 'Subjects'),
          _chips(_strings(p['categories'])),
        ],
        if (id != null) ...[
          _section(context, 'Explore'),
          Container(
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome_motion_outlined),
                  title: const Text('Similar papers'),
                  subtitle: const Text('Recommended by Semantic Scholar'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _loadingSheet<List<Map<String, dynamic>>>(
                    context,
                    () => _api(context).recommendations(id),
                    (context, list) => list.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(Space.xl),
                            child: Text('Semantic Scholar has no recommendations for this paper yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2)),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Similar to', style: context.text.labelSmall),
                              const SizedBox(height: 2),
                              MathText('${p['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                              const SizedBox(height: Space.s),
                              PaperList(title: 'Related papers', query: '', papers: list),
                            ],
                          ),
                  ),
                ),
                if (_str(p['venue']) != null || _str(p['journal_ref']) != null || _strings(p['issn']).isNotEmpty) ...[
                  Divider(height: 1, color: AppColors.line),
                  ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: Text(_str(p['venue']) ?? 'Where it was published', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Journal or conference'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _loadingSheet<Map<String, dynamic>>(
                      context,
                      () => _api(context).venue(id, issn: _strings(p['issn']), name: _str(p['venue']), openAlexId: _str(p['openalex_id'])),
                      (context, v) => _VenueBody(v: v),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (ids.isNotEmpty) ...[
          _section(context, 'Identifiers'),
          for (final (label, value, link) in ids)
            InkWell(
              onTap: () => _copy(context, value, label),
              onLongPress: link == null ? null : () => _open(link),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 120, child: Text(label, style: context.text.bodySmall?.copyWith(color: AppColors.text3))),
                    Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontFamily: 'monospace'))),
                    Icon(Icons.copy_rounded, size: 14, color: AppColors.text3),
                  ],
                ),
              ),
            ),
          Text('Tap to copy · long-press to open', style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontSize: 11)),
        ],
        if (_str(p['license']) case final l?) ...[
          const SizedBox(height: Space.m),
          Text('License: $l', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        ],
      ],
    );
  }
}

/// An author's name with their initial; opens their profile.
class _AuthorChip extends StatelessWidget {
  const _AuthorChip({required this.name, this.onTap, this.plain = false});
  final String name;
  final VoidCallback? onTap;
  final bool plain;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface2,
    borderRadius: BorderRadius.circular(99),
    child: InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(plain ? 12 : 4, 4, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!plain) ...[LetterAvatar(name, size: 22), const SizedBox(width: 7)],
            Text(name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: plain ? AppColors.text2 : AppColors.text)),
          ],
        ),
      ),
    ),
  );
}

/// A square-ish action: icon over label.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? AppColors.bg : AppColors.text;
    return Material(
      color: primary ? AppColors.text : AppColors.surface2,
      borderRadius: BorderRadius.circular(Radii.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.m, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: 5),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The profile of the author at [index] on [paper].
Future<void> showPaperAuthorSheet(BuildContext context, Map<String, dynamic> paper, int index) =>
    _loadingSheet<Map<String, dynamic>>(context, () => _api(context).authorOf(paper, index), (context, a) => _AuthorBody(a: a));

// ---- an author -----------------------------------------------------------------------------

class _AuthorBody extends StatelessWidget {
  const _AuthorBody({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final name = '${a['name'] ?? 'Unknown'}';
    final oa = a['openAlex'] as Map? ?? a['openalex'] as Map?;
    final affiliations = {..._strings(a['affiliations']), ..._strings(oa?['institutions'])}.toList();
    final years = _maps(a['papersByYear']);
    final top = _maps(a['topPapers']);
    final venues = _maps(a['topVenues']);
    final topics = _strings(oa?['topics']);
    final first = a['firstYear'] ?? a['first_year'];
    final last = a['lastYear'] ?? a['last_year'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LetterAvatar(name, size: 52),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (affiliations.isNotEmpty)
                    Text(affiliations.take(2).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
                  if (first != null)
                    Text('Publishing ${first == last || last == null ? '$first' : '$first–$last'}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.l),
        _stats([
          ('Papers', _n(a['paperCount'] ?? a['paper_count'])),
          ('Citations', _n(a['citationCount'] ?? a['citation_count'])),
          ('h-index', '${a['hIndex'] ?? a['h_index'] ?? '—'}'),
          if (oa?['i10Index'] != null) ('i10', '${oa!['i10Index']}'),
        ]),
        if (years.length > 1) ...[
          _section(context, 'Papers per year'),
          _YearBars(years: years),
        ],
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            if (_str(a['url']) case final u?) OutlinedButton.icon(onPressed: () => _open(u), icon: const Icon(Icons.person_outline_rounded, size: 18), label: const Text('Profile')),
            if (_str(a['homepage']) case final h?) OutlinedButton.icon(onPressed: () => _open(h), icon: const Icon(Icons.home_outlined, size: 18), label: const Text('Homepage')),
            if (_str(a['orcid']) case final o?)
              OutlinedButton.icon(onPressed: () => _open(o.startsWith('http') ? o : 'https://orcid.org/$o'), icon: const Icon(Icons.badge_outlined, size: 18), label: const Text('ORCID')),
          ],
        ),
        if (top.isNotEmpty) ...[
          _section(context, 'Top papers'),
          for (final p in top.take(8))
            InkWell(
              onTap: () => _open(_str(p['url'])),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MathText('${p['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25)),
                          const SizedBox(height: 2),
                          Text(
                            [?_str(p['year']), ?_str(p['venue'])].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                          ),
                        ],
                      ),
                    ),
                    if (p['citationCount'] ?? p['citations'] case final num c) ...[
                      const SizedBox(width: Space.s),
                      Column(
                        children: [
                          Text(_n(c), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text('cites', style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontSize: 10.5)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
        if (venues.isNotEmpty) ...[
          _section(context, 'Publishes in'),
          _chips([for (final v in venues.take(8)) '${v['name']} · ${v['count']}']),
        ] else if (_strings(a['top_venues']).isNotEmpty) ...[
          _section(context, 'Publishes in'),
          _chips(_strings(a['top_venues'])),
        ],
        if (topics.isNotEmpty) ...[
          _section(context, 'Topics'),
          _chips(topics.take(10).toList()),
        ],
        const SizedBox(height: Space.m),
        Text(
          'From ${a['source'] == 'openalex' ? 'OpenAlex' : 'Semantic Scholar'} via ScholarXIV',
          style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontSize: 11),
        ),
      ],
    );
  }
}

/// Papers per year as small bars, the last 20 years at most.
class _YearBars extends StatelessWidget {
  const _YearBars({required this.years});
  final List<Map<String, dynamic>> years;

  @override
  Widget build(BuildContext context) {
    final list = years.length > 20 ? years.sublist(years.length - 20) : years;
    final max = list.map((y) => (y['count'] as num?)?.toDouble() ?? 0).fold<double>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 84,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final y in list)
                  Expanded(
                    child: Tooltip(
                      message: '${y['year']}: ${y['count']} papers',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        height: (((y['count'] as num?)?.toDouble() ?? 0) / max * 64).clamp(2, 64),
                        decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.75), borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${list.first['year']}', style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontSize: 11)),
              Text('${list.last['year']}', style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- a venue ------------------------------------------------------------------------------

class _VenueBody extends StatelessWidget {
  const _VenueBody({required this.v});
  final Map<String, dynamic> v;

  @override
  Widget build(BuildContext context) {
    // The raw API answer (in a sheet, or the tool's full result) or the brief.
    final oa = v['openAlex'] as Map? ?? v;
    final journal = v['journal'] as Map?;
    final type = _str(v['type']);
    final place = [?_str(oa['publisher']), ?_str(oa['country'])];
    final first = oa['firstYear'] ?? oa['first_year'];
    final last = oa['lastYear'] ?? oa['last_year'];
    final apc = oa['apcUsd'] ?? oa['apc_usd'];
    final openAccess = oa['isOpenAccess'] ?? oa['open_access'];
    final doaj = oa['isInDoaj'] ?? oa['in_doaj'];
    final hIndex = oa['hIndex'] ?? oa['h_index'];
    final works = oa['worksCount'] ?? oa['works'];
    final cites = oa['citedByCount'] ?? oa['citations'];
    final mean = oa['meanCitedness2yr'] ?? oa['mean_citedness_2yr'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
              child: Icon(type == 'conference' ? Icons.groups_outlined : Icons.menu_book_outlined, color: AppColors.text2),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${v['name']}', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
                  if (place.isNotEmpty) Text(place.join(' · '), style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (type != null) _Badge(type),
                      if (openAccess == true) _Badge('Open access', color: AppColors.success, icon: Icons.lock_open_rounded),
                      if (doaj == true) _Badge('DOAJ', color: AppColors.success),
                      if (first != null) _Badge(last == null || last == first ? 'Since $first' : '$first–$last'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (hIndex != null || works != null || cites != null) ...[
          const SizedBox(height: Space.l),
          _stats([
            if (hIndex != null) ('h-index', '$hIndex'),
            if (works != null) ('Works', _n(works)),
            if (cites != null) ('Citations', _n(cites)),
            if (mean is num) ('2-yr mean', mean.toStringAsFixed(1)),
          ]),
        ],
        if (journal != null && (journal['volume'] != null || journal['pages'] != null)) ...[
          const SizedBox(height: Space.m),
          Text(
            'This paper: ${[if (journal['volume'] != null) 'vol. ${journal['volume']}', if (journal['pages'] != null) 'pp. ${journal['pages']}', ?_str(v['paperYear'])].join(', ')}',
            style: context.text.bodySmall?.copyWith(color: AppColors.text2),
          ),
        ],
        if (apc is num) ...[
          const SizedBox(height: Space.s),
          Text('Article processing charge: \$${NumberFormat.decimalPattern().format(apc)}', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
        ],
        if (_strings(oa['topics']).isNotEmpty) ...[
          _section(context, 'Topics'),
          _chips(_strings(oa['topics']).take(10).toList()),
        ],
        if (_strings(v['issn']).isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text('ISSN ${_strings(v['issn']).join(', ')}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        ],
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            if (_str(v['url']) case final u?) OutlinedButton.icon(onPressed: () => _open(u), icon: const Icon(Icons.language_rounded, size: 18), label: const Text('Website')),
            if (_str(oa['url']) case final u? when oa != v) OutlinedButton.icon(onPressed: () => _open(u), icon: const Icon(Icons.hub_outlined, size: 18), label: const Text('OpenAlex')),
            if (_str(v['semanticScholarUrl']) case final u?)
              OutlinedButton.icon(onPressed: () => _open(u), icon: const Icon(Icons.school_outlined, size: 18), label: const Text('Semantic Scholar')),
          ],
        ),
        const SizedBox(height: Space.m),
        Text(
          'From ${v['source'] == 'openalex' ? 'OpenAlex' : 'Semantic Scholar'} via ScholarXIV',
          style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontSize: 11),
        ),
      ],
    );
  }
}
