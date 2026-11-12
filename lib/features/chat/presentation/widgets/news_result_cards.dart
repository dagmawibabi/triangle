import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../domain/chat_models.dart';

/// Cards for Reddit and Hacker News: post lists, a post with its comments, a
/// subreddit and a Hacker News user. Null for other tools.
Widget? newsResultFor(ToolPart part, Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'reddit_posts' when list(j['posts']).isNotEmpty => _RedditList(
      title: 'r/${j['subreddit']} · ${j['sort'] ?? 'hot'}',
      posts: list(j['posts']),
      hidden: (j['hidden_nsfw'] as num?)?.toInt() ?? 0,
    ),
    'reddit_search' when list(j['posts']).isNotEmpty => _RedditList(
      title: 'Reddit · "${j['query']}"${j['subreddit'] == null ? '' : ' in r/${j['subreddit']}'}',
      posts: list(j['posts']),
    ),
    'reddit_post' when j['post'] is Map => _Thread(
      post: Map<String, dynamic>.from(j['post'] as Map),
      comments: list(j['comments']),
      reddit: true,
    ),
    'reddit_subreddit' when j['name'] != null => _SubredditCard(sub: j),
    'hn_stories' when list(j['stories']).isNotEmpty => _HnList(title: 'Hacker News · ${_hnListName('${j['list']}')}', stories: list(j['stories'])),
    'hn_search' when list(j['hits']).isNotEmpty => _HnList(
      title: 'Hacker News · "${j['query']}"${j['total'] == null ? '' : ' · ${NumberFormat.compact().format(j['total'])} results'}',
      stories: list(j['hits']),
    ),
    'hn_item' when j['item'] is Map => _HnThreadCard(
      post: Map<String, dynamic>.from(j['item'] as Map),
      comments: list(j['comments']),
    ),
    'hn_user' when j['username'] != null => _HnUserCard(user: j),
    _ => null,
  };
}

const _reddit = Color(0xFFFF4500);
const _hn = Color(0xFFFF6600);

String _hnListName(String l) => switch (l) {
  'top' => 'Top',
  'new' => 'New',
  'best' => 'Best',
  'ask' => 'Ask HN',
  'show' => 'Show HN',
  'job' => 'Jobs',
  _ => l,
};

String _ago(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}');
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 30) return '${d.inDays}d';
  if (d.inDays < 365) return '${d.inDays ~/ 30}mo';
  return '${d.inDays ~/ 365}y';
}

String _n(Object? v) => v is num ? NumberFormat.compact().format(v) : '—';

Future<void> _open(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _Panel extends StatelessWidget {
  const _Panel({required this.color, required this.icon, required this.title, required this.children, this.footer});
  final Color color;
  final IconData icon;
  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: Space.s),
              Expanded(child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
            ],
          ),
        ),
        ...children,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Text(footer!, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
          ),
        const SizedBox(height: Space.xs),
      ],
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta(this.parts);
  final List<(IconData?, String)> parts;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.s,
    runSpacing: 2,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final (icon, text) in parts)
        if (text.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 13, color: AppColors.text3), const SizedBox(width: 3)],
              Text(text, style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontSize: 12)),
            ],
          ),
    ],
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.url, {this.size = 56});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.s),
      child: NetImage(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: const SizedBox.shrink(),
      ),
    );
  }
}

// ---- Reddit -------------------------------------------------------------------------

class _RedditList extends StatelessWidget {
  const _RedditList({required this.title, required this.posts, this.hidden = 0});
  final String title;
  final List<Map<String, dynamic>> posts;
  final int hidden;

  @override
  Widget build(BuildContext context) => _Panel(
    color: _reddit,
    icon: Icons.reddit_rounded,
    title: title,
    footer: hidden > 0 ? '$hidden NSFW post${hidden == 1 ? '' : 's'} hidden' : null,
    children: [
      for (final (i, p) in posts.indexed) ...[
        if (i > 0) Divider(height: 1, indent: Space.m, endIndent: Space.m, color: AppColors.line),
        _RedditRow(post: p),
      ],
    ],
  );
}

