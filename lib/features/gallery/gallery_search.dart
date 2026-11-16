import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:handy_tdlib/api.dart' as td;
import 'package:omni_ai/omni_ai.dart' show CancelToken, FilePart, OmniAI;
import 'package:path_provider/path_provider.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../../infrastructure/telegram/telegram_client.dart' show TelegramClient;
import '../ai/data/ai.dart';
import '../sections/ai_run.dart';
import '../sections/section_kit.dart';
import '../settings/data/settings.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/data/telegram_store.dart';
import '../usage/usage.dart';
import 'gallery.dart';

// Searching the gallery: by caption and source at once, by Telegram's own
// search for older posts, and by what is in the picture once a vision model
// has described it ("smart search"). The descriptions stay on this phone.

/// What a vision model saw in one photo.
class PhotoNote {
  PhotoNote({required this.description, this.text = '', this.tags = const [], required this.at});
  final String description;

  /// Words written in the picture (signs, receipts, screenshots).
  final String text;
  final List<String> tags;
  final DateTime at;

  late final String haystack = '$description $text ${tags.join(' ')}'.toLowerCase();

  Map<String, dynamic> toJson() => {'d': description, if (text.isNotEmpty) 'x': text, if (tags.isNotEmpty) 't': tags, 'at': at.millisecondsSinceEpoch};
  factory PhotoNote.fromJson(Map j) => PhotoNote(
    description: '${j['d'] ?? ''}',
    text: '${j['x'] ?? ''}',
    tags: [for (final t in (j['t'] as List? ?? const [])) '$t'],
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );
}

/// One picture's result in a run.
@immutable
class IndexLog {
  const IndexLog({required this.key, this.error, required this.at});
  final String key;
  final String? error;
  final DateTime at;
}

@immutable
class GalleryIndexState {
  const GalleryIndexState({this.notes = const {}, this.running = false, this.done = 0, this.total = 0, this.failed = 0, this.error, this.model = '', this.log = const [], this.current = const [], this.startedAt, this.endedAt, this.stopped = false, this.items = const {}});
  final Map<String, PhotoNote> notes;
  final bool running;
  final int done;
  final int total;
  final int failed;
  final String? error;
  final String model;

  /// Newest first.
  final List<IndexLog> log;

  /// The pictures being looked at now.
  final List<String> current;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final bool stopped;

  /// The run's pictures by key, for the page to show them.
  final Map<String, GalleryItem> items;

  GalleryIndexState copyWith({
    Map<String, PhotoNote>? notes,
    bool? running,
    int? done,
    int? total,
    int? failed,
    String? error,
    bool clearError = false,
    String? model,
    List<IndexLog>? log,
    List<String>? current,
    DateTime? startedAt,
    DateTime? endedAt,
    bool? stopped,
    Map<String, GalleryItem>? items,
  }) => GalleryIndexState(
    notes: notes ?? this.notes,
    running: running ?? this.running,
    done: done ?? this.done,
    total: total ?? this.total,
    failed: failed ?? this.failed,
    error: clearError ? null : (error ?? this.error),
    model: model ?? this.model,
    log: log ?? this.log,
    current: current ?? this.current,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    stopped: stopped ?? this.stopped,
    items: items ?? this.items,
  );
}

bool _keyed(OmniAI ai, String id) {
  final r = AiRouter.of(id);
  return r != null && ai.provider(r.providerId).isConfigured;
}

/// A model that can look at pictures: the chat model when it can, else the
/// cheapest one with a key that can. Null when there is none.
String? visionModel(Ref ref) {
  final ai = ref.read(aiProvider);
  final main = canonicalModelId(ref.read(settingsProvider).model);
  if (ai.catalog.byId(main)?.vision ?? false) return main;
  final usable = [
    for (final m in ai.catalog.models)
      if (!m.isVariant && m.vision && m.isText && _keyed(ai, m.id)) m,
  ]..sort((a, b) => ((a.inputPrice ?? 1e9) + 4 * (a.outputPrice ?? 1e9)).compareTo((b.inputPrice ?? 1e9) + 4 * (b.outputPrice ?? 1e9)));
  if (usable.isNotEmpty) return usable.first.id;
  // Not in the catalog yet (it loads lazily): trust the chat model.
  return ai.catalog.models.isEmpty ? main : null;
}

class GalleryIndex extends Notifier<GalleryIndexState> {
  late Future<void> ready;
  Timer? _save;
  bool _stop = false;
  CancelToken? _cancel;

  /// The call in flight: the pictures, the model's thinking and answer.
  final live = AiLiveNotifier();

  @override
  GalleryIndexState build() {
    ready = _load();
    ref.onDispose(() => _save?.cancel());
    return const GalleryIndexState();
  }

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/gallery_index.json');

