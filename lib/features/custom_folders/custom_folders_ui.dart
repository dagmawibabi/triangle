import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/data/search_history.dart';
import '../telegram/presentation/chat_list_screen.dart' show ChatTile, RecentChatRow;
import '../telegram/presentation/recent_searches.dart';
import '../telegram/presentation/chat_view_screen.dart';
import 'custom_folders.dart';

const _emojis = ['📁', '⭐', '💼', '🏠', '👨‍👩‍👧', '❤️', '🎓', '💰', '📰', '🎮', '🎵', '🛒', '✈️', '⚽', '🤖', '🔥', '📌', '🧪', '🧠', '📚'];

/// The icons a folder can wear instead of an emoji, by the key it's saved as.
const folderIcons = <String, IconData>{
  'folder': Icons.folder_outlined,
  'star': Icons.star_outline_rounded,
  'work': Icons.work_outline_rounded,
  'home': Icons.home_outlined,
  'family': Icons.family_restroom_rounded,
  'favorite': Icons.favorite_border_rounded,
  'school': Icons.school_outlined,
  'money': Icons.payments_outlined,
  'news': Icons.newspaper_rounded,
  'games': Icons.sports_esports_outlined,
  'music': Icons.music_note_rounded,
  'shopping': Icons.shopping_bag_outlined,
  'travel': Icons.flight_rounded,
  'sports': Icons.sports_soccer_rounded,
  'bot': Icons.smart_toy_outlined,
  'fire': Icons.local_fire_department_outlined,
  'pin': Icons.push_pin_outlined,
  'science': Icons.science_outlined,
  'ideas': Icons.lightbulb_outline_rounded,
  'books': Icons.menu_book_rounded,
  'people': Icons.group_outlined,
  'channel': Icons.campaign_outlined,
  'code': Icons.code_rounded,
  'chat': Icons.chat_bubble_outline_rounded,
  'important': Icons.label_important_outline_rounded,
  'archive': Icons.inventory_2_outlined,
};

/// A folder's mark: its emoji, its icon, or nothing at all (null).
Widget? folderMark(CustomFolder f, {double size = 20, Color? color}) {
  final icon = folderIcons[f.icon];
  if (icon != null) return Icon(icon, size: size, color: color ?? AppColors.text2);
  if (f.emoji.isEmpty) return null;
  return Text(f.emoji, textAlign: TextAlign.center, style: TextStyle(fontSize: size * 0.9, height: 1.1));
}

/// Name and mark for a new or existing folder; the folder, or null if
/// cancelled.
Future<CustomFolder?> showCustomFolderEditor(BuildContext context, WidgetRef ref, {CustomFolder? folder}) async {
  final out = await showFormSheet<({String name, String emoji, String? icon})>(
    context,
    builder: (_) => _FolderEditor(folder: folder),
  );
  if (out == null || out.name.isEmpty) return null;
  final store = ref.read(customFoldersProvider.notifier);
  if (folder == null) return store.create(out.name, emoji: out.emoji, icon: out.icon);
  return store.update(
    folder.id,
    (f) => f.copyWith(name: out.name, emoji: out.emoji, icon: out.icon, clearIcon: out.icon == null),
  );
}

enum _Mark { emoji, icon, none }

/// The editor owns its text controllers, so they're only disposed once the
/// sheet is gone (disposing them as soon as the sheet's future returned,
/// while it was still animating closed, crashed the app).
class _FolderEditor extends StatefulWidget {
  const _FolderEditor({this.folder});
  final CustomFolder? folder;

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final _name = TextEditingController(text: widget.folder?.name ?? '');
  late final _custom = TextEditingController();
  late _Mark _mark = widget.folder == null
      ? _Mark.emoji
      : folderIcons.containsKey(widget.folder!.icon)
      ? _Mark.icon
      : widget.folder!.emoji.isEmpty
      ? _Mark.none
      : _Mark.emoji;
  late String _emoji = widget.folder?.emoji.isNotEmpty == true ? widget.folder!.emoji : '📁';
  late String _icon = folderIcons.containsKey(widget.folder?.icon) ? widget.folder!.icon! : 'folder';

