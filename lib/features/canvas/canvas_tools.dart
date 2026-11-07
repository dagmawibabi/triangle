import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/domain/chat_models.dart';
import '../telegram/data/telegram_tools.dart';
import 'canvas_export.dart';
import 'canvas_store.dart';

final _ref = RegExp(r'post:(-?\d+):(\d+)');

/// Runs one of the Content Canvas tools.
/// [account] is the Telegram account posts are read from (the run's).
Future<ToolOutput> runCanvasTool(Ref ref, String name, Map<String, dynamic> a, {String? account}) async {
  final store = ref.read(canvasProvider.notifier);
  final s = await store.ready();
  String str(String k) => '${a[k] ?? ''}'.trim();
  List<String> strs(String k) => [for (final v in (a[k] as List? ?? const [])) '$v'];

  CanvasFolder need(String k) {
    final f = s.find(str(k));
    if (f == null) throw ArgumentError('No canvas folder "${str(k)}". Folders: ${s.folders.map((f) => s.pathOf(f)).join(', ')}');
    return f;
  }

  /// A folder by id, name or path, made (with its parents) when missing.
  Future<CanvasFolder> ensure(String spec) async {
    final hit = ref.read(canvasProvider).find(spec);
    if (hit != null) return hit;
    String? parent;
    late CanvasFolder f;
    for (final part in spec.split('/').map((p) => p.trim()).where((p) => p.isNotEmpty)) {
      f = await store.createFolder(part, parentId: parent);
      parent = f.id;
    }
    return f;
  }

  Map<String, dynamic> itemJson(CanvasItem i) => {
    'item_id': i.id,
    'kind': i.kind.name,
    if (i.post case final p?) ...{
      'ref': 'post:${p.chatId}:${p.messageId}',
      'chat': p.chatTitle,
      'sender': ?p.sender,
      'date': p.date.toIso8601String().substring(0, 16),
      'text': p.text.length > 280 ? '${p.text.substring(0, 280)}…' : p.text,
    } else
      'text': i.text,
    if (i.note.isNotEmpty) 'note': i.note,
    if (i.tags.isNotEmpty) 'tags': i.tags,
  };

  switch (name) {
    case 'canvas_overview':
      final st = ref.read(canvasProvider);
      final f = str('folder').isEmpty ? null : need('folder');
      final items = f == null ? const <CanvasItem>[] : st.itemsIn(f.id);
      return ToolOutput({
        'folders': [
          for (final x in st.folders)
            {
              'folder_id': x.id,
              'path': st.pathOf(x),
              'items': st.itemsIn(x.id).length,
              if (x.description.isNotEmpty) 'description': x.description,
            },
        ],
        if (st.folders.isEmpty) 'note': 'The canvas is empty.',
        if (f != null) 'folder': st.pathOf(f),
        if (f != null) 'items': [for (final i in items) itemJson(i)],
      }, posts: [for (final i in items) ?i.post]);
    case 'canvas_create_folder':
      final parent = str('parent').isEmpty ? null : await ensure(str('parent'));
      final f = await store.createFolder(str('name'), parentId: parent?.id, description: str('description'));
      return ToolOutput({'folder_id': f.id, 'path': ref.read(canvasProvider).pathOf(f)});
    case 'canvas_update_folder':
      final f = need('folder');
      final hasParent = a.containsKey('parent');
      final parent = hasParent && str('parent').isNotEmpty ? await ensure(str('parent')) : null;
      if (parent?.id == f.id) throw ArgumentError('A folder can\'t be inside itself.');
      final next = f.copyWith(
        name: str('name').isEmpty ? null : str('name'),
        description: a.containsKey('description') ? str('description') : null,
        parentId: parent?.id,
        root: hasParent && parent == null,
      );
      await store.updateFolder(next);
      return ToolOutput({'folder_id': f.id, 'path': ref.read(canvasProvider).pathOf(next)});
    case 'canvas_export':
      final f = need('folder');
      final format = CanvasExportFormat.parse(str('format')) ??
          (throw ArgumentError('format must be json, md, html or pdf'));
      final file = await exportCanvasFolder(s, f, format, subfolders: a['subfolders'] != false);
      return ToolOutput({
        'exported': s.pathOf(f),
        'format': format.label,
        // file_path makes it sendable with send_message, like other made files.
        'file_path': file.path,
        'name': file.path.split(RegExp(r'[\\/]')).last,
        'size_kb': ((await file.length()) / 1024).ceil(),
        'items': a['subfolders'] == false ? s.itemsIn(f.id).length : s.countDeep(f.id),
      });
    case 'canvas_delete_folder':
      final f = need('folder');
      final to = str('move_items_to').isEmpty ? null : await ensure(str('move_items_to'));
      final n = s.countDeep(f.id);
      await store.deleteFolder(f.id, moveItemsTo: to?.id);
      return ToolOutput({'deleted': s.pathOf(f), 'items': n, if (to != null) 'items_moved_to': to.name});
    case 'canvas_add':
      final f = await ensure(str('folder'));
      final keys = <(int, int)>{
        for (final r in strs('refs'))
          if (_ref.firstMatch(r) case final m?) (int.parse(m[1]!), int.parse(m[2]!)),
        if (a['chat_id'] case final num chat)
          for (final id in (a['message_ids'] as List? ?? const []))
            if (id is num) (chat.toInt(), id.toInt()),
      };
      if (keys.isEmpty) throw ArgumentError('Pass refs, or chat_id with message_ids.');
      final runner = ref.read(account == null ? toolRunnerProvider : toolRunnerFamily(account));
      final posts = <PostSnapshot>[];
      final missing = <String>[];
      for (final (chat, id) in keys.take(100)) {
        try {
          posts.add(await runner.snapshotMessage(chat, id));
        } catch (_) {
          missing.add('post:$chat:$id');
        }
      }
      final added = await store.addPosts(f.id, posts, note: str('note'), tags: strs('tags'));
      return ToolOutput({
        'folder': ref.read(canvasProvider).pathOf(f),
        'folder_id': f.id,
        'added': added,
        if (posts.length > added) 'already_there': posts.length - added,
        if (missing.isNotEmpty) 'not_found': missing,
      }, posts: posts);
    case 'canvas_save':
      final f = await ensure(str('folder'));
      final kind = CanvasKind.values.asNameMap()[str('kind')] ?? CanvasKind.link;
      final i = await store.addSaved(
        f.id,
        kind: kind,
        title: str('title'),
        text: str('text'),
        url: str('url'),
        source: str('source'),
        path: str('file'),
        note: str('note'),
        tags: strs('tags'),
      );
      return ToolOutput({'item_id': i.id, 'kind': kind.name, 'folder': ref.read(canvasProvider).pathOf(f)});
    case 'canvas_add_note':
      final f = await ensure(str('folder'));
      final i = await store.addNote(f.id, str('text'));
      return ToolOutput({'item_id': i.id, 'folder': ref.read(canvasProvider).pathOf(f)});
    case 'canvas_move':
      final to = await ensure(str('to_folder'));
      final n = await store.moveItems(strs('item_ids'), to.id);
      return ToolOutput({'moved': n, 'to': ref.read(canvasProvider).pathOf(to)});
    case 'canvas_remove':
      final n = await store.removeItems(strs('item_ids'));
      return ToolOutput({'removed': n});
  }
  return ToolOutput({'error': 'Unknown tool $name'});
}
