import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../chat/presentation/widgets/post_viewer.dart';
import '../data/message_content.dart';
import '../data/search_history.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'media_viewer.dart';
import 'message_tile.dart' show snapshotOf;
import 'recent_searches.dart';
import 'td_image.dart';
import 'tg_avatar.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../account/account_switcher.dart';

/// Every chat at once, by kind of content: all the photos, files, links or
/// voice messages people sent, optionally matching words, newest first.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.chatId, this.initialType = 'any', this.initialQuery = ''});

  /// Search only this chat.
  final int? chatId;
  final String initialType;

  /// Searched straight away, e.g. a tapped #hashtag.
  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _query = TextEditingController(text: widget.initialQuery);
  final _scroll = ScrollController();
  late String _type = widget.initialType;
  String _scope = 'all';
  final List<td.Message> _results = [];
  String _next = '';
  bool _loading = false;
  bool _searched = false;
  String? _error;
  Timer? _debounce;
  int _run = 0;

  /// Kept for dispose, where ref can no longer be read.
  late final SearchHistoryController _history;

  /// Saves what's typed as a recent search.
  void _remember() => unawaited(_history.add(_query.text));

  bool get _visual => const {'photos', 'videos', 'photos_and_videos', 'gifs'}.contains(_type);

  @override
  void initState() {
    super.initState();
    _history = ref.read(searchHistoryProvider('messages').notifier);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) _more();
    });
    if (widget.initialQuery.isNotEmpty) _remember();
    if (_type != 'any' || widget.initialQuery.isNotEmpty) _search();
    // A search of all chats follows the account picked in the app bar.
    if (widget.chatId == null) {
      ref.listenManual(activeAccountIdProvider, (_, _) {
        setState(() {
          _results.clear();
          _searched = false;
          _error = null;
        });
        if (_query.text.trim().isNotEmpty || _type != 'any') _search();
      });
    }
  }

  @override
  void dispose() {
    // Leaving after a search that found something counts as searching it,
    // even without pressing search or opening a result.
    if (_searched && _results.isNotEmpty) _remember();
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Typing: a search is about to start, so it shows as searching already.
  bool _pending = false;

  void _queue() {
    _debounce?.cancel();
    if (!_pending) setState(() => _pending = true);
    _debounce = Timer(const Duration(milliseconds: 450), _search);
  }

  bool get _busy => _loading || _pending;

  Future<void> _search() async {
    _debounce?.cancel();
    final run = ++_run;
    setState(() {
      _pending = false;
      _results.clear();
      _next = '';
      _error = null;
    });
    if (_query.text.trim().isEmpty && _type == 'any' && widget.chatId == null) {
      setState(() => _searched = false);
      return;
    }
    await _page(run);
  }

  Future<void> _more() async {
    if (_loading || _next.isEmpty) return;
    await _page(_run);
  }

  Future<void> _page(int run) async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(toolRunnerProvider).searchByType(
        type: _type,
        query: _query.text.trim(),
        chatId: widget.chatId,
        archived: _scope == 'archived',
        channelsOnly: _scope == 'channels',
        limit: 50,
        offset: _next,
      );
      if (!mounted || run != _run) return;
      setState(() {
        _results.addAll(r.messages);
        _next = r.next;
        _searched = true;
      });
    } catch (e) {
      if (mounted && run == _run) setState(() => _error = '$e');
    } finally {
      if (mounted && run == _run) setState(() => _loading = false);
    }
  }

  void _open(td.Message m) {
    _remember();
    final store = ref.read(telegramStoreProvider);
    final chat = store.chat(m.chatId);
    if (m.content is td.MessagePhoto || m.content is td.MessageVideo || m.content is td.MessageAnimation) {
      showMediaViewer(context, m.content, title: chat?.title ?? 'Media');
      return;
    }
    final kind = chat == null ? null : store.kindOf(chat);
    showPost(context, snapshotOf(m, chat?.title ?? 'Chat', kind == ChatKind.channel ? null : store.senderName(m.senderId)));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final history = ref.watch(searchHistoryProvider('messages'));
    final showHistory = history.isNotEmpty && _query.text.trim().isEmpty && _type == 'any' && !_busy;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: widget.initialType == 'any',
          textInputAction: TextInputAction.search,
          onChanged: (_) => _queue(),
          onSubmitted: (_) {
            _remember();
            _search();
          },
          decoration: InputDecoration(
            hintText: widget.chatId == null ? 'Search all chats' : 'Search ${store.chat(widget.chatId!)?.title ?? 'this chat'}',
            border: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [if (widget.chatId == null) const AccountSwitcherButton()],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
              children: [
                for (final e in searchFilters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(e.value.$1),
                      selected: _type == e.key,
                      onSelected: (_) {
                        setState(() => _type = e.key);
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (widget.chatId == null)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.m),
                children: [
                  for (final (k, label) in const [('all', 'All chats'), ('channels', 'Channels only'), ('archived', 'Archived')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(label, style: const TextStyle(fontSize: 12)),
                        selected: _scope == k,
                        onSelected: (_) {
                          setState(() => _scope = k);
                          _search();
                        },
                      ),
                    ),
                ],
              ),
            ),
          // Searching (or about to): a bar while anything is loading, and
          // a clear "Searching…" until the first results arrive.
          SizedBox(height: 2, child: _busy ? const LinearProgressIndicator(minHeight: 2) : null),
          if (_searched || _busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
              child: Row(
                children: [
                  Text(
                    _busy && _results.isEmpty
                        ? 'Searching…'
                        : '${_results.length}${_next.isEmpty ? '' : '+'} result${_results.length == 1 ? '' : 's'}',
                    style: context.text.labelSmall,
                  ),
                  if (_busy && _results.isNotEmpty) ...[
                    const SizedBox(width: Space.s),
                    const SizedBox.square(dimension: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
                  ],
                ],
              ),
            ),
          Expanded(
            child: showHistory
                ? RecentSearches(
                    history: history,
                    onPick: (q) {
                      _query.text = q;
                      _query.selection = TextSelection.collapsed(offset: q.length);
                      _remember();
                      _search();
                    },
                    onRemove: _history.remove,
                    onClear: _history.clear,
                  )
                : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(Space.xl), child: Text(_error!, textAlign: TextAlign.center)))
                : _busy && _results.isEmpty
                ? const _SearchingPlaceholder()
                : !_searched
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Text(
                        'Type to search, or pick a kind: every photo, file, link or voice message across your chats.',
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall,
                      ),
                    ),
                  )
                : _results.isEmpty && !_loading
                ? Center(child: Text('Nothing found', style: context.text.bodySmall))
                : _visual
                ? GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(3),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3),
                    itemCount: _results.length + (_next.isEmpty ? 0 : 1),
                    itemBuilder: (_, i) {
                      if (i == _results.length) {
                        return const Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)));
                      }
                      final m = _results[i];
                      return GestureDetector(
                        onTap: () => _open(m),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.s),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              TdFileImage(file: previewFileOf(m.content), priority: 6),
                              if (m.content is td.MessageVideo)
                                const Positioned(right: 4, bottom: 4, child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20)),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _results.length + (_next.isEmpty ? 0 : 1),
                    itemBuilder: (_, i) {
                      if (i == _results.length) {
                        return const Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                      }
                      final m = _results[i];
                      final chat = store.chat(m.chatId);
                      final g = gistOf(m.content);
                      return ListTile(
                        leading: TgAvatar(chatId: m.chatId, title: chat?.title ?? '?', size: 40),
                        title: Text(chat?.title ?? 'Chat ${m.chatId}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${g.kind == 'text' ? '' : '${g.detail ?? g.kind} · '}${g.text}'.replaceAll('\n', ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                        trailing: Text(
                          DateFormat('d MMM').format(DateTime.fromMillisecondsSinceEpoch(m.date * 1000)),
                          style: context.text.labelSmall,
                        ),
                        onTap: () => _open(m),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// What the page shows while the first results load: a few shimmering rows.
class _SearchingPlaceholder extends StatefulWidget {
  const _SearchingPlaceholder();

  @override
  State<_SearchingPlaceholder> createState() => _SearchingPlaceholderState();
}

class _SearchingPlaceholderState extends State<_SearchingPlaceholder> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.35, end: 0.8).animate(_pulse),
    child: ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(radius: 20, backgroundColor: AppColors.surface3),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.45 + (i % 3) * 0.12,
                    child: Container(height: 11, decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(4))),
                  ),
                  const SizedBox(height: 7),
                  FractionallySizedBox(
                    widthFactor: 0.8 - (i % 2) * 0.15,
                    child: Container(height: 9, decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
