import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../bible/bible.dart';
import '../../domain/chat_models.dart';

/// Cards for the Bible tools: a passage, the verse of the day, a chapter to
/// read (and page through), translations side by side, versions and books.
/// Null for other tools.
Widget? bibleResultFor(ToolPart part, Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'bible_passage' when j['text'] != null => _PassageCard(p: j),
    'bible_verse_of_the_day' when j['text'] != null => _PassageCard(p: j, daily: true),
    'bible_chapter' when j['text'] != null => _ChapterCard(p: j),
    'bible_search' when list(j['results']).isNotEmpty => _SearchCard(data: j, results: list(j['results'])),
    'bible_compare' when list(j['translations']).isNotEmpty => _CompareCard(data: j, translations: list(j['translations'])),
    'bible_versions' when list(j['versions']).isNotEmpty => _VersionsCard(data: j, versions: list(j['versions'])),
    'bible_books' when list(j['old_testament']).isNotEmpty || list(j['new_testament']).isNotEmpty => _BooksCard(data: j),
    _ => null,
  };
}

const _gold = Color(0xFFC9A227);
Color get _goldText => AppColors.isLight ? const Color(0xFF8A6D10) : const Color(0xFFE2C25A);

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

String _versionLabel(Map<String, dynamic> p) => '${_map(p['version'])['abbreviation'] ?? ''}';

/// Bible text with verse numbers set small, raised and gold: "16 For God
/// so…" becomes ¹⁶For God so… where the text carries its numbers. Words in
/// [highlight] (a search) are set bold in gold.
Widget _scripture(BuildContext context, String text, {double size = 16, int? maxLines, List<String> highlight = const []}) {
  final style = TextStyle(fontFamily: 'serif', fontSize: size, height: 1.65, color: AppColors.text, letterSpacing: 0.1);
  final words = highlight.where((w) => w.trim().length > 1).map((w) => RegExp.escape(w.trim())).toList();
  final hl = words.isEmpty ? null : RegExp('(${words.join('|')})', caseSensitive: false);
  void addText(List<InlineSpan> to, String s) {
    if (hl == null) {
      to.add(TextSpan(text: s));
      return;
    }
    var at = 0;
    for (final m in hl.allMatches(s)) {
      if (m.start > at) to.add(TextSpan(text: s.substring(at, m.start)));
      to.add(TextSpan(text: m[0], style: TextStyle(fontWeight: FontWeight.w700, color: _goldText, backgroundColor: _gold.withValues(alpha: 0.12))));
      at = m.end;
    }
    if (at < s.length) to.add(TextSpan(text: s.substring(at)));
  }

  final spans = <InlineSpan>[];
  final re = RegExp(r'(?:(?<=^)|(?<=\s))(\d{1,3})(?=\s?[A-Z“"‘‘“(])');
  var at = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > at) addText(spans, text.substring(at, m.start));
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text(m[1]!, style: TextStyle(fontSize: size * 0.58, fontWeight: FontWeight.w800, color: _goldText)),
        ),
      ),
    );
    at = m.end;
    if (at < text.length && text[at] == ' ') at++;
  }
  if (at < text.length) addText(spans, text.substring(at));
  return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.fade);
}

Future<void> _open(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Copy, open in YouVersion and read the chapter, as one quiet bar.
class _Actions extends StatelessWidget {
  const _Actions({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData i, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(i, size: 19, color: AppColors.text2),
    );
    return Row(
      children: [
        icon(Icons.copy_rounded, 'Copy', () {
          Clipboard.setData(ClipboardData(text: '${p['text']}\n— ${p['reference']} (${_versionLabel(p)})'));
          showSnack(context, 'Copied ${p['reference']}');
        }),
        if (p['link'] != null) icon(Icons.open_in_new_rounded, 'Open in YouVersion', () => _open(p['link'] as String?)),
        const Spacer(),
        if (p['passage_id'] != null)
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _goldText),
            onPressed: () {
              final r = BibleRef.parse('${p['passage_id']}');
              if (r != null) _openReader(context, BibleRef(r.book, r.chapter), '${_map(p['version'])['version_id'] ?? ''}');
            },
            icon: const Icon(Icons.auto_stories_rounded, size: 18),
            label: const Text('Read chapter'),
          ),
      ],
    );
  }
}