  Future<void> _load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      state = state.copyWith(notes: {for (final e in j.entries) if (e.value is Map) '${e.key}': PhotoNote.fromJson(e.value as Map)});
    } catch (e) {
      debugPrint('[GalleryIndex] $e');
    }
  }

  void _persist() {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () async {
      try {
        final f = await _file();
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode({for (final e in state.notes.entries) e.key: e.value.toJson()}));
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('[GalleryIndex] save: $e');
      }
    });
  }

  Future<void> forget() async {
    await ready;
    state = const GalleryIndexState();
    _persist();
  }

  /// Stops now, mid-call too.
  void stop() {
    _stop = true;
    _cancel?.cancel();
    if (state.running) state = state.copyWith(running: false, stopped: true, current: const [], endedAt: DateTime.now());
    live.idle();
  }

  void clearLog() => state = state.copyWith(log: const [], done: 0, total: 0, failed: 0, clearError: true);

  /// Describes up to [limit] of [items] (photos, and videos by their
  /// thumbnail) that aren't described yet, four to a model call. Returns
  /// how many were described.
  Future<int> run(List<GalleryItem> items, {int limit = 60}) async {
    await ready;
    if (state.running) return 0;
    final todo = [for (final i in items) if (!state.notes.containsKey(i.key) && (i.thumb != null || i.full != null)) i].take(limit).toList();
    if (todo.isEmpty) return 0;
    final model = visionModel(ref);
    if (model == null) {
      state = state.copyWith(error: 'No model that can see pictures. Pick one under Settings → AI & models.');
      return 0;
    }
    _stop = false;
    state = GalleryIndexState(
      notes: state.notes,
      running: true,
      total: todo.length,
      model: model,
      startedAt: DateTime.now(),
      log: state.log,
      items: {for (final i in todo) i.key: i},
    );
    live.clearNotes();
    var described = 0;
    try {
      for (var n = 0; n < todo.length && !_stop; n += 4) {
        final batch = todo.sublist(n, (n + 4).clamp(0, todo.length));
        state = state.copyWith(current: [for (final i in batch) i.key]);
        try {
          described += await _describe(model, batch);
        } on AiCancelled {
          break;
        } catch (e) {
          if (_stop) break;
          final msg = aiErrorText(e);
          state = state.copyWith(
            error: msg,
            failed: state.failed + batch.length,
            log: [for (final i in batch) IndexLog(key: i.key, error: msg, at: DateTime.now()), ...state.log].take(300).toList(),
          );
          // A model that can't see at all fails every batch: stop early.
          if ('$e'.toLowerCase().contains('image')) break;
        }
        if (_stop) break;
        state = state.copyWith(done: (n + batch.length).clamp(0, todo.length));
      }
    } finally {
      _cancel = null;
      live.idle();
      if (state.running) state = state.copyWith(running: false, stopped: _stop, current: const [], endedAt: DateTime.now());
      _persist();
    }
    return described;
  }

  Future<int> _describe(String model, List<GalleryItem> batch) async {
    final files = <FilePart>[];
    final kept = <GalleryItem>[];
    final shown = <Uint8List>[];
    live.begin(items: [for (final i in batch) i.caption.isNotEmpty ? (i.caption.length > 40 ? '${i.caption.substring(0, 40)}…' : i.caption) : i.source], phase: 'Fetching ${batch.length} pictures');
    _cancel = CancelToken();
    for (final i in batch) {
      if (_stop) throw const AiCancelled();
      final loader = ref.read(fileLoaderFamily(i.account));
      // The small picture is plenty to say what's in it, and fast to fetch.
      final f = i.thumb ?? i.full;
      if (f == null) continue;
      final path = loader.cachedPath(f) ?? await loader.download(f, priority: 4).timeout(const Duration(seconds: 40), onTimeout: () => null);
      if (path == null) continue;
      final bytes = await File(path).readAsBytes();
      if (bytes.length > 4 * 1024 * 1024) continue;
      files.add(FilePart.image(bytes));
      kept.add(i);
      shown.add(bytes);
      live.value = live.value.copyWith(images: [...shown]);
    }
    if (kept.isEmpty) {
      state = state.copyWith(failed: state.failed + batch.length, log: [for (final i in batch) IndexLog(key: i.key, error: 'Couldn’t fetch the picture', at: DateTime.now()), ...state.log].take(300).toList());
      return 0;
    }
    final ai = ref.read(aiProvider);
    final (list, r) = await aiJsonCall(
      ai: ai,
      model: model,
      cancel: _cancel!,
      live: live,
      system:
          'You index a photo library for search. For each picture, in order, write: description (one plain sentence '
          'naming the main subjects, the setting and anything notable: people count, objects, colours, document or '
          'screenshot type), text (any readable words in it, up to 30 words, else empty) and tags (5-10 lowercase '
          'search words: things, places, kinds like receipt, screenshot, selfie, food, document, meme, chart). Answer '
          'with only a JSON array of objects with "i" (0-based picture number), "description", "text" and "tags".',
      prompt: 'Describe these ${kept.length} pictures.${[for (final (n, i) in kept.indexed) if (i.caption.isNotEmpty) '\nPicture $n caption: ${i.caption.length > 140 ? i.caption.substring(0, 140) : i.caption}'].join()}',
      files: files,
      maxOutputTokens: 500 * kept.length + 1200,
    );
    try {
      ref.read(usageProvider.notifier).recordChat(model: r.model, usage: r.usage, info: ref.read(modelCatalogProvider).byId(r.model));
    } catch (_) {}
    final got = <String, PhotoNote>{};
    for (final o in list) {
      final i = (o['i'] as num?)?.toInt();
      if (i == null || i < 0 || i >= kept.length) continue;
      got[kept[i].key] = PhotoNote(
        description: '${o['description'] ?? ''}'.trim(),
        text: '${o['text'] ?? ''}'.trim(),
        tags: [for (final t in (o['tags'] as List? ?? const [])) '$t'.trim().toLowerCase()],
        at: DateTime.now(),
      );
    }
    final missed = [for (final i in batch) if (!got.containsKey(i.key)) i];
    state = state.copyWith(
      notes: {...state.notes, ...got},
      failed: state.failed + missed.length,
      log: [
        for (final i in batch) IndexLog(key: i.key, error: got.containsKey(i.key) ? null : 'No description came back', at: DateTime.now()),
        ...state.log,
      ].take(300).toList(),
    );
    _persist();
    return got.length;
  }
}

