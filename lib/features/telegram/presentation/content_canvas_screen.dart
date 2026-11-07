import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../canvas/canvas_export.dart';
import '../../canvas/canvas_store.dart';
import '../../chat/data/chat_controller.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/presentation/widgets/post_viewer.dart';
import '../data/message_content.dart';
import '../data/telegram_store.dart';
import 'chat_actions.dart' show confirmAction;
import 'tg_avatar.dart';
import '../../../infrastructure/telegram/accounts.dart';

/// Exports [folder]: pick a format, then open the file or save a copy.
Future<void> showCanvasExport(BuildContext context, WidgetRef ref, CanvasFolder folder) async {
  final s = ref.read(canvasProvider);
  final hasChildren = s.childrenOf(folder.id).isNotEmpty;
  var subfolders = true;
  final format = await showModalBottomSheet<CanvasExportFormat>(
    context: context,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Export “${folder.name}”', style: c.text.titleMedium),
              const SizedBox(height: 2),
              Text(
                '${hasChildren && subfolders ? s.countDeep(folder.id) : s.itemsIn(folder.id).length} items · saved to Files',
                style: c.text.bodySmall,
              ),
              const SizedBox(height: Space.m),
              for (final (f, icon, about) in [
                (CanvasExportFormat.pdf, Icons.picture_as_pdf_outlined, 'To read, print or share'),
                (CanvasExportFormat.html, Icons.language_rounded, 'A web page, light and dark'),
                (CanvasExportFormat.markdown, Icons.notes_rounded, 'For notes apps like Obsidian'),
                (CanvasExportFormat.json, Icons.data_object_rounded, 'Everything, for other apps'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: Material(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(Radii.m),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
                      leading: lead(Icon(icon, color: AppColors.accent)),
                      title: Text(f.label),
                      subtitle: Text(about, style: c.text.bodySmall),
                      trailing: Text('.${f.extension}', style: c.text.labelSmall),
                      onTap: () => Navigator.pop(c, f),
                    ),
                  ),
                ),
              if (hasChildren)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include subfolders'),
                  value: subfolders,
                  onChanged: (v) => set(() => subfolders = v),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (format == null || !context.mounted) return;
  final File file;
  try {
    file = await exportCanvasFolder(s, folder, format, subfolders: subfolders);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Export failed: $e', icon: Icons.error_outline_rounded);
    return;
  }
  if (!context.mounted) return;
  final name = file.path.split(RegExp(r'[\\/]')).last;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 36),
            const SizedBox(height: Space.s),
            Text('Exported', style: c.text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(name, style: c.text.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: Space.l),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(c);
                OpenFilex.open(file.path);
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open'),
            ),
            const SizedBox(height: Space.s),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(c);
                final saved = await FilePicker.saveFile(
                  dialogTitle: 'Save a copy',
                  fileName: name,
                  bytes: await file.readAsBytes(),
                );
                if (saved != null && context.mounted) showSnack(context, 'Saved a copy');
              },
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save a copy…'),
            ),
          ],
        ),
      ),
    ),
  );
}

const canvasColors = [
  Color(0xFF8AB4FF),
  Color(0xFFB69CFF),
  Color(0xFF6FCF97),
  Color(0xFFF2C46D),
  Color(0xFFFF9B85),
  Color(0xFF7FD6E8),
  Color(0xFFE88FD0),
  Color(0xFFB0B8C4),
];

PostSnapshot _snapshot(WidgetRef ref, td.Message m, String chatTitle) {
  final store = ref.read(telegramStoreProvider);
  final g = gistOf(m.content);
  final chat = store.chat(m.chatId);
  final channel = chat != null && store.kindOf(chat) == ChatKind.channel;
  return PostSnapshot(
    chatId: m.chatId,
    messageId: m.id,
    chatTitle: chat?.title ?? chatTitle,
    date: DateTime.fromMillisecondsSinceEpoch(m.date * 1000),
    text: g.text.isNotEmpty ? g.text : (g.detail ?? ''),
    sender: channel ? null : (m.isOutgoing ? 'You' : store.senderName(m.senderId)),
    kind: g.kind,
    accountId: ref.read(activeAccountIdProvider),
  );
}

/// Saves one message to a folder the user picks (or makes).
Future<void> saveToCanvas(BuildContext context, WidgetRef ref, td.Message m, String chatTitle) =>
    saveManyToCanvas(context, ref, [m], chatTitle);