/// The Bible cards' panel: a warm, faintly gold surface.
class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.highlight = false});
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(
      color: AppColors.surface,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.alphaBlend(_gold.withValues(alpha: highlight ? 0.14 : 0.07), AppColors.surface), AppColors.surface],
      ),
      borderRadius: BorderRadius.circular(Radii.xl),
    ),
    // The edge is drawn over the content so artwork can't cover the
    // rounded corners.
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.xl),
      border: Border.all(color: _gold.withValues(alpha: highlight ? 0.45 : 0.22)),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// The small gold heading of a Bible card.
class _Kicker extends StatelessWidget {
  const _Kicker({required this.icon, required this.text, this.trailing});
  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: _gold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 15, color: _goldText),
      ),
      const SizedBox(width: Space.s),
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: _goldText, letterSpacing: 1.2, fontWeight: FontWeight.w700))),
      ?trailing,
    ],
  );
}

/// "— John 3:16" over a thin gold rule, with the version.
class _Citation extends StatelessWidget {
  const _Citation({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 22, height: 1.5, color: _gold.withValues(alpha: 0.7)),
      const SizedBox(width: Space.s),
      Flexible(child: Text('${p['reference']}', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text, letterSpacing: 0.2))),
      const SizedBox(width: Space.s),
      _Badge(_versionLabel(p)),
    ],
  );
}

class _PassageCard extends StatelessWidget {
  const _PassageCard({required this.p, this.daily = false});
  final Map<String, dynamic> p;
  final bool daily;