class _RedditRow extends StatelessWidget {
  const _RedditRow({required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final p = post;
    return InkWell(
      onTap: () => _showRedditPost(context, p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  const Icon(Icons.arrow_upward_rounded, size: 16, color: _reddit),
                  Text(_n(p['score']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p['flair'] != null || p['pinned'] == true || p['nsfw'] == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Wrap(
                        spacing: 4,
                        children: [
                          if (p['pinned'] == true) const _Tag('Pinned', Color(0xFF2E7D32)),
                          if (p['nsfw'] == true) const _Tag('NSFW', Color(0xFFC62828)),
                          if (p['flair'] != null) _Tag('${p['flair']}', AppColors.text2),
                        ],
                      ),
                    ),
                  Text('${p['title']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25)),
                  const SizedBox(height: 3),
                  _Meta([
                    (null, 'r/${p['subreddit']}'),
                    (null, 'u/${p['author']}'),
                    (Icons.schedule_rounded, _ago(p['created'])),
                    (Icons.mode_comment_outlined, _n(p['comments'])),
                    if (p['domain'] != null && !'${p['domain']}'.startsWith('self.')) (Icons.link_rounded, '${p['domain']}'),
                  ]),
                ],
              ),
            ),
            if (p['image'] != null && p['nsfw'] != true) ...[
              const SizedBox(width: Space.s),
              Stack(
                alignment: Alignment.center,
                children: [
                  _Thumb(p['image'] as String?),
                  if (p['video'] == true) const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 22),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
  );
}

void _showRedditPost(BuildContext context, Map<String, dynamic> p) => showAppSheet<void>(
  context,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: [
      _Meta([(null, 'r/${p['subreddit']}'), (null, 'u/${p['author']}'), (Icons.schedule_rounded, _ago(p['created']))]),
      const SizedBox(height: Space.s),
      Text('${p['title']}', style: context.text.titleLarge),
      const SizedBox(height: Space.s),
      _Meta([
        (Icons.arrow_upward_rounded, '${_n(p['score'])} points'),
        if (p['upvote_ratio'] is num) (Icons.thumb_up_alt_outlined, '${((p['upvote_ratio'] as num) * 100).round()}% upvoted'),
        (Icons.mode_comment_outlined, '${_n(p['comments'])} comments'),
        if (p['gallery_count'] != null) (Icons.photo_library_outlined, '${p['gallery_count']} pictures'),
      ]),
      if (p['image'] != null && p['nsfw'] != true) ...[
        const SizedBox(height: Space.m),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.m),
          child: NetImage('${p['image']}', fit: BoxFit.cover, errorWidget: const SizedBox.shrink()),
        ),
      ],
      if (p['text'] != null) ...[
        const SizedBox(height: Space.m),
        SelectableText('${p['text']}', style: context.text.bodyMedium?.copyWith(height: 1.45)),
      ],
      const SizedBox(height: Space.l),
      Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          FilledButton.icon(onPressed: () => _open(p['permalink'] as String?), icon: const Icon(Icons.reddit_rounded, size: 18), label: const Text('Open on Reddit')),
          if (p['url'] != null)
            OutlinedButton.icon(onPressed: () => _open(p['url'] as String?), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text('${p['domain'] ?? 'Link'}')),
        ],
      ),
    ],
  ),
);

class _SubredditCard extends StatelessWidget {
  const _SubredditCard({required this.sub});
  final Map<String, dynamic> sub;

