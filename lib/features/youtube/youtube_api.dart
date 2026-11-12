import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';

class YoutubeException implements Exception {
  YoutubeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The YouTube Data API v3 with the person's key: search, videos, channels,
/// playlists, comments, the trending charts and live streams. Each call's
/// cost is counted against the 10,000 units Google allows a key each day
/// (search costs 100, most others 1).
class YoutubeApi {
  YoutubeApi(this.key, {http.Client? client}) : _http = client ?? http.Client();
  final String key;
  final http.Client _http;

  static const dailyQuota = 10000;
  static const _quotaDay = 'youtube_quota_day';
  static const _quotaUsed = 'youtube_quota_used';

  /// Units used today, by Google's day (it resets at midnight Pacific time).
  static final used = ValueNotifier<int>(0);

  static String _today() => DateTime.now().toUtc().subtract(const Duration(hours: 8)).toIso8601String().substring(0, 10);

  static Future<int> loadUsed() async {
    final p = await SharedPreferences.getInstance();
    used.value = p.getString(_quotaDay) == _today() ? (p.getInt(_quotaUsed) ?? 0) : 0;
    return used.value;
  }

  static Future<void> _spend(int units) async {
    final p = await SharedPreferences.getInstance();
    final day = _today();
    final now = (p.getString(_quotaDay) == day ? (p.getInt(_quotaUsed) ?? 0) : 0) + units;
    await p.setString(_quotaDay, day);
    await p.setInt(_quotaUsed, now);
    used.value = now;
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query, {int cost = 1}) async {
    final r = await _http
        .get(Uri.https('www.googleapis.com', '/youtube/v3/$path', {...query, 'key': key}), headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    await _spend(cost);
    final body = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      final e = (body is Map ? body['error'] : null) as Map?;
      final reason = ((e?['errors'] as List?)?.firstOrNull as Map?)?['reason'];
      throw YoutubeException(switch (reason) {
        'quotaExceeded' => 'The YouTube key\'s daily quota is used up; it resets at midnight Pacific time.',
        'keyInvalid' || 'badRequest' when '${e?['message']}'.contains('API key') => 'The YouTube API key isn\'t valid. Check it in Settings → More apps → YouTube.',
        'accessNotConfigured' => 'YouTube Data API v3 isn\'t enabled for this key\'s Google Cloud project.',
        'invalidRegionCode' => 'YouTube has no chart for that country.',
        'commentsDisabled' => 'Comments are turned off for this video.',
        'videoNotFound' => 'No such video.',
        _ => 'YouTube said: ${_plain('${e?['message'] ?? r.statusCode}')}',
      });
    }
    return Map<String, dynamic>.from(body as Map);
  }

