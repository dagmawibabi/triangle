import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../chat/data/chat_controller.dart';
import '../assistant/watches.dart';
import 'brief_store.dart';
import 'brief_widget.dart';
import 'home_widgets.dart';

/// Settings → Home-screen widget: the widgets there are (the brief, and
/// custom ones the person or the assistant made), which one each widget on
/// the home screen shows, and how they look, with a live preview.
class WidgetCustomizerScreen extends ConsumerStatefulWidget {
  const WidgetCustomizerScreen({super.key, this.openWidget});

  /// A widget to open straight away (a tap on it on the home screen).
  final String? openWidget;

  @override
  ConsumerState<WidgetCustomizerScreen> createState() => _WidgetCustomizerScreenState();
}

class _WidgetCustomizerScreenState extends ConsumerState<WidgetCustomizerScreen> {
  String _previewed = briefWidgetId;
  List<int> _instances = const [];
  Map<int, String> _bindings = const {};
  String _default = briefWidgetId;

  @override
  void initState() {
    super.initState();
    _loadPlacement();
    final open = widget.openWidget;
    if (open != null) {
      _previewed = open;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(homeWidgetsProvider.notifier).ready;
        final d = ref.read(homeWidgetsProvider.notifier).byId(open);
        if (d != null && mounted) await showWidgetSheet(context, d.id);
      });
    }
  }

  Future<void> _loadPlacement() async {
    final store = ref.read(homeWidgetsProvider.notifier);
    final instances = await store.instances();
    final bindings = await store.bindings();
    final fallback = await store.defaultWidget();
    if (mounted) {
      setState(() {
        _instances = instances;
        _bindings = bindings;
        _default = fallback;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(widgetLookProvider);
    final ctl = ref.read(widgetLookProvider.notifier);
    final defs = ref.watch(homeWidgetsProvider);
    final previewed = defs.where((d) => d.id == _previewed).firstOrNull ?? defs.first;
    final brief = ref.watch(briefStoreProvider).briefs.where((b) => b.error == null && b.text.isNotEmpty).firstOrNull;
    final briefText = brief == null
        ? 'TL;DR: three people are waiting on you, the team moved Friday\'s meeting to 10:00, and a delivery arrives today.\n\n'
              '🔴 Liya asked whether you can review the budget by tonight. Dawit wants the slides.'
        : BriefHomeWidget.forWidget(brief.text, look.content, null);
    final previewItems = previewed.isBrief
        ? [
            for (final p in briefText.split(RegExp(r'\n\s*\n')))
              if (p.trim().isNotEmpty) WidgetItem(text: p.trim()),
          ]
        : previewed.items;

    Widget section(String title, List<Widget> children, {String? note}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
          child: Text(
            note == null ? title.toUpperCase() : '${title.toUpperCase()} · $note',
            style: context.text.labelSmall,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        ),
      ],
    );

    Widget slider(String label, double value, double min, double max, int divisions, String shown, ValueChanged<double> onChanged) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Text(label, style: context.text.titleSmall), const Spacer(), Text(shown, style: context.text.labelSmall)]),
          Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: shown, onChanged: onChanged),
        ],
      ),
    );

    String nameOf(String id) => defs.where((d) => d.id == id).firstOrNull?.title ?? 'Brief';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home-screen widgets'),
        actions: [
          IconButton(
            tooltip: 'Reset the look',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => ctl.update((_) => WidgetLook(accent: AppColors.activeAccent.toARGB32())),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
            children: [
              if (defs.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.m),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final d in defs)
                        ChoiceChip(
                          label: Text(d.title),
                          selected: d.id == previewed.id,
                          onSelected: (_) => setState(() => _previewed = d.id),
                        ),
                    ],
                  ),
                ),
              // On a wallpaper-ish backdrop, as on the home screen.
              Container(
                padding: const EdgeInsets.all(Space.xl),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xl),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3A4E7A), Color(0xFF7A4E6A), Color(0xFFC08A5A)],
                  ),
                ),
                child: WidgetPreview(
                  look: look,
                  title: previewed.isBrief ? (brief == null ? '☀️ Morning brief' : '${brief.kind.emoji} ${brief.kind.label}') : previewed.title,
                  when: previewed.isBrief
                      ? (brief == null ? 'Sat 24 Oct, 08:00' : DateFormat('EEE d MMM, HH:mm').format(brief.at))
                      : (previewed.updatedAt == null ? '' : DateFormat('EEE d MMM, HH:mm').format(previewed.updatedAt!)),
                  items: previewItems,
                  full: previewed.isBrief,
                  empty: previewed.byAssistant ? 'The assistant fills this in on its next refresh.' : 'Nothing here yet.',
                ),
              ),
              if (Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xs, Space.m, Space.xs, 0),
                  child: Text(
                    'Add one from your home screen: long-press an empty spot → Widgets → Triangle. Each one scrolls, '
                    'and you choose below what it shows.',
                    style: context.text.bodySmall,
                  ),
                ),
              section('Your widgets', [
                for (final d in defs) ...[
                  ListTile(
                    leading: lead(Icon(d.isBrief ? Icons.wb_sunny_outlined : d.byAssistant ? Icons.auto_awesome_outlined : Icons.notes_rounded)),
                    title: Text(d.title),
                    subtitle: Text(
                      d.isBrief
                          ? 'Your latest brief · built in'
                          : [
                              d.byAssistant ? 'Refreshed by the assistant every ${d.everyHours ?? 6} h' : 'Your text',
                              '${d.items.length} row${d.items.length == 1 ? '' : 's'}',
                            ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () => showWidgetSheet(context, d.id),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: lead(const Icon(Icons.add_rounded)),
                  title: const Text('New widget'),
                  subtitle: Text(
                    'Something the assistant keeps up to date (subscribers, news, movies with posters), or your own text. '
                    'You can also ask in chat: "make a widget with the latest tech news".',
                    style: context.text.bodySmall,
                  ),
                  onTap: () async {
                    final made = await showFormSheet<String>(context, builder: (_) => const _NewWidgetSheet());
                    if (made != null && mounted) setState(() => _previewed = made);
                  },
                ),
              ]),
              if (Platform.isAndroid)
                section('On your home screen', note: _instances.isEmpty ? 'none added yet' : '${_instances.length}', [
                  for (final (i, id) in _instances.indexed) ...[
                    ListTile(
                      leading: lead(const Icon(Icons.widgets_outlined)),
                      title: Text('Widget ${i + 1}'),
                      subtitle: Text('Shows ${nameOf(_bindings[id] ?? _default)}', style: context.text.bodySmall),
                      trailing: Icon(Icons.unfold_more_rounded, color: AppColors.text3),
                      onTap: () async {
                        final picked = await _pick(context, defs, _bindings[id] ?? _default, 'Widget ${i + 1} shows');
                        if (picked == null) return;
                        await ref.read(homeWidgetsProvider.notifier).bind(id, picked);
                        await _loadPlacement();
                      },
                    ),
                    const Divider(height: 1),
                  ],
                  ListTile(
                    leading: lead(const Icon(Icons.add_to_home_screen_outlined)),
                    title: const Text('Newly added widgets show'),
                    subtitle: Text(nameOf(_default), style: context.text.bodySmall),
                    trailing: Icon(Icons.unfold_more_rounded, color: AppColors.text3),
                    onTap: () async {
                      final picked = await _pick(context, defs, _default, 'New widgets show');
                      if (picked == null) return;
                      await ref.read(homeWidgetsProvider.notifier).setDefault(picked);
                      await _loadPlacement();
                    },
                  ),
                ]),
              section('Text', [
                slider('Text size', look.fontSize, 9, 20, 22, '${look.fontSize.toStringAsFixed(1)} sp', (v) => ctl.update((l) => l.copyWith(fontSize: (v * 2).round() / 2))),
                slider('Title size', look.titleSize, 10, 24, 28, '${look.titleSize.toStringAsFixed(1)} sp', (v) => ctl.update((l) => l.copyWith(titleSize: (v * 2).round() / 2))),
                slider('Lines per row (custom widgets)', look.maxLines.toDouble(), 2, 30, 28, '${look.maxLines}', (v) => ctl.update((l) => l.copyWith(maxLines: v.round()))),
                const SizedBox(height: Space.s),
              ]),
              section('Content', [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs),
                  child: Text('How much of the brief', style: context.text.titleSmall),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<WidgetContent>(
                      showSelectedIcon: false,
                      segments: [for (final c in WidgetContent.values) ButtonSegment(value: c, label: Text(c.label))],
                      selected: {look.content},
                      onSelectionChanged: (v) => ctl.update((l) => l.copyWith(content: v.first)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
                  child: Text(look.content.explanation, style: context.text.bodySmall),
                ),
                SwitchListTile(
                  title: const Text('Pictures'),
                  subtitle: Text('Images in custom widgets\' rows', style: context.text.bodySmall),
                  value: look.showImages,
                  onChanged: (v) => ctl.update((l) => l.copyWith(showImages: v)),
                ),
                SwitchListTile(
                  title: const Text('Title'),
                  value: look.showTitle,
                  onChanged: (v) => ctl.update((l) => l.copyWith(showTitle: v)),
                ),
                SwitchListTile(
                  title: const Text('When it was updated'),
                  value: look.showTime,
                  onChanged: (v) => ctl.update((l) => l.copyWith(showTime: v)),
                ),
                SwitchListTile(
                  title: const Text('"Open Triangle" line'),
                  value: look.showFooter,
                  onChanged: (v) => ctl.update((l) => l.copyWith(showFooter: v)),
                ),
              ]),
              section('Background', [
                Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      for (final t in WidgetTheme.values)
                        ChoiceChip(
                          avatar: CircleAvatar(
                            radius: 8,
                            backgroundColor: Color(t == WidgetTheme.accent ? AppColors.activeAccent.toARGB32() : t.background),
                          ),
                          label: Text(t.label),
                          selected: look.theme == t,
                          onSelected: (_) => ctl.update(
                            (l) => l.copyWith(theme: t, accent: t == WidgetTheme.accent ? AppColors.activeAccent.toARGB32() : null),
                          ),
                        ),
                    ],
                  ),
                ),
                slider('Opacity', look.opacity.toDouble(), 0, 100, 20, '${look.opacity}%', (v) => ctl.update((l) => l.copyWith(opacity: v.round()))),
                const SizedBox(height: Space.s),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// Picks one of [defs] in a sheet.
  Future<String?> _pick(BuildContext context, List<HomeWidgetDef> defs, String current, String title) => showFormSheet<String>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: sheet.text.titleMedium),
        const SizedBox(height: Space.m),
        for (final d in defs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(d.id == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
            title: Text(d.title),
            onTap: () => Navigator.pop(sheet, d.id),
          ),
      ],
    ),
  );
}