final galleryIndexProvider = NotifierProvider<GalleryIndex, GalleryIndexState>(GalleryIndex.new);

// ---- matching -----------------------------------------------------------------------

enum PhotoShape { portrait, landscape, square }

/// A search result: the item and where the words matched.
typedef GalleryHit = ({GalleryItem item, int score, String seen});

/// Words without their plural ending, for matching "receipts" to "receipt".
String _stem(String w) => w.length > 4 && w.endsWith('ies') ? '${w.substring(0, w.length - 3)}y' : (w.length > 3 && w.endsWith('s') && !w.endsWith('ss') ? w.substring(0, w.length - 1) : w);

/// Gallery items matching [query] (every word somewhere: caption, source,
/// date words, or what the picture shows) and the filters, best first.
List<GalleryHit> searchGallery(
  GalleryState g,
  List<GalleryItem> items,
  Map<String, PhotoNote> notes, {
  String query = '',
  bool? videos,
  DateTime? since,
  DateTime? until,
  String? sourceKey,
  PhotoShape? shape,
  bool favorites = false,
}) {
  final words = [for (final w in query.toLowerCase().split(RegExp(r'[\s,]+'))) if (w.trim().isNotEmpty) _stem(w.trim())];
  const months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
  final out = <GalleryHit>[];
  for (final i in items) {
    if (videos != null && i.video != videos) continue;
    if (since != null && i.date.isBefore(since)) continue;
    if (until != null && i.date.isAfter(until.add(const Duration(days: 1)))) continue;
    if (sourceKey != null && '${i.account}:${i.chatId}' != sourceKey) continue;
    if (favorites && !g.isFavorite(i.key)) continue;
    if (shape != null) {
      if (i.width <= 0 || i.height <= 0) continue;
      final r = i.width / i.height;
      final s = r > 1.15 ? PhotoShape.landscape : (r < 0.87 ? PhotoShape.portrait : PhotoShape.square);
      if (s != shape) continue;
    }
    if (words.isEmpty) {
      out.add((item: i, score: 0, seen: ''));
      continue;
    }
    final caption = i.caption.toLowerCase();
    final source = i.source.toLowerCase();
    final note = notes[i.key];
    final when = '${months[i.date.month - 1]} ${i.date.year} ${i.video ? 'video' : 'photo'}';
    var score = 0;
    final seen = <String>{};
    var all = true;
    for (final w in words) {
      var hit = false;
      if (caption.contains(w)) {
        score += 3;
        seen.add('caption');
        hit = true;
      }
      if (note != null && note.haystack.contains(w)) {
        score += note.tags.any((t) => _stem(t) == w) ? 4 : 2;
        seen.add('picture');
        hit = true;
      }
      if (source.contains(w)) {
        score += 1;
        seen.add('source');
        hit = true;
      }
      if (when.contains(w)) {
        score += 1;
        hit = true;
      }
      if (!hit) {
        all = false;
        break;
      }
    }
    if (all) out.add((item: i, score: score, seen: seen.join(', ')));
  }
  out.sort((a, b) => a.score != b.score ? b.score.compareTo(a.score) : b.item.date.compareTo(a.item.date));
  return out;
}

/// Asks Telegram for photos and videos whose captions match [query] in each
/// of [sources], and adds what it finds to the gallery's feed. Returns how
/// many new items came in.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

Future<int> deepSearchGallery(ProviderReader read, List<SourceRef> sources, String query) async {
  if (query.trim().isEmpty) return 0;
  final GalleryFeed feed = read(galleryFeedProvider.notifier);
  var added = 0;
  await pooled(sources, 3, (s) async {
    final TelegramClient client = read(telegramClientFamily(s.account));
    final TelegramStore store = read(telegramStoreFamily(s.account));
    final title = store.chat(s.chatId)?.title ?? s.title;
    final page = await loadChatPage(client, s.chatId, filter: const td.SearchMessagesFilterPhotoAndVideo(), query: query.trim(), limit: 100);
    final found = [for (final m in page.messages) ?GalleryItem.fromMessage(m, s.account, title)];
    added += feed.merge(s.key, found);
  });
  return added;
}
