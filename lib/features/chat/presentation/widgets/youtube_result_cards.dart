import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/net_image.dart';
import '../../domain/chat_models.dart';
import 'rich_results.dart' show showVideo;

/// Cards for the YouTube API tools: comments, trending, live streams, a
/// channel's videos, channel comparisons, new uploads, and channel or
/// playlist search results.
Widget? youtubeResultFor(ToolPart part, Map<String, dynamic> j) {
  if (j['error'] != null) return null;
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'youtube_comments' => _CommentsCard(data: j, comments: list(j['comments'])),
    'youtube_trending' => _VideoList(
      icon: Icons.trending_up_rounded,
      title: 'Trending in ${j['region']}${j['category'] != null && j['category'] != 'all' ? ' · ${j['category']}' : ''}',
      subtitle: j['note'] as String? ?? 'Most popular on YouTube now',
      videos: list(j['videos']),
      ranked: true,
    ),
    'youtube_live' => _VideoList(
      icon: j['kind'] == 'upcoming' ? Icons.event_outlined : Icons.sensors_rounded,
      title: j['kind'] == 'upcoming' ? 'Upcoming streams' : 'Live now',
      subtitle: '${j['query'] ?? ''}'.isEmpty ? 'On YouTube' : '"${j['query']}"',
      videos: list(j['videos']),
    ),
    'youtube_channel_videos' => _ChannelVideos(data: j, videos: list(j['videos'])),
    'youtube_compare_channels' => _CompareCard(channels: list(j['channels']).where((c) => c['error'] == null).toList()),
    'youtube_new_uploads' => _VideoList(
      icon: Icons.fiber_new_outlined,
      title: list(j['videos']).isEmpty ? 'No new uploads' : '${list(j['videos']).length} new upload${list(j['videos']).length == 1 ? '' : 's'}',
      subtitle: 'From ${(j['checked'] as List? ?? const []).join(', ')} · last ${(j['since_hours'] as num?)?.round() ?? 24} h',
      videos: list(j['videos']),
    ),
    'youtube_search' when j['type'] == 'channel' || j['type'] == 'playlist' => _ResultList(type: '${j['type']}', query: '${j['query']}', results: list(j['results'])),
    _ => null,
  };
}

// ---- shared ---------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
  );
}

class _Head extends StatelessWidget {
  const _Head({required this.icon, required this.title, this.subtitle, this.avatar});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? avatar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
    child: Row(
      children: [
        if (avatar != null)
          ClipOval(child: NetImage(avatar, width: 34, height: 34, placeholder: Icons.person_rounded))
        else
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFFF0033), borderRadius: BorderRadius.circular(Radii.s + 2)),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        const SizedBox(width: Space.s + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ],
          ),
        ),
      ],
    ),
  );
}

String _n(Object? v) => v is num ? NumberFormat.compact().format(v) : '${v ?? ''}';

String _age(Object? date) {
  final d = DateTime.tryParse('${date ?? ''}');
  if (d == null) return '';
  final days = DateTime.now().difference(d).inDays;
  if (days < 1) return 'today';
  if (days < 7) return '$days d ago';
  if (days < 30) return '${days ~/ 7} wk ago';
  if (days < 365) return '${days ~/ 30} mo ago';
  return '${days ~/ 365} y ago';
}

String _startsIn(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  final diff = d.difference(DateTime.now());
  if (diff.isNegative) return 'starting';
  if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'in ${diff.inHours} h';
  return 'in ${diff.inDays} d';
}

void _play(BuildContext context, Map<String, dynamic> v) {
  final id = v['video_id'] as String?;
  if (id == null) return;
  showVideo(context, id, v);
}

