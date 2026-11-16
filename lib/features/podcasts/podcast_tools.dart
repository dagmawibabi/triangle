import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sections/section_kit.dart' show SourceRef;
import '../telegram/data/telegram_store.dart';
import 'podcast_models.dart';
import 'podcast_store.dart';
import 'radio_store.dart';

String _s(Map<String, dynamic> a, String k) => '${a[k] ?? ''}'.trim();
int? _i(Map<String, dynamic> a, String k) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(_s(a, k));

/// Runs the podcast and radio tools for the assistant.
Future<Map<String, dynamic>> runPodcastTool(Ref ref, String name, Map<String, dynamic> a, String account) async {
  final pods = ref.read(podcastsProvider);
  await pods.ready;
  final limit = (_i(a, 'limit') ?? 20).clamp(1, 80);
  switch (name) {
    case 'podcast_discover':
      final genre = _s(a, 'genre').isEmpty ? null : podcastGenres.where((g) => g.$1.toLowerCase() == _s(a, 'genre').toLowerCase()).firstOrNull?.$2;
      final country = _s(a, 'country').isEmpty ? null : _s(a, 'country').toLowerCase();
      final hits = _s(a, 'query').isEmpty && genre == null ? await pods.top(country: country) : await pods.search(_s(a, 'query').isEmpty ? (podcastGenres.firstWhere((g) => g.$2 == genre).$1) : _s(a, 'query'), genre: genre, country: country);
      return {
        'shows': [for (final h in hits.take(limit)) {...h.describe(), if (h.feedUrl != null && pods.subscribed(h.feedUrl!)) 'following': true}],
        if (hits.isEmpty && pods.unreachable) 'error': 'The podcast directory isn\'t answering.',
      };

    case 'podcast_shows':
      switch (_s(a, 'action')) {
        case 'follow':
          var url = _s(a, 'feed_url');
          if (url.isEmpty && _s(a, 'apple_id').isNotEmpty) url = await pods.feedFor(PodcastHit(id: _s(a, 'apple_id'), title: '')) ?? '';
          if (url.isEmpty) return {'error': 'Give feed_url or apple_id (from podcast_discover).'};
          final p = await pods.addByUrl(url);
          if (p == null) return {'error': 'That isn\'t a readable podcast feed.'};
          return {'followed': p.describe()};
        case 'unfollow':
          pods.unsubscribe(_s(a, 'show_id'));
          return {'unfollowed': _s(a, 'show_id')};
        case 'add_telegram':
          final store = ref.read(telegramStoreFamily(account));
          final ids = [for (final v in (a['chat_ids'] as List? ?? const [])) if (v is num) v.toInt()];
          if (ids.isEmpty) return {'error': 'Give chat_ids of channels that post audio.'};
          await pods.addTelegramShows([for (final id in ids) SourceRef(account: account, chatId: id, title: store.chat(id)?.title ?? 'Channel $id')]);
        case 'refresh':
          await pods.refreshAll(quiet: true);
      }
      return {
        'shows': [for (final s in pods.subscriptions) {...s.describe(), 'new': pods.unplayedIn(s)}],
      };

    case 'podcast_library':
      final which = _s(a, 'list');
      List<Episode> eps;
      if (_s(a, 'show_id').isNotEmpty) {
        final p = await pods.feed(_s(a, 'show_id'));
        if (p == null) return {'error': 'Couldn\'t read that show.'};
        eps = pods.sortOf(p.feedUrl).apply(p.episodes);
      } else {
        eps = switch (which) {
          'in_progress' => [for (final s in pods.inProgress) s.episode],
          'queue' => pods.queue,
          'downloaded' => [for (final s in pods.downloaded) s.episode],
          'history' => [for (final s in pods.history) s.episode],
          'saved' => [for (final s in pods.bookmarked) s.episode],
          _ => pods.latest,
        };
      }
      final q = _s(a, 'query');
      if (q.isNotEmpty) eps = eps.where((e) => e.matches(q)).toList();
      return {'episodes': [for (final e in eps.take(limit)) e.describe(state: pods.states[e.guid])], 'total': eps.length};

    case 'podcast_play':
      final e = pods.episodeById(_s(a, 'episode_id'));
      final action = _s(a, 'action').isEmpty ? 'play' : _s(a, 'action');
      if (action == 'clear_queue') {
        pods.clearQueue();
        return {'done': 'queue cleared'};
      }
      if (e == null) return {'error': 'No episode with that id; get one from podcast_library.'};
      switch (action) {
        case 'play':
          await pods.play(e);
        case 'play_next':
          pods.enqueue(e, next: true);
        case 'queue':
          pods.enqueue(e);
        case 'dequeue':
          pods.dequeue(e);
        case 'played':
          pods.setPlayed(e, true);
        case 'unplayed':
          pods.setPlayed(e, false);
        case 'download':
          if (!await pods.download(e)) return {'error': 'The download failed.'};
        case 'remove_download':
          await pods.removeDownload(e);
        case 'favorite':
          pods.episodeMark(e).favorite = true;
          pods.marksChanged();
      }
      return {'done': action, 'episode': e.describe(state: pods.states[e.guid]), 'queue': pods.queue.length};

    case 'radio':
      final radio = ref.read(radioProvider);
      await radio.ready;
      final country = _s(a, 'country');
      if (country.isNotEmpty) {
        final list = await radio.countries();
        final c = list.where((c) => c.code.toLowerCase() == country.toLowerCase() || c.name.toLowerCase() == country.toLowerCase()).firstOrNull;
        if (c == null) return {'error': 'No country "$country".'};
        radio.setCountry(c.code, c.name);
      }
      switch (_s(a, 'action')) {
        case 'play':
          final id = _s(a, 'station_id');
          var s = radio.stationFor(id);
          if (s == null && _s(a, 'query').isNotEmpty) s = (await radio.browse(name: _s(a, 'query'))).firstOrNull;
          if (s == null) return {'error': 'No such station; search first.'};
          await radio.play(s);
          return {'playing': s.describe()};
        case 'favorite' || 'unfavorite':
          final s = radio.stationFor(_s(a, 'station_id'));
          if (s == null) return {'error': 'No such station; search first.'};
          if (radio.isFavorite(s.id) != (_s(a, 'action') == 'favorite')) radio.toggleFavorite(s);
          return {'done': _s(a, 'action'), 'station': s.describe()};
        case 'favorites':
          return {'stations': [for (final s in radio.favorites) s.describe()]};
        case 'recent':
          return {'stations': [for (final s in radio.recents) s.describe()]};
      }
      final list = await radio.browse(name: _s(a, 'query'), tag: _s(a, 'tag').isEmpty ? null : _s(a, 'tag'));
      return {
        'country': radio.country.isEmpty ? 'all' : radio.countryName,
        'stations': [for (final s in list.take(limit)) {...s.describe(), if (radio.isFavorite(s.id)) 'favorite': true}],
        if (list.isEmpty && radio.unreachable) 'error': 'The radio directory isn\'t answering.',
      };
  }
  return {'error': 'Unknown tool $name.'};
}