  @override
  void initState() {
    super.initState();
    // A custom emoji from before shows in the box to edit.
    if (!_emojis.contains(_emoji)) _custom.text = _emoji;
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _custom.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (
      name: name,
      emoji: _mark == _Mark.emoji ? _emoji : '',
      icon: _mark == _Mark.icon ? _icon : null,
    ));
  }

  Widget _cell({required bool selected, required VoidCallback onTap, required Widget child}) => InkWell(
    borderRadius: BorderRadius.circular(Radii.s),
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColors.tint.withValues(alpha: 0.15) : AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(color: selected ? AppColors.tint : Colors.transparent),
      ),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final preview = switch (_mark) {
      _Mark.emoji => Text(_emoji, style: const TextStyle(fontSize: 20)),
      _Mark.icon => Icon(folderIcons[_icon], size: 22, color: AppColors.text2),
      _Mark.none => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(folder == null ? 'New folder' : 'Edit folder', style: context.text.titleMedium),
        const SizedBox(height: Space.m),
        TextField(
          controller: _name,
          autofocus: folder == null,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _done(),
          decoration: InputDecoration(
            labelText: 'Name',
            prefixIcon: preview == null ? null : SizedBox(width: 44, child: Center(child: preview)),
          ),
        ),
        const SizedBox(height: Space.m),
        SegmentedButton<_Mark>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Mark.emoji, icon: Icon(Icons.emoji_emotions_outlined, size: 18), label: Text('Emoji')),
            ButtonSegment(value: _Mark.icon, icon: Icon(Icons.category_outlined, size: 18), label: Text('Icon')),
            ButtonSegment(value: _Mark.none, icon: Icon(Icons.block_rounded, size: 18), label: Text('None')),
          ],
          selected: {_mark},
          onSelectionChanged: (v) => setState(() => _mark = v.first),
        ),
        const SizedBox(height: Space.m),
        if (_mark == _Mark.emoji) ...[
          TextField(
            controller: _custom,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Your own emoji',
              hintText: 'Type or paste any emoji',
              prefixIcon: Icon(Icons.edit_outlined, size: 18),
            ),
            onChanged: (v) {
              // Keep just the first character the person sees (one emoji,
              // however many code points it takes).
              final first = v.trim().characters.take(1).toString();
              if (first.isNotEmpty) setState(() => _emoji = first);
            },
          ),
          const SizedBox(height: Space.m),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _emojis)
                _cell(
                  selected: e == _emoji,
                  onTap: () => setState(() {
                    _emoji = e;
                    _custom.clear();
                  }),
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
            ],
          ),
        ] else if (_mark == _Mark.icon)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final MapEntry(:key, :value) in folderIcons.entries)
                _cell(
                  selected: key == _icon,
                  onTap: () => setState(() => _icon = key),
                  child: Icon(value, size: 21, color: key == _icon ? AppColors.tint : AppColors.text2),
                ),
            ],
          )
        else
          Text('Just the name, with no mark beside it.', style: context.text.bodySmall),
        const SizedBox(height: Space.l),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _done,
          child: Text(folder == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

/// Picks which of the active account's chats are in [folder].
Future<void> showFolderChatPicker(BuildContext context, CustomFolder folder) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.9,
    builder: (context, scroll) => _ChatPicker(folder: folder, scroll: scroll),
  ),
);

class _ChatPicker extends ConsumerStatefulWidget {
  const _ChatPicker({required this.folder, required this.scroll});
  final CustomFolder folder;
  final ScrollController scroll;

