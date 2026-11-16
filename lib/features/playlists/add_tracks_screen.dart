import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../../infrastructure/telegram/telegram_client.dart';
import '../auth/data/auth_controller.dart';
import '../media/audio_center.dart';
import '../media/audio_player_ui.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/presentation/chat_list_screen.dart' show inTelegramOrder;
import '../telegram/presentation/tg_avatar.dart';
import 'playlist_sources.dart';
import 'playlist_widgets.dart';
import 'playlists.dart';

import '../sections/skeletons.dart';
/// Opens the picker that finds audio in Telegram and in Files. With
/// [playlistId] the picks go straight into that playlist; without, the
/// person chooses one at the end. [chatId] starts inside one chat.
Future<void> openAddTracks(BuildContext context, {String? playlistId, int? chatId, TgAudioType type = TgAudioType.music, bool files = false}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddTracksScreen(playlistId: playlistId, chatId: chatId, type: type, startOnFiles: files),
      ),
    );

class AddTracksScreen extends ConsumerStatefulWidget {
  const AddTracksScreen({super.key, this.playlistId, this.chatId, this.type = TgAudioType.music, this.startOnFiles = false});
  final String? playlistId;
  final int? chatId;
  final TgAudioType type;
  final bool startOnFiles;

  @override
  ConsumerState<AddTracksScreen> createState() => _AddTracksScreenState();
}