  @override
  Widget build(BuildContext context) {
    final text = '${p['text']}';
    final long = text.length > 700;
    final images = [
      if (p['image'] is String) '${p['image']}',
      for (final i in (p['images'] as List? ?? const []))
        if (i is Map && i['url'] is String) '${i['url']}',
    ];
    final date = DateTime.tryParse('${p['date'] ?? ''}');
    return _Frame(
      highlight: daily,
      child: InkWell(
        onTap: () => _showPassage(context, p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (daily && images.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(images.first, fit: BoxFit.cover, errorWidget: const SizedBox.shrink()),
                    Positioned(
                      left: Space.m,
                      top: Space.m,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wb_sunny_rounded, size: 14, color: Color(0xFFFFD66B)),
                            const SizedBox(width: 6),
                            Text(
                              'Verse of the day${date == null ? '' : ' · ${MaterialLocalizations.of(context).formatShortMonthDay(date)}'}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Stack(
              children: [
                // A large, faint opening quote mark behind the text.
                if (!(daily && images.isNotEmpty)) Positioned(
                  right: Space.l,
                  top: Space.xs,
                  child: Text('”', style: TextStyle(fontFamily: 'serif', fontSize: 96, height: 1, color: _gold.withValues(alpha: 0.18), fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.s, Space.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!(daily && images.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(right: Space.s, bottom: Space.m),
                          child: _Kicker(icon: daily ? Icons.wb_sunny_rounded : Icons.menu_book_rounded, text: daily ? 'VERSE OF THE DAY' : 'SCRIPTURE'),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: _scripture(context, text, size: daily ? 19 : 17.5, maxLines: long ? 12 : null),
                      ),
                      const SizedBox(height: Space.m),
                      Padding(padding: const EdgeInsets.only(right: Space.s), child: _Citation(p: p)),
                      const SizedBox(height: Space.xs),
                      _Actions(p: p),
                      if (!daily && images.isNotEmpty) ...[
                        SizedBox(
                          height: 96,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: Space.s, bottom: Space.m),
                            itemCount: images.length,
                            separatorBuilder: (_, _) => const SizedBox(width: Space.s),
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => _showPassage(context, p, image: i),
                              child: NetImage(images[i], width: 84, height: 84, radius: Radii.m, fit: BoxFit.cover, errorWidget: const SizedBox.shrink()),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.data, required this.results});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context) {
    final version = _map(data['version']);
    final words = '${data['query'] ?? ''}'.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    return _Frame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
            child: _Kicker(icon: Icons.manage_search_rounded, text: '"${data['query']}" · ${results.length} VERSES', trailing: _Badge('${version['abbreviation'] ?? ''}')),
          ),
          for (final (i, r) in results.indexed)
            InkWell(
              onTap: () => _showPassage(context, {...r, 'version': version, 'link': null}),
              child: Container(
                margin: EdgeInsets.fromLTRB(Space.m, i == 0 ? 0 : Space.xs, Space.m, Space.xs),
                padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s + 2),
                decoration: BoxDecoration(
                  color: AppColors.surface2.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(Radii.m),
                  border: Border(left: BorderSide(color: _gold.withValues(alpha: 0.7), width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['reference']}', style: TextStyle(fontWeight: FontWeight.w800, color: _goldText, fontSize: 13, letterSpacing: 0.2)),
                    const SizedBox(height: 3),
                    _scripture(context, '${r['text']}', size: 15, maxLines: 4, highlight: words),
                  ],
                ),
              ),
            ),
          if ((data['did_you_mean'] as List?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, 0),
              child: Text('Did you mean: ${(data['did_you_mean'] as List).join(', ')}', style: context.text.bodySmall),
            ),
          const SizedBox(height: Space.m),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => text.isEmpty
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: _gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20), border: Border.all(color: _gold.withValues(alpha: 0.35))),
          child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: _goldText)),
        );
}

List<String> _imagesOf(Map<String, dynamic> p) => [
  if (p['image'] is String) '${p['image']}',
  for (final i in (p['images'] as List? ?? const []))
    if (i is Map && i['url'] is String) '${i['url']}',
];

/// A verse's sheet: its artwork (swipe through when there are several),
/// the text, and copy, save art, YouVersion, read chapter and full-size art.
void _showPassage(BuildContext context, Map<String, dynamic> p, {int image = 0}) => showAppSheet<void>(
  context,
  initialSize: 0.9,
  builder: (context, scroll) => _VerseSheet(p: p, scroll: scroll, start: image),
);

class _VerseSheet extends StatefulWidget {
  const _VerseSheet({required this.p, required this.scroll, this.start = 0});
  final Map<String, dynamic> p;
  final ScrollController scroll;
  final int start;

  @override
  State<_VerseSheet> createState() => _VerseSheetState();
}

class _VerseSheetState extends State<_VerseSheet> {
  late final _images = _imagesOf(widget.p);
  late int _at = widget.start.clamp(0, _images.isEmpty ? 0 : _images.length - 1);
  late final _pages = PageController(initialPage: _at);
  bool _saving = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_images.isEmpty) return;
    setState(() => _saving = true);
    try {
      final r = await http.get(Uri.parse(_images[_at])).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw Exception('${r.statusCode}');
      await Gal.putImageBytes(r.bodyBytes, album: 'Triangle', name: 'verse_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) showSnack(context, 'Saved to your gallery', icon: Icons.check_rounded);
    } catch (_) {
      if (mounted) showSnack(context, 'Couldn\'t save the image', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _fullScreen() => Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text('${widget.p['reference']}')),
        body: Center(child: InteractiveViewer(maxScale: 5, child: NetImage(_images[_at], fit: BoxFit.contain, placeholder: null))),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final date = DateTime.tryParse('${p['date'] ?? ''}');
    final r = p['passage_id'] == null ? null : BibleRef.parse('${p['passage_id']}');
    Widget action(IconData icon, String label, VoidCallback? onTap, {bool busy = false}) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.l),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: _gold.withValues(alpha: 0.13), shape: BoxShape.circle, border: Border.all(color: _gold.withValues(alpha: 0.3))),
                child: busy ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 20, color: _goldText),
              ),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
            ],
          ),
        ),
      ),
    );
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        if (_images.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xl),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pages,
                    itemCount: _images.length,
                    onPageChanged: (i) => setState(() => _at = i),
                    itemBuilder: (_, i) => GestureDetector(onTap: _fullScreen, child: NetImage(_images[i], fit: BoxFit.cover, placeholder: Icons.image_outlined)),
                  ),
                  if (_images.length > 1)
                    Positioned(
                      bottom: Space.m,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _images.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: i == _at ? 16 : 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == _at ? 0.95 : 0.5), borderRadius: BorderRadius.circular(3)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.l),
        ],
        _Kicker(
          icon: date != null ? Icons.wb_sunny_rounded : Icons.menu_book_rounded,
          text: date != null ? 'VERSE OF THE DAY · ${MaterialLocalizations.of(context).formatMediumDate(date).toUpperCase()}' : '${_map(p['version'])['title'] ?? 'SCRIPTURE'}'.toUpperCase(),
          trailing: _Badge(_versionLabel(p)),
        ),
        const SizedBox(height: Space.m),
        Text('${p['reference']}', style: TextStyle(fontFamily: 'serif', fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.2)),
        const SizedBox(height: Space.m),
        _scripture(context, '${p['text']}', size: 19),
        const SizedBox(height: Space.xl),
        Container(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.xl)),
          child: Row(
            children: [
              action(Icons.copy_rounded, 'Copy', () {
                Clipboard.setData(ClipboardData(text: '${p['text']}\n— ${p['reference']} (${_versionLabel(p)})'));
                showSnack(context, 'Copied ${p['reference']}');
              }),
              if (_images.isNotEmpty) action(Icons.download_rounded, 'Save art', _save, busy: _saving),
              if (r != null)
                action(Icons.auto_stories_rounded, 'Chapter', () => _openReader(context, BibleRef(r.book, r.chapter), '${_map(p['version'])['version_id'] ?? ''}')),
              if (p['link'] != null) action(Icons.open_in_new_rounded, 'YouVersion', () => _open(p['link'] as String?)),
              if (_images.isNotEmpty) action(Icons.fullscreen_rounded, 'Full screen', _fullScreen),
            ],
          ),
        ),
        if (p['copyright'] != null) ...[
          const SizedBox(height: Space.l),
          Text('${p['copyright']}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        ],
        if (_images.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Text('Verse art from YouVersion', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        ],
      ],
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final r = BibleRef.parse('${p['passage_id']}');
    final ref = '${p['reference'] ?? ''}';
    final digits = RegExp(r'(\d+)$').firstMatch(ref)?.group(1);
    final book = digits == null ? ref : ref.substring(0, ref.length - digits.length).trim();
    final ch = (p['chapter'] as num?)?.toInt() ?? int.tryParse(digits ?? '');
    final of = (p['chapters_in_book'] as num?)?.toInt();
    var text = '${p['text'] ?? ''}'.trim().replaceFirst(RegExp(r'^\d{1,3}\s*'), '');
    final first = text.isEmpty ? '' : text.characters.first;
    if (text.isNotEmpty) text = text.characters.skip(1).toString();
    void read() => r == null ? null : _openReader(context, r, '${_map(p['version'])['version_id'] ?? ''}');
    return _Frame(
      child: InkWell(
        onTap: read,
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Kicker(icon: Icons.auto_stories_rounded, text: 'READ', trailing: _Badge(_versionLabel(p))),
              const SizedBox(height: Space.m),
              Text(book, style: TextStyle(fontFamily: 'serif', fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.1)),
              if (ch != null) Text('Chapter $ch', style: TextStyle(fontFamily: 'serif', fontSize: 15, color: _goldText, fontStyle: FontStyle.italic)),
              const SizedBox(height: Space.m),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Colors.white, Colors.transparent], stops: [0, 0.6, 1]).createShader(b),
                blendMode: BlendMode.dstIn,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A gold drop cap.
                    if (first.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 6, top: 2),
                        child: Text(first, style: TextStyle(fontFamily: 'serif', fontSize: 46, height: 1, fontWeight: FontWeight.w700, color: _goldText)),
                      ),
                    Expanded(child: _scripture(context, text, size: 15.5, maxLines: 7)),
                  ],
                ),
              ),
              const SizedBox(height: Space.m),
              Row(
                children: [
                  if (ch != null && of != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$ch of $of', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(value: (ch / of).clamp(0.0, 1.0), minHeight: 4, color: _gold, backgroundColor: _gold.withValues(alpha: 0.15)),
                          ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: Space.l),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black, visualDensity: VisualDensity.compact),
                    onPressed: r == null ? null : read,
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: const Text('Read'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openReader(BuildContext context, BibleRef ref, String version) => showAppSheet<void>(
  context,
  initialSize: 0.92,
  builder: (context, scroll) => _Reader(start: ref, version: version, scroll: scroll),
);

/// A chapter to read: bigger or smaller text, and the previous and next
/// chapters a tap away (fetched from YouVersion as you go).
class _Reader extends ConsumerStatefulWidget {
  const _Reader({required this.start, required this.version, required this.scroll});
  final BibleRef start;
  final String version;
  final ScrollController scroll;

  @override
  ConsumerState<_Reader> createState() => _ReaderState();
}

class _ReaderState extends ConsumerState<_Reader> {
  late BibleRef _ref = widget.start;
  double _size = 18;
  String? _text;
  String? _title;
  String? _abbr;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(bibleServiceProvider);
      final v = await svc.version(widget.version, book: _ref.book.code);
      final p = await svc.read(v, _ref);
      if (!mounted) return;
      setState(() {
        _text = p.text;
        _title = p.reference.isNotEmpty ? p.reference : _ref.label;
        _abbr = v.short;
        _loading = false;
      });
      if (widget.scroll.hasClients) widget.scroll.jumpTo(0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = BibleService.explain(e);
          _loading = false;
        });
      }
    }
  }

  void _go(BibleRef? r) {
    if (r == null) return;
    _ref = r;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous chapter',
              onPressed: _ref.previousChapter == null || _loading ? null : () => _go(_ref.previousChapter),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(_title ?? _ref.label, style: context.text.titleMedium, textAlign: TextAlign.center),
                  if (_abbr != null) Text(_abbr!, style: context.text.labelSmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Next chapter',
              onPressed: _ref.nextChapter == null || _loading ? null : () => _go(_ref.nextChapter),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.text_decrease_rounded, size: 18),
            Expanded(
              child: Slider(min: 14, max: 26, divisions: 6, value: _size, onChanged: (v) => setState(() => _size = v)),
            ),
            const Icon(Icons.text_increase_rounded, size: 18),
          ],
        ),
        const SizedBox(height: Space.s),
        if (_loading)
          const _ChapterSkeleton()
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(_error!, style: TextStyle(color: AppColors.danger)),
          )
        else
          SelectionArea(child: _scripture(context, _text ?? '', size: _size)),
        const SizedBox(height: Space.xl),
        if (!_loading && _error == null)
          Row(
            children: [
              if (_ref.previousChapter != null)
                OutlinedButton.icon(
                  onPressed: () => _go(_ref.previousChapter),
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: Text(_ref.previousChapter!.label),
                ),
              const Spacer(),
              if (_ref.nextChapter != null)
                FilledButton.icon(onPressed: () => _go(_ref.nextChapter), icon: const Icon(Icons.chevron_right_rounded), label: Text(_ref.nextChapter!.label)),
            ],
          ),
      ],
    );
  }
}