  @override
  ConsumerState<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends ConsumerState<_ChatPicker> {
  late final String _account = ref.read(activeAccountIdProvider);
  late final Set<int> _picked = widget.folder.chats.where((c) => c.account == _account).map((c) => c.chatId).toSet();
  late final Set<ChatKind> _kinds = {...widget.folder.kinds};
  late final Set<int> _excluded = widget.folder.excluded.where((c) => c.account == _account).map((c) => c.chatId).toSet();
  String _q = '';
  ChatKind? _kind;

  bool _in(int id, ChatKind kind) => _picked.contains(id) || (_kinds.contains(kind) && !_excluded.contains(id));

  void _toggle(int id, ChatKind kind, bool on) => setState(() {
    if (_kinds.contains(kind)) {
      // In through its type: ticking or unticking it is an exception.
      on ? _excluded.remove(id) : _excluded.add(id);
      if (!on) _picked.remove(id);
    } else {
      on ? _picked.add(id) : _picked.remove(id);
    }
  });

  void _toggleKind(ChatKind kind, bool on) => setState(() {
    if (on) {
      _kinds.add(kind);
    } else {
      _kinds.remove(kind);
    }
  });

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final q = _q.toLowerCase();
    final all = [for (final c in store.chats.values) if (c.title.isNotEmpty) c];
    final count = all.where((c) => _in(c.id, store.kindOf(c))).length;
    final chats = [
      for (final c in all)
        if ((q.isEmpty || c.title.toLowerCase().contains(q)) && (_kind == null || store.kindOf(c) == _kind)) c,
    ]..sort((a, b) {
        final pa = _in(a.id, store.kindOf(a)) ? 0 : 1, pb = _in(b.id, store.kindOf(b)) ? 0 : 1;
        if (pa != pb) return pa - pb;
        return (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0);
      });
    final mark = folderMark(widget.folder, size: 22);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (mark != null) ...[mark, const SizedBox(width: Space.s)],
                  Expanded(child: Text('Chats in ${widget.folder.name}', style: context.text.titleMedium)),
                  FilledButton(
                    onPressed: () async {
                      await ref.read(customFoldersProvider.notifier).setMembers(
                        widget.folder.id,
                        _account,
                        chatIds: _picked,
                        kinds: _kinds,
                        // Only exceptions to a type still in the folder matter.
                        excluded: [
                          for (final id in _excluded)
                            if (store.chat(id) case final c? when _kinds.contains(store.kindOf(c))) id,
                        ],
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text('Save · $count'),
                  ),
                ],
              ),
              const SizedBox(height: Space.m),
              Text('INCLUDE EVERY', style: context.text.labelSmall),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in CustomFolder.pickableKinds)
                    FilterChip(
                      avatar: Icon(_kindIcon(k), size: 16),
                      label: Text(CustomFolder.kindLabel(k)),
                      selected: _kinds.contains(k),
                      onSelected: (v) => _toggleKind(k, v),
                    ),
                ],
              ),
              if (_kinds.isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Text(
                  'New ${_kinds.map((k) => CustomFolder.kindLabel(k).toLowerCase()).join(', ')} join by themselves. Untick one below to leave it out.',
                  style: context.text.bodySmall,
                ),
              ],
              const SizedBox(height: Space.m),
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded, size: 20), hintText: 'Search chats'),
              ),
              const SizedBox(height: Space.s),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (label, kind) in [('All', null), ('People', ChatKind.private), ('Groups', ChatKind.group), ('Channels', ChatKind.channel), ('Bots', ChatKind.bot)])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(label: Text(label), selected: _kind == kind, onSelected: (_) => setState(() => _kind = kind)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: widget.scroll,
            itemCount: chats.length,
            itemBuilder: (context, i) {
              final c = chats[i];
              final kind = store.kindOf(c);
              final viaType = _kinds.contains(kind) && !_picked.contains(c.id);
              return CheckboxListTile(
                value: _in(c.id, kind),
                onChanged: (v) => _toggle(c.id, kind, v == true),
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${switch (kind) {
                    ChatKind.private => 'Person',
                    ChatKind.bot => 'Bot',
                    ChatKind.group => 'Group',
                    ChatKind.channel => 'Channel',
                    ChatKind.secret => 'Secret chat',
                    ChatKind.saved => 'Saved messages',
                  }}${viaType ? (_excluded.contains(c.id) ? ' · left out of ${CustomFolder.kindLabel(kind)}' : ' · with all ${CustomFolder.kindLabel(kind)}') : ''}',
                  style: context.text.labelSmall,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

IconData _kindIcon(ChatKind k) => switch (k) {
  ChatKind.private => Icons.person_outline_rounded,
  ChatKind.bot => Icons.smart_toy_outlined,
  ChatKind.group => Icons.group_outlined,
  ChatKind.channel => Icons.campaign_outlined,
  _ => Icons.chat_bubble_outline_rounded,
};

/// One custom folder's chats, in the active account.
class CustomFolderScreen extends ConsumerStatefulWidget {
  const CustomFolderScreen({super.key, required this.folderId});
  final String folderId;

  @override
  ConsumerState<CustomFolderScreen> createState() => _CustomFolderScreenState();
}

class _CustomFolderScreenState extends ConsumerState<CustomFolderScreen> {
  // The same search as Telegram's chat lists: words, Unread, and while the
  // box is empty and focused, recent searches and recently opened chats
  // (each folder keeps its own).
  final _search = TextEditingController();
  final _focus = FocusNode();
  String _q = '';
  bool _unread = false;
  ChatKind? _kind;

  String get _scope => 'myfolder:${widget.folderId}';
  SearchHistoryController get _history => ref.read(searchHistoryProvider(_scope).notifier);
  SearchHistoryController get _recent => ref.read(recentChatsProvider(_scope).notifier);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open(int id, {bool fromRecent = false}) {
    if (_q.trim().isNotEmpty) _history.add(_q.trim());
    if (_q.trim().isNotEmpty || fromRecent) _recent.add('$id');
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: id)));
  }

  void _pick(String q) {
    _search.text = q;
    _search.selection = TextSelection.collapsed(offset: q.length);
    setState(() => _q = q);
    _history.add(q);
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(customFoldersProvider);
    final folder = folders.folders.where((f) => f.id == widget.folderId).firstOrNull;
    if (folder == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This folder was deleted.')));
    final account = ref.watch(activeAccountIdProvider);
    final store = ref.watch(telegramStoreProvider);
    store.ensureChatsLoaded();
    final ids = folder.chatIdsIn(account, store);
    final all = [for (final id in ids) ?store.chat(id)]
      ..sort((a, b) => (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0));
    final q = _q.toLowerCase().trim();
    final chats = [
      for (final c in all)
        if ((q.isEmpty || c.title.toLowerCase().contains(q)) && (!_unread || c.unreadCount > 0 || c.markedUnread) && (_kind == null || store.kindOf(c) == _kind)) c,
    ];
    final kinds = {for (final c in all) store.kindOf(c)};
    final elsewhere = folder.chats.where((c) => c.account != account).length;
    final mark = folderMark(folder, size: 22);
    final unread = all.fold<int>(0, (a, c) => a + c.unreadCount);
    final history = ref.watch(searchHistoryProvider(_scope));
    final recentIds = [
      for (final x in ref.watch(recentChatsProvider(_scope)))
        if (int.tryParse(x) case final id? when ids.contains(id)) id,
    ];
    final showHistory = _focus.hasFocus && q.isEmpty && (history.isNotEmpty || recentIds.isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (mark != null) ...[mark, const SizedBox(width: Space.s)],
            Flexible(child: Text(folder.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Space.s),
            if (all.isNotEmpty) Text('${all.length}', style: context.text.titleMedium?.copyWith(color: AppColors.text3)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Add or remove chats', icon: const Icon(Icons.playlist_add_rounded), onPressed: () => showFolderChatPicker(context, folder)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') await showCustomFolderEditor(context, ref, folder: folder);
              if (v == 'delete' && context.mounted) {
                final ok = await confirmDelete(context, title: 'Delete ${folder.name}?', message: 'Only the folder goes; its chats stay as they are.', action: 'Delete');
                if (ok) {
                  await ref.read(customFoldersProvider.notifier).delete(folder.id);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger), title: const Text('Delete folder'))),
            ],
          ),
        ],
      ),
      body: all.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    folderMark(folder, size: 48) ?? Icon(Icons.folder_open_rounded, size: 48, color: AppColors.text3),
                    const SizedBox(height: Space.m),
                    Text('No chats here yet', style: context.text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      elsewhere > 0 ? '$elsewhere chat${elsewhere == 1 ? ' is' : 's are'} in your other accounts.' : 'Add any chats: people, groups, channels or bots.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: Space.l),
                    FilledButton.icon(onPressed: () => showFolderChatPicker(context, folder), icon: const Icon(Icons.add_rounded), label: const Text('Add chats')),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          focusNode: _focus,
                          textInputAction: TextInputAction.search,
                          onChanged: (v) => setState(() => _q = v),
                          onSubmitted: (v) {
                            if (v.trim().isNotEmpty) _history.add(v.trim());
                          },
                          decoration: InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                            hintText: 'Search ${folder.name}',
                            prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.text3),
                            suffixIcon: _q.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () {
                                      _search.clear();
                                      setState(() => _q = '');
                                    },
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      FilterChip(label: const Text('Unread'), selected: _unread, onSelected: (v) => setState(() => _unread = v)),
                    ],
                  ),
                ),
                if (kinds.length > 1)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: Space.l),
                      children: [
                        for (final (k, label) in const [(null, 'All'), (ChatKind.private, 'People'), (ChatKind.group, 'Groups'), (ChatKind.channel, 'Channels'), (ChatKind.bot, 'Bots')])
                          if (k == null || kinds.contains(k))
                            Padding(
                              padding: const EdgeInsets.only(right: Space.s),
                              child: ChoiceChip(
                                label: Text(k == null ? label : '$label · ${all.where((c) => store.kindOf(c) == k).length}'),
                                selected: _kind == k,
                                onSelected: (_) => setState(() => _kind = k),
                              ),
                            ),
                      ],
                    ),
                  ),
                Expanded(
                  child: showHistory
                      ? ListView(
                          children: [
                            RecentHeader(
                              onClear: () {
                                _history.clear();
                                _recent.clear();
                              },
                            ),
                            if (history.isNotEmpty) RecentTermChips(terms: history, onPick: _pick, onRemove: _history.remove),
                            for (final id in recentIds) RecentChatRow(id: id, contact: false, onTap: () => _open(id, fromRecent: true), onRemove: () => _recent.remove('$id')),
                          ],
                        )
                      : chats.isEmpty
                      ? Center(child: Text(q.isEmpty ? 'Nothing here with these filters' : 'No chat matches "$_q"', style: context.text.bodySmall))
                      : ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.xs),
                              child: Text(
                                q.isNotEmpty || _unread || _kind != null
                                    ? '${chats.length} of ${all.length}'
                                    : '${all.length} chat${all.length == 1 ? '' : 's'}${unread > 0 ? ' · $unread unread' : ''}${elsewhere > 0 ? ' · $elsewhere in other accounts' : ''} · long-press to remove',
                                style: context.text.labelSmall,
                              ),
                            ),
                            for (final c in chats)
                              ChatTile(
                                chat: c,
                                onTap: () => _open(c.id),
                                onLongPress: () async {
                                  final ok = await confirmDelete(context, title: 'Remove ${c.title}?', message: 'It leaves ${folder.name}; the chat stays as it is.', action: 'Remove');
                                  if (ok) await ref.read(customFoldersProvider.notifier).removeChats(folder.id, [FolderChatRef(account, c.id)]);
                                },
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

/// Settings → Telegram → My folders: make, reorder, edit and delete them.
class CustomFoldersSettingsScreen extends ConsumerWidget {
  const CustomFoldersSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(customFoldersProvider);
    final store = ref.read(customFoldersProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('My folders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final f = await showCustomFolderEditor(context, ref);
          if (f != null && context.mounted) await showFolderChatPicker(context, f);
        },
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New folder'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 96),
        children: [
          Text(
            'Your own folders, beside Telegram\'s: put any chat (people, groups, channels, bots, from any account) in as '
            'many as you like. They show in the drawer, and the assistant can sort chats into them.',
            style: context.text.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: Space.m),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show in the drawer'),
            value: s.inDrawer,
            onChanged: store.setInDrawer,
          ),
          const SizedBox(height: Space.s),
          if (s.folders.isEmpty)
            Padding(padding: const EdgeInsets.all(Space.xl), child: Text('No folders yet.', textAlign: TextAlign.center, style: context.text.bodySmall))
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: store.reorder,
              children: [
                for (final (i, f) in s.folders.indexed)
                  Material(
                    key: ValueKey(f.id),
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(width: 28, child: Center(child: folderMark(f, size: 24))),
                      title: Text(f.name),
                      subtitle: Text(
                        [
                          if (f.kinds.isNotEmpty) 'All ${f.kinds.map((k) => CustomFolder.kindLabel(k).toLowerCase()).join(', ')}',
                          if (f.chats.isNotEmpty || f.kinds.isEmpty) '${f.chats.length} chat${f.chats.length == 1 ? '' : 's'}',
                        ].join(' + '),
                        style: context.text.bodySmall,
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomFolderScreen(folderId: f.id))),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => showCustomFolderEditor(context, ref, folder: f)),
                          IconButton(tooltip: 'Chats', icon: const Icon(Icons.playlist_add_rounded, size: 20), onPressed: () => showFolderChatPicker(context, f)),
                          ReorderableDragStartListener(index: i, child: Icon(Icons.drag_handle_rounded, color: AppColors.text3)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
