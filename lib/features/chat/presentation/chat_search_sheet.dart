import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../data/chat_controller.dart';
import '../data/chat_repository.dart';
import '../data/chat_search.dart';

/// Searches the assistant's conversations, from the drawer: titles, and with
/// the switch on, what was written in them. Picking one opens it.
class ChatSearchSheet extends ConsumerStatefulWidget {
  const ChatSearchSheet({super.key});

  /// Shows the sheet; true when a conversation was opened from it.
  static Future<bool?> show(BuildContext context) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const ChatSearchSheet(),
      );

  @override
  ConsumerState<ChatSearchSheet> createState() => _ChatSearchSheetState();
}

class _ChatSearchSheetState extends ConsumerState<ChatSearchSheet> {
  final _query = TextEditingController();
  bool _content = false;
  bool _searching = false;
  List<ChatSearchHit> _hits = const [];
  Timer? _debounce;
  int _run = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    final run = ++_run;
    final q = _query.text.trim();
    if (q.isEmpty) {
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final repo = ref.read(chatRepositoryProvider);
    final hits = await searchChats(
      ref.read(chatControllerProvider).history,
      q,
      load: repo.load,
      content: _content,
    );
    // A newer search started meanwhile: its results win.
    if (!mounted || run != _run) return;
    setState(() {
      _hits = hits;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final words = searchWords(_query.text);
    final current = ref.watch(chatControllerProvider.select((s) => s.conversation.id));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => _changed(),
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: _content ? 'Search titles and messages' : 'Search chat titles',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _query.clear();
                            _search();
                          },
                        ),
                ),
              ),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Search messages too'),
              subtitle: Text('What you and the assistant wrote, not only titles', style: context.text.bodySmall),
              value: _content,
              onChanged: (v) {
                setState(() => _content = v);
                _search();
              },
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
            Expanded(
              child: _query.text.trim().isEmpty
                  ? const SizedBox.shrink()
                  : !_searching && _hits.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xl),
                        child: Text(
                          _content ? 'No chat mentions that.' : 'No chat title has that. Turn on "Search messages too" to look inside them.',
                          textAlign: TextAlign.center,
                          style: context.text.bodySmall,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
                      itemCount: _hits.length,
                      itemBuilder: (context, i) {
                        final h = _hits[i];
                        return ListTile(
                          selected: h.summary.id == current,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
                          leading: Icon(h.summary.archived ? Icons.archive_outlined : Icons.chat_bubble_outline_rounded, size: 20),
                          title: Text.rich(_highlight(context, h.summary.title, words), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final s in h.snippets.take(2))
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: s.fromUser ? 'You: ' : 'Triangle: ', style: TextStyle(color: AppColors.text3)),
                                      _highlight(context, s.text, words),
                                    ]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.bodySmall,
                                  ),
                                ),
                              Text(
                                [
                                  _when(h.summary.updatedAt),
                                  if (h.matches > 2) '${h.matches} matching messages',
                                ].join(' · '),
                                style: context.text.labelSmall,
                              ),
                            ],
                          ),
                          onTap: () {
                            ref.read(chatControllerProvider.notifier).open(h.summary.id);
                            Navigator.pop(context, true);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// [text] with the searched words in bold, in the accent colour.
  TextSpan _highlight(BuildContext context, String text, List<String> words) {
    if (words.isEmpty) return TextSpan(text: text);
    final pattern = RegExp(words.map(RegExp.escape).join('|'), caseSensitive: false);
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: m[0], style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: spans);
  }

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