/// One video: thumbnail with length or LIVE, title, channel and stats.
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.v, this.rank});
  final Map<String, dynamic> v;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final live = v['live'] == true;
    final upcoming = v['upcoming'] == true;
    return InkWell(
      onTap: () => _play(context, v),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(width: 26, child: Text('$rank', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: rank! <= 3 ? AppColors.text : AppColors.text3))),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.m),
              child: SizedBox(
                width: 124,
                height: 70,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(v['thumbnail'] as String?, fit: BoxFit.cover, placeholder: Icons.smart_display_outlined),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: live ? const Color(0xFFFF0033) : Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          live ? '● LIVE' : (upcoming ? 'SOON' : '${v['length'] ?? ''}'),
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${v['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (v['channel'] != null) '${v['channel']}',
                      if (live && v['watching'] != null) '${_n(v['watching'])} watching',
                      if (upcoming && v['starts'] != null) _startsIn(v['starts']),
                      if (!live && !upcoming && v['view_count'] != null) '${_n(v['view_count'])} views',
                      if (!live && !upcoming) _age(v['published']),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                  ),
                  if (v['like_count'] != null && !live)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.thumb_up_alt_outlined, size: 11, color: AppColors.text3),
                          const SizedBox(width: 3),
                          Text(_n(v['like_count']), style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 10.5)),
                          if (v['comment_count'] != null) ...[
                            const SizedBox(width: Space.s),
                            Icon(Icons.mode_comment_outlined, size: 11, color: AppColors.text3),
                            const SizedBox(width: 3),
                            Text(_n(v['comment_count']), style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 10.5)),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoList extends StatelessWidget {
  const _VideoList({required this.icon, required this.title, required this.subtitle, required this.videos, this.ranked = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> videos;
  final bool ranked;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      _Head(icon: icon, title: title, subtitle: subtitle),
      if (videos.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          child: Text('Nothing right now.', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
        ),
      for (final (i, v) in videos.take(6).indexed) _VideoTile(v: v, rank: ranked ? i + 1 : null),
      if (videos.length > 6)
        InkWell(
          onTap: () => showAppSheet<void>(
            context,
            builder: (context, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.only(bottom: Space.x4),
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s), child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                for (final (i, v) in videos.indexed) _VideoTile(v: v, rank: ranked ? i + 1 : null),
              ],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            padding: const EdgeInsets.all(Space.s + 2),
            child: Center(child: Text('All ${videos.length}', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
          ),
        )
      else
        const SizedBox(height: Space.s),
    ],
  );
}

// ---- comments ---------------------------------------------------------------------

class _CommentsCard extends StatelessWidget {
  const _CommentsCard({required this.data, required this.comments});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> comments;

  @override
  Widget build(BuildContext context) {
    void all() => showAppSheet<void>(
      context,
      initialSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Text('${data['title'] ?? 'Comments'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text('${_n(data['comment_count'])} comments · ${data['order'] == 'newest' ? 'newest first' : 'top first'}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          const SizedBox(height: Space.m),
          for (final c in comments) _Comment(c: c, replies: true),
        ],
      ),
    );
    return _Card(
      children: [
        InkWell(
          onTap: () => _play(context, data),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.s + 2),
                  child: NetImage(data['thumbnail'] as String?, width: 88, height: 50, fit: BoxFit.cover, placeholder: Icons.smart_display_outlined),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${data['title'] ?? 'Video'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                      Text('${data['channel'] ?? ''} · ${_n(data['comment_count'])} comments', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.line),
        const SizedBox(height: Space.xs),
        for (final c in comments.take(4)) Padding(padding: const EdgeInsets.symmetric(horizontal: Space.m), child: _Comment(c: c)),
        if (comments.isEmpty)
          Padding(padding: const EdgeInsets.all(Space.m), child: Text('No comments.', style: context.text.bodySmall?.copyWith(color: AppColors.text2))),
        InkWell(
          onTap: all,
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            padding: const EdgeInsets.all(Space.s + 2),
            child: Center(child: Text('Read all ${comments.length} with replies', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
          ),
        ),
      ],
    );
  }
}

class _Comment extends StatelessWidget {
  const _Comment({required this.c, this.replies = false, this.reply = false});
  final Map<String, dynamic> c;
  final bool replies;
  final bool reply;

  @override
  Widget build(BuildContext context) {
    final rs = [for (final r in (c['replies'] as List? ?? const [])) if (r is Map) Map<String, dynamic>.from(r)];
    return Padding(
      padding: EdgeInsets.only(left: reply ? 40 : 0, top: Space.s, bottom: Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(child: NetImage(c['avatar'] as String?, width: reply ? 24 : 30, height: reply ? 24 : 30, placeholder: Icons.person_rounded)),
              const SizedBox(width: Space.s + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c['author'] ?? ''}  ·  ${_age(c['published'])}${c['edited'] == true ? ' (edited)' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${c['text'] ?? ''}', maxLines: replies ? null : 3, overflow: replies ? null : TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(height: 1.4)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.thumb_up_alt_outlined, size: 12, color: AppColors.text3),
                        const SizedBox(width: 3),
                        Text(_n(c['likes']), style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                        if ((c['reply_count'] as num? ?? 0) > 0) ...[
                          const SizedBox(width: Space.m),
                          Icon(Icons.reply_rounded, size: 13, color: AppColors.text3),
                          const SizedBox(width: 3),
                          Text('${_n(c['reply_count'])} replies', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (replies) for (final r in rs) _Comment(c: r, reply: true),
        ],
      ),
    );
  }
}

// ---- channels ---------------------------------------------------------------------

class _ChannelVideos extends StatelessWidget {
  const _ChannelVideos({required this.data, required this.videos});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> videos;

  @override
  Widget build(BuildContext context) {
    final avg = (data['average_views'] as num?)?.toDouble() ?? 0;
    final top = videos.map((v) => (v['view_count'] as num?)?.toDouble() ?? 0).fold<double>(1, (m, v) => v > m ? v : m);
    return _Card(
      children: [
        _Head(
          icon: Icons.video_library_outlined,
          avatar: data['avatar'] as String?,
          title: '${data['channel']} · ${data['order'] == 'popular' ? 'most viewed' : 'latest'}',
          subtitle: [
            if (data['subscribers'] != null) '${data['subscribers']}',
            if (avg > 0) '${_n(avg)} avg views',
            if (data['uploads_every_days'] != null) 'uploads every ${data['uploads_every_days']} d',
          ].join(' · '),
        ),
        // Each video's views against the best one: a quick read of what landed.
        if (videos.length >= 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in videos.reversed)
                    Expanded(
                      child: Tooltip(
                        message: '${v['title']}\n${_n(v['view_count'])} views',
                        child: GestureDetector(
                          onTap: () => _play(context, v),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            height: 6 + 58 * (((v['view_count'] as num?)?.toDouble() ?? 0) / top),
                            decoration: BoxDecoration(
                              color: ((v['view_count'] as num?)?.toDouble() ?? 0) >= avg ? AppColors.text : AppColors.text3,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        for (final v in videos.take(5)) _VideoTile(v: v),
        if (videos.length > 5)
          InkWell(
            onTap: () => showAppSheet<void>(
              context,
              builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.only(bottom: Space.x4), children: [for (final v in videos) _VideoTile(v: v)]),
            ),
            child: Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              padding: const EdgeInsets.all(Space.s + 2),
              child: Center(child: Text('All ${videos.length} videos', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
            ),
          )
        else
          const SizedBox(height: Space.s),
      ],
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.channels});
  final List<Map<String, dynamic>> channels;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Subscribers', 'subscriber_count'),
      ('Total views', 'view_count'),
      ('Videos', 'video_count'),
      ('Avg views / video', 'average_views'),
    ];
    return _Card(
      children: [
        _Head(icon: Icons.compare_arrows_rounded, title: 'Channels compared', subtitle: channels.map((c) => c['channel']).join(' vs ')),
        SizedBox(
          height: 82,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            children: [
              for (final c in channels)
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse('${c['url']}'), mode: LaunchMode.externalApplication),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        ClipOval(child: NetImage(c['avatar'] as String?, width: 44, height: 44, placeholder: Icons.person_rounded)),
                        const SizedBox(height: 4),
                        Text('${c['channel']}', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.15)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final (label, key) in metrics) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 4),
            child: Text(label.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.7, fontWeight: FontWeight.w600)),
          ),
          () {
            final top = channels.map((c) => (c[key] as num?)?.toDouble() ?? 0).fold<double>(1, (m, v) => v > m ? v : m);
            return Column(
              children: [
                for (final c in channels)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(width: 82, child: Text('${c['channel']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final v = (c[key] as num?)?.toDouble() ?? 0;
                              final best = v == top && v > 0;
                              return Row(
                                children: [
                                  Container(
                                    width: (box.maxWidth - 52) * (v / top),
                                    height: 10,
                                    decoration: BoxDecoration(color: best ? AppColors.text : AppColors.text3, borderRadius: BorderRadius.circular(3)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(c[key] == null ? '–' : _n(c[key]), style: context.text.labelSmall?.copyWith(fontWeight: best ? FontWeight.w800 : FontWeight.w500, fontFeatures: tabularFigures)),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }(),
        ],
        const SizedBox(height: Space.m),
      ],
    );
  }
}

/// Channels or playlists from a search.
class _ResultList extends StatelessWidget {
  const _ResultList({required this.type, required this.query, required this.results});
  final String type;
  final String query;
  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      _Head(icon: type == 'channel' ? Icons.account_circle_outlined : Icons.playlist_play_rounded, title: '${type == 'channel' ? 'Channels' : 'Playlists'} for "$query"', subtitle: '${results.length} found'),
      for (final r in results)
        InkWell(
          onTap: () => launchUrl(Uri.parse('${r['url']}'), mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
            child: Row(
              children: [
                type == 'channel'
                    ? ClipOval(child: NetImage(r['thumbnail'] as String?, width: 44, height: 44, placeholder: Icons.person_rounded))
                    : ClipRRect(borderRadius: BorderRadius.circular(Radii.s + 2), child: NetImage(r['thumbnail'] as String?, width: 78, height: 44, fit: BoxFit.cover)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${r['description'] ?? r['channel'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: Space.s),
    ],
  );
}
