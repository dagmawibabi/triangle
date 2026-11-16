import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart' show confirmDelete;
import '../../core/widgets/net_image.dart';
import '../telegram/data/telegram_store.dart' show telegramStoreFamily;
import '../../infrastructure/telegram/accounts.dart';
import '../movies/movies.dart';
import '../sections/section_kit.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'cinema.dart';

/// What the editor returns when the series was deleted.
const seriesDeleted = '__deleted__';

/// Opens the editor for a new series, or [series] to change it. Returns
/// the saved series' title key, or null.
Future<String?> openSeriesEditor(BuildContext context, {CustomSeries? series}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => SeriesEditorScreen(series: series)));

/// Put a series together: its name and year, channels for the whole of it
/// (their posts are sorted into seasons by "S02E03" and the like), and
/// seasons, each with channels of its own whose videos are its episodes in
/// the order they were posted.
class SeriesEditorScreen extends ConsumerStatefulWidget {
  const SeriesEditorScreen({super.key, this.series});
  final CustomSeries? series;

  @override
  ConsumerState<SeriesEditorScreen> createState() => _SeriesEditorScreenState();
}

class _SeriesEditorScreenState extends ConsumerState<SeriesEditorScreen> {
  late final _name = TextEditingController(text: widget.series?.name ?? '');
  late final _year = TextEditingController(text: widget.series?.year?.toString() ?? '');
  late List<SourceRef> _sources = [...?widget.series?.sources];
  late List<CustomSeason> _seasons = [...?widget.series?.seasons];
  late String _poster = widget.series?.poster ?? 'channel';
  late String? _posterPath = widget.series?.posterPath;