  @override
  Widget build(BuildContext context) {
    final s = sub;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(s['url'] as String?),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 64,
              color: _reddit.withValues(alpha: 0.18),
              child: s['banner'] == null ? null : NetImage('${s['banner']}', fit: BoxFit.cover, errorWidget: const SizedBox.shrink()),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: _reddit,
                        foregroundImage: s['icon'] == null ? null : NetworkImage('${s['icon']}'),
                        child: const Icon(Icons.reddit_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('r/${s['name']}', style: context.text.titleMedium),
                            if (s['title'] != null) Text('${s['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      if (s['nsfw'] == true) const _Tag('NSFW', Color(0xFFC62828)),
                    ],
                  ),
                  const SizedBox(height: Space.s),
                  _Meta([
                    (Icons.group_outlined, '${_n(s['members'])} members'),
                    if (s['online'] != null) (Icons.circle, '${_n(s['online'])} online'),
                    if (s['created'] != null) (Icons.cake_outlined, 'since ${'${s['created']}'.substring(0, 4)}'),
                  ]),
                  if (s['description'] != null) ...[
                    const SizedBox(height: Space.s),
                    Text('${s['description']}', maxLines: 5, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
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

// ---- Hacker News --------------------------------------------------------------------

// ---- Hacker News ------------------------------------------------------------------

/// "Ask HN: …" → ("Ask HN", "…"): the kind of post as a tag, and the rest.
(String?, String) _hnKind(String title) {
  final m = RegExp(r'^(Ask HN|Show HN|Launch HN|Tell HN)\s*:\s*', caseSensitive: false).firstMatch(title);
  return m == null ? (null, title) : (m[1], title.substring(m.end));
}

/// HN's HTML comment text as plain paragraphs.
String _hnText(Object? html) {
  final s = '${html ?? ''}';
  if (s.isEmpty) return '';
  final t = html_parser.parse(s.replaceAll(RegExp(r'<p>', caseSensitive: false), '\n\n')).documentElement?.text ?? s;
  return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

class _HnMark extends StatelessWidget {
  const _HnMark({this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: _hn, borderRadius: BorderRadius.circular(size * 0.22)),
    child: Text('Y', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.62, height: 1)),
  );
}

class _HnTag extends StatelessWidget {
  const _HnTag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: _hn.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: const TextStyle(color: _hn, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

/// Points, comments, age and author in one quiet line.
class _HnStats extends StatelessWidget {
  const _HnStats({required this.s, this.big = false});
  final Map<String, dynamic> s;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final style = (big ? context.text.bodySmall : context.text.labelSmall)?.copyWith(color: AppColors.text3);
    Widget item(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(right: Space.m),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: big ? 16 : 14, color: color ?? AppColors.text3),
          const SizedBox(width: 3),
          Text(text, style: style?.copyWith(color: color, fontWeight: color == null ? null : FontWeight.w700)),
        ],
      ),
    );
    final points = s['points'] ?? s['score'];
    return Wrap(
      runSpacing: 2,
      children: [
        if (points != null) item(Icons.arrow_upward_rounded, _n(points), color: _hn),
        if (s['comments'] != null) item(Icons.mode_comment_outlined, _n(s['comments'])),
        if (s['created'] != null) item(Icons.schedule_rounded, _ago(s['created'])),
        if (s['author'] != null) item(Icons.person_outline_rounded, '${s['author']}'),
      ],
    );
  }
}

/// One story in a list: its rank, title (with an Ask/Show tag), site and
/// stats. Opens the story with its comments.
class _HnRow extends StatelessWidget {
  const _HnRow({required this.s, required this.rank});
  final Map<String, dynamic> s;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final (kind, title) = _hnKind('${s['title'] ?? s['text'] ?? ''}');
    final site = '${s['site'] ?? ''}';
    return InkWell(
      onTap: () => showHnStory(context, s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: rank <= 3 ? _hn.withValues(alpha: 0.16) : AppColors.surface2, borderRadius: BorderRadius.circular(8)),
              child: Text('$rank', style: TextStyle(color: rank <= 3 ? _hn : AppColors.text2, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (kind != null) ...[_HnTag(kind), const SizedBox(height: 4)],
                  Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                  if (site.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        NetImage('https://www.google.com/s2/favicons?domain=$site&sz=64', width: 14, height: 14, radius: 3, placeholder: Icons.language_rounded),
                        const SizedBox(width: 5),
                        Flexible(child: Text(site, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text2))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 5),
                  _HnStats(s: s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HnList extends StatelessWidget {
  const _HnList({required this.title, required this.stories});
  final String title;
  final List<Map<String, dynamic>> stories;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
          child: Row(
            children: [
              const _HnMark(),
              const SizedBox(width: Space.s + 2),
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            ],
          ),
        ),
        for (final (i, s) in stories.indexed) ...[
          if (i > 0) Divider(height: 1, indent: Space.m + 28 + Space.m, endIndent: Space.m, color: AppColors.line),
          _HnRow(s: s, rank: (s['rank'] as num?)?.toInt() ?? i + 1),
        ],
      ],
    ),
  );
}

/// A story's sheet: its header and link, its text, and the whole comment
/// tree from HN (through Algolia's HN API), threads collapsible.
void showHnStory(BuildContext context, Map<String, dynamic> s) => showAppSheet<void>(
  context,
  initialSize: 0.92,
  builder: (context, scroll) => _HnStorySheet(story: s, scroll: scroll),
);

class _HnStorySheet extends StatefulWidget {
  const _HnStorySheet({required this.story, required this.scroll});
  final Map<String, dynamic> story;
  final ScrollController scroll;

  @override
  State<_HnStorySheet> createState() => _HnStorySheetState();
}

class _HnStorySheetState extends State<_HnStorySheet> {
  Map<String, dynamic>? _item;
  String? _error;
  final _collapsed = <Object>{};

  Object? get _id => widget.story['id'] ?? Uri.tryParse('${widget.story['hn_url'] ?? ''}')?.queryParameters['id'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _id;
    if (id == null) {
      setState(() => _error = 'This story has no id to load comments for.');
      return;
    }
    try {
      final r = await http.get(Uri.https('hn.algolia.com', '/api/v1/items/$id')).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('HN answered ${r.statusCode}');
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (mounted) setState(() => _item = Map<String, dynamic>.from(j as Map));
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t load the comments. Check the connection and try again.');
    }
  }

  /// The tree as rows, skipping the replies under collapsed comments.
  List<(Map<String, dynamic>, int)> _rows() {
    final out = <(Map<String, dynamic>, int)>[];
    void walk(List kids, int depth) {
      for (final k in kids.whereType<Map>()) {
        final c = Map<String, dynamic>.from(k);
        if (c['text'] == null && (c['children'] as List? ?? const []).isEmpty) continue;
        out.add((c, depth));
        if (!_collapsed.contains(c['id'])) walk(c['children'] as List? ?? const [], depth + 1);
      }
    }

    walk(_item?['children'] as List? ?? const [], 0);
    return out;
  }

  int _count(Map c) => (c['children'] as List? ?? const []).whereType<Map>().fold(0, (n, k) => n + 1 + _count(k));

  @override
  Widget build(BuildContext context) {
    final s = {...widget.story};
    final item = _item;
    if (item != null) {
      s['title'] ??= item['title'];
      s['url'] ??= item['url'];
      s['author'] ??= item['author'];
      s['points'] ??= item['points'];
    }
    final (kind, title) = _hnKind('${s['title'] ?? 'Hacker News'}');
    final url = s['url'] as String?;
    final site = '${s['site'] ?? (url == null ? '' : Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '')}';
    final text = item == null ? '${s['text'] ?? ''}' : _hnText(item['text']);
    final rows = _rows();
    final total = item == null ? (s['comments'] as num?)?.toInt() : _count(item);
    return ListView.builder(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      itemCount: 1 + (item == null ? 1 : rows.length + (rows.isEmpty ? 1 : 0)),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _HnMark(size: 18),
                    const SizedBox(width: Space.s),
                    if (kind != null) ...[_HnTag(kind), const SizedBox(width: Space.s)],
                    Text('Hacker News', style: context.text.labelMedium?.copyWith(color: AppColors.text2)),
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                const SizedBox(height: Space.s),
                _HnStats(s: {...s, 'comments': total ?? s['comments']}, big: true),
                if (url != null) ...[
                  const SizedBox(height: Space.m),
                  Material(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(Radii.l),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.l),
                      onTap: () => _open(url),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.m),
                        child: Row(
                          children: [
                            NetImage('https://www.google.com/s2/favicons?domain=$site&sz=128', width: 32, height: 32, radius: 8, placeholder: Icons.language_rounded),
                            const SizedBox(width: Space.m),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(site, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                                ],
                              ),
                            ),
                            Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.text2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (text.isNotEmpty) ...[
                  const SizedBox(height: Space.m),
                  SelectableText(text, style: context.text.bodyMedium?.copyWith(height: 1.55)),
                ],
                const SizedBox(height: Space.m),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _open('https://news.ycombinator.com/item?id=${_id ?? ''}'),
                      icon: const Icon(Icons.forum_outlined, size: 17),
                      label: const Text('Open on HN'),
                    ),
                    const Spacer(),
                    if (item != null && rows.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() {
                          final tops = [for (final k in (item['children'] as List? ?? const []).whereType<Map>()) k['id'] as Object];
                          if (tops.every(_collapsed.contains)) {
                            _collapsed.clear();
                          } else {
                            _collapsed.addAll(tops);
                          }
                        }),
                        child: Text((item['children'] as List? ?? const []).whereType<Map>().every((k) => _collapsed.contains(k['id'])) ? 'Expand all' : 'Collapse all'),
                      ),
                  ],
                ),
                const SizedBox(height: Space.s),
                Divider(height: 1, color: AppColors.line),
                Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Text('${total ?? ''} COMMENTS'.trim(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
        }
        if (item == null) {
          return _error != null
              ? Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: Column(children: [Text(_error!, style: context.text.bodySmall), TextButton(onPressed: () => setState(() {
                    _error = null;
                    _load();
                  }), child: const Text('Try again'))]),
                )
              : const _CommentSkeletons();
        }
        if (rows.isEmpty) return Padding(padding: const EdgeInsets.all(Space.l), child: Text('No comments yet.', style: context.text.bodySmall));
        final (c, depth) = rows[i - 1];
        final replies = _count(c);
        return _HnComment(
          c: c,
          depth: depth,
          op: c['author'] != null && c['author'] == s['author'],
          collapsed: _collapsed.contains(c['id']),
          replies: replies,
          onToggle: replies == 0 && !_collapsed.contains(c['id'])
              ? null
              : () => setState(() => _collapsed.contains(c['id']) ? _collapsed.remove(c['id']) : _collapsed.add(c['id'] as Object)),
        );
      },
    );
  }
}