/// A widget as the launcher draws it: a header and rows that scroll.
class WidgetPreview extends StatelessWidget {
  const WidgetPreview({
    super.key,
    required this.look,
    required this.title,
    required this.when,
    required this.items,
    required this.empty,
    this.full = false,
  });
  final WidgetLook look;

  /// The brief: rows shown whole, as on the home screen.
  final bool full;
  final String title;
  final String when;
  final List<WidgetItem> items;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final body = Color(look.theme.body);
    return Container(
      height: 280,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color(look.background).withValues(alpha: look.opacity / 100),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (look.showTitle || look.showTime)
            Row(
              children: [
                if (look.showTitle)
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(look.theme.title), fontSize: look.titleSize, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  const Spacer(),
                if (look.showTime && when.isNotEmpty) Text(when, style: TextStyle(color: body, fontSize: 11)),
              ],
            ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Text(empty, style: TextStyle(color: body, fontSize: look.fontSize, height: 1.3))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, i) => _PreviewRow(item: items[i], look: look, full: full),
                  ),
          ),
          if (look.showFooter) ...[
            const SizedBox(height: 6),
            Text('Open Triangle ›', style: TextStyle(color: body, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item, required this.look, this.full = false});
  final WidgetItem item;
  final WidgetLook look;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final body = Color(look.theme.body);
    final image = item.imagePath == null || !look.showImages ? null : File(item.imagePath!);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null && image.existsSync())
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Image.file(image, width: double.infinity, fit: BoxFit.cover),
                ),
              ),
            ),
          if (item.title.isNotEmpty)
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Color(look.theme.title), fontSize: look.fontSize + 0.5, fontWeight: FontWeight.bold),
            ),
          if (item.text.isNotEmpty)
            Text(
              item.text,
              maxLines: full ? null : look.maxLines,
              overflow: full ? null : TextOverflow.ellipsis,
              style: TextStyle(color: body, fontSize: look.fontSize, height: 1.3),
            ),
          if (item.subtitle.isNotEmpty) Text(item.subtitle, maxLines: 1, style: TextStyle(color: body.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }
}