  /// Copies a picture from the gallery into the app's folder (the
  /// picker's copy is temporary).
  Future<void> _pickPicture() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 1400);
    if (x == null) return;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/cinema_posters');
    if (!await dir.exists()) await dir.create(recursive: true);
    final to = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(to);
    if (mounted) {
      setState(() {
        _posterPath = to;
        _poster = 'picture';
      });
    }
  }

  Widget _posterCard() {
    final src = [..._sources, for (final s in _seasons) ...s.sources].firstOrNull;
    final store = src == null ? null : ref.watch(telegramStoreFamily(src.account));
    final photo = src == null ? null : store?.chat(src.chatId)?.photo;
    final name = _name.text.trim();
    final meta = name.isEmpty || _poster != 'online' ? null : ref.watch(titleMetaProvider((TitleKind.show, name, int.tryParse(_year.text.trim())))).value;
    final Widget preview = switch (_poster) {
      'picture' when _posterPath != null => Image.file(File(_posterPath!), fit: BoxFit.cover),
      'online' => meta?.poster == null
          ? Center(child: Text(name.isEmpty ? 'Name it first' : 'Looking it up…', textAlign: TextAlign.center, style: context.text.labelSmall))
          : NetImage(meta!.poster, fit: BoxFit.cover),
      _ => src == null
          ? Center(child: Text('Pick a channel', textAlign: TextAlign.center, style: context.text.labelSmall))
          : TgPicture(file: photo?.big, mini: photo?.minithumbnail, account: src.account, cacheWidth: 300),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.m),
          child: Container(width: 84, height: 126, color: AppColors.surface2, child: preview),
        ),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (v, icon, label, sub) in const [
                ('channel', Icons.campaign_outlined, 'From the channel', 'Its poster posts, else the channel’s photo'),
                ('online', Icons.public_rounded, 'Look it up online', 'By the series’ name'),
                ('picture', Icons.photo_library_outlined, 'Pick a picture', 'From your gallery'),
              ])
                InkWell(
                  borderRadius: BorderRadius.circular(Radii.s),
                  onTap: () => v == 'picture' ? _pickPicture() : setState(() => _poster = v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(_poster == v ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 20, color: _poster == v ? AppColors.text : AppColors.text3),
                        const SizedBox(width: Space.s),
                        Icon(icon, size: 18, color: AppColors.text2),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              Text(v == 'picture' && _posterPath != null ? 'Tap to pick another' : sub, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.series == null) _seasons = [const CustomSeason(number: 1)];
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<List<SourceRef>?> _pick(List<SourceRef> current, String title, String hint) => pickSources(
    context,
    account: ref.read(activeAccountIdProvider),
    current: current,
    title: title,
    hint: hint,
  );

  Future<void> _pickSeries() async {
    final picked = await _pick(_sources, 'Channels for the whole series', 'Their videos are sorted into seasons and episodes by names like “S02E03” or “Season 2 Episode 3”.');
    if (picked != null) setState(() => _sources = picked);
  }

  Future<void> _pickSeason(int i) async {
    final s = _seasons[i];
    final picked = await _pick(s.sources, 'Channels for season ${s.number}', 'Their videos become this season’s episodes, in the order they were posted (or by the episode number they name).');
    if (picked != null) setState(() => _seasons[i] = s.copyWith(sources: picked));
  }

  void _addSeason() {
    final next = _seasons.fold<int>(0, (a, s) => s.number > a ? s.number : a) + 1;
    setState(() => _seasons = [..._seasons, CustomSeason(number: next)]);
  }

  Future<void> _renameSeason(int i) async {
    final s = _seasons[i];
    final c = TextEditingController(text: s.name);
    final number = TextEditingController(text: '${s.number}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Season ${s.number}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: number, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number')),
            const SizedBox(height: Space.m),
            TextField(controller: c, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'e.g. The Final Season')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      final n = int.tryParse(number.text.trim());
      setState(() => _seasons[i] = s.copyWith(name: c.text.trim(), number: n != null && n > 0 && _seasons.every((x) => x == s || x.number != n) ? n : s.number));
    }
    c.dispose();
    number.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final seasons = [..._seasons]..sort((a, b) => a.number.compareTo(b.number));
    final base = widget.series;
    final series = base == null
        ? CustomSeries(id: const Uuid().v4(), name: name, year: int.tryParse(_year.text.trim()), sources: _sources, seasons: seasons, createdAt: DateTime.now(), poster: _poster, posterPath: _posterPath)
        : base.copyWith(name: name, year: int.tryParse(_year.text.trim()), clearYear: _year.text.trim().isEmpty, sources: _sources, seasons: seasons, poster: _poster, posterPath: _posterPath);
    await ref.read(cinemaProvider.notifier).saveSeries(series);
    // Reads the channels it uses.
    unawaited(ref.read(videoFeedProvider.notifier).loadAll(series.allSources));
    if (mounted) Navigator.pop(context, series.key);
  }

  Future<void> _delete() async {
    final s = widget.series;
    if (s == null) return;
    if (!await confirmDelete(context, title: 'Delete “${s.name}”?', message: 'Only the series goes; its videos stay in their channels.')) return;
    await ref.read(cinemaProvider.notifier).deleteSeries(s.id);
    // The title page under this closes too.
    if (mounted) Navigator.pop(context, seriesDeleted);
  }

  Widget _channels(List<SourceRef> sources, VoidCallback onAdd, void Function(SourceRef) onRemove, {required String empty}) {
    final feed = ref.watch(videoFeedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: Text(empty, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
          ),
        for (final s in sources)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                TgAvatar(chatId: s.chatId, title: s.title, size: 30, accountId: s.account),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        feed.loading.contains(s.key) ? 'Loading…' : '${feed.bySource[s.key]?.length ?? 0}${feed.hasMore(s.key) ? '+' : ''} videos',
                        style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                      ),
                    ],
                  ),
                ),
                IconButton(visualDensity: VisualDensity.compact, tooltip: 'Remove', icon: Icon(Icons.close_rounded, size: 18, color: AppColors.text3), onPressed: () => onRemove(s)),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: Text(sources.isEmpty ? 'Pick channels' : 'Change channels')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.series != null;
    Widget card({required Widget child}) => Container(
      margin: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      child: child,
    );
    Widget heading(String t, [String? sub]) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: context.text.labelSmall),
          if (sub != null) Text(sub, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit series' : 'New series'),
        actions: [
          if (editing) IconButton(tooltip: 'Delete series', icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger), onPressed: _delete),
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: FilledButton(onPressed: _name.text.trim().isEmpty ? null : _save, child: Text(editing ? 'Save' : 'Create')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: Space.m, bottom: Space.x4),
        children: [
          card(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _name,
                    autofocus: !editing,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Series name', hintText: 'e.g. Breaking Bad'),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(child: TextField(controller: _year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Year'))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 0),
            child: Text('The poster, plot, cast and episode names are looked up by the name.', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
          ),
          heading('POSTER'),
          card(child: _posterCard()),
          heading('WHOLE SERIES', 'Channels that post every season; episodes are placed by names like “S02E03”.'),
          card(
            child: _channels(
              _sources,
              _pickSeries,
              (s) => setState(() => _sources = [for (final x in _sources) if (x.key != s.key) x]),
              empty: 'None — optional when each season has its own channels.',
            ),
          ),
          heading('SEASONS', 'A season’s channels: their videos are its episodes, in the order they were posted.'),
          for (final (i, s) in _seasons.indexed)
            card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
                        child: Text('${s.number}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Text(s.name.isEmpty ? 'Season ${s.number}' : 'Season ${s.number} · ${s.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      IconButton(visualDensity: VisualDensity.compact, tooltip: 'Rename', icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.text2), onPressed: () => _renameSeason(i)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove season',
                        icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.text3),
                        onPressed: () => setState(() => _seasons = [for (final (j, x) in _seasons.indexed) if (j != i) x]),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s),
                  _channels(
                    s.sources,
                    () => _pickSeason(i),
                    (r) => setState(() => _seasons[i] = s.copyWith(sources: [for (final x in s.sources) if (x.key != r.key) x])),
                    empty: _sources.isEmpty ? 'No channels yet.' : 'None — takes this season’s episodes from the whole-series channels.',
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _addSeason,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a season'),
            ),
          ),
        ],
      ),
    );
  }
}