Future<void> saveManyToCanvas(BuildContext context, WidgetRef ref, List<td.Message> messages, String chatTitle) async {
  if (messages.isEmpty) return;
  final folder = await pickCanvasFolder(context, ref, title: 'Save ${messages.length == 1 ? 'to' : '${messages.length} to'}…');
  if (folder == null || !context.mounted) return;
  final n = await ref
      .read(canvasProvider.notifier)
      .addPosts(folder.id, [for (final m in messages) _snapshot(ref, m, chatTitle)]);
  if (context.mounted) {
    showSnack(
      context,
      n == 0 ? 'Already in ${folder.name}' : 'Saved $n to ${folder.name}',
      icon: Icons.dashboard_customize_outlined,
    );
  }
}

/// A folder picker with "New folder" at the top.
Future<CanvasFolder?> pickCanvasFolder(BuildContext context, WidgetRef ref, {String title = 'Pick a folder', String? exclude}) =>
    showModalBottomSheet<CanvasFolder>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(canvasProvider);
          final all = [...s.folders.where((f) => f.id != exclude)]..sort((a, b) => s.pathOf(a).compareTo(s.pathOf(b)));
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                    child: Text(title, style: context.text.titleMedium),
                  ),
                  ListTile(
                    leading: lead(Icon(Icons.create_new_folder_outlined, color: AppColors.accent)),
                    title: const Text('New folder'),
                    onTap: () async {
                      final name = await _askName(context, 'New folder');
                      if (name == null) return;
                      final f = await ref.read(canvasProvider.notifier).createFolder(name);
                      if (sheet.mounted) Navigator.pop(sheet, f);
                    },
                  ),
                  for (final f in all)
                    ListTile(
                      leading: lead(Icon(Icons.folder_rounded, color: canvasColors[f.color % canvasColors.length])),
                      title: Text(s.pathOf(f)),
                      trailing: Text('${s.itemsIn(f.id).length}', style: context.text.labelSmall),
                      onTap: () => Navigator.pop(sheet, f),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

Future<String?> _askName(BuildContext context, String title, {String initial = '', String hint = 'Name'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(d, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(d, c.text.trim().isEmpty ? null : c.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// The Content Canvas: folders (nested) of saved posts, messages, comments
/// and notes. [folderId] null is the top level.
class ContentCanvasScreen extends ConsumerStatefulWidget {
  const ContentCanvasScreen({super.key, this.folderId});
  final String? folderId;

  @override
  ConsumerState<ContentCanvasScreen> createState() => _ContentCanvasScreenState();
}

class _ContentCanvasScreenState extends ConsumerState<ContentCanvasScreen> {
  String _q = '';
  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(canvasProvider);
    final folder = s.folder(widget.folderId);
    final q = _q.toLowerCase().trim();
    final children = s.childrenOf(widget.folderId).where((f) => q.isEmpty || f.name.toLowerCase().contains(q)).toList();
    final items = widget.folderId == null
        ? (q.isEmpty
              ? const <CanvasItem>[]
              : s.items.where((i) => _matches(i, q)).toList())
        : s.itemsIn(widget.folderId!).where((i) => q.isEmpty || _matches(i, q)).toList();
    final store = ref.read(canvasProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(folder == null ? 'Content Canvas' : folder.name),
        actions: [
          if (_picked.isNotEmpty) ...[
            IconButton(
              tooltip: 'Move',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: () async {
                final to = await pickCanvasFolder(context, ref, title: 'Move ${_picked.length} to…', exclude: widget.folderId);
                if (to == null) return;
                await store.moveItems(_picked, to.id);
                setState(_picked.clear);
              },
            ),
            IconButton(
              tooltip: 'Remove',
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              onPressed: () async {
                if (!await confirmDelete(
                  context,
                  title: 'Remove ${_picked.length} from the canvas?',
                  message: 'Only the saved copies go. Telegram is not touched.',
                  action: 'Remove',
                )) {
                  return;
                }
                await store.removeItems(_picked);
                setState(_picked.clear);
              },
            ),
          ] else if (folder != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'rename':
                    final name = await _askName(context, 'Rename folder', initial: folder.name);
                    if (name != null) await store.updateFolder(folder.copyWith(name: name));
                  case 'describe':
                    final d = await _askName(context, 'Description', initial: folder.description, hint: 'What it holds');
                    if (d != null) await store.updateFolder(folder.copyWith(description: d));
                  case 'color':
                    await store.updateFolder(folder.copyWith(color: (folder.color + 1) % canvasColors.length));
                  case 'export':
                    await showCanvasExport(context, ref, folder);
                  case 'ai':
                    final controller = ref.read(chatControllerProvider.notifier);
                    controller.newChat();
                    controller.send(
                      'Look at my Content Canvas folder "${s.pathOf(folder)}" (canvas_overview with folder ${folder.id}) '
                      'and summarise what it holds, grouping related items.',
                    );
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  case 'delete':
                    if (!await confirmAction(
                      context,
                      title: 'Delete ${folder.name}?',
                      message: 'Deletes the folder, its subfolders and their ${s.countDeep(folder.id)} items from the '
                          'canvas. Nothing in Telegram is touched.',
                      action: 'Delete',
                    )) {
                      return;
                    }
                    await store.deleteFolder(folder.id);
                    if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'describe', child: Text('Edit description')),
                PopupMenuItem(value: 'color', child: Text('Change colour')),
                PopupMenuItem(value: 'export', child: Text('Export…')),
                PopupMenuItem(value: 'ai', child: Text('Ask AI about this folder')),
                PopupMenuItem(value: 'delete', child: Text('Delete folder')),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: Text(folder == null ? 'Folder' : 'Add'),
        onPressed: () async {
          if (folder == null) {
            final name = await _askName(context, 'New folder');
            if (name != null) await store.createFolder(name);
            return;
          }
          final what = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: lead(const Icon(Icons.create_new_folder_outlined)),
                    title: const Text('Subfolder'),
                    onTap: () => Navigator.pop(c, 'folder'),
                  ),
                  ListTile(
                    leading: lead(const Icon(Icons.sticky_note_2_outlined)),
                    title: const Text('Note'),
                    onTap: () => Navigator.pop(c, 'note'),
                  ),
                  ListTile(
                    leading: lead(const Icon(Icons.link_rounded)),
                    title: const Text('Link'),
                    subtitle: const Text('A web page to keep'),
                    onTap: () => Navigator.pop(c, 'link'),
                  ),
                  ListTile(
                    leading: lead(const Icon(Icons.auto_awesome_outlined)),
                    title: const Text('Ask AI to fill it'),
                    subtitle: const Text('e.g. "the last 10 posts from a channel about this"'),
                    onTap: () => Navigator.pop(c, 'ai'),
                  ),
                ],
              ),
            ),
          );
          if (!context.mounted) return;
          switch (what) {
            case 'folder':
              final name = await _askName(context, 'New subfolder');
              if (name != null) await store.createFolder(name, parentId: folder.id);
            case 'note':
              final text = await _askName(context, 'New note', hint: 'Write something');
              if (text != null) await store.addNote(folder.id, text);
            case 'link':
              final url = await _askName(context, 'Add a link', hint: 'https://…');
              if (url == null || !context.mounted) return;
              final link = url.startsWith('http') ? url : 'https://$url';
              final title = await _askName(context, 'Its title', initial: Uri.tryParse(link)?.host ?? link);
              await store.addSaved(folder.id, kind: CanvasKind.link, title: title ?? link, url: link, source: 'The web');
            case 'ai':
              final ask = await _askName(context, 'What should go in ${folder.name}?', hint: 'Describe it');
              if (ask == null || !context.mounted) return;
              final controller = ref.read(chatControllerProvider.notifier);
              controller.newChat();
              controller.send('Fill my Content Canvas folder "${s.pathOf(folder)}" (folder_id ${folder.id}): $ask');
              Navigator.of(context).popUntil((r) => r.isFirst);
          }
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 96),
        children: [
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: folder == null ? 'Search the whole canvas' : 'Search ${folder.name}',
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.text3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
            ),
          ),
          if (folder != null && folder.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Text(folder.description, style: context.text.bodySmall),
            ),
          if (folder == null && s.folders.isEmpty && s.loaded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x4),
              child: Column(
                children: [
                  Icon(Icons.dashboard_customize_outlined, size: 44, color: AppColors.text3),
                  const SizedBox(height: Space.m),
                  Text('Nothing on the canvas yet', style: context.text.titleMedium),
                  const SizedBox(height: Space.s),
                  Text(
                    'Make folders and save anything into them: notes, links, emails, files, app items, and Telegram posts '
                    'and messages (long-press one → Save to Content Canvas). Or ask the assistant: "save my unread '
                    'newsletters here" or "organise the last 10 posts from this channel into folders".',
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Space.s,
              crossAxisSpacing: Space.s,
              childAspectRatio: 1.7,
              children: [
                for (final f in children)
                  _FolderCard(
                    folder: f,
                    count: s.countDeep(f.id),
                    subfolders: s.childrenOf(f.id).length,
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => ContentCanvasScreen(folderId: f.id))),
                  ),
              ],
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            Text('${items.length} ITEM${items.length == 1 ? '' : 'S'}', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            for (final i in items)
              _ItemCard(
                item: i,
                path: widget.folderId == null ? s.pathOf(s.folder(i.folderId) ?? folder!) : null,
                picked: _picked.contains(i.id),
                picking: _picked.isNotEmpty,
                onPick: () => setState(() => _picked.contains(i.id) ? _picked.remove(i.id) : _picked.add(i.id)),
              ),
          ],
        ],
      ),
    );
  }

  static bool _matches(CanvasItem i, String q) =>
      i.text.toLowerCase().contains(q) ||
      i.title.toLowerCase().contains(q) ||
      i.source.toLowerCase().contains(q) ||
      i.url.toLowerCase().contains(q) ||
      i.note.toLowerCase().contains(q) ||
      i.tags.any((t) => t.toLowerCase().contains(q)) ||
      (i.post?.text.toLowerCase().contains(q) ?? false) ||
      (i.post?.chatTitle.toLowerCase().contains(q) ?? false);
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.folder, required this.count, required this.subfolders, required this.onTap});
  final CanvasFolder folder;
  final int count;
  final int subfolders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = canvasColors[folder.color % canvasColors.length];
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(Radii.l),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.l),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.folder_rounded, color: color),
              const Spacer(),
              Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
              Text(
                [
                  '$count item${count == 1 ? '' : 's'}',
                  if (subfolders > 0) '$subfolders folder${subfolders == 1 ? '' : 's'}',
                ].join(' · '),
                style: context.text.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({required this.item, this.path, required this.picked, required this.picking, required this.onPick});
  final CanvasItem item;
  final String? path;
  final bool picked;
  final bool picking;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = item;
    final p = i.post;
    final body = p?.text ?? i.text;
    final saved = const {CanvasKind.link, CanvasKind.email, CanvasKind.file, CanvasKind.app}.contains(i.kind);
    void openSaved() {
      if (i.path.isNotEmpty && File(i.path).existsSync()) {
        OpenFilex.open(i.path);
      } else if (i.url.isNotEmpty) {
        launchUrl(Uri.parse(i.url), mode: LaunchMode.externalApplication);
      } else {
        _editNote(context, ref);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: picked ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: picking ? onPick : (saved ? openSaved : (p == null ? () => _editNote(context, ref) : () => showPost(context, p))),
          onLongPress: onPick,
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: picked ? AppColors.accent : AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (p != null)
                      TgAvatar(chatId: p.chatId, title: p.chatTitle, size: 26)
                    else
                      Icon(
                        switch (i.kind) {
                          CanvasKind.link => Icons.link_rounded,
                          CanvasKind.email => Icons.mail_outline_rounded,
                          CanvasKind.file => Icons.insert_drive_file_outlined,
                          CanvasKind.app => Icons.apps_rounded,
                          _ => Icons.sticky_note_2_outlined,
                        },
                        size: 22,
                        color: saved ? AppColors.accent : AppColors.warning,
                      ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Text(
                        p != null
                            ? [p.chatTitle, ?p.sender].join(' · ')
                            : saved
                            ? [i.title, if (i.source.isNotEmpty) i.source].join(' · ')
                            : 'Note',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall,
                      ),
                    ),
                    Text(
                      DateFormat('d MMM').format(p?.date ?? i.addedAt),
                      style: context.text.labelSmall,
                    ),
                    if (p != null && p.kind != 'text') ...[
                      const SizedBox(width: Space.xs),
                      Icon(kindIcon(p.kind), size: 14, color: AppColors.text3),
                    ],
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Text(body, maxLines: 5, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                ],
                if (i.note.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Text('“${i.note}”', style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                ],
                if (i.tags.isNotEmpty || path != null) ...[
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (path != null) _Chip(Icons.folder_outlined, path!),
                      for (final t in i.tags) _Chip(Icons.tag_rounded, t),
                    ],
                  ),
                ],
                if (!picking)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Note',
                          icon: Icon(Icons.edit_note_rounded, size: 18, color: AppColors.text3),
                          onPressed: () => _editNote(context, ref),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Copy',
                          icon: Icon(Icons.copy_rounded, size: 16, color: AppColors.text3),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: body));
                            showSnack(context, 'Copied');
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref) async {
    final isNote = item.kind == CanvasKind.note;
    final v = await _askName(
      context,
      isNote ? 'Edit note' : 'Note on this item',
      initial: isNote ? item.text : item.note,
      hint: isNote ? 'Write something' : 'Why it\'s here',
    );
    if (v == null) return;
    await ref.read(canvasProvider.notifier).updateItem(isNote ? item.copyWith(text: v) : item.copyWith(note: v));
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.text3),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: AppColors.text2)),
      ],
    ),
  );
}