/// Rows from text: a blank line starts a new row; a row's first line ending
/// in ":" is its title, and a line that is an https link to a picture is its
/// image (any other link is what a tap opens).
List<WidgetItem> parseWidgetText(String text) => [
  for (final block in text.split(RegExp(r'\n\s*\n')))
    if (block.trim().isNotEmpty) _row(block.trim()),
];

WidgetItem _row(String block) {
  final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  String? image, link, local;
  var title = '';
  final text = <String>[];
  for (final (i, l) in lines.indexed) {
    final uri = Uri.tryParse(l);
    if (uri != null && uri.scheme == 'file') {
      // A picture from the gallery, kept on this phone.
      local ??= uri.toFilePath();
    } else if (uri != null && uri.scheme == 'https' && !l.contains(' ')) {
      if (RegExp(r'\.(png|jpe?g|webp|gif)(\?.*)?$', caseSensitive: false).hasMatch(uri.path) || l.contains('image')) {
        image ??= l;
      } else {
        link ??= l;
      }
    } else if (i == 0 && l.endsWith(':') && lines.length > 1) {
      title = l.substring(0, l.length - 1);
    } else {
      text.add(l);
    }
  }
  return WidgetItem(title: title, text: text.join('\n'), imageUrl: image, imagePath: image == null ? local : null, link: link);
}