class _AddTracksScreenState extends ConsumerState<AddTracksScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this, initialIndex: widget.startOnFiles ? 1 : 0)..addListener(() => setState(() {}));

  /// Picked tracks by key, in the order picked.
  final Map<String, PlaylistTrack> _picked = {};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toggle(PlaylistTrack t) => setState(() => _picked.containsKey(t.key) ? _picked.remove(t.key) : _picked[t.key] = t);

  void _pickAll(List<PlaylistTrack> list) => setState(() {
    final all = list.every((t) => _picked.containsKey(t.key));
    for (final t in list) {
      all ? _picked.remove(t.key) : _picked[t.key] = t;
    }
  });

  Future<void> _add() async {
    final tracks = _picked.values.toList();
    if (tracks.isEmpty) return;
    final store = ref.read(playlistsProvider.notifier);
    final target = widget.playlistId == null ? null : store.byId(widget.playlistId!);
    if (target == null) {
      final p = await showAddToPlaylist(context, ref, tracks);
      if (p != null && mounted) Navigator.pop(context);
      return;
    }
    final added = await store.addTracks(target.id, tracks);
    if (!mounted) return;
    showSnack(
      context,
      added == 0 ? 'Already in ${target.name}' : 'Added ${added == 1 ? '“${tracks.first.title}”' : '$added tracks'} to ${target.name}',
      icon: Icons.playlist_add_check_rounded,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.playlistId == null ? null : ref.watch(playlistsProvider.select((s) => s.playlists.where((p) => p.id == widget.playlistId).firstOrNull));
    final telegram = ref.watch(telegramConnectedProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add audio'),
            if (target != null) Text('to ${target.name}', style: context.text.bodySmall),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          dividerColor: AppColors.line,
          tabs: const [
            Tab(icon: Icon(Icons.send_rounded, size: 20), text: 'Telegram'),
            Tab(icon: Icon(Icons.folder_copy_outlined, size: 20), text: 'Files'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                telegram
                    ? _TelegramSource(initialChat: widget.chatId, initialType: widget.type, picked: _picked, onToggle: _toggle, onPickAll: _pickAll)
                    : const _Note(icon: Icons.send_rounded, title: 'Telegram isn\'t connected', body: 'Connect it to add songs, voice messages and audio files from your chats and channels.'),
                _FilesSource(picked: _picked, onToggle: _toggle, onPickAll: _pickAll),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _picked.isEmpty
            ? const SafeArea(top: false, child: AudioMiniBar(margin: EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s)))
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
                  child: Row(
                    children: [
                      TextButton(onPressed: () => setState(_picked.clear), child: const Text('Clear')),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                          onPressed: _add,
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: Text('Add ${_picked.length} ${_picked.length == 1 ? 'track' : 'tracks'}${target == null ? '…' : ''}'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Plays one found track on its own, to hear it before adding it.
void _preview(WidgetRef ref, PlaylistTrack t, List<PlaylistTrack> around) {
  final store = ref.read(playlistsProvider.notifier);
  final a = ref.read(audioCenterProvider);
  unawaited(a.play(store.trackFor(t), playlist: [for (final x in around) store.trackFor(x)]));
}

Widget _previewButton(WidgetRef ref, PlaylistTrack t, List<PlaylistTrack> around) {
  final a = ref.watch(audioCenterProvider);
  final on = a.current?.key == t.key;
  return IconButton(
    tooltip: on && a.playing ? 'Pause' : 'Listen',
    icon: on && a.loading
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(on && a.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_outline_rounded, color: on ? AppColors.tint : AppColors.text2),
    onPressed: () => on ? a.toggle() : _preview(ref, t, around),
  );
}

// ---- Telegram ----------------------------------------------------------------

class _TelegramSource extends ConsumerStatefulWidget {
  const _TelegramSource({required this.initialChat, required this.initialType, required this.picked, required this.onToggle, required this.onPickAll});
  final int? initialChat;
  final TgAudioType initialType;
  final Map<String, PlaylistTrack> picked;
  final ValueChanged<PlaylistTrack> onToggle;
  final ValueChanged<List<PlaylistTrack>> onPickAll;

  @override
  ConsumerState<_TelegramSource> createState() => _TelegramSourceState();
}

class _TelegramSourceState extends ConsumerState<_TelegramSource> with AutomaticKeepAliveClientMixin {
  late TgAudioType _type = widget.initialType;
  late int? _chat = widget.initialChat;
  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<PlaylistTrack> _found = const [];
  String _next = '';
  int _total = 0;
  bool _loading = false;
  String? _error;

  /// Oldest first: everything is loaded (up to a cap), then shown reversed.
  bool _oldestFirst = false;
  bool _loadingAll = false;

  List<PlaylistTrack> get _shown => _oldestFirst ? _found.reversed.toList() : _found;

  /// Bumped on each new search so late pages of an old one are dropped.
  int _gen = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_oldestFirst && _scroll.position.extentAfter < 400) _load();
    });
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _search() {
    _gen++;
    setState(() {
      _found = const [];
      _next = '';
      _total = 0;
      _error = null;
      _loading = false;
    });
    _load(first: true).then((_) {
      if (_oldestFirst) _loadAll();
    });
  }

  Future<void> _load({bool first = false}) async {
    if (_loading || (!first && _next.isEmpty)) return;
    // Every chat needs words or a type; a type is always set.
    final gen = _gen;
    setState(() => _loading = true);
    try {
      final account = ref.read(activeAccountIdProvider);
      final r = await searchTelegramAudio(
        ref.read(telegramClientProvider),
        ref.read(telegramStoreProvider),
        account,
        type: _type,
        chatId: _chat,
        query: _query.text.trim(),
        next: first ? '' : _next,
      );
      if (gen != _gen || !mounted) return;
      final have = {for (final t in _found) t.key};
      setState(() {
        _found = [..._found, for (final t in r.tracks) if (!have.contains(t.key)) t];
        _next = r.next;
        _total = r.total;
      });
    } catch (e) {
      if (gen == _gen && mounted) setState(() => _error = '$e');
    } finally {
      if (gen == _gen && mounted) setState(() => _loading = false);
    }
  }

  /// Loads every page (up to a cap) so the oldest can come first.
  Future<void> _loadAll() async {
    if (_loadingAll) return;
    final gen = _gen;
    setState(() => _loadingAll = true);
    final cap = _chat == null ? 300 : 2000;
    while (mounted && gen == _gen && _next.isNotEmpty && _found.length < cap) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (gen != _gen || _next.isEmpty) break;
      await _load();
    }
    if (mounted) setState(() => _loadingAll = false);
  }

  void _setOldest(bool v) {
    setState(() => _oldestFirst = v);
    if (v) _loadAll();
  }

  Future<void> _pickChat() async {
    final picked = await pickTelegramChat(context, allowAll: true);
    if (picked == null) return;
    setState(() => _chat = picked == 0 ? null : picked);
    _search();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = ref.watch(telegramStoreProvider);
    final chat = _chat == null ? null : store.chat(_chat!);
    final shown = _shown;
    final allPicked = shown.isNotEmpty && shown.every((t) => widget.picked.containsKey(t.key));
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: chat == null ? 'Search songs, artists, voice notes in every chat' : 'Search in ${chat.title}',
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _query.clear();
                              _search();
                            },
                          ),
                  ),
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 450), _search);
                  },
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: Space.m),
                // Where to look.
                Material(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(Radii.l),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.l),
                    onTap: _pickChat,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 10),
                      child: Row(
                        children: [
                          if (chat == null)
                            Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [Color(0xFF2AABEE), Color(0xFF229ED9)]),
                              ),
                              child: const Icon(Icons.all_inclusive_rounded, size: 18, color: Colors.white),
                            )
                          else
                            TgAvatar(chatId: chat.id, title: chat.title, size: 36),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(chat?.title ?? 'All chats & channels', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                Text(chat == null ? 'Tap to pick one chat or channel' : 'Tap to change', style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          if (chat != null)
                            IconButton(
                              tooltip: 'All chats',
                              icon: Icon(Icons.close_rounded, color: AppColors.text3),
                              onPressed: () {
                                setState(() => _chat = null);
                                _search();
                              },
                            )
                          else
                            Icon(Icons.unfold_more_rounded, color: AppColors.text3),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.m),
                SegmentedButton<TgAudioType>(
                  showSelectedIcon: false,
                  segments: [
                    for (final (t, icon) in const [
                      (TgAudioType.music, Icons.music_note_rounded),
                      (TgAudioType.voice, Icons.mic_rounded),
                      (TgAudioType.files, Icons.audio_file_outlined),
                    ])
                      ButtonSegment(value: t, icon: Icon(icon, size: 18), label: Text(t.label)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) {
                    setState(() => _type = v.first);
                    _search();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xs, Space.m, 0, Space.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _found.isEmpty && _loading
                              ? 'Searching…'
                              : _type == TgAudioType.files
                              ? '${_found.length} audio files${_next.isEmpty ? '' : '+'}'
                              : '${_total > _found.length ? _total : _found.length} found',
                          style: context.text.labelSmall,
                        ),
                      ),
                      PopupMenuButton<bool>(
                        tooltip: 'Order',
                        initialValue: _oldestFirst,
                        onSelected: _setOldest,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: false, child: Text('Newest first')),
                          PopupMenuItem(value: true, child: Text('Oldest first')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_loadingAll)
                                const SizedBox.square(dimension: 13, child: CircularProgressIndicator(strokeWidth: 1.6))
                              else
                                Icon(Icons.swap_vert_rounded, size: 17, color: AppColors.text2),
                              const SizedBox(width: 4),
                              Text(_oldestFirst ? 'Oldest first' : 'Newest first', style: context.text.labelMedium),
                            ],
                          ),
                        ),
                      ),
                      if (shown.isNotEmpty)
                        TextButton(onPressed: _loadingAll ? null : () => widget.onPickAll(shown), child: Text(allPicked ? 'Unselect all' : 'Select all')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null && _found.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _Note(icon: Icons.error_outline_rounded, title: 'Couldn\'t search', body: _error!))
        else if (_found.isEmpty && !_loading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Note(
              icon: _type == TgAudioType.voice ? Icons.mic_none_rounded : Icons.library_music_outlined,
              title: 'Nothing here yet',
              body: chat == null
                  ? 'No ${_type.label.toLowerCase()} matched. Try other words, or pick a channel that posts music, sermons or podcasts.'
                  : '${chat.title} has no ${_type.label.toLowerCase()}${_query.text.isEmpty ? '' : ' matching “${_query.text}”'}.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            sliver: SliverList.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final t = shown[i];
                return TrackRow(
                  track: t,
                  selected: widget.picked.containsKey(t.key),
                  onTap: () => widget.onToggle(t),
                  trailing: _previewButton(ref, t, shown),
                );
              },
            ),
          ),
        if (_loading && _found.isNotEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
        const SliverToBoxAdapter(child: SizedBox(height: Space.x4)),
      ],
    );
  }
}

