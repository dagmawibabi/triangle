import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/code_highlight.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../assistant/presentation/watches_screen.dart';
import '../../../assistant/watches.dart';
import '../../../canvas/canvas_store.dart';
import '../../../settings/data/settings.dart';
import '../../../telegram/presentation/content_canvas_screen.dart';
import '../../domain/chat_models.dart';

/// Cards for the assistant's own workspace: code it ran on the phone, the
/// Content Canvas, watches, and YouTube transcripts.
Widget? workspaceResultFor(ToolPart part, Map<String, dynamic> j) {
  Map<String, dynamic> args() {
    try {
      return Map<String, dynamic>.from(jsonDecode(part.arguments) as Map);
    } catch (_) {
      return const {};
    }
  }

  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  final name = part.name;
  if (name == 'run_code') return _CodeCard(args: args(), result: j);
  if (name.startsWith('canvas_')) {
    if (j['error'] != null) return null;
    return switch (name) {
      'canvas_overview' => _CanvasOverview(data: j, folders: list(j['folders']), items: list(j['items'])),
      'canvas_export' => _CanvasExport(data: j),
      _ => _CanvasDone(tool: name, data: j, args: args()),
    };
  }
  if (j['error'] != null) return null;
  return switch (name) {
    'create_watch' || 'update_watch' when j['watch_id'] != null => _WatchCard(data: j, created: name == 'create_watch'),
    'list_watches' => _WatchList(watches: list(j['watches']), proactive: j['proactivity_on'] != false),
    'delete_watch' when j['deleted'] == true => _Done(icon: Icons.visibility_off_outlined, title: 'Watch deleted', detail: 'It won\'t run again.'),
    'youtube_transcript' when j['transcript'] is String => _TranscriptCard(data: j),
    _ => null,
  };
}

// ---- shared ---------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.children, this.danger = false});
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: danger ? AppColors.danger.withValues(alpha: 0.5) : AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

class _Head extends StatelessWidget {
  const _Head({required this.icon, required this.title, this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.s),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s + 2), border: Border.all(color: AppColors.line)),
          child: Icon(icon, size: 17, color: AppColors.text),
        ),
        const SizedBox(width: Space.s + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.25))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
          Text(text, style: context.text.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.s, Space.xs),
    child: Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600))),
        ?trailing,
      ],
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
    padding: const EdgeInsets.fromLTRB(Space.s, 2, Space.s, 2),
    child: Row(children: children),
  );
}

Widget _button(IconData icon, String label, VoidCallback onTap) => TextButton.icon(
  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text),
  onPressed: onTap,
  icon: Icon(icon, size: 16),
  label: Text(label),
);