const _threadColors = [_hn, Color(0xFF60A5FA), Color(0xFF34D399), Color(0xFFA78BFA), Color(0xFFF472B6), Color(0xFFFACC15)];

class _HnComment extends StatelessWidget {
  const _HnComment({required this.c, required this.depth, required this.op, required this.collapsed, required this.replies, this.onToggle});
  final Map<String, dynamic> c;
  final int depth;
  final bool op;
  final bool collapsed;
  final int replies;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final author = '${c['author'] ?? '[deleted]'}';
    final line = _threadColors[depth % _threadColors.length];
    final created = c['created_at'] ?? c['created'];
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.l + (depth.clamp(0, 6) * 12.0), depth == 0 ? Space.m : Space.s, Space.l, 0),
      child: Container(
        padding: EdgeInsets.only(left: depth == 0 ? 0 : Space.m),
        decoration: depth == 0 ? null : BoxDecoration(border: Border(left: BorderSide(color: line.withValues(alpha: 0.55), width: 2))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: HSLColor.fromAHSL(1, (author.hashCode % 360).abs().toDouble(), 0.45, 0.42).toColor(),
                    child: Text(author.isEmpty ? '?' : author[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: op ? _hn : AppColors.text))),
                  if (op) ...[const SizedBox(width: 4), const _HnTag('OP')],
                  Text('  ·  ${_ago(created)}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                  const Spacer(),
                  if (onToggle != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (collapsed && replies > 0) Text('+$replies', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                        Icon(collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded, size: 18, color: AppColors.text3),
                      ],
                    ),
                ],
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(height: 4),
              SelectableText(_hnText(c['text']).isEmpty ? '[deleted]' : _hnText(c['text']), style: context.text.bodyMedium?.copyWith(height: 1.45, fontSize: 14)),
            ],
            const SizedBox(height: Space.xs),
          ],
        ),
      ),
    );
  }
}

