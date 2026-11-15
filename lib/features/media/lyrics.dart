import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/theme.dart';
import 'audio_center.dart';
import 'audio_tags.dart';

// Lyrics for what's playing: the song's own (from its tags, synced when
// they carry LRC timestamps), else the free LRCLIB database (lrclib.net),
// preferring synced lyrics of the same length. As in Musicly.

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  Lyrics({required this.track, required this.artist, this.duration, this.synced = const [], this.plain, this.instrumental = false, this.source = 'LRCLIB', this.id});
  final String track;
  final String artist;
  final Duration? duration;
  final List<LyricLine> synced;
  final String? plain;
  final bool instrumental;
  final String source;
  final int? id;

  bool get isSynced => synced.isNotEmpty;

  static final _tag = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');

  /// LRC text: lines may carry several timestamps.
  static List<LyricLine> parseLrc(String lrc) {
    final out = <LyricLine>[];
    for (final raw in const LineSplitter().convert(lrc)) {
      final tags = _tag.allMatches(raw).toList();
      if (tags.isEmpty) continue;
      final text = raw.substring(tags.last.end).trim();
      for (final t in tags) {
        out.add(LyricLine(Duration(milliseconds: (int.parse(t.group(1)!) * 60000 + double.parse(t.group(2)!) * 1000).round()), text));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  factory Lyrics.fromJson(Map j) => Lyrics(
    id: (j['id'] as num?)?.toInt(),
    track: '${j['trackName'] ?? ''}',
    artist: '${j['artistName'] ?? ''}',
    duration: j['duration'] == null ? null : Duration(milliseconds: ((j['duration'] as num) * 1000).round()),
    synced: j['syncedLyrics'] == null ? const [] : parseLrc('${j['syncedLyrics']}'),
    plain: j['plainLyrics'] as String?,
    instrumental: j['instrumental'] == true,
  );

  /// The line playing at [pos]; -1 before the first.
  int lineAt(Duration pos) {
    var i = -1;
    for (var k = 0; k < synced.length; k++) {
      if (synced[k].time <= pos) {
        i = k;
      } else {
        break;
      }
    }
    return i;
  }
}

class LyricsApi {
  static const _host = 'https://lrclib.net/api';
  static const _headers = {'User-Agent': 'Triangle/1.0'};

  static Future<List<Lyrics>> search(String query) async {
    final r = await http.get(Uri.parse('$_host/search?q=${Uri.encodeQueryComponent(query)}'), headers: _headers).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw 'Lyrics search failed (${r.statusCode}).';
    return [for (final j in jsonDecode(r.body) as List) if (j is Map) Lyrics.fromJson(j)];
  }

  /// The best match for a song: synced, the same length, the same artist.
  static Future<Lyrics?> find(String title, String artist, Duration? duration) async {
    final clean = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]|official|video|audio|lyrics?', caseSensitive: false), '').trim();
    var results = await search(artist.isEmpty ? clean : '$clean $artist');
    if (results.isEmpty && artist.isNotEmpty) results = await search(clean);
    if (results.isEmpty) return null;
    bool plausible(Lyrics l) {
      final a = artist.toLowerCase(), la = l.artist.toLowerCase();
      final artistOk = a.isNotEmpty && (la.contains(a) || a.contains(la));
      final durOk = duration != null && duration > Duration.zero && l.duration != null && (l.duration!.inSeconds - duration.inSeconds).abs() <= 4;
      final t = clean.toLowerCase(), lt = l.track.toLowerCase();
      final titleOk = lt.contains(t) || t.contains(lt);
      return titleOk && (artistOk || durOk || (a.isEmpty && duration == null));
    }

    int score(Lyrics l) {
      var s = l.isSynced ? 10 : 0;
      if (duration != null && l.duration != null) {
        final d = (l.duration!.inSeconds - duration.inSeconds).abs();
        if (d <= 3) s += 6;
        if (d > 20) s -= 6;
      }
      if (l.artist.toLowerCase() == artist.toLowerCase()) s += 4;
      return s;
    }

    final ok = results.where(plausible).toList()..sort((a, b) => score(b).compareTo(score(a)));
    return ok.firstOrNull;
  }
}

/// Lyrics found per track, for the session; a person's own pick wins.
final _cache = <String, Lyrics?>{};

Future<Lyrics?> lyricsFor(Track t, {String? path, Duration? duration}) async {
  if (_cache.containsKey(t.key)) return _cache[t.key];
  Lyrics? found;
  if (path != null) {
    final tags = await readAudioTags(path);
    final own = tags.lyrics;
    if (own != null && own.trim().isNotEmpty) {
      final synced = Lyrics.parseLrc(own);
      found = Lyrics(track: tags.title ?? t.title, artist: tags.artist ?? t.subtitle, synced: synced, plain: synced.isEmpty ? own : null, source: 'the song file');
    }
  }
  if (found == null) {
    String artist = t.subtitle.split(' · ').first;
    String title = t.title;
    if (path != null) {
      final tags = await readAudioTags(path);
      title = tags.title ?? title;
      artist = tags.artist ?? artist;
    }
    // "Artist - Title" names.
    if (artist.isEmpty && title.contains(' - ')) {
      final parts = title.split(' - ');
      artist = parts.first.trim();
      title = parts.sublist(1).join(' - ').trim();
    }
    found = await LyricsApi.find(title, artist, duration);
  }
  return _cache[t.key] = found;
}

/// Lyrics in a sheet: the playing line lit and kept in view, tap a line to
/// go there, nudge the timing, or search for other lyrics.
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({super.key, required this.scroll});
  final ScrollController scroll;

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  Lyrics? _lyrics;
  bool _loading = true;
  String? _error;
  String? _for;
  Duration _offset = Duration.zero;
  int _line = -1;
  final _keys = <int, GlobalKey>{};
  DateTime _userScrolled = DateTime(0);

  void _load(Track t, String? path, Duration duration) {
    if (_for == t.key) return;
    _for = t.key;
    _lyrics = null;
    _loading = true;
    _error = null;
    lyricsFor(t, path: path, duration: duration).then((l) {
      if (mounted && _for == t.key) setState(() => (_lyrics = l, _loading = false));
    }).catchError((Object e) {
      if (mounted && _for == t.key) setState(() => (_error = '$e', _loading = false));
    });
  }

  Future<void> _search(Track t) async {
    final c = TextEditingController(text: '${t.title} ${t.subtitle.split(' · ').first}'.trim());
    final picked = await showModalBottomSheet<Lyrics>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LyricsSearch(controller: c),
    );
    if (picked != null && mounted) {
      _cache[t.key] = picked;
      setState(() => _lyrics = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(audioCenterProvider);
    final t = a.current;
    if (t == null) return const Center(child: Text('Nothing playing'));
    _load(t, a.currentPath, a.duration);
    final l = _lyrics;
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (l == null || (!l.isSynced && (l.plain ?? '').trim().isEmpty && !l.instrumental)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, size: 40, color: AppColors.text3),
            const SizedBox(height: Space.m),
            Text(_error == null ? 'No lyrics found for this song.' : 'Couldn\'t load lyrics.', style: context.text.bodyMedium),
            const SizedBox(height: Space.m),
            FilledButton.icon(onPressed: () => _search(t), icon: const Icon(Icons.search_rounded, size: 18), label: const Text('Search lyrics')),
          ],
        ),
      );
    }
    if (l.instrumental) return Center(child: Text('Instrumental. Enjoy the music.', style: context.text.bodyLarge));
    final synced = l.isSynced;
    final pos = a.position + _offset;
    if (synced) {
      final i = l.lineAt(pos);
      if (i != _line) {
        _line = i;
        if (DateTime.now().difference(_userScrolled) > const Duration(seconds: 4)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _keys[_line < 0 ? 0 : _line]?.currentContext;
            if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
          });
        }
      }
    }
    final lines = synced ? [for (final x in l.synced) x.text] : (l.plain ?? '').split('\n');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: synced ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surface2, borderRadius: BorderRadius.circular(99)),
                child: Text(synced ? 'Synced' : 'Not synced', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: synced ? AppColors.accent : AppColors.text2)),
              ),
              const SizedBox(width: Space.s),
              Flexible(child: Text('from ${l.source}', style: context.text.labelSmall, overflow: TextOverflow.ellipsis)),
              const Spacer(),
              if (synced) ...[
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_rounded, size: 18), onPressed: () => setState(() => _offset -= const Duration(milliseconds: 500))),
                Text('${_offset.isNegative ? '' : '+'}${(_offset.inMilliseconds / 1000).toStringAsFixed(1)}s', style: context.text.labelSmall),
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_rounded, size: 18), onPressed: () => setState(() => _offset += const Duration(milliseconds: 500))),
              ],
              IconButton(tooltip: 'Search lyrics', icon: const Icon(Icons.manage_search_rounded), onPressed: () => _search(t)),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<UserScrollNotification>(
            onNotification: (_) {
              _userScrolled = DateTime.now();
              return false;
            },
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.08, 0.85, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ListView.builder(
                controller: widget.scroll,
                padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: 60),
                itemCount: lines.length,
                itemBuilder: (_, i) {
                  final active = synced && i == _line;
                  final passed = synced && i < _line;
                  final text = lines[i].trim();
                  return GestureDetector(
                    key: _keys.putIfAbsent(i, GlobalKey.new),
                    onTap: synced ? () => a.seek(l.synced[i].time - _offset) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          fontSize: active ? 24 : 21,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: !synced ? AppColors.text : (active ? AppColors.text : (passed ? AppColors.text3 : AppColors.text2.withValues(alpha: 0.55))),
                        ),
                        child: Text(text.isEmpty ? '♪' : text),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LyricsSearch extends StatefulWidget {
  const _LyricsSearch({required this.controller});
  final TextEditingController controller;

  @override
  State<_LyricsSearch> createState() => _LyricsSearchState();
}

class _LyricsSearchState extends State<_LyricsSearch> {
  Future<List<Lyrics>>? _results;

  @override
  void initState() {
    super.initState();
    _results = LyricsApi.search(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: TextField(
              controller: widget.controller,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Song and artist'),
              onSubmitted: (v) => setState(() => _results = LyricsApi.search(v)),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Lyrics>>(
              future: _results,
              builder: (_, snap) {
                if (snap.hasError) return Center(child: Text('${snap.error}'));
                final list = snap.data;
                if (list == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                if (list.isEmpty) return const Center(child: Text('Nothing found'));
                return ListView(
                  children: [
                    for (final l in list)
                      ListTile(
                        leading: Icon(l.isSynced ? Icons.lyrics_rounded : Icons.notes_rounded),
                        title: Text(l.track),
                        subtitle: Text([l.artist, if (l.duration != null) '${l.duration!.inMinutes}:${(l.duration!.inSeconds % 60).toString().padLeft(2, '0')}', l.isSynced ? 'synced' : 'plain'].join(' · ')),
                        onTap: () => Navigator.pop(context, l),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// Text in one line that scrolls sideways when it doesn't fit.
class MarqueeText extends StatefulWidget {
  const MarqueeText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final tp = TextPainter(text: TextSpan(text: widget.text, style: widget.style), maxLines: 1, textDirection: Directionality.of(context))..layout();
      final w = tp.width;
      final h = tp.height;
      if (w <= box.maxWidth) {
        _c.stop();
        return Text(widget.text, maxLines: 1, style: widget.style);
      }
      const gap = 48.0;
      final travel = w + gap;
      // About 35 px a second, with a pause at the start of each lap.
      final ms = (travel / 35 * 1000).round() + 1800;
      if (_c.duration?.inMilliseconds != ms || !_c.isAnimating) {
        _c.duration = Duration(milliseconds: ms);
        _c.repeat();
      }
      final pause = 1800 / ms;
      return SizedBox(
        height: h,
        width: box.maxWidth,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final t = _c.value < pause ? 0.0 : (_c.value - pause) / (1 - pause);
              return OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Transform.translate(
                  offset: Offset(-travel * t, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text(widget.text, maxLines: 1, style: widget.style), const SizedBox(width: gap), Text(widget.text, maxLines: 1, style: widget.style)],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