/// A one-line outcome: done, with what and where.
class _Done extends StatelessWidget {
  const _Done({required this.icon, required this.title, this.detail, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? detail;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      InkWell(
        onTap: onAction,
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: AppColors.bg),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (detail != null && detail!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(detail!, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: Space.s),
                Text(action!, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text2),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

// ---- run_code ---------------------------------------------------------------------

class _CodeCard extends ConsumerStatefulWidget {
  const _CodeCard({required this.args, required this.result});
  final Map<String, dynamic> args;
  final Map<String, dynamic> result;

  @override
  ConsumerState<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends ConsumerState<_CodeCard> {
  bool _code = false;
  bool _output = false;

  @override
  Widget build(BuildContext context) {
    final j = widget.result;
    final theme = ref.watch(settingsProvider.select((s) => s.codeTheme));
    final code = '${widget.args['code'] ?? ''}'.trimRight();
    final language = '${widget.args['language'] ?? 'python'}';
    final output = '${j['output'] ?? ''}'.trimRight();
    final error = j['error'] is String ? '${j['error']}'.trimRight() : null;
    final result = j['result'];
    final files = [for (final f in (j['created_files'] as List? ?? const [])) '$f'];
    final images = files.where((f) => RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false).hasMatch(f) && File(f).existsSync()).toList();
    final others = files.where((f) => !images.contains(f)).toList();
    final lines = code.isEmpty ? 0 : code.split('\n').length;
    final outLines = output.split('\n').length;
    final lang = language.isEmpty ? 'Code' : language[0].toUpperCase() + language.substring(1);
    return _Card(
      danger: error != null,
      children: [
        _Head(
          icon: Icons.terminal_rounded,
          title: '$lang on this phone',
          subtitle: [if (lines > 0) '$lines line${lines == 1 ? '' : 's'}', if (files.isNotEmpty) '${files.length} file${files.length == 1 ? '' : 's'} made'].join(' · '),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Pill(error == null ? 'Ran' : 'Error', icon: error == null ? Icons.check_rounded : Icons.close_rounded, color: error == null ? AppColors.success : AppColors.danger),
              if (code.isNotEmpty)
                IconButton(
                  tooltip: 'Copy code',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.copy_rounded, size: 16, color: AppColors.text2),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    showSnack(context, 'Code copied');
                  },
                ),
            ],
          ),
        ),
        if (code.isNotEmpty)
          InkWell(
            onTap: lines > 8 ? () => setState(() => _code = !_code) : null,
            child: Container(
              margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HighlightedCode(code: code, language: language, theme: theme, maxLines: _code ? null : 8),
                  if (lines > 8)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Text(_code ? 'Show less' : 'Show all $lines lines', style: context.text.labelSmall?.copyWith(color: AppColors.text2, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
        if (output.isNotEmpty) ...[
          _Label(
            'Output',
            trailing: IconButton(
              tooltip: 'Copy output',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_rounded, size: 14, color: AppColors.text3),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: output));
                showSnack(context, 'Output copied');
              },
            ),
          ),
          InkWell(
            onTap: outLines > 12 ? () => setState(() => _output = !_output) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(output, maxLines: _output ? null : 12, overflow: TextOverflow.fade, style: codeTextStyle.copyWith(fontSize: 12.5, color: AppColors.text2)),
                  if (outLines > 12)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Text(_output ? 'Show less' : 'Show all $outLines lines', style: context.text.labelSmall?.copyWith(color: AppColors.text2, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (result != null && '$result'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_forward_rounded, size: 15, color: AppColors.text3),
                const SizedBox(width: 6),
                Expanded(child: SelectableText(result is String ? result : const JsonEncoder.withIndent('  ').convert(result), style: codeTextStyle.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        if (error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.danger.withValues(alpha: 0.3))),
            child: Text(error, maxLines: 14, overflow: TextOverflow.fade, style: codeTextStyle.copyWith(fontSize: 12, color: AppColors.danger)),
          ),
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
            child: Column(
              children: [
                for (final img in images)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s),
                    child: GestureDetector(
                      onTap: () => OpenFilex.open(img),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.m),
                        child: Container(color: Colors.white, child: Image.file(File(img), fit: BoxFit.contain, width: double.infinity)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final f in others)
                  ActionChip(
                    avatar: Icon(Icons.insert_drive_file_outlined, size: 15, color: AppColors.text2),
                    label: Text(f.split(RegExp(r'[\\/]')).last),
                    onPressed: () => OpenFilex.open(f),
                  ),
              ],
            ),
          ),
        if (output.isEmpty && error == null && result == null && files.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Text('Ran without printing anything.', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
          ),
      ],
    );
  }
}

// ---- canvas ---------------------------------------------------------------------

IconData _canvasKindIcon(String kind) => switch (kind) {
  'post' => Icons.campaign_outlined,
  'message' => Icons.chat_bubble_outline_rounded,
  'comment' => Icons.mode_comment_outlined,
  'note' => Icons.sticky_note_2_outlined,
  'link' => Icons.link_rounded,
  'email' => Icons.mail_outline_rounded,
  'file' => Icons.insert_drive_file_outlined,
  'app' => Icons.apps_rounded,
  _ => Icons.bookmark_border_rounded,
};

/// The canvas's folders as a tree, and a folder's items when one was asked.
class _CanvasOverview extends ConsumerWidget {
  const _CanvasOverview({required this.data, required this.folders, required this.items});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> folders;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = folders.fold<int>(0, (n, f) => n + ((f['items'] as num?)?.toInt() ?? 0));
    final opened = data['folder'] is String ? '${data['folder']}' : null;
    final openedId = opened == null ? null : folders.where((f) => f['path'] == opened).firstOrNull?['folder_id'];
    final sorted = [...folders]..sort((a, b) => '${a['path']}'.toLowerCase().compareTo('${b['path']}'.toLowerCase()));
    return _Card(
      children: [
        _Head(
          icon: Icons.dashboard_customize_outlined,
          title: opened ?? 'Content Canvas',
          subtitle: opened != null ? '${items.length} item${items.length == 1 ? '' : 's'}' : '${folders.length} folder${folders.length == 1 ? '' : 's'} · $total item${total == 1 ? '' : 's'}',
        ),
        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Text('The canvas is empty. Ask to save posts, links or notes into a folder.', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
          ),
        if (opened == null)
          for (final f in sorted.take(12))
            _FolderRow(folder: f, onTap: () => _push(context, ContentCanvasScreen(folderId: '${f['folder_id']}'))),
        if (opened == null && sorted.length > 12)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Text('and ${sorted.length - 12} more', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          ),
        if (opened != null)
          for (final (i, item) in items.take(8).indexed) ...[
            if (i > 0) Divider(height: 1, indent: Space.m, endIndent: Space.m, color: AppColors.line),
            _CanvasItemRow(item: item),
          ],
        if (opened != null && items.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
            child: Text('and ${items.length - 8} more', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          ),
        _Footer(
          children: [
            const Spacer(),
            _button(Icons.open_in_new_rounded, opened == null ? 'Open canvas' : 'Open folder', () => _push(context, ContentCanvasScreen(folderId: openedId == null ? null : '$openedId'))),
          ],
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder, required this.onTap});
  final Map<String, dynamic> folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = '${folder['path']}'.split(' / ');
    final depth = path.length - 1;
    final count = (folder['items'] as num?)?.toInt() ?? 0;
    final description = '${folder['description'] ?? ''}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.m + depth * 18.0, 7, Space.m, 7),
        child: Row(
          children: [
            if (depth > 0) ...[Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: AppColors.text3), const SizedBox(width: 4)],
            Icon(count == 0 ? Icons.folder_outlined : Icons.folder_rounded, size: 18, color: AppColors.text2),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(path.last, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (description.isNotEmpty) Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
              child: Text('$count', style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasItemRow extends StatelessWidget {
  const _CanvasItemRow({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final kind = '${item['kind'] ?? ''}';
    final who = [if (item['chat'] != null) '${item['chat']}', if (item['sender'] != null && item['sender'] != item['chat']) '${item['sender']}'].join(' · ');
    final note = '${item['note'] ?? ''}';
    final tags = [for (final t in (item['tags'] as List? ?? const [])) '$t'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
            child: Icon(_canvasKindIcon(kind), size: 15, color: AppColors.text2),
          ),
          const SizedBox(width: Space.s + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (who.isNotEmpty) Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('${item['text'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.35)),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('“$note”', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: AppColors.text3)),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 4, children: [for (final t in tags.take(4)) _Pill('#$t')]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a canvas change did, with the folder a tap away.
class _CanvasDone extends ConsumerWidget {
  const _CanvasDone({required this.tool, required this.data, required this.args});
  final String tool;
  final Map<String, dynamic> data;
  final Map<String, dynamic> args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvas = ref.watch(canvasProvider);
    final folderPath = '${data['folder'] ?? data['path'] ?? data['to'] ?? ''}';
    String? folderId = data['folder_id'] is String ? data['folder_id'] as String : null;
    folderId ??= canvas.folders.where((f) => canvas.pathOf(f) == folderPath).firstOrNull?.id;
    final count = canvas.folders.isEmpty || folderId == null ? null : canvas.itemsIn(folderId).length;
    int n(String k) => (data[k] as num?)?.toInt() ?? 0;
    final (IconData icon, String title, String detail) = switch (tool) {
      'canvas_add' => (
        Icons.bookmark_added_outlined,
        'Saved ${n('added')} message${n('added') == 1 ? '' : 's'} to $folderPath',
        [
          if (n('already_there') > 0) '${n('already_there')} already there',
          if ((data['not_found'] as List?)?.isNotEmpty ?? false) '${(data['not_found'] as List).length} not found',
          if (count != null) '$count in the folder now',
        ].join(' · '),
      ),
      'canvas_save' => (
        _canvasKindIcon('${data['kind']}'),
        'Saved ${_article('${data['kind'] ?? 'item'}')} to $folderPath',
        '${args['title'] ?? args['url'] ?? args['text'] ?? ''}'.trim(),
      ),
      'canvas_add_note' => (Icons.sticky_note_2_outlined, 'Note added to $folderPath', '${args['text'] ?? ''}'.trim()),
      'canvas_create_folder' => (Icons.create_new_folder_outlined, 'Folder ready: $folderPath', '${args['description'] ?? ''}'.trim()),
      'canvas_update_folder' => (Icons.drive_file_rename_outline_rounded, 'Folder updated: $folderPath', ''),
      'canvas_move' => (Icons.drive_file_move_outline, 'Moved ${n('moved')} item${n('moved') == 1 ? '' : 's'} to $folderPath', ''),
      'canvas_remove' => (Icons.bookmark_remove_outlined, 'Removed ${n('removed')} item${n('removed') == 1 ? '' : 's'} from the canvas', 'Nothing in Telegram changed.'),
      'canvas_delete_folder' => (
        Icons.folder_delete_outlined,
        'Deleted ${data['deleted']}',
        data['items_moved_to'] != null ? '${n('items')} items moved to ${data['items_moved_to']}' : '${n('items')} item${n('items') == 1 ? '' : 's'} removed with it',
      ),
      _ => (Icons.dashboard_customize_outlined, 'Canvas updated', ''),
    };
    final opens = tool != 'canvas_remove' && tool != 'canvas_delete_folder';
    return _Done(
      icon: icon,
      title: title,
      detail: detail,
      action: opens ? 'Open' : null,
      onAction: opens ? () => _push(context, ContentCanvasScreen(folderId: folderId)) : null,
    );
  }

  static String _article(String kind) => '${'aeiou'.contains(kind.isEmpty ? 'x' : kind[0]) ? 'an' : 'a'} $kind';
}

class _CanvasExport extends StatelessWidget {
  const _CanvasExport({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final path = '${data['file_path'] ?? ''}';
    final format = '${data['format'] ?? ''}';
    final ext = '${data['name'] ?? path}'.split('.').last.toUpperCase();
    return _Card(
      children: [
        InkWell(
          onTap: path.isEmpty ? null : () => OpenFilex.open(path),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s + 2), border: Border.all(color: AppColors.line)),
                  child: Text(ext.length > 4 ? ext.substring(0, 4) : ext, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: 0.4)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${data['name'] ?? 'Export'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        ['Canvas · ${data['exported']}', if (format.isNotEmpty) format, if (data['items'] != null) '${data['items']} items', if (data['size_kb'] != null) '${data['size_kb']} KB'].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(color: AppColors.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _Footer(
          children: [
            const Spacer(),
            _button(Icons.copy_rounded, 'Copy path', () {
              Clipboard.setData(ClipboardData(text: path));
              showSnack(context, 'Path copied');
            }),
            _button(Icons.open_in_new_rounded, 'Open', () => OpenFilex.open(path)),
          ],
        ),
      ],
    );
  }
}

// ---- watches ---------------------------------------------------------------------

/// The trigger in words: "Every 6 h", "Daily at 08:00", "Gmail · invoices".
String _trigger(Map<String, dynamic> w) {
  final scope = WatchScope.values.asNameMap()['${w['trigger']}'];
  final every = (w['every_minutes'] as num?)?.toInt();
  final chats = (w['chat_ids'] as List?)?.length ?? 0;
  return switch (scope) {
    WatchScope.schedule => w['daily_at'] != null ? 'Daily at ${w['daily_at']}' : (every == null ? 'On a schedule' : (every % 60 == 0 ? 'Every ${every ~/ 60} h' : 'Every $every min')),
    WatchScope.chats => '$chats chat${chats == 1 ? '' : 's'}',
    WatchScope.app => 'New in ${_cap('${w['app'] ?? 'an app'}')}${'${w['query'] ?? ''}'.isEmpty ? '' : ' · ${w['query']}'}',
    WatchScope.device => '${(w['phone_trigger'] as Map?)?['means'] ?? 'On the phone'}',
    null => '${w['trigger'] ?? ''}',
    final s => s.label,
  };
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

IconData _triggerIcon(String trigger) => switch (WatchScope.values.asNameMap()[trigger]) {
  WatchScope.schedule => Icons.schedule_rounded,
  WatchScope.app => Icons.apps_rounded,
  WatchScope.device => Icons.phone_android_rounded,
  WatchScope.mentions => Icons.alternate_email_rounded,
  WatchScope.folder => Icons.folder_outlined,
  WatchScope.allChannels => Icons.campaign_outlined,
  WatchScope.allGroups => Icons.groups_outlined,
  WatchScope.allDms => Icons.person_outline_rounded,
  _ => Icons.chat_bubble_outline_rounded,
};

/// A watch as it stands now (read live, so the switch works), with what
/// sets it off, what it does and how it has run.
class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.data, required this.created});
  final Map<String, dynamic> data;
  final bool created;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${data['watch_id']}';
    final live = ref.watch(watchStoreProvider).where((w) => w.id == id).firstOrNull;
    final w = live == null ? data : {...data, ...live.describe()};
    final mode = WatchMode.values.asNameMap()['${w['mode']}'];
    final enabled = live?.enabled ?? w['enabled'] != false;
    final instructions = '${w['instructions'] ?? ''}'.trim();
    final runs = (w['runs'] as num?)?.toInt() ?? 0;
    final last = DateTime.tryParse('${w['last_run'] ?? ''}');
    final tools = w['tools'];
    return _Card(
      children: [
        _Head(
          icon: Icons.visibility_outlined,
          title: '${w['name'] ?? 'Watch'}',
          subtitle: created ? 'New watch' : 'Watch updated',
          trailing: live == null
              ? null
              : Switch(
                  value: enabled,
                  onChanged: (v) => ref.read(watchStoreProvider.notifier).update(id, (x) => x.copyWith(enabled: v)),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _Fact(icon: _triggerIcon('${w['trigger']}'), label: 'When', value: _trigger(w))),
              const SizedBox(width: Space.s),
              Expanded(child: _Fact(icon: mode == WatchMode.act ? Icons.bolt_rounded : (mode == WatchMode.summarize ? Icons.short_text_rounded : Icons.notifications_none_rounded), label: 'Does', value: mode?.label ?? '${w['mode']}')),
            ],
          ),
          ),
        ),
        if (instructions.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
            child: Text(instructions, maxLines: 4, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.4)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Pill(enabled ? 'On' : 'Off', icon: enabled ? Icons.play_arrow_rounded : Icons.pause_rounded, color: enabled ? AppColors.success : AppColors.text3),
              _Pill(runs == 0 ? 'Not run yet' : '$runs run${runs == 1 ? '' : 's'}${last == null ? '' : ' · last ${_ago(last)}'}', icon: Icons.history_rounded),
              if (w['notify'] == false) const _Pill('Silent', icon: Icons.notifications_off_outlined),
              if (w['quiet_at_night'] == true) const _Pill('Quiet at night', icon: Icons.nightlight_outlined),
              if (w['accounts'] is List) _Pill('${(w['accounts'] as List).length} account${(w['accounts'] as List).length == 1 ? '' : 's'}', icon: Icons.person_outline_rounded),
              if (tools is List) _Pill('${tools.length} tools', icon: Icons.handyman_outlined),
              if (w['model'] != null && w['model'] != WatchModel.free) _Pill('${w['model']}', icon: Icons.auto_awesome_outlined),
            ],
          ),
        ),
        if (data['note'] != null || data['approvals'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Text('${data['note'] ?? data['approvals']}', style: context.text.labelSmall?.copyWith(color: AppColors.warning)),
          ),
        _Footer(
          children: [
            const Spacer(),
            _button(Icons.tune_rounded, 'All watches', () => _push(context, const WatchesScreen())),
          ],
        ),
      ],
    );
  }

}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s + 2),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.text2),
        const SizedBox(width: Space.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 9.5, letterSpacing: 0.6)),
              Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WatchList extends ConsumerWidget {
  const _WatchList({required this.watches, required this.proactive});
  final List<Map<String, dynamic>> watches;
  final bool proactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = {for (final w in ref.watch(watchStoreProvider)) w.id: w};
    final on = watches.where((w) => (live['${w['watch_id']}']?.enabled ?? w['enabled']) != false).length;
    return _Card(
      children: [
        _Head(icon: Icons.visibility_outlined, title: 'Watches', subtitle: '$on of ${watches.length} on'),
        if (!proactive)
          Container(
            margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            padding: const EdgeInsets.all(Space.s + 2),
            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.m)),
            child: Row(
              children: [
                Icon(Icons.pause_circle_outline_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: Space.s),
                Expanded(child: Text('Proactivity is off, so every watch is paused.', style: context.text.bodySmall?.copyWith(color: AppColors.warning))),
              ],
            ),
          ),
        if (watches.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Text('No watches yet. Ask for one, like "tell me when my boss messages".', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
          ),
        for (final (i, w) in watches.indexed) ...[
          if (i > 0) Divider(height: 1, indent: Space.m + 40, color: AppColors.line),
          _WatchRow(data: w, live: live['${w['watch_id']}']),
        ],
        _Footer(
          children: [
            const Spacer(),
            _button(Icons.tune_rounded, 'Manage', () => _push(context, const WatchesScreen())),
          ],
        ),
      ],
    );
  }
}

class _WatchRow extends ConsumerWidget {
  const _WatchRow({required this.data, required this.live});
  final Map<String, dynamic> data;
  final Watch? live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = live == null ? data : {...data, ...live!.describe()};
    final enabled = live?.enabled ?? w['enabled'] != false;
    final mode = WatchMode.values.asNameMap()['${w['mode']}'];
    final runs = (w['runs'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.xs, Space.xs),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: enabled ? AppColors.text : AppColors.surface2, shape: BoxShape.circle),
            child: Icon(_triggerIcon('${w['trigger']}'), size: 15, color: enabled ? AppColors.bg : AppColors.text3),
          ),
          const SizedBox(width: Space.s + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${w['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: enabled ? AppColors.text : AppColors.text3)),
                Text(
                  [_trigger(w), if (mode != null) mode.label, if (runs > 0) '$runs runs'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                ),
              ],
            ),
          ),
          if (live != null)
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: enabled,
                onChanged: (v) => ref.read(watchStoreProvider.notifier).update(live!.id, (x) => x.copyWith(enabled: v)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- YouTube transcript ---------------------------------------------------------------

class _TranscriptCard extends StatefulWidget {
  const _TranscriptCard({required this.data});
  final Map<String, dynamic> data;

  @override
  State<_TranscriptCard> createState() => _TranscriptCardState();
}

class _TranscriptCardState extends State<_TranscriptCard> {
  static final _line = RegExp(r'^\[(\d+(?::\d+){1,2})\]\s*(.*)$');

  /// "[1:23] text" → (seconds, "1:23", text).
  List<(int, String, String)> get _lines => [
    for (final l in '${widget.data['transcript']}'.split('\n'))
      if (_line.firstMatch(l) case final m?) (_seconds(m[1]!), m[1]!, m[2]!) else if (l.trim().isNotEmpty) (-1, '', l.trim()),
  ];

  static int _seconds(String t) => t.split(':').fold(0, (n, p) => n * 60 + (int.tryParse(p) ?? 0));

  void _open(int at) {
    final id = widget.data['video_id'];
    if (id == null) return;
    launchUrl(Uri.parse('https://www.youtube.com/watch?v=$id${at > 0 ? '&t=${at}s' : ''}'), mode: LaunchMode.externalApplication);
  }

  void _all(List<(int, String, String)> lines) => showAppSheet<void>(
    context,
    initialSize: 0.85,
    builder: (context, scroll) => ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      itemCount: lines.length + 1,
      itemBuilder: (context, i) => i == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: Space.m),
              child: Text('${widget.data['title'] ?? 'Transcript'}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            )
          : _TranscriptLine(line: lines[i - 1], onTap: () => _open(lines[i - 1].$1)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final lines = _lines;
    final id = d['video_id'];
    final secs = (d['seconds'] as num?)?.toInt();
    final words = '${d['transcript']}'.split(RegExp(r'\s+')).length;
    String clock(int s) => s >= 3600 ? '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return _Card(
      children: [
        InkWell(
          onTap: () => _open(0),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.m),
                  child: SizedBox(
                    width: 112,
                    height: 63,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        id == null ? Container(color: AppColors.surface2) : NetImage('https://i.ytimg.com/vi/$id/mqdefault.jpg', fit: BoxFit.cover),
                        Center(
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                          ),
                        ),
                        if (secs != null)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
                              child: Text(clock(secs), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
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
                      Text('${d['title'] ?? 'YouTube transcript'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                      if (d['channel'] != null) Text('${d['channel']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          _Pill('${'${d['language'] ?? ''}'.toUpperCase()}${d['auto_generated'] == true ? ' · auto' : ''}', icon: Icons.closed_caption_outlined),
                          _Pill(words < 1000 ? '$words words' : '${(words / 1000).toStringAsFixed(words >= 10000 ? 0 : 1)}k words'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xs),
          child: Column(
            children: [for (final l in lines.take(6)) _TranscriptLine(line: l, onTap: () => _open(l.$1))],
          ),
        ),
        _Footer(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Space.s),
              child: Text('${lines.length} lines', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ),
            const Spacer(),
            _button(Icons.copy_rounded, 'Copy', () {
              Clipboard.setData(ClipboardData(text: [for (final l in lines) l.$3].join(' ')));
              showSnack(context, 'Transcript copied');
            }),
            _button(Icons.subject_rounded, 'Read all', () => _all(lines)),
          ],
        ),
      ],
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({required this.line, required this.onTap});
  final (int, String, String) line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: line.$1 < 0 ? null : onTap,
    borderRadius: BorderRadius.circular(Radii.s),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(line.$2, style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
          ),
          Expanded(child: Text(line.$3, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.4))),
        ],
      ),
    ),
  );
}