class _CommentSkeletons extends StatelessWidget {
  const _CommentSkeletons();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
    child: Column(
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: EdgeInsets.only(left: i.isOdd ? 24 : 0, bottom: Space.l),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Skeleton(width: 20, height: 20, shape: BoxShape.circle), SizedBox(width: 8), Skeleton(width: 90, height: 10, radius: 4)]),
                SizedBox(height: 8),
                Skeleton(height: 10, radius: 4),
                SizedBox(height: 6),
                Skeleton(height: 10, radius: 4),
                SizedBox(height: 6),
                FractionallySizedBox(widthFactor: 0.6, child: Skeleton(height: 10, radius: 4)),
              ],
            ),
          ),
      ],
    ),
  );
}

/// An HN item from the hn_item tool: the story's header, its first
/// comments, and the full thread a tap away.
class _HnThreadCard extends StatelessWidget {
  const _HnThreadCard({required this.post, required this.comments});
  final Map<String, dynamic> post;
  final List<Map<String, dynamic>> comments;

  @override
  Widget build(BuildContext context) {
    final (kind, title) = _hnKind('${post['title'] ?? ''}');
    final site = '${post['site'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => showHnStory(context, post),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _HnMark(size: 18),
                    const SizedBox(width: Space.s),
                    if (kind != null) ...[_HnTag(kind), const SizedBox(width: Space.s)],
                    if (site.isNotEmpty) ...[
                      NetImage('https://www.google.com/s2/favicons?domain=$site&sz=64', width: 14, height: 14, radius: 3, placeholder: Icons.language_rounded),
                      const SizedBox(width: 5),
                      Flexible(child: Text(site, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text2))),
                    ],
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: Space.s),
                _HnStats(s: post),
                if (post['text'] != null) ...[
                  const SizedBox(height: Space.s),
                  Text('${post['text']}', maxLines: 5, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45)),
                ],
                if (comments.isNotEmpty) ...[
                  const SizedBox(height: Space.m),
                  for (final c in comments.take(3))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: Space.s),
                      padding: const EdgeInsets.all(Space.m),
                      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c['author'] ?? '[deleted]'}  ·  ${_ago(c['created'])}', style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text('${c['text'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text, height: 1.4)),
                        ],
                      ),
                    ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => showHnStory(context, post),
                    icon: const Icon(Icons.forum_outlined, size: 17),
                    label: Text(post['comments'] == null ? 'Read the thread' : 'Read all ${_n(post['comments'])} comments'),
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