/// One passage in several translations: tap a version to read it, or show
/// them all.
class _CompareCard extends StatefulWidget {
  const _CompareCard({required this.data, required this.translations});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> translations;

  @override
  State<_CompareCard> createState() => _CompareCardState();
}

class _CompareCardState extends State<_CompareCard> {
  int? _at = 0;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final ts = widget.translations;
    final shown = _at == null ? ts : [ts[_at!.clamp(0, ts.length - 1)]];
    Widget pill(String label, bool on, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on ? _gold : _gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _gold.withValues(alpha: on ? 1 : 0.35)),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: on ? Colors.black : _goldText)),
        ),
      ),
    );
    return _Frame(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Kicker(icon: Icons.compare_arrows_rounded, text: '${ts.length} TRANSLATIONS'),
            const SizedBox(height: Space.m),
            Text('${data['reference']}', style: TextStyle(fontFamily: 'serif', fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: Space.m),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (i, t) in ts.indexed) pill('${t['abbreviation']}', _at == i, () => setState(() => _at = i)),
                  pill('ALL', _at == null, () => setState(() => _at = null)),
                ],
              ),
            ),
            for (final t in shown) ...[
              const SizedBox(height: Space.m),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  key: ValueKey('${t['abbreviation']}${_at == null}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_at == null) ...[_Badge('${t['abbreviation']}'), const SizedBox(width: Space.s)],
                        Expanded(child: Text('${t['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3))),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Copy',
                          icon: Icon(Icons.copy_rounded, size: 17, color: AppColors.text2),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: '${t['text']}\n— ${data['reference']} (${t['abbreviation']})'));
                            showSnack(context, 'Copied ${t['abbreviation']}');
                          },
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.only(left: Space.m),
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: _gold.withValues(alpha: 0.6), width: 2))),
                      child: _scripture(context, '${t['text']}', size: _at == null ? 15.5 : 17.5),
                    ),
                  ],
                ),
              ),
            ],
            if ((data['failed'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: Space.m),
              Text('Not found: ${(data['failed'] as List).join('; ')}', style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
            ],
          ],
        ),
      ),
    );
  }
}


