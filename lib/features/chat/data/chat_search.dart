import '../domain/chat_models.dart';

// Searching the assistant's own conversations (the drawer's search sheet and
// the search_ai_chats tool): by title, and with content on, by what the
// user and the assistant wrote in them.

/// A bit of a conversation around a match.
class ChatSnippet {
  const ChatSnippet({required this.fromUser, required this.text});

  /// The user wrote it; otherwise the assistant did.
  final bool fromUser;
  final String text;

  Map<String, dynamic> toJson() => {'from': fromUser ? 'user' : 'assistant', 'text': text};
}

/// A conversation that matches a search.
class ChatSearchHit {
  const ChatSearchHit({required this.summary, required this.inTitle, this.snippets = const [], this.matches = 0});
  final ConversationSummary summary;

  /// Every word of the query is in the title.
  final bool inTitle;

  /// Up to three places in the conversation that match.
  final List<ChatSnippet> snippets;

  /// How many messages match.
  final int matches;
}

/// The query's words, lower-cased. All of them have to appear.
List<String> searchWords(String query) =>
    query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

bool _hasAll(String text, List<String> words) {
  final t = text.toLowerCase();
  return words.every(t.contains);
}

/// About [width] characters of [text] around the first of [words] in it,
/// on one line.
String snippetAround(String text, List<String> words, {int width = 140}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= width) return flat;
  final lower = flat.toLowerCase();
  var at = -1;
  for (final w in words) {
    final i = lower.indexOf(w);
    if (i >= 0 && (at < 0 || i < at)) at = i;
  }
  if (at < 0) return '${flat.substring(0, width).trimRight()}…';
  var start = (at - width ~/ 3).clamp(0, flat.length);
  final end = (start + width).clamp(0, flat.length);
  start = (end - width).clamp(0, flat.length);
  return '${start > 0 ? '…' : ''}${flat.substring(start, end).trim()}${end < flat.length ? '…' : ''}';
}

/// The conversations in [chats] that match [query]: every word in the title,
/// or with [content], anywhere in what was written. Title matches come first,
/// then those with more matching messages, then the newest. [load] reads a
/// conversation (null when it can't be read).
Future<List<ChatSearchHit>> searchChats(
  List<ConversationSummary> chats,
  String query, {
  required Future<Conversation?> Function(String id) load,
  bool content = false,
  int limit = 50,
}) async {
  final words = searchWords(query);
  if (words.isEmpty) return const [];
  final hits = <ChatSearchHit>[];
  for (final s in chats) {
    final inTitle = _hasAll(s.title, words);
    if (!content) {
      if (inTitle) hits.add(ChatSearchHit(summary: s, inTitle: true));
      continue;
    }
    final c = await load(s.id);
    final snippets = <ChatSnippet>[];
    var matches = 0;
    void check(String text, bool fromUser) {
      if (text.trim().isEmpty || !_hasAll(text, words)) return;
      matches++;
      if (snippets.length < 3) snippets.add(ChatSnippet(fromUser: fromUser, text: snippetAround(text, words)));
    }

    for (final e in c?.entries ?? const <ChatEntry>[]) {
      if (e is UserEntry) {
        check(e.text, true);
      } else if (e is AssistantEntry) {
        check(e.steps.map((s) => s.text).join('\n'), false);
      }
    }
    if (c?.summary case final summary? when matches == 0) check(summary, false);
    if (inTitle || matches > 0) hits.add(ChatSearchHit(summary: s, inTitle: inTitle, snippets: snippets, matches: matches));
  }
  hits.sort((a, b) {
    if (a.inTitle != b.inTitle) return a.inTitle ? -1 : 1;
    if (a.matches != b.matches) return b.matches.compareTo(a.matches);
    return b.summary.updatedAt.compareTo(a.summary.updatedAt);
  });
  return hits.take(limit).toList();
}
