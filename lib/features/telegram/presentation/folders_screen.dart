import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import '../../../infrastructure/telegram/td_compat.dart';
import '../../settings/data/settings.dart';

/// The account's chat folders: reorder by dragging, rename, choose what
/// goes in, delete, or create one (also from Telegram's suggestions).
class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  List<Map<String, dynamic>> _suggested = const [];

  @override
  void initState() {
    super.initState();
    ref.read(toolRunnerProvider).run('suggested_folders', const {}).then((r) {
      if (mounted) setState(() => _suggested = [for (final s in (r.json['suggestions'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)]);
    });
  }

  Future<void> _call(String tool, Map<String, dynamic> args, String done) async {
    final r = await ref.read(toolRunnerProvider).run(tool, args);
    if (!mounted) return;
    showSnack(context, r.json['error'] != null ? '${r.json['error']}' : done, icon: r.json['error'] != null ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded);
  }

  Future<void> _edit({FolderInfo? folder, Map<String, dynamic>? preset}) async {
    td.ChatFolder? current;
    if (folder != null) {
      current = await ref.read(telegramClientProvider).send<td.ChatFolder>(td.GetChatFolder(chatFolderId: folder.id), limited: true);
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _FolderEditor(folder: current, preset: preset),
    );
    if (result == null) return;
    if (result['delete'] == true && folder != null) {
      await _call('delete_folder', {'folder_id': folder.id}, 'Folder deleted');
    } else if (folder != null) {
      await _call('edit_folder', {'folder_id': folder.id, ...result}, 'Folder saved');
    } else {
      await _call('create_folder', result, 'Folder created');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final folders = store.folders;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat folders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New folder'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          SwitchListTile(
            secondary: lead(const Icon(Icons.view_sidebar_outlined)),
            title: const Text('Show in the drawer'),
            subtitle: Text('Your Telegram folders, in the side drawer', style: context.text.bodySmall),
            value: ref.watch(settingsProvider.select((s) => s.drawerFolders)),
            onChanged: ref.read(settingsProvider.notifier).setDrawerFolders,
          ),
          const Divider(),
          if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text('No folders yet. Make one, or ask the assistant: "make a Work folder with my work groups".', textAlign: TextAlign.center, style: context.text.bodySmall),
            ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (from, to) {
              final ids = [for (final f in folders) f.id];
              final moved = ids.removeAt(from);
              ids.insert(to > from ? to - 1 : to, moved);
              _call('reorder_folders', {'folder_ids': ids}, 'Order saved');
            },
            children: [
              for (final f in folders)
                ListTile(
                  key: ValueKey(f.id),
                  leading: lead(const Icon(Icons.folder_outlined)),
                  title: Text(f.title),
                  subtitle: Text('${store.folderChats[f.id]?.length ?? '…'} chats', style: context.text.bodySmall),
                  trailing: Icon(Icons.drag_handle_rounded, color: AppColors.text3),
                  onTap: () => _edit(folder: f),
                ),
            ],
          ),
          if (_suggested.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.s),
              child: Text('SUGGESTED', style: context.text.labelSmall),
            ),
            for (final s in _suggested)
              ListTile(
                leading: lead(const Icon(Icons.auto_awesome_outlined)),
                title: Text('${s['title']}'),
                subtitle: Text('${s['description']}', style: context.text.bodySmall),
                trailing: TextButton(onPressed: () => _edit(preset: s), child: const Text('Add')),
              ),
          ],
        ],
      ),
    );
  }
}

class _FolderEditor extends StatefulWidget {
  const _FolderEditor({this.folder, this.preset});
  final td.ChatFolder? folder;
  final Map<String, dynamic>? preset;

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final _title = TextEditingController(text: widget.folder?.title ?? '${widget.preset?['title'] ?? ''}');
  late final Set<String> _types = {
    if (widget.folder case final f?) ...[
      if (f.includeContacts) 'contacts',
      if (f.includeNonContacts) 'non_contacts',
      if (f.includeBots) 'bots',
      if (f.includeGroups) 'groups',
      if (f.includeChannels) 'channels',
    ],
    for (final t in (widget.preset?['include_types'] as List? ?? const [])) '$t',
  };
  late bool _muted = widget.folder?.excludeMuted ?? widget.preset?['exclude_muted'] == true;
  late bool _read = widget.folder?.excludeRead ?? widget.preset?['exclude_read'] == true;
  late bool _archived = widget.folder?.excludeArchived ?? widget.preset?['exclude_archived'] == true;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l + MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.folder == null ? 'New folder' : 'Edit folder', style: context.text.titleLarge),
          const SizedBox(height: Space.m),
          TextField(controller: _title, maxLength: 12, decoration: const InputDecoration(labelText: 'Name')),
          Text('INCLUDE ALL', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (k, label) in const [('contacts', 'Contacts'), ('non_contacts', 'Non-contacts'), ('groups', 'Groups'), ('channels', 'Channels'), ('bots', 'Bots')])
                FilterChip(label: Text(label), selected: _types.contains(k), onSelected: (v) => setState(() => v ? _types.add(k) : _types.remove(k))),
            ],
          ),
          const SizedBox(height: Space.s),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Leave out muted chats'), value: _muted, onChanged: (v) => setState(() => _muted = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Leave out read chats'), value: _read, onChanged: (v) => setState(() => _read = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Leave out archived chats'), value: _archived, onChanged: (v) => setState(() => _archived = v)),
          Text('Pick single chats from a chat\'s long-press menu (Add to folder), or ask the assistant.', style: context.text.bodySmall),
          const SizedBox(height: Space.l),
          Row(
            children: [
              if (widget.folder != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => Navigator.pop(context, {'delete': true}),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context, {
                  'title': _title.text.trim(),
                  'include_types': _types.toList(),
                  'exclude_muted': _muted,
                  'exclude_read': _read,
                  'exclude_archived': _archived,
                }),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