/// [items] back as editable text, the way [parseWidgetText] reads it.
String widgetText(List<WidgetItem> items) => [
  for (final i in items)
    [
      if (i.title.isNotEmpty) '${i.title}:',
      if (i.text.isNotEmpty) i.text,
      if (i.imageUrl != null) i.imageUrl! else if (i.imagePath != null) Uri.file(i.imagePath!).toString(),
      ?i.link,
    ].join('\n'),
].join('\n\n');

/// One widget: what it shows, and changing, refreshing or deleting it.
Future<void> showWidgetSheet(BuildContext context, String id) =>
    showAppSheet<void>(context, initialSize: 0.8, builder: (context, scroll) => _WidgetSheet(id: id, scroll: scroll));

class _WidgetSheet extends ConsumerStatefulWidget {
  const _WidgetSheet({required this.id, required this.scroll});
  final String id;
  final ScrollController scroll;

  @override
  ConsumerState<_WidgetSheet> createState() => _WidgetSheetState();
}

class _WidgetSheetState extends ConsumerState<_WidgetSheet> {
  late final HomeWidgetDef? _start = ref.read(homeWidgetsProvider.notifier).byId(widget.id);
  late final _title = TextEditingController(text: _start?.title ?? '');
  late final _prompt = TextEditingController(text: _start?.prompt ?? '');
  late final _text = TextEditingController(text: widgetText(_start?.items ?? const []));
  late int _every = _start?.everyHours ?? 6;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(HomeWidgetDef d) async {
    setState(() => _busy = true);
    final store = ref.read(homeWidgetsProvider.notifier);
    try {
      if (d.byAssistant) {
        await store.edit(d.id, title: _title.text, prompt: _prompt.text.trim().isEmpty ? d.prompt : _prompt.text, everyHours: _every);
      } else {
        await store.edit(d.id, title: _title.text);
        await store.setItems(d.id, parseWidgetText(_text.text), note: 'Edited by you');
      }
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Saved ${_title.text.trim().isEmpty ? d.title : _title.text.trim()}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A picture from the gallery as a new row (rows typed so far are kept).
  Future<void> _addPicture(HomeWidgetDef d) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final store = ref.read(homeWidgetsProvider.notifier);
      await store.setItems(d.id, parseWidgetText(_text.text));
      final updated = await store.addPicture(d.id, File(picked.path));
      if (updated != null && mounted) _text.text = widgetText(updated.items);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh(HomeWidgetDef d) async {
    ref.read(homeWidgetsProvider.notifier).refreshNow(d.id);
    showSnack(context, 'Refreshing ${d.title}: the widget updates when the assistant is done.');
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(homeWidgetsProvider).where((x) => x.id == widget.id).firstOrNull;
    if (d == null) return const SizedBox.shrink();
    final look = ref.watch(widgetLookProvider);
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      children: [
        Text(d.title, style: context.text.titleMedium),
        Text(
          d.isBrief
              ? 'Built in: your latest brief. Change how much of it shows under Content.'
              : d.byAssistant
              ? 'The assistant refreshes it every ${d.everyHours ?? 6} hours${d.updatedAt == null ? '' : ' · updated ${DateFormat('d MMM HH:mm').format(d.updatedAt!)}'}.'
              : 'Your own text.',
          style: context.text.bodySmall,
        ),
        if (!d.isBrief) ...[
          const SizedBox(height: Space.l),
          WidgetPreview(
            look: look,
            title: d.title,
            when: d.updatedAt == null ? '' : DateFormat('EEE d MMM, HH:mm').format(d.updatedAt!),
            items: d.items,
            empty: d.byAssistant ? 'The assistant fills this in on its next refresh.' : 'Nothing here yet.',
          ),
          const SizedBox(height: Space.l),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: Space.m),
          if (d.byAssistant) ...[
            TextField(
              controller: _prompt,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'What it shows', hintText: 'The five newest movies in cinemas, with posters'),
            ),
            const SizedBox(height: Space.m),
            Text('REFRESH', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final h in const [1, 3, 6, 12, 24, 72])
                  ChoiceChip(
                    label: Text(h < 24 ? 'Every $h h' : h == 24 ? 'Daily' : 'Every 3 days'),
                    selected: _every == h,
                    onSelected: (_) => setState(() => _every = h),
                  ),
              ],
            ),
          ] else ...[
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Rows',
                helperText: 'A blank line starts a new row. "Title:" on a row\'s first line makes it bold; a picture link '
                    '(or a file:// line from "Add a picture") shows the picture, any other link opens on tap.',
                helperMaxLines: 4,
              ),
            ),
            const SizedBox(height: Space.s),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _addPicture(d),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Add a picture from the gallery'),
              ),
            ),
          ],
          const SizedBox(height: Space.l),
          Row(
            children: [
              if (d.byAssistant) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _refresh(d),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh now'),
                  ),
                ),
                const SizedBox(width: Space.s),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _save(d),
                  child: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Text('IN THE ROWS', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          SettingsCardLike(
            children: [
              SwitchListTile(
                title: const Text('Pictures'),
                subtitle: Text('Images in its rows', style: context.text.bodySmall),
                value: d.showImages,
                onChanged: (v) => ref.read(homeWidgetsProvider.notifier).setOptions(d.id, showImages: v),
              ),
              SwitchListTile(
                title: const Text('Link previews'),
                subtitle: Text('A row with a link gets its page\'s title, summary and picture', style: context.text.bodySmall),
                value: d.linkPreviews,
                onChanged: (v) => ref.read(homeWidgetsProvider.notifier).setOptions(d.id, linkPreviews: v),
              ),
              SwitchListTile(
                title: const Text('Tap opens the link'),
                subtitle: Text('Off, tapping a row opens Triangle', style: context.text.bodySmall),
                value: d.openLinks,
                onChanged: (v) => ref.read(homeWidgetsProvider.notifier).setOptions(d.id, openLinks: v),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(child: Text(d.runs.isEmpty ? 'HISTORY' : 'HISTORY · ${d.runs.length}', style: context.text.labelSmall)),
              if (d.watchId != null && ref.watch(watchStoreProvider.notifier).byId(d.watchId!)?.conversationId != null)
                TextButton(
                  onPressed: () {
                    final id = ref.read(watchStoreProvider.notifier).byId(d.watchId!)!.conversationId!;
                    ref.read(chatControllerProvider.notifier).open(id);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  child: const Text('Open its chat'),
                ),
            ],
          ),
          const SizedBox(height: Space.s),
          if (d.runs.isEmpty)
            Text(
              d.byAssistant ? 'No refreshes yet. The first one starts when the widget is made.' : 'No changes yet.',
              style: context.text.bodySmall,
            )
          else
            SettingsCardLike(
              children: [
                for (final (i, r) in d.runs.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: lead(Icon(
                      r.ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                      color: r.ok ? AppColors.success : AppColors.warning,
                      size: 20,
                    )),
                    title: Text(DateFormat('EEE d MMM, HH:mm').format(r.at)),
                    subtitle: Text(r.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ),
                ],
              ],
            ),
          const SizedBox(height: Space.l),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () async {
              if (!await confirmDelete(
                context,
                title: 'Delete ${d.title}?',
                message: 'Home-screen widgets showing it go back to the brief${d.byAssistant ? ', and its refresh stops' : ''}.',
              )) {
                return;
              }
              await ref.read(homeWidgetsProvider.notifier).remove(d.id);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete widget'),
          ),
        ],
      ],
    );
  }
}

