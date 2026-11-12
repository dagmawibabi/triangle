import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recent searches in one place, newest first, kept on this phone. [scope]
/// names the place: 'messages' for the message search, a chat list's
/// section ('dms', 'channels', …) or `folder:<id>`.
class SearchHistoryController extends Notifier<List<String>> {
  SearchHistoryController(this.scope);
  final String scope;

  static const _max = 30;

  String get _key => scope == 'messages' ? 'tg_search_history' : 'tg_search_history:$scope';

  @override
  List<String> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList(_key);
    if (saved != null) state = saved;
  }

  Future<void> _save(List<String> next) async {
    state = next;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, next);
  }

  /// Puts [query] at the top, once (matching ignores case).
  Future<void> add(String query) {
    final q = query.trim();
    if (q.isEmpty) return Future.value();
    final rest = state.where((x) => x.toLowerCase() != q.toLowerCase());
    return _save([q, ...rest].take(_max).toList());
  }

  Future<void> remove(String query) => _save(state.where((x) => x != query).toList());

  Future<void> clear() => _save(const []);
}

final searchHistoryProvider = NotifierProvider.family<SearchHistoryController, List<String>, String>(
  SearchHistoryController.new,
);

/// Chats (or, for contacts, users) opened from a list's search, newest first,
/// by id. Kept like [searchHistoryProvider], under its own scope.
final recentChatsProvider = NotifierProvider.family<SearchHistoryController, List<String>, String>(
  (scope) => SearchHistoryController('chats:$scope'),
);