class _HnUserCard extends StatelessWidget {
  const _HnUserCard({required this.user});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final subs = [for (final x in (u['submissions'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    return _Panel(
      color: _hn,
      icon: Icons.person_outline_rounded,
      title: 'Hacker News user',
      children: [
        InkWell(
          onTap: () => _open(u['url'] as String?),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 20, backgroundColor: _hn, child: Text('${u['username']}'.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${u['username']}', style: context.text.titleMedium),
                          Text('${_n(u['karma'])} karma${u['created'] == null ? '' : ' · joined ${'${u['created']}'.substring(0, 4)}'}', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                if (u['about'] != null) ...[
                  const SizedBox(height: Space.s),
                  Text('${u['about']}', maxLines: 6, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        if (subs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xs),
            child: Text('LATEST', style: context.text.labelSmall),
          ),
          for (final s in subs)
            ListTile(
              dense: true,
              leading: Icon(s['type'] == 'comment' ? Icons.mode_comment_outlined : Icons.article_outlined, size: 18),
              title: Text('${s['title'] ?? s['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(_ago(s['created']), style: context.text.bodySmall),
              onTap: () => _open('https://news.ycombinator.com/item?id=${s['id']}'),
            ),
        ],
      ],
    );
  }
}

// ---- threads (both) -----------------------------------------------------------------

/// A post (Reddit) or story (Hacker News) and its comments, with replies
/// folded under each.
class _Thread extends StatelessWidget {
  const _Thread({required this.post, required this.comments, required this.reddit});
  final Map<String, dynamic> post;
  final List<Map<String, dynamic>> comments;
  final bool reddit;

  @override
  Widget build(BuildContext context) {
    final p = post;
    final color = reddit ? _reddit : _hn;
    return _Panel(
      color: color,
      icon: reddit ? Icons.reddit_rounded : Icons.whatshot_outlined,
      title: reddit ? 'r/${p['subreddit']}' : 'Hacker News${p['site'] == null ? '' : ' · ${p['site']}'}',
      children: [
        InkWell(
          onTap: () => reddit ? _showRedditPost(context, p) : showHnStory(context, p),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['title'] ?? ''}', style: context.text.titleMedium),
                const SizedBox(height: 4),
                _Meta([
                  (Icons.arrow_upward_rounded, _n(p['score'] ?? p['points'])),
                  (Icons.person_outline_rounded, '${p['author'] ?? ''}'),
                  (Icons.schedule_rounded, _ago(p['created'])),
                  (Icons.mode_comment_outlined, _n(p['comments'])),
                ]),
                if (reddit && p['image'] != null && p['nsfw'] != true) ...[
                  const SizedBox(height: Space.s),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.m),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: NetImage('${p['image']}', width: double.infinity, fit: BoxFit.cover, errorWidget: const SizedBox.shrink()),
                    ),
                  ),
                ],
                if (p['text'] != null) ...[
                  const SizedBox(height: Space.s),
                  Text('${p['text']}', maxLines: 8, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(height: 1.4)),
                ],
              ],
            ),
          ),
        ),
        if (comments.isNotEmpty) ...[
          Divider(height: 1, color: AppColors.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
            child: Text('TOP COMMENTS', style: context.text.labelSmall),
          ),
          for (final c in comments.take(6)) _Comment(comment: c, accent: color),
          if (comments.length > 6)
            TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (context, scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.x4),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s),
                      child: Text('${p['title'] ?? ''}', style: context.text.titleMedium),
                    ),
                    for (final c in comments) _Comment(comment: c, accent: color, expanded: true),
                  ],
                ),
              ),
              child: Text('All ${comments.length} comments'),
            ),
        ],
      ],
    );
  }
}