/// Makes a widget: one the assistant keeps up to date, or the person's text.
class _NewWidgetSheet extends ConsumerStatefulWidget {
  const _NewWidgetSheet();

  @override
  ConsumerState<_NewWidgetSheet> createState() => _NewWidgetSheetState();
}

class _NewWidgetSheetState extends ConsumerState<_NewWidgetSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _assistant = true;
  int _every = 6;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_body.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final store = ref.read(homeWidgetsProvider.notifier);
    final d = await store.create(
      title: _title.text,
      prompt: _assistant ? _body.text : '',
      everyHours: _assistant ? _every : null,
      items: _assistant ? const [] : parseWidgetText(_body.text),
    );
    // The store runs its first refresh right away.
    if (mounted) {
      Navigator.pop(context, d.id);
      showSnack(context, _assistant ? 'Made ${d.title}: the assistant is filling it in.' : 'Made ${d.title}');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('New widget', style: context.text.titleMedium),
      const SizedBox(height: Space.l),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, label: Text('Kept up to date')),
          ButtonSegment(value: false, label: Text('My text')),
        ],
        selected: {_assistant},
        onSelectionChanged: (v) => setState(() => _assistant = v.first),
      ),
      const SizedBox(height: Space.m),
      TextField(
        controller: _title,
        decoration: InputDecoration(labelText: 'Title', hintText: _assistant ? 'New movies' : 'Shopping list'),
      ),
      const SizedBox(height: Space.s),
      TextField(
        controller: _body,
        minLines: 3,
        maxLines: 10,
        decoration: InputDecoration(
          labelText: _assistant ? 'What it shows' : 'Rows',
          hintText: _assistant
              ? 'The five newest movies in cinemas, each with its poster and a one-line plot'
              : 'Milk\n\nBread\n\nCoffee',
          helperText: _assistant
              ? 'The assistant looks it up with its tools (web, your apps) and fills the rows, with pictures if useful.'
              : 'A blank line starts a new row. A picture link shows the picture.',
          helperMaxLines: 3,
        ),
      ),
      if (_assistant) ...[
        const SizedBox(height: Space.m),
        Text('REFRESH', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final h in const [1, 3, 6, 12, 24])
              ChoiceChip(
                label: Text(h < 24 ? 'Every $h h' : 'Daily'),
                selected: _every == h,
                onSelected: (_) => setState(() => _every = h),
              ),
          ],
        ),
      ],
      const SizedBox(height: Space.l),
      FilledButton(
        onPressed: _busy ? null : _create,
        child: _busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Create widget'),
      ),
    ],
  );
}

/// A rounded, bordered group of rows inside a sheet.
class SettingsCardLike extends StatelessWidget {
  const SettingsCardLike({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface2.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(type: MaterialType.transparency, child: Column(children: children)),
  );
}