/// Picks one of the open account's chats; with [allowAll], 0 stands for
/// every chat. Null if cancelled.
Future<int?> pickTelegramChat(BuildContext context, {bool allowAll = false, String? title}) =>
    showAppSheet<int>(context, builder: (context, scroll) => _ChatPicker(scroll: scroll, allowAll: allowAll, title: title));

class _ChatPicker extends ConsumerStatefulWidget {
  const _ChatPicker({required this.scroll, required this.allowAll, this.title});
  final ScrollController scroll;
  final bool allowAll;
  final String? title;

  @override
  ConsumerState<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends ConsumerState<_ChatPicker> {
  String _q = '';
  ChatKind? _kind;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final q = _q.toLowerCase();
    final all = inTelegramOrder(store.chats.values.where((c) => c.title.isNotEmpty && c.isListed), 'main');
    final saved = all.where((c) => store.kindOf(c) == ChatKind.saved).firstOrNull;
    final list = [
      for (final c in all)
        if (c != saved && (q.isEmpty || c.title.toLowerCase().contains(q)) && (_kind == null || store.kindOf(c) == _kind)) c,
    ];
    return Column(
      children: [
        if (widget.title != null)
          Padding(padding: const EdgeInsets.only(bottom: Space.m), child: Text(widget.title!, style: context.text.titleMedium)),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Find a chat or channel'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            children: [
              for (final (k, label) in const [(null, 'All'), (ChatKind.channel, 'Channels'), (ChatKind.group, 'Groups'), (ChatKind.private, 'People'), (ChatKind.bot, 'Bots')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              if (q.isEmpty && _kind == null) ...[
                if (widget.allowAll)
                ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF2AABEE), Color(0xFF229ED9)])),
                    child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 20),
                  ),
                  title: const Text('All chats & channels'),
                  subtitle: Text('Search everything at once', style: context.text.bodySmall),
                  onTap: () => Navigator.pop(context, 0),
                ),
                if (saved != null)
                  ListTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.tint),
                      child: Icon(Icons.bookmark_rounded, color: AppColors.isLight ? Colors.white : AppColors.bg, size: 20),
                    ),
                    title: const Text('Saved Messages'),
                    subtitle: Text('What you forwarded to yourself', style: context.text.bodySmall),
                    onTap: () => Navigator.pop(context, saved.id),
                  ),
                const Divider(indent: Space.l, endIndent: Space.l),
              ],
              for (final c in list.take(300))
                ListTile(
                  leading: TgAvatar(chatId: c.id, title: c.title, size: 42),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(switch (store.kindOf(c)) {
                    ChatKind.channel => 'Channel',
                    ChatKind.group => 'Group',
                    ChatKind.bot => 'Bot',
                    _ => 'Chat',
                  }, style: context.text.bodySmall),
                  onTap: () => Navigator.pop(context, c.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- Files -------------------------------------------------------------------

class _FilesSource extends ConsumerStatefulWidget {
  const _FilesSource({required this.picked, required this.onToggle, required this.onPickAll});
  final Map<String, PlaylistTrack> picked;
  final ValueChanged<PlaylistTrack> onToggle;
  final ValueChanged<List<PlaylistTrack>> onPickAll;

  @override
  ConsumerState<_FilesSource> createState() => _FilesSourceState();
}

class _FilesSourceState extends ConsumerState<_FilesSource> with AutomaticKeepAliveClientMixin {
  List<PlaylistTrack>? _all;
  String _q = '';
  TrackKind? _kind;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    savedAudioFiles().then((v) {
      if (mounted) setState(() => _all = v);
    }).ignore();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final all = _all;
    if (all == null) return const SingleChildScrollView(child: SkeletonRows(count: 9, art: 44, artRadius: 10));
    final q = _q.toLowerCase();
    final kinds = {for (final t in all) t.kind};
    final list = [
      for (final t in all)
        if ((_kind == null || t.kind == _kind) && (q.isEmpty || '${t.title} ${t.artist}'.toLowerCase().contains(q))) t,
    ];
    final allPicked = list.isNotEmpty && list.every((t) => widget.picked.containsKey(t.key));
    if (all.isEmpty) {
      return const _Note(
        icon: Icons.folder_off_outlined,
        title: 'No audio in Files yet',
        body: 'Podcast episodes and audiobook chapters you download, Telegram audio you save, and audio the assistant makes show up here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.m, Space.xs, Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search your audio files'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        const SizedBox(height: Space.s),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text('All · ${all.length}'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
              ),
              for (final k in TrackKind.values)
                if (kinds.contains(k))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: Icon(k.icon, size: 16),
                      label: Text('${k.label} · ${all.where((t) => t.kind == k).length}'),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, 0),
          child: Row(
            children: [
              Expanded(child: Text('${list.length} files', style: context.text.labelSmall)),
              if (list.isNotEmpty) TextButton(onPressed: () => widget.onPickAll(list), child: Text(allPicked ? 'Unselect all' : 'Select all')),
            ],
          ),
        ),
        for (final t in list)
          TrackRow(track: t, selected: widget.picked.containsKey(t.key), onTap: () => widget.onToggle(t), trailing: _previewButton(ref, t, list)),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface2),
            child: Icon(icon, size: 32, color: AppColors.text2),
          ),
          const SizedBox(height: Space.l),
          Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          Text(body, style: context.text.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