class _Comment extends StatefulWidget {
  const _Comment({required this.comment, required this.accent, this.depth = 0, this.expanded = false});
  final Map<String, dynamic> comment;
  final Color accent;
  final int depth;
  final bool expanded;

  @override
  State<_Comment> createState() => _CommentState();
}

class _CommentState extends State<_Comment> {
  late bool _open = widget.expanded;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final replies = [for (final r in (c['replies'] as List? ?? const [])) if (r is Map) Map<String, dynamic>.from(r)];
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.m + widget.depth * 12.0, Space.s, Space.m, 0),
      child: Container(
        padding: EdgeInsets.only(left: widget.depth == 0 ? 0 : Space.s),
        decoration: widget.depth == 0 ? null : BoxDecoration(border: Border(left: BorderSide(color: widget.accent.withValues(alpha: 0.4), width: 2))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${c['author'] ?? '[deleted]'}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: c['op'] == true ? widget.accent : null)),
                if (c['op'] == true) Text(' · OP', style: TextStyle(fontSize: 11, color: widget.accent)),
                const SizedBox(width: Space.s),
                Expanded(
                  child: _Meta([
                    if (c['score'] != null) (Icons.arrow_upward_rounded, _n(c['score'])),
                    (null, _ago(c['created'])),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 2),
            SelectableText('${c['text'] ?? ''}', style: context.text.bodyMedium?.copyWith(height: 1.4, fontSize: 13.5)),
            if (replies.isNotEmpty)
              if (_open)
                for (final r in replies) _Comment(comment: r, accent: widget.accent, depth: widget.depth + 1, expanded: true)
              else
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  onPressed: () => setState(() => _open = true),
                  child: Text('${replies.length} repl${replies.length == 1 ? 'y' : 'ies'}', style: TextStyle(color: widget.accent, fontSize: 12.5)),
                ),
            if (widget.depth == 0) const SizedBox(height: Space.xs),
          ],
        ),
      ),
    );
  }
}