class _VersionsCard extends ConsumerWidget {
  const _VersionsCard({required this.data, required this.versions});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> versions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(bibleSettingsProvider).versionId;
    return _Frame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
            child: Row(
              children: [
                const Icon(Icons.translate_rounded, size: 16, color: _gold),
                const SizedBox(width: Space.s),
                Expanded(child: Text('BIBLE VERSIONS · ${'${data['language']}'.toUpperCase()} · ${data['count']}', style: context.text.labelSmall)),
              ],
            ),
          ),
          for (final v in versions.take(12))
            ListTile(
              dense: true,
              titleAlignment: ListTileTitleAlignment.center,
              leading: SizedBox(width: 56, child: Center(child: _Badge('${v['abbreviation']}'))),
              title: Text('${v['local_title'] ?? v['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${v['books']} books · ${v['language']}${v['licensed'] == false ? ' · needs license' : ''}',
                style: context.text.bodySmall?.copyWith(color: v['licensed'] == false ? AppColors.warning : null),
              ),
              trailing: v['licensed'] == false
                  ? Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.text3)
                  : v['version_id'] == current
                  ? const Icon(Icons.check_circle_rounded, color: _gold, size: 20)
                  : TextButton(
                      onPressed: () async {
                        await ref.read(bibleSettingsProvider.notifier).setVersion((v['version_id'] as num).toInt(), '${v['abbreviation']}');
                        if (context.mounted) showSnack(context, '${v['abbreviation']} is your default version');
                      },
                      child: const Text('Use'),
                    ),
              onTap: () => showAppSheet<void>(
                context,
                initialSize: 0.5,
                builder: (context, scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
                  children: [
                    Text('${v['title']}', style: context.text.titleLarge),
                    Text('${v['abbreviation']} · ${v['language']} · id ${v['version_id']}', style: context.text.bodySmall),
                    if (v['info'] != null) ...[const SizedBox(height: Space.m), Text('${v['info']}')],
                    if (v['copyright'] != null) ...[
                      const SizedBox(height: Space.m),
                      Text('${v['copyright']}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                    ],
                    if (v['publisher_url'] != null) ...[
                      const SizedBox(height: Space.m),
                      OutlinedButton.icon(
                        onPressed: () => _open(v['publisher_url'] as String?),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Publisher'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (versions.length > 12)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              child: Text('+${versions.length - 12} more', style: context.text.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _BooksCard extends StatelessWidget {
  const _BooksCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final version = _map(data['version']);
    List<Map<String, dynamic>> list(String k) => [
      for (final x in (data[k] as List? ?? const []))
        if (x is Map) Map<String, dynamic>.from(x),
    ];
    Widget section(String title, List<Map<String, dynamic>> books) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.m, bottom: Space.s),
          child: Text('$title · ${books.length}', style: context.text.labelSmall),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final b in books)
              ActionChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                label: Text('${b['name']} · ${b['chapters']}', style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  final r = BibleRef.parse('${b['code']}.1');
                  if (r != null) _openReader(context, r, '${version['version_id'] ?? ''}');
                },
              ),
          ],
        ),
      ],
    );
    return _Frame(
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.library_books_outlined, size: 16, color: _gold),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text('Books · ${version['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                ),
                _Badge('${version['abbreviation'] ?? ''}'),
              ],
            ),
            if (list('old_testament').isNotEmpty) section('OLD TESTAMENT', list('old_testament')),
            if (list('new_testament').isNotEmpty) section('NEW TESTAMENT', list('new_testament')),
            if (list('other').isNotEmpty) section('OTHER BOOKS', list('other')),
            const SizedBox(height: Space.xs),
            Text('Tap a book to start reading.', style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// The reader while a chapter loads: a heading and paragraphs of text
/// lines, shimmering.
class _ChapterSkeleton extends StatelessWidget {
  const _ChapterSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Skeleton(width: 160, height: 14, radius: 6),
        const SizedBox(height: Space.l),
        for (var p = 0; p < 4; p++) ...[
          for (var l = 0; l < 4; l++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              // The last line of a paragraph is shorter, like real text.
              child: FractionallySizedBox(widthFactor: l == 3 ? 0.55 + (p % 2) * 0.2 : 1, alignment: Alignment.centerLeft, child: const Skeleton(height: 12, radius: 5)),
            ),
          const SizedBox(height: Space.m),
        ],
      ],
    ),
  );
}