  static String _plain(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

  // ---- shaping -------------------------------------------------------------------

  /// "PT1H2M10S" → seconds.
  static int seconds(String? iso) {
    final m = RegExp(r'P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(iso ?? '');
    if (m == null) return 0;
    int g(int i) => int.tryParse(m[i] ?? '') ?? 0;
    return g(1) * 86400 + g(2) * 3600 + g(3) * 60 + g(4);
  }

  static String clock(int s) => s >= 3600
      ? '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
      : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  static String compact(num n) => NumberFormat.compact().format(n);

  static String? _thumb(Map? thumbs) {
    if (thumbs == null) return null;
    for (final k in const ['maxres', 'standard', 'high', 'medium', 'default']) {
      if ((thumbs[k] as Map?)?['url'] case final String u) return u;
    }
    return null;
  }

  static int? _int(Object? v) => int.tryParse('${v ?? ''}');

  /// A videos.list item as the cards and the model read it.
  static Map<String, dynamic> video(Map v) {
    final s = v['snippet'] as Map? ?? const {};
    final st = v['statistics'] as Map? ?? const {};
    final c = v['contentDetails'] as Map? ?? const {};
    final live = v['liveStreamingDetails'] as Map?;
    final id = '${v['id'] is Map ? (v['id'] as Map)['videoId'] : v['id']}';
    final secs = seconds(c['duration'] as String?);
    final views = _int(st['viewCount']);
    return {
      'video_id': id,
      'title': s['title'],
      'channel': s['channelTitle'],
      'channel_id': s['channelId'],
      'published': '${s['publishedAt'] ?? ''}'.split('T').first,
      if (secs > 0) 'length': clock(secs),
      if (secs > 0) 'seconds': secs,
      if (views != null) 'views': compact(views),
      'view_count': ?views,
      'like_count': ?_int(st['likeCount']),
      'comment_count': ?_int(st['commentCount']),
      if (s['liveBroadcastContent'] == 'live') 'live': true,
      if (s['liveBroadcastContent'] == 'upcoming') 'upcoming': true,
      if (live?['concurrentViewers'] != null) 'watching': _int(live!['concurrentViewers']),
      if (live?['scheduledStartTime'] != null) 'starts': live!['scheduledStartTime'],
      if (live?['actualStartTime'] != null) 'started': live!['actualStartTime'],
      'thumbnail': _thumb(s['thumbnails'] as Map?) ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      'url': 'https://youtu.be/$id',
    };
  }

  // ---- calls ---------------------------------------------------------------------

  /// Full details of up to 50 videos, in the order given.
  Future<List<Map<String, dynamic>>> videos(List<String> ids, {bool full = false}) async {
    if (ids.isEmpty) return const [];
    final out = <String, Map>{};
    for (var i = 0; i < ids.length; i += 50) {
      final r = await _get('videos', {
        'part': full ? 'snippet,statistics,contentDetails,liveStreamingDetails,topicDetails,status' : 'snippet,statistics,contentDetails,liveStreamingDetails',
        'id': ids.skip(i).take(50).join(','),
        'maxResults': '50',
      });
      for (final v in (r['items'] as List? ?? const []).cast<Map>()) {
        out['${v['id']}'] = v;
      }
    }
    return [for (final id in ids) if (out[id] != null) full ? _full(out[id]!) : video(out[id]!)];
  }

  static Map<String, dynamic> _full(Map v) {
    final s = v['snippet'] as Map? ?? const {};
    final c = v['contentDetails'] as Map? ?? const {};
    final status = v['status'] as Map? ?? const {};
    final region = c['regionRestriction'] as Map?;
    final topics = [for (final t in ((v['topicDetails'] as Map?)?['topicCategories'] as List? ?? const [])) '$t'.split('/').last.replaceAll('_', ' ')];
    return {
      ...video(v),
      'description': '${s['description'] ?? ''}',
      if ((s['tags'] as List?)?.isNotEmpty ?? false) 'tags': (s['tags'] as List).take(25).toList(),
      'category_id': s['categoryId'],
      'category': ?_categories[s['categoryId']],
      'definition': '${c['definition'] ?? ''}'.toUpperCase(),
      'captions': c['caption'] == 'true',
      'licensed': c['licensedContent'] == true,
      'made_for_kids': status['madeForKids'] == true,
      if (s['defaultAudioLanguage'] != null) 'language': s['defaultAudioLanguage'],
      if (topics.isNotEmpty) 'topics': topics,
      if (region?['blocked'] is List) 'blocked_in': region!['blocked'],
      if (region?['allowed'] is List) 'only_in': region!['allowed'],
    };
  }

  static const _categories = {
    '1': 'Film & Animation', '2': 'Autos & Vehicles', '10': 'Music', '15': 'Pets & Animals', '17': 'Sports', '19': 'Travel & Events',
    '20': 'Gaming', '22': 'People & Blogs', '23': 'Comedy', '24': 'Entertainment', '25': 'News & Politics', '26': 'Howto & Style',
    '27': 'Education', '28': 'Science & Technology', '29': 'Nonprofits & Activism',
  };

  static const categoryIds = {
    'film': '1', 'autos': '2', 'music': '10', 'pets': '15', 'sports': '17', 'travel': '19', 'gaming': '20', 'people': '22',
    'comedy': '23', 'entertainment': '24', 'news': '25', 'howto': '26', 'education': '27', 'science': '28',
  };

  /// Search; videos come back with full statistics (100 units + 1).
  Future<Map<String, dynamic>> search(
    String q, {
    String type = 'video',
    String order = 'relevance',
    String? duration,
    int? withinDays,
    String? region,
    String? eventType,
    String? channelId,
    bool captions = false,
    int limit = 10,
  }) async {
    final r = await _get('search', {
      'part': 'snippet',
      if (q.isNotEmpty) 'q': q,
      'type': type,
      'order': order,
      'maxResults': '${limit.clamp(1, 50)}',
      if (duration != null && type == 'video') 'videoDuration': duration,
      if (withinDays != null) 'publishedAfter': DateTime.now().toUtc().subtract(Duration(days: withinDays)).toIso8601String().split('.').first + 'Z',
      if (region != null && region.isNotEmpty) 'regionCode': region.toUpperCase(),
      if (eventType != null) 'eventType': eventType,
      if (channelId != null) 'channelId': channelId,
      if (captions && type == 'video') 'videoCaption': 'closedCaption',
    }, cost: 100);
    final items = (r['items'] as List? ?? const []).cast<Map>();
    if (type == 'video') {
      final ids = [for (final i in items) '${(i['id'] as Map)['videoId']}'];
      return {'total': (r['pageInfo'] as Map?)?['totalResults'], 'results': await videos(ids)};
    }
    return {
      'total': (r['pageInfo'] as Map?)?['totalResults'],
      'results': [
        for (final i in items)
          {
            'kind': type,
            'title': (i['snippet'] as Map)['title'],
            'channel': (i['snippet'] as Map)['channelTitle'],
            'description': (i['snippet'] as Map)['description'],
            'thumbnail': _thumb((i['snippet'] as Map)['thumbnails'] as Map?),
            if (type == 'channel') 'channel_id': (i['id'] as Map)['channelId'],
            if (type == 'playlist') 'playlist_id': (i['id'] as Map)['playlistId'],
            'url': type == 'channel' ? 'https://www.youtube.com/channel/${(i['id'] as Map)['channelId']}' : 'https://www.youtube.com/playlist?list=${(i['id'] as Map)['playlistId']}',
          },
      ],
    };
  }

  /// A channel by id (UC…), @handle, link or name (a name costs a search).
  Future<Map<String, dynamic>> channel(String c) async {
    var s = c.trim();
    final id = RegExp(r'(UC[\w-]{22})').firstMatch(s)?[1];
    final handle = RegExp(r'@([\w.\-]+)').firstMatch(s)?[1] ?? (RegExp(r'^[\w.\-]+$').hasMatch(s) && id == null ? s : null);
    Map? item;
    if (id != null) {
      item = ((await _get('channels', {'part': 'snippet,statistics,contentDetails,brandingSettings', 'id': id}))['items'] as List?)?.firstOrNull as Map?;
    } else if (handle != null) {
      item = ((await _get('channels', {'part': 'snippet,statistics,contentDetails,brandingSettings', 'forHandle': '@$handle'}))['items'] as List?)?.firstOrNull as Map?;
    }
    if (item == null) {
      final found = await search(s, type: 'channel', limit: 1);
      final cid = ((found['results'] as List).firstOrNull as Map?)?['channel_id'];
      if (cid == null) throw YoutubeException('No YouTube channel "$c".');
      return channel('$cid');
    }
    final sn = item['snippet'] as Map? ?? const {};
    final st = item['statistics'] as Map? ?? const {};
    final views = _int(st['viewCount']) ?? 0;
    final count = _int(st['videoCount']) ?? 0;
    return {
      'channel': sn['title'],
      'channel_id': item['id'],
      'handle': sn['customUrl'],
      'description': sn['description'],
      'avatar': _thumb(sn['thumbnails'] as Map?),
      'banner': ((item['brandingSettings'] as Map?)?['image'] as Map?)?['bannerExternalUrl'],
      'country': sn['country'],
      'created': '${sn['publishedAt'] ?? ''}'.split('T').first,
      if (st['hiddenSubscriberCount'] != true) 'subscriber_count': _int(st['subscriberCount']),
      if (st['hiddenSubscriberCount'] != true) 'subscribers': '${compact(_int(st['subscriberCount']) ?? 0)} subscribers',
      'view_count': views,
      'video_count': count,
      'videos': '$count videos',
      if (count > 0) 'average_views': (views / count).round(),
      'uploads_playlist': ((item['contentDetails'] as Map?)?['relatedPlaylists'] as Map?)?['uploads'],
      'url': 'https://www.youtube.com/channel/${item['id']}',
    };
  }

  /// A playlist's videos with full statistics, up to [max].
  Future<List<Map<String, dynamic>>> playlistVideos(String playlistId, {int max = 50}) async {
    final ids = <String>[];
    String? page;
    do {
      final r = await _get('playlistItems', {'part': 'contentDetails', 'playlistId': playlistId, 'maxResults': '50', 'pageToken': ?page});
      for (final i in (r['items'] as List? ?? const []).cast<Map>()) {
        ids.add('${(i['contentDetails'] as Map)['videoId']}');
      }
      page = r['nextPageToken'] as String?;
    } while (page != null && ids.length < max);
    return videos(ids.take(max).toList());
  }

  Future<Map<String, dynamic>> playlist(String id) async {
    final r = await _get('playlists', {'part': 'snippet,contentDetails', 'id': id});
    final p = (r['items'] as List?)?.firstOrNull as Map?;
    if (p == null) throw YoutubeException('No public playlist $id.');
    final s = p['snippet'] as Map;
    return {
      'playlist': s['title'],
      'by': s['channelTitle'],
      'channel_id': s['channelId'],
      'description': s['description'],
      'thumbnail': _thumb(s['thumbnails'] as Map?),
      'count': (p['contentDetails'] as Map?)?['itemCount'],
      'url': 'https://www.youtube.com/playlist?list=$id',
    };
  }

  /// Top-level comments (with up to 5 replies each).
  Future<Map<String, dynamic>> comments(String videoId, {String order = 'relevance', int limit = 20, String? search}) async {
    final r = await _get('commentThreads', {
      'part': 'snippet,replies',
      'videoId': videoId,
      'order': order,
      'maxResults': '${limit.clamp(1, 100)}',
      'textFormat': 'plainText',
      if (search != null && search.isNotEmpty) 'searchTerms': search,
    });
    Map<String, dynamic> one(Map c) {
      final s = c['snippet'] as Map? ?? const {};
      return {
        'author': s['authorDisplayName'],
        'avatar': s['authorProfileImageUrl'],
        'text': s['textDisplay'],
        'likes': _int(s['likeCount']) ?? 0,
        'published': '${s['publishedAt'] ?? ''}'.split('T').first,
        if (s['updatedAt'] != s['publishedAt']) 'edited': true,
      };
    }

    return {
      'comments': [
        for (final t in (r['items'] as List? ?? const []).cast<Map>())
          {
            ...one((t['snippet'] as Map)['topLevelComment'] as Map),
            'reply_count': (t['snippet'] as Map)['totalReplyCount'] ?? 0,
            if (((t['replies'] as Map?)?['comments'] as List?)?.isNotEmpty ?? false)
              'replies': [for (final x in ((t['replies'] as Map)['comments'] as List).cast<Map>().take(5)) one(x)],
          },
      ],
    };
  }

  /// The most popular videos in a country, optionally one category.
  Future<List<Map<String, dynamic>>> trending({String region = 'US', String? category, int limit = 20}) async {
    final r = await _get('videos', {
      'part': 'snippet,statistics,contentDetails',
      'chart': 'mostPopular',
      'regionCode': region.toUpperCase(),
      'videoCategoryId': ?category,
      'maxResults': '${limit.clamp(1, 50)}',
    });
    return [for (final v in (r['items'] as List? ?? const []).cast<Map>()) video(v)];
  }
}
