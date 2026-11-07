import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:omni_ai/omni_ai.dart' as omni;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/files/generated_files.dart';
import '../../ai/data/ai.dart';
import '../../ai/data/decision_settings.dart';
import '../../ai/data/selected_models.dart';
import '../../brief/brief_store.dart';
import '../../brief/home_widgets.dart';
import '../../canvas/canvas_tools.dart';
import '../../integrations/app_toolkits.dart';
import '../../integrations/e2b_session.dart';
import '../../integrations/integrations_store.dart';
import '../../usage/usage.dart';
import '../../assistant/notifications.dart';
import '../../assistant/reminders.dart';
import '../../assistant/online_alerts.dart';
import '../../assistant/watches.dart';

import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../../settings/data/settings.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/data/telegram_tools.dart';
import '../../web/inapp_engine.dart';
import '../domain/chat_models.dart';
import 'chat_repository.dart';
import 'creative_audio.dart';
import 'image_input.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../telegram/data/account_tools.dart';

@immutable
class ChatState {
  const ChatState({
    required this.conversation,
    this.history = const [],
    this.busy = false,
    this.revision = 0,
  });

  final Conversation conversation;
  final List<ConversationSummary> history;
  final bool busy;

  /// Bumped on every change to the (mutable) conversation, so the UI rebuilds.
  final int revision;

  ChatState copyWith({
    Conversation? conversation,
    List<ConversationSummary>? history,
    bool? busy,
  }) => ChatState(
    conversation: conversation ?? this.conversation,
    history: history ?? this.history,
    busy: busy ?? this.busy,
    revision: revision + 1,
  );
}

/// Tools omni_ai runs itself (its memory toolkit). The app keeps their
/// entries in the tool list for Settings and the cards.
const _memoryTools = {
  'remember',
  'update_memory',
  'forget_memory',
  'list_memories',
};

/// Tools that act on this phone rather than on Telegram.
const _localTools = {
  'create_watch',
  'list_watches',
  'update_watch',
  'delete_watch',
  'create_widget',
  'update_widget',
  'list_widgets',
  'delete_widget',
  'online_alert',
  'list_online_alerts',
  'notify_me',
  'list_attachments',
  'list_briefs',
  'read_brief',
  'write_brief',
  'transcribe_message',
  'view_image',
  'create_reminder',
  'list_reminders',
  'update_reminder',
  'delete_reminder',
  'zip_files',
};

/// Runs conversations as omni_ai agent runs: the model streams, the app's
/// tools run as omni_ai tools (pausing for approval where a tool needs it
/// and the settings say so), and every exchange is kept on disk.
///
/// The conversation on screen is [state]. Watches run their own
/// conversations alongside it; while one runs it is kept in [_live], so
/// opening it shows the turn as it happens, approval cards included.
class ChatController extends Notifier<ChatState> {
  static const _uuid = Uuid();

  final Map<String, omni.AgentRun> _runs = {};
  final Map<String, Completer<bool>> _approvals = {};
  final Set<String> _stopping = {};
  final Map<String, Conversation> _live = {};

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  /// The accounts a running automatic turn (watch, job, brief) may use, by
  /// conversation: limited to the ones it covers, defaulting to the account
  /// its message came from. Other turns see every account.
  final Map<String, AccountsState> _accountViews = {};

  AccountsState _accountsFor(String conversationId) =>
      _accountViews[conversationId] ?? ref.read(accountsProvider);

  /// Runs [turn] with [c] limited to [accounts] (null: all), defaulting to
  /// [preferred].
  Future<void> _withAccounts(
    Conversation c,
    List<String>? accounts,
    String? preferred,
    Future<void> Function() turn,
  ) async {
    if (accounts == null && preferred == null) return turn();
    _accountViews[c.id] = ref.read(accountsProvider).limitedTo(accounts, preferred: preferred);
    try {
      await turn();
    } finally {
      _accountViews.remove(c.id);
    }
  }

  @override
  ChatState build() {
    _loadHistory();
    return ChatState(conversation: Conversation(id: _uuid.v4()));
  }

  Future<void> _loadHistory() async {
    final history = await _repo.list();
    if (ref.mounted) state = state.copyWith(history: history);
  }

  bool _onScreen(Conversation c) => identical(state.conversation, c);

  /// The conversation being talked in, in voice mode: its answers are
  /// written to be heard.
  String? voiceConversationId;

  static const _voiceGuidance =
      'The user is talking to you out loud in voice mode, and your answer is read aloud as it is written. '
      'Talk the way people talk: short, natural sentences, a sentence or two unless they ask for more. '
      'No markdown, lists, tables, code, links or emoji. Say numbers and dates as they are spoken. '
      'Before a tool that takes a while, say in a few words what you are doing.';

  void _touch(Conversation c) {
    if (ref.mounted && (_onScreen(c) || _observed.contains(c.id)))
      state = state.copyWith();
  }

  /// Conversations run out of sight (briefs): never saved to the history,
  /// and only allowed to read.
  final Set<String> _hidden = {};

  /// Hidden conversations someone is watching live: their progress still
  /// bumps the revision.
  final Set<String> _observed = {};

  /// Runs one read-only turn in a conversation of its own that doesn't
  /// appear in the history, and returns it once the answer is written.
  /// [onStart] gets the conversation as it begins, to follow it live.
  Future<Conversation> runHidden(
    String title,
    String prompt, {
    void Function(Conversation c)? onStart,
    List<String>? accounts,
  }) async {
    final settings = ref.read(settingsProvider);
    final c = Conversation(id: _uuid.v4(), title: title);
    _hidden.add(c.id);
    c.entries.add(UserEntry(id: _uuid.v4(), text: prompt, event: title));
    final reply = AssistantEntry(id: _uuid.v4(), model: settings.model);
    c.entries.add(reply);
    if (onStart != null) {
      _observed.add(c.id);
      onStart(c);
    }
    try {
      await _withAccounts(c, accounts, null, () => _runTurn(c, reply));
    } finally {
      reply.done = true;
      _observed.remove(c.id);
    }
    return c;
  }

  /// Chats deleted while a turn in them was still running: the turn ends
  /// without saving them back.
  final Set<String> _deleted = {};

  Future<void> _persist(Conversation c) async {
    if (c.entries.isEmpty || _hidden.contains(c.id) || _deleted.contains(c.id))
      return;
    c.updatedAt = DateTime.now();
    final history = await _repo.save(c);
    if (ref.mounted) state = state.copyWith(history: history);
  }

  // ---- conversations -------------------------------------------------------

  /// Opening the app again: a new chat, unless the one on screen is still
  /// empty. A turn running in the old one carries on in the background.
  void freshStart() {
    if (state.conversation.entries.isEmpty) return;
    newChat();
  }

  static const _lastChatKey = 'last_open_chat';

  /// The app was opened: the last chat the person had open, or a new one,
  /// as Settings → Appearance says.
  Future<void> appOpened() async {
    if (!ref.read(settingsProvider).openLastChat) return freshStart();
    final id = (await SharedPreferences.getInstance()).getString(_lastChatKey);
    final history = state.history.isEmpty ? await _repo.list() : state.history;
    final last =
        history.where((h) => h.id == id).firstOrNull ??
        (history.where((h) => !h.archived).toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
            .firstOrNull;
    if (last == null) return freshStart();
    if (last.id != state.conversation.id) await open(last.id);
  }

  /// Remembers the chat on screen, for "open the last chat".
  void _rememberOpen(String id) => unawaited(
    SharedPreferences.getInstance().then((p) => p.setString(_lastChatKey, id)),
  );

  /// Starts a new chat. A turn running in the one being left carries on in
  /// the background; it's in [_live] until it ends.
  void newChat() {
    state = state.copyWith(
      conversation: Conversation(id: _uuid.v4()),
      busy: false,
    );
  }

  /// Opens a saved chat, or one still running (its live copy, so its
  /// progress shows).
  Future<void> open(String id) async {
    final c = _live[id] ?? await _repo.load(id);
    if (c == null) return;
    state = state.copyWith(conversation: c, busy: _live.containsKey(id));
    _rememberOpen(id);
    if (_screenVisible) await _markSeen(c);
  }

  // ---- where watch updates go ----------------------------------------------

  bool _screenVisible = false;

  /// The chat screen is in front, with the app on screen. Set by the chat
  /// screen as routes and the app's lifecycle change.
  void setScreenVisible(bool visible) {
    if (_screenVisible == visible) return;
    _screenVisible = visible;
    if (visible) unawaited(_markSeen(state.conversation));
  }

  Future<void> _markSeen(Conversation c) async {
    if (c.unread == 0) return;
    c.unread = 0;
    if (c.entries.isNotEmpty) await _persist(c);
  }

  /// Where a watch's update goes: always the watch's own conversation (the
  /// one it was set up in), made if it is gone, never whatever chat happens
  /// to be on screen.
  Future<Conversation> _targetFor(Watch watch) async {
    final current = state.conversation;
    final id = watch.conversationId;
    Conversation? c = id == null
        ? null
        : (id == current.id ? current : (_live[id] ?? await _repo.load(id)));
    if (c == null) {
      c = Conversation(id: _uuid.v4(), title: 'Watch · ${watch.name}');
      final made = c;
      await ref
          .read(watchStoreProvider.notifier)
          .update(watch.id, (w) => w.copyWith(conversationId: made.id));
    }
    return c;
  }

  bool _seen(Conversation c) => _screenVisible && _onScreen(c);

  /// Posts a watch's update without the AI: what happened, as the
  /// assistant's message, with post chips. Returns where it went and
  /// whether the person is looking at it.
  Future<({String conversationId, bool seen})> postNotice(
    Watch watch,
    String event,
    String markdown,
    List<PostSnapshot> posts,
  ) async {
    final c = await _targetFor(watch);
    c.entries.add(UserEntry(id: _uuid.v4(), text: event, event: watch.name));
    c.entries.add(
      AssistantEntry(
        id: _uuid.v4(),
        model: 'watch',
        done: true,
        steps: [ModelStep(text: markdown)],
      ),
    );
    for (final p in posts) {
      c.posts[p.key] = p;
    }
    final seen = _seen(c);
    if (!seen) c.unread++;
    _touch(c);
    await _persist(c);
    return (conversationId: c.id, seen: seen);
  }

  /// Removes every conversation from this phone.
  Future<void> deleteAll() async {
    if (state.busy) stop();
    await _repo.clearAll();
    state = state.copyWith(
      history: const [],
      conversation: Conversation(id: _uuid.v4()),
      busy: false,
    );
  }

  /// Deletes a chat. A watch or job that wrote in it carries on: its next
  /// run starts a new chat of its own (see [_targetFor]).
  Future<void> delete(String id) async {
    _deleted.add(id);
    final history = await _repo.remove(id);
    state = state.copyWith(history: history);
    if (state.conversation.id == id) newChat();
  }

  Future<void> rename(String id, String title) async {
    final history = await _repo.rename(id, title);
    if (state.conversation.id == id) state.conversation.title = title;
    state = state.copyWith(history: history);
  }

  /// Pins conversation [id] to the top of the drawer, or unpins it.
  Future<void> pin(String id, bool pinned) async =>
      state = state.copyWith(history: await _repo.mark(id, pinned: pinned));

  /// Moves conversation [id] under Archived in the drawer, or back. An
  /// archived chat isn't pinned.
  Future<void> archive(String id, bool archived) async =>
      state = state.copyWith(
        history: await _repo.mark(
          id,
          archived: archived,
          pinned: archived ? false : null,
        ),
      );

  /// The conversation [id], from the screen, a running turn or storage.
  Future<Conversation?> conversationById(String id) async =>
      state.conversation.id == id
      ? state.conversation
      : _live[id] ?? await _repo.load(id);

  /// A short model call for housekeeping (titles, summaries) with the chat
  /// model, counted in usage like any other.
  Future<String> _ask(
    String system,
    String prompt, {
    int maxOutputTokens = 800,
  }) async {
    final settings = ref.read(settingsProvider);
    final model = canonicalModelId(settings.model);
    final result = await ref
        .read(aiProvider)
        .generateText(
          model: model,
          system: system,
          prompt: prompt,
          maxOutputTokens: maxOutputTokens,
        );
    ref
        .read(usageProvider.notifier)
        .recordChat(
          model: model,
          usage: result.usage,
          info: ref.read(modelCatalogProvider).byId(model),
        );
    return result.text.trim();
  }

  /// The conversation as plain text for a model to read: what was asked,
  /// what was answered, and which tools ran. [upTo] stops after that entry.
  static String transcript(
    Conversation c, {
    String? upTo,
    int maxChars = 60000,
  }) {
    final b = StringBuffer();
    for (final e in c.entries) {
      switch (e) {
        case UserEntry(:final text, :final attachments):
          b.writeln(
            'User: $text${attachments.isEmpty ? '' : ' [files: ${attachments.map((a) => a.name).join(', ')}]'}',
          );
        case AssistantEntry(:final steps):
          final tools = [
            for (final s in steps)
              for (final t in s.tools) t.name,
          ];
          final text = steps
              .map((s) => s.text)
              .where((t) => t.trim().isNotEmpty)
              .join('\n');
          if (tools.isNotEmpty)
            b.writeln('(Assistant used: ${tools.toSet().join(', ')})');
          if (text.isNotEmpty) b.writeln('Assistant: $text');
      }
      b.writeln();
      if (e.id == upTo || b.length > maxChars) break;
    }
    return b.toString();
  }

  /// A title for [c] written by the chat model from how it began.
  Future<String?> suggestTitle(Conversation c) async {
    if (c.entries.isEmpty || !ref.read(settingsProvider).hasAnyKey) return null;
    try {
      final title = await _ask(
        'Write a short title (2 to 6 words) for this conversation, in its language. Reply with the title only: '
        'no quotes, no full stop.',
        transcript(c, maxChars: 4000),
        maxOutputTokens: 40,
      );
      final line = title
          .split('\n')
          .first
          .replaceAll(RegExp(r'^["“”\x27*#\s]+|["“”\x27*.\s]+$'), '');
      return line.isEmpty ? null : _titleFrom(line);
    } catch (e) {
      debugPrint('[Chat] title: $e');
      return null;
    }
  }

  /// Names [c] with the model after its first answer, unless renamed since.
  Future<void> _autoTitle(Conversation c, String firstLine) async {
    if (c.title != firstLine) return;
    final title = await suggestTitle(c);
    if (title == null || c.title != firstLine) return;
    await rename(c.id, title);
  }

  /// How full the model's context is for [c]: the prompt the last model
  /// call sent (or an estimate from the text) against the model's window.
  ({int used, int? window, bool estimated}) contextOf(Conversation c) {
    final settings = ref.read(settingsProvider);
    final window = ref
        .read(modelCatalogProvider)
        .byId(canonicalModelId(settings.model))
        ?.contextWindow;
    // What the model reads besides the chat (instructions, tools, memories),
    // learned from the last real measurement when there is one.
    var overhead = 6000;
    for (final e in c.entries.reversed) {
      if (e is AssistantEntry) {
        final last = e.steps.lastWhere(
          (s) => s.usage != null && s.usage!.input > 0,
          orElse: () => ModelStep(),
        );
        if (last.usage case final u?) {
          final measured = u.input + u.output;
          // Measured before a compaction: it still counted what the summary replaced.
          if (c.compactedAt == null || e.at.isAfter(c.compactedAt!)) {
            return (used: measured, window: window, estimated: false);
          }
          final before =
              transcript(c, upTo: e.id, maxChars: 1 << 30).length ~/ 4;
          overhead = (measured - before).clamp(0, measured);
          break;
        }
      }
    }
    return (
      used: overhead + _modelText(c).length ~/ 4,
      window: window,
      estimated: true,
    );
  }

  /// The chat as the model reads it now: the summary, then what follows it.
  static String _modelText(Conversation c) {
    final covered = c.summaryUntil == null
        ? -1
        : c.entries.indexWhere((e) => e.id == c.summaryUntil);
    if (covered < 0) return transcript(c, maxChars: 1 << 30);
    final rest = Conversation(
      id: c.id,
      entries: c.entries.sublist(covered + 1),
    );
    return '${c.summary ?? ''}\n${transcript(rest, maxChars: 1 << 30)}';
  }

  /// Conversations being compacted right now.
  final Set<String> _compacting = {};
  bool isCompacting(String conversationId) =>
      _compacting.contains(conversationId);

  /// Summarises everything before [c]'s last two questions, so the model
  /// reads the summary instead of those messages. The chat itself keeps
  /// every message on screen.
  Future<bool> compact([Conversation? conversation]) async {
    final c = conversation ?? state.conversation;
    final users = [
      for (final (i, e) in c.entries.indexed)
        if (e is UserEntry) i,
    ];
    if (users.length < 3 || _compacting.contains(c.id)) return false;
    final until = c.entries[users[users.length - 2] - 1];
    // Kept by the controller, not the sheet that asked: it finishes (and
    // shows in the chat) even when the sheet is closed.
    _compacting.add(c.id);
    _touch(c);
    try {
      final previous = c.summary == null
          ? ''
          : 'Summary of what came before:\n${c.summary}\n\n';
      final summary = await _ask(
        'Summarise this conversation so it can continue without the original messages. Keep every fact, '
            'decision, preference and open task; names, numbers, dates, chat ids and post refs (post:chat:message) '
            'exactly; and what the user is working toward. Use short bullet points under headings. No preamble.',
        '$previous${transcript(c, upTo: until.id, maxChars: 120000)}',
        maxOutputTokens: 2000,
      );
      if (summary.isEmpty) return false;
      c
        ..summary = summary
        ..summaryUntil = until.id
        ..compactedAt = DateTime.now();
      await _persist(c);
      return true;
    } catch (e) {
      debugPrint('[Chat] compact: $e');
      return false;
    } finally {
      _compacting.remove(c.id);
      _touch(c);
    }
  }

  // ---- approvals -----------------------------------------------------------

  /// Approves a pending call. For a message, [text] and [files] are what
  /// the person settled on in the card, and replace the model's draft.
  void approve(
    String callId, {
    String? text,
    List<Attachment>? files,
    bool? asFiles,
  }) {
    if (ref.read(settingsProvider).haptics) HapticFeedback.mediumImpact();
    if (text != null || files != null || asFiles != null)
      _approvalEdits[callId] = (text: text, files: files, asFiles: asFiles);
    _approvals.remove(callId)?.complete(true);
  }

  final Map<String, ({String? text, List<Attachment>? files, bool? asFiles})>
  _approvalEdits = {};

  /// Files the assistant may attach to a message: what the person attached
  /// in this conversation and the images the assistant made.
  List<Attachment> sendableFiles([Conversation? conversation]) {
    final out = <Attachment>[];
    for (final e in (conversation ?? state.conversation).entries) {
      switch (e) {
        case UserEntry(:final attachments):
          out.addAll(attachments);
        case AssistantEntry(:final steps):
          for (final s in steps) {
            for (final t in s.tools) {
              // Images and audio made here, and files zipped or downloaded.
              if (t.result == null ||
                  !(t.result!.contains('_path"') ||
                      t.result!.contains('created_files')))
                continue;
              try {
                final result = jsonDecode(t.result!) as Map;
                // Code runs can make several files.
                for (final p
                    in (result['created_files'] as List? ?? const [])) {
                  if (p is String && p != result['image_path']) {
                    out.add(
                      Attachment(
                        path: p,
                        name: p.split(RegExp(r'[\\/]')).last,
                        mime: lookupMimeType(p) ?? 'application/octet-stream',
                        size: 0,
                      ),
                    );
                  }
                }
                final path =
                    result['image_path'] ??
                    result['audio_path'] ??
                    result['file_path'];
                if (path is String) {
                  out.add(
                    Attachment(
                      path: path,
                      name: path.split(RegExp(r'[\\/]')).last,
                      mime: lookupMimeType(path) ?? 'application/octet-stream',
                      size: 0,
                    ),
                  );
                }
              } catch (_) {}
            }
          }
      }
    }
    return out;
  }

  void deny(String callId) => _approvals.remove(callId)?.complete(false);

  /// Stops the turn running in the conversation on screen.
  void stop() {
    final id = state.conversation.id;
    _stopping.add(id);
    _runs[id]?.cancel();
    for (final part in _pendingParts(state.conversation)) {
      _approvals.remove(part.callId)?.complete(false);
    }
    for (final part in _runningParts(state.conversation)) {
      cancelTool(part);
    }
  }

  final Map<String, Completer<ToolOutput>> _toolCancels = {};
  final Map<String, omni.CancelToken> _creativeAudioCancels = {};

  bool canCancel(ToolPart part) => _toolCancels.containsKey(part.callId);

  /// Stops one running tool: its result becomes "stopped", and what it was
  /// doing is told to quit where that's possible (code, browsing, pages).
  /// A message already handed to Telegram may still go out.
  void cancelTool(ToolPart part) {
    final waiter = _toolCancels.remove(part.callId);
    if (waiter == null || waiter.isCompleted) return;
    _creativeAudioCancels.remove(part.callId)?.cancel();
    switch (part.name) {
      case 'run_code':
        unawaited(ref.read(aiProvider).deviceSandbox.sandbox.cancel());
      case final n when n.startsWith('browser_'):
        unawaited(ref.read(aiProvider).browser.session.stop());
      case 'web_screenshot' || 'web_inspect' || 'web_run_async_js':
        unawaited(ref.read(inAppEngineProvider).stop());
      // E2B can't interrupt a running cell, so the sandbox itself goes.
      case 'e2b_run_code' || 'e2b_run_command':
        unawaited(
          ref.read(e2bSessionProvider).stop(null, 'stopped by the user'),
        );
    }
    final e2b = part.name == 'e2b_run_code' || part.name == 'e2b_run_command';
    final sends = toolNamed(part.name)?.modifiesData ?? false;
    waiter.complete(
      ToolOutput({
        'error':
            'Stopped by the user before it finished.'
            '${e2b
                ? ' The E2B sandbox was shut down, so its files and variables are gone.'
                : sends
                ? ' It may already have reached Telegram or the site; check before trying again.'
                : ''}',
        'stopped': true,
      }),
    );
  }

  Iterable<ToolPart> _runningParts(Conversation c) sync* {
    for (final e in c.entries) {
      if (e is AssistantEntry) {
        for (final s in e.steps) {
          yield* s.tools.where((t) => t.status == ToolStatus.running);
        }
      }
    }
  }

  Iterable<ToolPart> _pendingParts(Conversation c) sync* {
    for (final e in c.entries) {
      if (e is AssistantEntry) {
        for (final s in e.steps) {
          yield* s.tools.where((t) => t.status == ToolStatus.awaitingApproval);
        }
      }
    }
  }

  // ---- sending ---------------------------------------------------------------

  /// Copies a picked file into the app's folder so the conversation keeps
  /// it after the picker's temporary copy is gone.
  static Future<Attachment> attach(String sourcePath, {String? name}) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/attachments',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final base = name ?? sourcePath.split(RegExp(r'[\\/]')).last;
    final dest = await File(sourcePath)
        .copy('${dir.path}/${_uuid.v4().substring(0, 8)}_$base');
    return Attachment(
      path: dest.path,
      name: base,
      mime: lookupMimeType(base) ?? 'application/octet-stream',
      size: await dest.length(),
    );
  }

  Future<void> send(
    String text, {
    List<Attachment> attachments = const [],
  }) async {
    text = text.trim();
    final c = state.conversation;
    // AI chat turned off in Settings: nothing reaches a model from here.
    if (!ref.read(settingsProvider).aiChatEnabled) return;
    if ((text.isEmpty && attachments.isEmpty) || _live.containsKey(c.id))
      return;
    final settings = ref.read(settingsProvider);
    if (settings.haptics) HapticFeedback.lightImpact();
    if (c.entries.isEmpty)
      c.title = _titleFrom(text.isEmpty ? attachments.first.name : text);
    _rememberOpen(c.id);
    c.entries.add(
      UserEntry(id: _uuid.v4(), text: text, attachments: attachments),
    );
    final reply = AssistantEntry(id: _uuid.v4(), model: settings.model);
    c.entries.add(reply);
    // Kept live while it runs, so switching chats doesn't stop it and coming
    // back shows it still going.
    _live[c.id] = c;
    state = state.copyWith(busy: true);
    unawaited(_persist(c));
    final firstTitle = c.entries.length == 2 ? c.title : null;
    try {
      // Near the model's limit: summarise older messages first.
      final ctx = contextOf(c);
      if (settings.autoCompact &&
          ctx.window != null &&
          ctx.used > ctx.window! * 0.8)
        await compact(c);
      await _runTurn(c, reply);
      if (firstTitle != null && reply.error == null)
        unawaited(_autoTitle(c, firstTitle));
    } finally {
      _live.remove(c.id);
      if (ref.mounted) {
        if (_onScreen(c)) {
          state = state.copyWith(busy: false);
        } else {
          // Finished while the person was in another chat: mark it unread.
          c.unread++;
          await _persist(c);
        }
      }
    }
  }

  /// Conversations with a turn under way (shown with a spinner in the
  /// drawer).
  Set<String> get runningIds => _live.keys.toSet();

  /// A watch fired: [event] describes what happened. Runs a turn in the
  /// watch's own conversation and returns the assistant's final words, for
  /// the notification.
  /// [accounts] limits the Telegram accounts it may use (null: all), and
  /// [account] is the one its message came from, used when a call names none.
  Future<({String text, String conversationId, bool seen})?> runAutomatic(
    Watch watch,
    String event, {
    List<String>? accounts,
    String? account,
  }) async {
    // Keys load from secure storage a moment after start (or a restore):
    // a watch firing then waits for them instead of reporting none.
    for (var i = 0; i < 40 && !ref.read(settingsProvider).loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final settings = ref.read(settingsProvider);
    if (!settings.hasAnyKey) return null;
    final c = await _targetFor(watch);
    // One turn at a time per conversation: wait for one under way.
    for (var i = 0; i < 120 && _live.containsKey(c.id); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    c.entries.add(UserEntry(id: _uuid.v4(), text: event, event: watch.name));
    final reply = AssistantEntry(id: _uuid.v4(), model: settings.model);
    c.entries.add(reply);
    _live[c.id] = c;
    if (_onScreen(c)) state = state.copyWith(busy: true);
    unawaited(_persist(c));
    try {
      await _withAccounts(c, accounts, account, () => _runTurn(c, reply, watch: watch));
    } finally {
      _live.remove(c.id);
      if (ref.mounted && _onScreen(c)) state = state.copyWith(busy: false);
    }
    final seen = _seen(c);
    if (!seen) {
      c.unread++;
      _touch(c);
      await _persist(c);
    }
    final text = reply.steps
        .map((s) => s.text)
        .where((t) => t.trim().isNotEmpty)
        .join('\n')
        .trim();
    return (text: reply.error ?? text, conversationId: c.id, seen: seen);
  }

  Future<void> _runTurn(
    Conversation c,
    AssistantEntry reply, {
    Watch? watch,
  }) async {
    final settings = ref.read(settingsProvider);
    final ai = ref.read(aiProvider);
    await ref.read(decisionSettingsProvider.notifier).ready;
    final model = canonicalModelId(settings.model);
    _stopping.remove(c.id);
    final runner = ref.read(toolRunnerProvider);
    final connected = ref.read(integrationsProvider).connected;
    final accounts = _accountsFor(c.id);
    // Telegram tools work when any account the assistant may use is signed
    // in, not only the one on screen.
    final telegram =
        accounts.forAi.isNotEmpty ||
        (_accountViews[c.id] == null &&
            ref.read(telegramClientProvider).authState is td.AuthorizationStateReady &&
            accounts.active.aiAccess);
    final offered = [
      for (final t in telegramTools)
        // Hidden runs (briefs) only read, so they aren't offered the rest.
        if (toolOnSomewhere(t, settings, accounts) &&
            !(_hidden.contains(c.id) && t.modifiesData) &&
            toolPrerequisiteProblems(
              t,
              settings,
              telegram: telegram,
              connected: connected,
              modelSeesImages: _modelSees(),
              decisionsReady: ref.read(decisionsReadyProvider),
            ).isEmpty)
          t,
    ];
    bool stopped() => _stopping.contains(c.id);

    final agent = ai.agent(
      name: 'triangle',
      instructions:
          '${_systemPrompt(c.id, watch: watch)}\n${c.id == voiceConversationId ? '$_voiceGuidance\n' : ''}${await ai.memory.prompt() ?? ''}\n'
          '${await _capabilityGuidance(offered)}',
      model: model,
      // Every tool, omni_ai's included, is the app's: switches, approval
      // cards and read-only rules apply the same way.
      toolkits: const [],
      useInstalledSkills: false,
      tools: [for (final t in offered) _asTool(t, c, runner, watch)],
      // Memory tools use the same per-call read-only and approval guards.
      limits: omni.AgentLimits(maxSteps: settings.maxSteps.clamp(2, 40)),
      reasoning: reasoningFor(settings.thinking),
      onToolApproval: (call) => _approve(call, c, watch),
      // One at a time: Telegram rate-limits, and approval cards come in order.
      parallelToolCalls: false,
    );
    ModelStep? s;
    DateTime? thinkingStart;
    var lastPaint = DateTime.now();
    void endThinking() {
      final step = s;
      if (thinkingStart != null && step != null && step.thinkingMs == null) {
        step.thinkingMs = DateTime.now()
            .difference(thinkingStart)
            .inMilliseconds;
      }
    }

    try {
      final session = agent.session(history: await _history(c, model));
      final run = _runs[c.id] = session.respond();
      // A stop pressed while the history was being read.
      if (stopped()) run.cancel();
      await for (final p in run.fullStream) {
        switch (p) {
          case omni.StepStart():
            final step = s = ModelStep();
            reply.steps.add(step);
            thinkingStart = null;
          case omni.ReasoningDelta(:final text):
            thinkingStart ??= DateTime.now();
            s?.reasoning += text;
          case omni.TextDelta(:final text):
            endThinking();
            s?.text += text;
          case omni.ToolCallStart(:final id, :final name):
            endThinking();
            final step = s;
            if (step != null && _partIn(step, id) == null)
              step.tools.add(ToolPart(callId: id, name: name));
          case omni.ToolCall(:final call):
            endThinking();
            final step = s;
            final part = step == null ? null : _partIn(step, call.id);
            if (part == null) {
              step?.tools.add(
                ToolPart(
                  callId: call.id,
                  name: call.name,
                  arguments: jsonEncode(call.input),
                  extra: call.providerData,
                ),
              );
            } else {
              part
                ..arguments = jsonEncode(call.input)
                ..extra = call.providerData;
            }
          case omni.ToolResult(:final result):
            // The app's own tools fill their card as they run; this covers
            // omni_ai's tools and calls that never ran.
            final step = s;
            final part = step == null ? null : _partIn(step, result.toolCallId);
            if (part != null && part.result == null) {
              part
                ..result = result.outputText
                ..status = result.isError ? ToolStatus.error : ToolStatus.done
                ..durationMs = DateTime.now()
                    .difference(part.startedAt)
                    .inMilliseconds;
            }
          case omni.StepFinish(:final usage, :final providerData):
            endThinking();
            final step = s;
            step?.providerData = providerData;
            if (step != null && (usage.totalTokens > 0 || usage.cost != null)) {
              step.usage = ref
                  .read(usageProvider.notifier)
                  .recordChat(
                    model: model,
                    usage: usage,
                    info: ref.read(modelCatalogProvider).byId(model),
                    conversationId: c.id,
                    conversationTitle: c.title,
                  );
            }
            unawaited(_persist(c));
          default:
            break;
        }
        // Repaint at most every 40 ms while text streams in.
        final now = DateTime.now();
        if (p is! omni.TextDelta && p is! omni.ReasoningDelta ||
            now.difference(lastPaint).inMilliseconds > 40) {
          lastPaint = now;
          _touch(c);
        }
      }
      if (stopped() &&
          reply.steps.isNotEmpty &&
          reply.steps.last.text.isEmpty) {
        reply.error = 'Stopped.';
      }
    } catch (e) {
      reply.error = stopped()
          ? 'Stopped.'
          : (e is omni.AiException
                ? aiErrorText(e)
                : 'Something went wrong: $e');
    } finally {
      endThinking();
      // Calls the model made that never ran (a stop or an error).
      for (final step in reply.steps) {
        for (final t in step.tools.where((t) => t.result == null)) {
          t
            ..status = ToolStatus.error
            ..result = jsonEncode({'error': 'Stopped by the user.'});
        }
      }
      // Drop an empty trailing step left by a stop or an error.
      if (reply.steps.isNotEmpty) {
        final last = reply.steps.last;
        if (last.text.isEmpty && last.reasoning.isEmpty && last.tools.isEmpty)
          reply.steps.removeLast();
      }
      reply.done = true;
      _runs.remove(c.id);
      _stopping.remove(c.id);
      _touch(c);
      if (ref.mounted) await _persist(c);
    }
  }

  static ToolPart? _partIn(ModelStep s, String callId) =>
      s.tools.where((t) => t.callId == callId).firstOrNull;

  ToolPart? _partOf(Conversation c, String callId) {
    for (final e in c.entries.reversed) {
      if (e is AssistantEntry) {
        for (final s in e.steps.reversed) {
          final p = _partIn(s, callId);
          if (p != null) return p;
        }
      }
    }
    return null;
  }

  /// Whether this call has to wait for a tap, given the approval setting
  /// and whether a watch is running it.
  bool _mustAsk(TelegramTool tool, Watch? watch, Conversation c, Map<String, dynamic> input) {
    if (!tool.requiresApproval) return false;
    // Destructive and money-spending tools always ask, whatever the
    // approval setting.
    if (tool.destructive || tool.alwaysAsk) return true;
    // An account can have its own approval mode for actions in it.
    final view = _accountsFor(c.id);
    final account = isAccountTool(tool) ? view.byId(accountForCall(view, input)) : null;
    return switch (approvalModeFor(ref.read(settingsProvider), account)) {
      ApprovalMode.ask => true,
      ApprovalMode.watches => watch == null,
      ApprovalMode.never => false,
    };
  }

  /// One of the app's tools as an omni_ai tool. The agent asks [_approve]
  /// when the approval policy says so; the call itself runs in [_execute].
  omni.Tool _asTool(
    TelegramTool t,
    Conversation c,
    TelegramToolRunner runner,
    Watch? watch,
  ) => omni.Tool(
    name: t.name,
    description: t.description,
    // With several accounts, Telegram tools take an `account` to act in.
    parametersJson: parametersWithAccount(t, _accountsFor(c.id), ref.read(settingsProvider)),
    label: t.label,
    approval: !t.requiresApproval
        ? omni.ApprovalPolicy.never
        // Brief runs never act, so every acting call goes to _approve,
        // which refuses it.
        : omni.ApprovalPolicy.when(
            (input) =>
                _hidden.contains(c.id) ||
                (_mustAsk(t, watch, c, input) && callNeedsApproval(t, input)),
          ),
    execute: (input) =>
        _execute(t, omni.ToolContext.current!.call.id, c, runner, watch: watch),
  );

  /// What the model should know about installed skills and MCP servers,
  /// when their tools are offered.
  Future<String> _capabilityGuidance(List<TelegramTool> offered) async {
    final ai = ref.read(aiProvider);
    final names = {for (final t in offered) t.name};
    final out = StringBuffer();
    if (names.contains('load_skill'))
      out.writeln(await ai.skills.prompt() ?? '');
    if (names.contains('jev_batch')) {
      out.writeln(
        '- To judge several items with Jev (messages, emails, reviews), gather them first, then call jev_batch '
        'once with every item and its id. Never call a Jev tool once per item.',
      );
    }
    if (names.contains('mcp_call_tool')) {
      final servers = await ai.mcp.list();
      out.writeln(
        servers.isEmpty
            ? '- No MCP servers are installed; mcp_search finds them and mcp_install_catalog installs one.'
            : '- Installed MCP servers: ${servers.map((s) => s.id).join(', ')}. mcp_list_tools shows a server\'s tools; '
                  'mcp_call_tool uses one.',
      );
    }
    return out.toString();
  }

  /// Runs one of omni_ai's Jev, MCP or skills tools for [name]. The app has
  /// already checked its switch, read-only mode and approval.
  /// The assistant's home-screen widget tools.
  Future<ToolOutput> _widgetTool(String name, Map<String, dynamic> a) async {
    final store = ref.read(homeWidgetsProvider.notifier);
    await store.ready;
    List<WidgetItem>? items() => a['items'] is List
        ? [
            for (final i in a['items'] as List)
              if (i is Map) WidgetItem.fromJson(i),
          ]
        : null;
    String? text(String k) =>
        a[k] is String && (a[k] as String).trim().isNotEmpty
        ? (a[k] as String).trim()
        : null;
    int? hours() => (a['every_hours'] as num?)?.toInt();
    switch (name) {
      case 'create_widget':
        final d = await store.create(
          title: text('title') ?? 'Widget',
          prompt: text('shows') ?? '',
          everyHours: hours(),
          items: items() ?? const [],
        );
        return ToolOutput({
          ...d.describe(),
          'note': d.byAssistant
              ? 'Its first refresh is running now in its own chat; after that a scheduled watch refreshes it every '
                    '${d.everyHours} h with update_widget. Don\'t fill it yourself.'
              : 'Static: change it with update_widget.',
          'add_it': 'On Android: long-press the home screen → Widgets → Triangle. Settings → Home-screen widgets picks what each widget shows.',
        });
      case 'update_widget':
        final id = text('widget_id') ?? '';
        if (store.byId(id) == null)
          return const ToolOutput({
            'error': 'No widget with that id. list_widgets shows them.',
          });
        if (store.byId(id)!.isBrief)
          return const ToolOutput({
            'error':
                'The brief widget shows the latest brief; it can\'t be edited.',
          });
        if (text('shows') != null || hours() != null || text('title') != null) {
          await store.edit(
            id,
            title: text('title'),
            prompt: text('shows'),
            everyHours: hours(),
          );
        }
        final rows = items();
        final d = rows == null
            ? store.byId(id)!
            : (await store.setItems(id, rows))!;
        return ToolOutput({
          ...d.describe(),
          if (rows != null)
            'images_saved': d.items.where((i) => i.imagePath != null).length,
          if (rows != null &&
              rows.any((i) => i.imageUrl != null) &&
              d.items.every((i) => i.imagePath == null))
            'note': 'No picture could be saved: image_url must be an https link straight to an image under 4 MB.',
        });
      case 'list_widgets':
        return ToolOutput({
          'widgets': [
            for (final d in ref.read(homeWidgetsProvider)) d.describe(),
          ],
        });
      case 'delete_widget':
        final id = text('widget_id') ?? '';
        if (id == briefWidgetId)
          return const ToolOutput({
            'error': 'The brief widget is built in and can\'t be deleted.',
          });
        return await store.remove(id)
            ? const ToolOutput({'deleted': true})
            : const ToolOutput({'error': 'No widget with that id.'});
    }
    return ToolOutput({'error': 'Unknown tool $name.'});
  }

  Future<ToolOutput> _runCapability(
    String name,
    Map<String, dynamic> input,
    Conversation c,
  ) async {
    final clock = Stopwatch()..start();
    // Pictures a Jev call names come from this chat's files or the web.
    if (name.startsWith('jev_'))
      ref.read(aiProvider).jev.resolveImage = (pic) => _jevPicture(pic, c);
    final out = await _capability(name, input);
    ref
        .read(usageProvider.notifier)
        .recordCapability(
          tool: name,
          input: input,
          output: out.json,
          ms: clock.elapsedMilliseconds,
          conversationId: c.id,
          conversationTitle: c.title,
        );
    return out;
  }

  /// A picture for Jev: a file in [c] (by name or path), a file the app
  /// keeps, or an https link. Formats Jev doesn't take, and large photos,
  /// are redrawn as a PNG at most 1600 px wide.
  Future<List<int>?> _jevPicture(String pic, Conversation c) async {
    List<int>? bytes;
    final ref = pic.trim();
    final uri = Uri.tryParse(ref);
    if (uri != null && uri.scheme == 'https') {
      try {
        final r = await http.get(uri).timeout(const Duration(seconds: 30));
        if (r.statusCode < 400 && r.bodyBytes.length < 20 * 1024 * 1024)
          bytes = r.bodyBytes;
      } catch (_) {}
    } else {
      final want = ref.toLowerCase();
      final known = sendableFiles(c).reversed.toList();
      final hit =
          known.where((a) => a.name.toLowerCase() == want).firstOrNull ??
          known
              .where(
                (a) =>
                    a.name.toLowerCase().contains(want) ||
                    a.path.toLowerCase().endsWith(want),
              )
              .firstOrNull;
      final path = hit?.path ?? ref;
      final root = (await getApplicationSupportDirectory()).path;
      // Only the chat's files and the app's own: never anywhere on the phone.
      if (hit != null || path.startsWith(root)) {
        final f = File(path);
        if (await f.exists()) bytes = await f.readAsBytes();
      }
    }
    if (bytes == null) return null;
    final ok = omni.JevImage.detect(bytes) != null;
    if (ok && bytes.length <= 4 * 1024 * 1024) return bytes;
    try {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final first = (await codec.getNextFrame()).image;
      final scaled = first.width > 1600
          ? (await (await ui.instantiateImageCodec(
              Uint8List.fromList(bytes),
              targetWidth: 1600,
            )).getNextFrame()).image
          : first;
      final png = await scaled.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } catch (_) {
      return ok ? bytes : null;
    }
  }

  Future<ToolOutput> _capability(
    String name,
    Map<String, dynamic> input,
  ) async {
    final ai = ref.read(aiProvider);
    final tools = name.startsWith('jev_')
        ? await ai.jev.tools()
        : name.startsWith('mcp_')
        ? await ai.mcp.managementTools()
        : await ai.skills.tools();
    final tool = tools.where((t) => t.name == name).firstOrNull;
    if (tool == null) return ToolOutput({'error': 'Unknown tool $name.'});
    try {
      final result = await tool.execute!(input);
      return ToolOutput(switch (result) {
        final Map m => Map<String, dynamic>.from(m),
        final String text => {'result': text},
        final other => {'result': other},
      });
    } on omni.AiException catch (e) {
      return ToolOutput({'error': e.message});
    } on ArgumentError catch (e) {
      return ToolOutput({'error': '${e.message}'});
    }
  }

  /// Asks the person about a call: its card waits for a tap (with a
  /// notification when a watch is running it). An approved message carries
  /// the text and files the person settled on.
  Future<omni.ToolApprovalDecision> _approve(
    omni.ToolCallPart call,
    Conversation c,
    Watch? watch,
  ) async {
    final part = _partOf(c, call.id);
    final tool = toolNamed(call.name);
    if (part == null || tool == null)
      return const omni.ToolApprovalDecision.deny();
    // Not asked about at all when it doesn't say which account acts.
    final accountProblem = _accountProblem(tool, part.args, watch, c);
    if (accountProblem != null) {
      part
        ..status = ToolStatus.error
        ..result = jsonEncode({'error': accountProblem});
      _touch(c);
      return omni.ToolApprovalDecision.deny(accountProblem);
    }
    // The approval card shows the account that will act, so a call that
    // relies on the default gets it written in.
    if (isAccountTool(tool) && ref.read(accountsProvider).hasSeveral) {
      final view = _accountsFor(c.id);
      final named = part.args[accountArgument];
      if (named == null || '$named'.trim().isEmpty) {
        part.arguments = jsonEncode({...part.args, accountArgument: accountForCall(view, part.args)});
      }
    }
    if (_hidden.contains(c.id)) {
      const why =
          'This is a read-only run (a brief): nothing can be sent or changed.';
      part
        ..status = ToolStatus.denied
        ..result = jsonEncode({'error': why});
      return const omni.ToolApprovalDecision.deny(why);
    }
    part.status = ToolStatus.awaitingApproval;
    final decision = _approvals[part.callId] = Completer<bool>();
    _touch(c);
    if (watch != null) {
      unawaited(
        ref
            .read(appNotifierProvider)
            .show(
              'Approval needed · ${watch.name}',
              '${tool.label}. Open to approve or decline.',
              conversationId: c.id,
            ),
      );
    }
    if (!await decision.future) {
      const why =
          'The user declined. Nothing was done. Don\'t retry unless they ask.';
      part
        ..status = ToolStatus.denied
        ..result = jsonEncode({'error': why});
      _touch(c);
      return const omni.ToolApprovalDecision.deny(why);
    }
    final edit = _approvalEdits.remove(part.callId);
    if (edit != null) {
      part.arguments = jsonEncode({
        ...part.args,
        'text': ?edit.text,
        if (edit.files != null) 'files': [for (final f in edit.files!) f.path],
        if (edit.asFiles != null) 'send_as': edit.asFiles! ? 'file' : 'media',
      });
    }
    _asked.add(part.callId);
    part.status = ToolStatus.running;
    _touch(c);
    return omni.ToolApprovalDecision.approve(input: part.args);
  }

  /// Calls the person approved with a tap (the others that act ran on the
  /// approval setting alone).
  final Set<String> _asked = {};

  /// Why a Telegram call can't go ahead in the account it names (or doesn't
  /// name), or null when it can.
  String? _accountProblem(TelegramTool tool, Map<String, dynamic> args, Watch? watch, Conversation c) {
    if (!isAccountTool(tool)) return null;
    final accounts = _accountsFor(c.id);
    if (accounts.forAi.isEmpty && _accountViews[c.id] != null) {
      return 'This run may not use any Telegram account (its accounts are off for the assistant or signed out).';
    }
    final target = accounts.byId(accountForCall(accounts, args));
    if (target != null && !target.aiAccess) {
      return 'The user turned off assistant access to ${target.label} (Settings → Telegram → Accounts).';
    }
    if (accounts.forAi.length < 2) return null;
    final named = args[accountArgument];
    final given = named != null && '$named'.trim().isNotEmpty;
    if (given && resolveAccount(accounts, named) == null) {
      return 'No Telegram account "$named" the assistant may use. Use one of: ${accounts.forAi.map(accountHandle).join(', ')}.';
    }
    // A tool switched off (or a read-only account) where the user is
    // working isn't done through another account instead, unless they
    // named that account or allow it (Settings → Approvals).
    final settings = ref.read(settingsProvider);
    final home = accounts.byId(defaultAiAccount(accounts));
    if (!settings.accountFallback && home != null && target != null && target.id != home.id && !toolOnFor(tool, settings, home)) {
      final asked = c.entries.whereType<UserEntry>().lastOrNull?.text ?? '';
      if (!namesAccount(asked, target)) {
        return '${tool.name} is off in ${home.label}, the account the user is working in, and the user doesn\'t let the assistant '
            'use another account instead (Settings → Approvals → "Use another account when a tool is off"). Don\'t try other '
            'accounts: tell the user it is off in ${home.label}. They can ask for ${accountHandle(target)} by name if they want that account.';
      }
    }
    // Acting in the wrong account (a reply from work sent as personal)
    // can't be taken back, so actions always say which account. Watches
    // act in the account their message came from (or their first one).
    if (!given && tool.modifiesData && watch == null) {
      return 'Several Telegram accounts are connected. Call again with account set to one of: '
          '${accounts.forAi.map(accountHandle).join(', ')}: the one the user meant (ask if it is unclear).';
    }
    return null;
  }

  /// Runs one of the app's tools for the call [callId] and records what it
  /// did on its card.
  Future<omni.ToolOutput> _execute(
    TelegramTool tool,
    String callId,
    Conversation c,
    TelegramToolRunner runner, {
    Watch? watch,
  }) async {
    final part =
        _partOf(c, callId) ?? ToolPart(callId: callId, name: tool.name);
    final timer = Stopwatch()..start();
    final settings = ref.read(settingsProvider);
    // Which Telegram account this call acts in, when it is a Telegram tool.
    final accounts = _accountsFor(c.id);
    final accountId = isAccountTool(tool) ? accountForCall(accounts, part.args) : null;
    final account = accountId == null ? null : accounts.byId(accountId);
    // Tools that touch Telegram without being routed (view_image reading a
    // post) use the run's default account.
    final runAccount = accountId ?? defaultAiAccount(accounts);
    final accountProblem = _accountProblem(tool, part.args, watch, c);
    if (accountProblem != null) {
      final out = {'error': accountProblem};
      part
        ..status = ToolStatus.error
        ..result = jsonEncode(out);
      _touch(c);
      return omni.ToolOutput(out);
    }
    // Apps & web and device tools follow the switches of the account being
    // worked in, Telegram tools those of the account they act in.
    final switchesOf = account ?? (accounts.hasSeveral ? accounts.byId(runAccount) : null);
    final on = switchesOf == null ? tool.isOn(settings) : toolOnFor(tool, settings, switchesOf);
    if (!on || (_hidden.contains(c.id) && tool.modifiesData)) {
      // Turned off in Settings while the answer was running.
      final out = {
        'error':
            (settings.readOnlyMode || _hidden.contains(c.id)) &&
                tool.modifiesData
            ? 'Read-only mode is on in Settings: nothing can be sent or changed.'
            : account != null && account.readOnly && tool.modifiesData
            ? '${account.label} is read-only for the assistant (Settings → Telegram → Accounts): nothing can be sent or changed there.'
            : 'The user turned this tool off in Settings${switchesOf != null && switchesOf.customTools ? ' for ${switchesOf.label}' : ''}.'
                  '${switchesOf != null && accounts.forAi.length > 1 && !settings.accountFallback ? ' Don\'t use another account to do it instead.' : ''}',
      };
      part
        ..status = ToolStatus.error
        ..result = jsonEncode(out);
      return omni.ToolOutput(out);
    }
    if (tool.requiresApproval && !_asked.remove(callId))
      part.autoApproved = true;
    part.status = ToolStatus.running;
    _touch(c);
    _resolveFiles(part, c);
    Future<ToolOutput> work() async {
      if (_memoryTools.contains(part.name)) {
        final memoryTool = (await ref.read(aiProvider).memory.tools())
            .firstWhere((t) => t.name == part.name);
        final result = await memoryTool.execute!(part.args);
        return ToolOutput(Map<String, dynamic>.from(result as Map));
      }
      if (part.name == getModelSettingsTool.name) return _modelSettings();
      if (part.name == generateImageTool.name)
        return _generateImage(part.args, c);
      if (part.name == generateVideoTool.name)
        return _generateVideo(part.args, c);
      if (part.name == generateAudioTool.name) return _generateAudio(part.args);
      if (part.name == generateAddisVoiceTool.name)
        return _generateAddisAudio(part.args);
      if (part.name == generateSoundEffectTool.name)
        return _generateCreativeAudio(part.args, music: false);
      if (part.name == generateMusicTool.name)
        return _generateCreativeAudio(part.args, music: true);
      if (_localTools.contains(part.name))
        return _runLocalTool(part.name, withoutAccount(part.args), c, account: runAccount);
      if (capabilityToolNames.contains(part.name))
        return _runCapability(part.name, part.args, c);
      if (canvasToolNames.contains(part.name)) {
        try {
          return await runCanvasTool(ref, part.name, withoutAccount(part.args), account: runAccount);
        } on ArgumentError catch (e) {
          return ToolOutput({'error': '${e.message}'});
        }
      }
      return ref.read(toolRunnerFamily(runAccount)).run(part.name, withoutAccount(part.args));
    }

    // A tool can be stopped while it runs (Stop on its card or sheet, or
    // stopping the whole answer); whatever it was doing is told to quit,
    // and the model hears that it was stopped.
    final cancel = _toolCancels[part.callId] = Completer<ToolOutput>();
    ToolOutput out;
    try {
      out = await Future.any([work(), cancel.future]);
    } catch (e) {
      // A tool that fails unexpectedly fails alone, not the whole answer.
      out = ToolOutput({
        'error': 'The tool failed: ${e is UnsupportedError ? e.message : e}',
      });
    } finally {
      _toolCancels.remove(part.callId);
    }
    for (final p in out.posts) {
      c.posts[p.key] = p;
    }
    part
      ..result = out.encode()
      ..full = _fullText(out.full)
      ..status = out.json.containsKey('error')
          ? ToolStatus.error
          : ToolStatus.done
      ..durationMs = timer.elapsedMilliseconds;
    _touch(c);
    return omni.ToolOutput(out.json, modelFiles: await _imagesFor(out.json));
  }

  /// A tool's complete response as stored with the conversation; very large
  /// ones are left out so saving the chat stays quick.
  static String? _fullText(Object? full) {
    if (full == null) return null;
    try {
      final text = jsonEncode(full);
      return text.length > 2 << 20 ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Pictures a tool fetched for the model to look at (view_image,
  /// view_profile_photo), when the model can see.
  Future<List<omni.FilePart>> _imagesFor(Map<String, dynamic> result) async {
    final paths = result['_images'];
    if (paths is! List || paths.isEmpty || !_modelSees()) return const [];
    return [
      for (final path in paths.map((p) => '$p'))
        if (await File(path).exists())
          omni.FilePart.image(
            await File(path).readAsBytes(),
            mediaType: lookupMimeType(path),
          ),
    ];
  }

  bool _modelSees() =>
      ref
          .read(modelCatalogProvider)
          .byId(ref.read(settingsProvider).model)
          ?.vision ??
      true;

  // ---- memory, watches, notifications ---------------------------------------

  Future<ToolOutput> _runLocalTool(
    String name,
    Map<String, dynamic> a,
    Conversation c, {
    required String account,
  }) async {
    final watches = ref.read(watchStoreProvider.notifier);
    final allAccounts = ref.read(accountsProvider);
    // "accounts": the Telegram accounts a watch or job covers.
    final List<String>? scopeAccounts;
    try {
      scopeAccounts = accountsArgument(allAccounts, a['accounts']);
    } on FormatException catch (e) {
      return ToolOutput({'error': e.message});
    }
    String str(String k) => '${a[k] ?? ''}'.trim();
    List<int>? ids(String k) => a[k] is List
        ? [
            for (final v in a[k] as List)
              if (v is num) v.toInt(),
          ]
        : null;
    int? integer(String k) =>
        a[k] is num ? (a[k] as num).toInt() : int.tryParse('${a[k] ?? ''}');
    switch (name) {
      case 'create_watch':
        final scope = switch (str('trigger')) {
          'all_dms' => WatchScope.allDms,
          'all_groups' => WatchScope.allGroups,
          'all_channels' => WatchScope.allChannels,
          'mentions' => WatchScope.mentions,
          'folder' => WatchScope.folder,
          'schedule' => WatchScope.schedule,
          'app' => WatchScope.app,
          _ => WatchScope.chats,
        };
        if (scope.needsTelegram && allAccounts.signedIn.isEmpty &&
            ref.read(telegramClientProvider).authState
                is! td.AuthorizationStateReady) {
          return const ToolOutput({
            'error': 'That trigger needs Telegram, which isn\'t connected. Use a schedule or an app watch, or ask the user to connect Telegram (Settings → Apps & web → Telegram).',
          });
        }
        if (scope == WatchScope.app && str('app').isEmpty) {
          return const ToolOutput({
            'error': 'Give app (e.g. gmail) for an app watch.',
          });
        }
        if (scope == WatchScope.chats &&
            (ids('chat_ids') ?? const []).isEmpty) {
          return const ToolOutput({
            'error': 'Give chat_ids for a chats watch.',
          });
        }
        if (scope == WatchScope.schedule &&
            a['daily_at'] == null &&
            a['every_minutes'] == null) {
          return const ToolOutput({
            'error': 'Give daily_at or every_minutes for a schedule.',
          });
        }
        final mode =
            WatchMode.values.asNameMap()[str('mode')] ?? WatchMode.notify;
        final w = await watches.add(
          (id) => Watch(
            id: id,
            name: str('name').isEmpty ? 'Watch' : str('name'),
            scope: scope,
            mode: mode,
            chatIds: ids('chat_ids') ?? const [],
            folderId: integer('folder_id'),
            instructions: str('instructions'),
            includeMuted: a['include_muted'] != false,
            notify: a['notify'] != false,
            dailyAt: a['daily_at'] == null ? null : str('daily_at'),
            everyMinutes: integer('every_minutes')?.clamp(15, 100000),
            app: scope == WatchScope.app ? str('app').toLowerCase() : null,
            query: str('query'),
            // Updates come back to the conversation it was set up in.
            conversationId: c.entries.isEmpty ? null : c.id,
            createdAt: DateTime.now(),
            accountIds: scope == WatchScope.folder ? null : scopeAccounts,
            // A folder id means a folder of one account: the one named, or
            // the one this call reads.
            folderAccountId: scope == WatchScope.folder
                ? (scopeAccounts?.length == 1 ? scopeAccounts!.first : account)
                : null,
          ),
        );
        final settings = ref.read(settingsProvider);
        return ToolOutput({
          'created': true,
          ...w.describe(),
          if (!settings.proactive) 'note': 'Watches are paused in Settings (Proactivity is off); tell the user.',
          if (mode == WatchMode.act &&
              settings.approvalMode == ApprovalMode.ask)
            'approvals': 'Actions this watch takes will still wait for the user\'s approval (Settings → Approvals).',
        });
      case 'list_watches':
        return ToolOutput({
          'proactivity_on': ref.read(settingsProvider).proactive,
          'watches': [
            for (final w in ref.read(watchStoreProvider)) w.describe(),
          ],
        });
      case 'update_watch':
        final w = await watches.update(
          str('watch_id'),
          (w) => w.copyWith(
            enabled: a['enabled'] is bool ? a['enabled'] as bool : null,
            name: a['name'] == null ? null : str('name'),
            chatIds: ids('chat_ids'),
            mode: WatchMode.values.asNameMap()[str('mode')],
            instructions: a['instructions'] == null
                ? null
                : str('instructions'),
            dailyAt: a['daily_at'] == null ? null : str('daily_at'),
            everyMinutes: integer('every_minutes'),
            includeMuted: a['include_muted'] is bool
                ? a['include_muted'] as bool
                : null,
            notify: a['notify'] is bool ? a['notify'] as bool : null,
            accountIds: scopeAccounts,
            allAccounts: a.containsKey('accounts') && scopeAccounts == null,
          ),
        );
        return w == null
            ? const ToolOutput({'error': 'No watch with that id.'})
            : ToolOutput({'updated': true, ...w.describe()});
      case 'online_alert':
        final userId = integer('user_id');
        if (userId == null)
          return const ToolOutput({'error': 'user_id is required'});
        final alerts = ref.read(onlineAlertStoreProvider.notifier);
        final store = ref.read(telegramStoreFamily(account));
        final name = store.userName(userId);
        if (a['remove'] == true) {
          return ToolOutput({
            'removed': await alerts.remove(userId),
            'who': name,
          });
        }
        await alerts.add(userId, name, once: a['once'] != false);
        final status = store.users[userId]?.status;
        final settings = ref.read(settingsProvider);
        return ToolOutput({
          'set': true,
          'who': name,
          'repeats': a['once'] == false,
          'online_now': status is td.UserStatusOnline,
          if (status is td.UserStatusRecently ||
              status is td.UserStatusLastWeek ||
              status is td.UserStatusLastMonth ||
              status is td.UserStatusEmpty)
            'warning':
                '$name hides their exact last seen from the user, so Telegram may not report when they come online.',
          if (!settings.keepAlive && !settings.backgroundAlways) 'note': '"Keep running in the background" is off, so alerts only work while the app is open.',
        });
      case 'list_online_alerts':
        final store = ref.read(telegramStoreFamily(account));
        return ToolOutput({
          'alerts': [
            for (final x in ref.read(onlineAlertStoreProvider))
              {
                'user_id': x.userId,
                'who': store.users.containsKey(x.userId)
                    ? store.userName(x.userId)
                    : x.name,
                'online_now':
                    store.users[x.userId]?.status is td.UserStatusOnline,
                'repeats': !x.once,
                if (x.fired > 0) 'times_alerted': x.fired,
              },
          ],
        });
      case 'create_widget' ||
          'update_widget' ||
          'list_widgets' ||
          'delete_widget':
        return _widgetTool(name, a);
      case 'delete_watch':
        if (watches.byId(str('watch_id'))?.builtIn ?? false) {
          return const ToolOutput({
            'error': 'The check-in is built in: it can be changed or turned off (update_watch with enabled false), not deleted.',
          });
        }
        return await watches.remove(str('watch_id'))
            ? const ToolOutput({'deleted': true})
            : const ToolOutput({'error': 'No watch with that id.'});
      case 'list_attachments':
        final files = sendableFiles(c);
        return ToolOutput({
          'count': files.length,
          'files': [
            for (final f in files.reversed)
              {
                'name': f.name,
                'type': f.isImage
                    ? 'image'
                    : f.isAudio
                    ? 'voice/audio'
                    : f.isVideo
                    ? 'video'
                    : f.isPdf
                    ? 'pdf'
                    : 'file',
                'mime': f.mime,
                if (f.size > 0) 'size_kb': (f.size / 1024).ceil(),
              },
          ],
          'note': 'Send any of these with send_message (or send_voice_message for voice notes) by passing the name in files.',
        });
      case 'transcribe_message':
        final chatId = (a['chat_id'] as num?)?.toInt();
        final messageId = (a['message_id'] as num?)?.toInt();
        if (chatId == null || messageId == null)
          return const ToolOutput({
            'error': 'chat_id and message_id are required.',
          });
        final f = await ref
            .read(toolRunnerFamily(account))
            .downloadMessageFile(chatId, messageId);
        if (f == null ||
            !const {'voice', 'audio', 'video_note', 'video'}.contains(f.kind)) {
          return const ToolOutput({
            'error': 'That message has no voice, audio or video to listen to.',
          });
        }
        final text = await _transcript(
          Attachment(path: f.path, name: f.name, mime: f.mime, size: f.size),
          language: (a['language'] as String?)?.trim(),
        );
        if (text == null) {
          return ToolOutput({
            'error': 'Couldn\'t transcribe it. Add an ElevenLabs key, or pick a dictation model whose key is set, in Settings → AI & models → Voice.',
            'created_files': [f.path],
          });
        }
        return ToolOutput({
          'chat': ref.read(telegramStoreFamily(account)).chat(chatId)?.title,
          'kind': f.kind,
          'duration_seconds': ?f.duration,
          'transcript': text,
          'created_files': [f.path],
        });
      case 'write_brief':
        final hours = (a['since_hours'] as num?)?.toDouble().clamp(1, 72);
        final b = await ref
            .read(briefStoreProvider.notifier)
            .generate(
              BriefKind.manual,
              window: hours == null
                  ? null
                  : Duration(minutes: (hours * 60).round()),
            );
        if (b == null) {
          return const ToolOutput({
            'error': 'A brief is already being written, or no AI key is set.',
          });
        }
        return ToolOutput({
          'brief_id': b.id,
          'written': b.at.toIso8601String().substring(0, 16),
          'covers_since': b.since.toIso8601String().substring(0, 16),
          'text': b.text,
          'error': ?b.error,
        });
      case 'list_briefs':
        final briefs = ref.read(briefStoreProvider).briefs;
        final n = (a['limit'] as num?)?.toInt() ?? 10;
        return ToolOutput({
          'count': briefs.length,
          'briefs': [
            for (final b in briefs.take(n.clamp(1, 50)))
              {
                'brief_id': b.id,
                'kind': b.kind.name,
                'written': b.at.toIso8601String().substring(0, 16),
                'covers_since': b.since.toIso8601String().substring(0, 16),
                'preview': b.text.length > 200
                    ? '${b.text.substring(0, 200)}…'
                    : b.text,
              },
          ],
        });
      case 'view_image':
        final hears =
            ref
                .read(modelCatalogProvider)
                .byId(ref.read(settingsProvider).model)
                ?.vision ??
            true;
        if (!hears) {
          return const ToolOutput({
            'error': 'The model in use can\'t see images. The user can pick a model with image input in Settings.',
          });
        }
        final images = <Map<String, String>>[];
        final missing = <String>[];
        final known = sendableFiles(c).reversed.toList();
        final loader = ImageInputLoader(
          directory: Directory(
            '${(await getApplicationSupportDirectory()).path}/viewed_images',
          ),
        );
        try {
          final inputs = [
            ...(a['files'] as List? ?? const []),
            ...(a['urls'] as List? ?? const []),
          ];
          for (final input in inputs) {
            if (images.length == 6) break;
            final f = '$input'.trim();
            final want = f.toLowerCase();
            final hit = want.isEmpty
                ? null
                : known
                      .where((x) => x.path == f || x.name.toLowerCase() == want)
                      .firstOrNull;
            final label = f.startsWith('data:')
                ? 'Inline image'
                : hit?.name ?? f;
            try {
              final file = await loader.load(hit?.path ?? f);
              images.add({'source': label, 'path': file.path});
            } catch (e) {
              missing.add('$label (could not load as an image)');
            }
          }
        } finally {
          loader.close();
        }
        final runner = ref.read(toolRunnerFamily(account));
        for (final r in (a['refs'] as List? ?? const []).map((e) => '$e')) {
          if (images.length == 6) break;
          final m = RegExp(r'post:(-?\d+):(\d+)').firstMatch(r);
          if (m == null) {
            missing.add(r);
            continue;
          }
          try {
            final path = await runner.messageImage(
              int.parse(m[1]!),
              int.parse(m[2]!),
            );
            path == null
                ? missing.add('$r (no image)')
                : images.add({'source': r, 'path': path});
          } catch (e) {
            missing.add(r);
          }
        }
        return ToolOutput({
          'shown': [for (final i in images.take(6)) i['source']],
          if (missing.isNotEmpty) 'not_found': missing,
          if (images.isEmpty) 'error': 'No images could be loaded. Supply an accessible image path, attachment name, direct image URL, image data URL or Telegram ref.',
          if (images.isNotEmpty)
            'note': 'The images follow in the next message, in this order.',
          '_images': [for (final i in images.take(6)) i['path']],
        });
      case 'read_brief':
        final briefs = ref.read(briefStoreProvider).briefs;
        final id = str('brief_id');
        final b = id == 'latest'
            ? briefs.firstOrNull
            : briefs.where((b) => b.id == id).firstOrNull;
        if (b == null) return const ToolOutput({'error': 'No such brief.'});
        return ToolOutput({
          'brief_id': b.id,
          'kind': b.kind.name,
          'written': b.at.toIso8601String().substring(0, 16),
          'text': b.text,
        }, posts: b.conversation.posts.values.toList());
      case 'create_reminder' || 'update_reminder':
        return _reminder(name, a, c, scopeAccounts);
      case 'list_reminders':
        final all = ref.read(reminderStoreProvider);
        final shown = a['include_done'] == true
            ? all
            : all.where((r) => r.enabled || r.next != null).toList();
        return ToolOutput({
          'now': DateTime.now().toIso8601String().substring(0, 16),
          'reminders': [for (final r in shown) r.describe()],
          if (shown.isEmpty) 'note': 'No reminders.',
        });
      case 'delete_reminder':
        return await ref
                .read(reminderStoreProvider.notifier)
                .remove(str('reminder_id'))
            ? const ToolOutput({'deleted': true})
            : const ToolOutput({'error': 'No reminder with that id.'});
      case 'zip_files':
        return _zip(a, c);
      case 'notify_me':
        await ref
            .read(appNotifierProvider)
            .show(str('title'), str('body'), conversationId: c.id);
        return const ToolOutput({'notified': true});
    }
    return ToolOutput({'error': 'Unknown tool $name'});
  }

  /// Sets up or changes a reminder from the assistant's arguments.
  Future<ToolOutput> _reminder(
    String name,
    Map<String, dynamic> a,
    Conversation c,
    List<String>? accounts,
  ) async {
    final store = ref.read(reminderStoreProvider.notifier);
    final minutes = a['in_minutes'] is num
        ? (a['in_minutes'] as num).toDouble()
        : double.tryParse('${a['in_minutes'] ?? ''}');
    final at = minutes != null
        ? DateTime.now().add(Duration(seconds: (minutes * 60).round()))
        : DateTime.tryParse('${a['at'] ?? ''}');
    final cron = '${a['cron'] ?? ''}'.trim();
    try {
      if (name == 'create_reminder') {
        final text = '${a['text'] ?? ''}'.trim();
        if (text.isEmpty) return const ToolOutput({'error': 'text is empty'});
        final r = await store.add(
          text: text,
          at: at,
          cron: cron.isEmpty ? null : cron,
          prompt: '${a['prompt'] ?? ''}'.trim(),
          conversationId: c.id,
          accountIds: accounts,
        );
        final s = ref.read(settingsProvider);
        return ToolOutput({
          'created': true,
          ...r.describe(),
          if (r.isJob && (!s.proactive || !s.keepAlive)) 'note': 'Jobs run only while the app is alive: tell the user to keep Proactivity and "Keep running in the background" on in Settings.',
        });
      }
      final id = '${a['reminder_id'] ?? ''}'.trim();
      final r = await store.update(
        id,
        (r) => r.copyWith(
          text: a['text'] == null ? null : '${a['text']}'.trim(),
          prompt: a['prompt'] == null ? null : '${a['prompt']}'.trim(),
          enabled: a['enabled'] is bool
              ? a['enabled'] as bool
              : (at != null || cron.isNotEmpty ? true : null),
          next: at,
          cron: cron.isEmpty ? null : cron,
          clearCron: a['cron'] != null && cron.isEmpty,
          accountIds: accounts,
          allAccounts: a.containsKey('accounts') && accounts == null,
        ),
      );
      return r == null
          ? const ToolOutput({'error': 'No reminder with that id.'})
          : ToolOutput({'updated': true, ...r.describe()});
    } on FormatException catch (e) {
      return ToolOutput({'error': e.message});
    }
  }

  /// Packs files of [c] into a zip kept with the app's files.
  Future<ToolOutput> _zip(Map<String, dynamic> a, Conversation c) async {
    final files = [for (final f in (a['files'] as List? ?? const [])) '$f']
        .where((f) => File(f).existsSync())
        .toList();
    if (files.isEmpty)
      return const ToolOutput({
        'error': 'None of those files are here. list_attachments shows what there is.',
      });
    var name = '${a['name'] ?? ''}'.trim();
    if (name.isEmpty)
      name = files.length == 1
          ? '${files.single.split(RegExp(r'[\\/]')).last}.zip'
          : 'files.zip';
    if (!name.toLowerCase().endsWith('.zip')) name = '$name.zip';
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/generated',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final out = '${dir.path}/${_uuid.v4().substring(0, 8)}_$name';
    final known = sendableFiles(c);
    final encoder = ZipFileEncoder()..create(out);
    final used = <String>{};
    try {
      for (final f in files) {
        // Inside the zip, files keep the names the user knows them by.
        var inner =
            known.where((k) => k.path == f).firstOrNull?.name ??
            f.split(RegExp(r'[\\/]')).last;
        for (var i = 2; !used.add(inner); i++) {
          final dot = inner.lastIndexOf('.');
          inner = dot > 0
              ? '${inner.substring(0, dot)} ($i)${inner.substring(dot)}'
              : '$inner ($i)';
        }
        await encoder.addFile(File(f), inner);
      }
    } finally {
      await encoder.close();
    }
    final size = await File(out).length();
    return ToolOutput({
      'created': true,
      'file_path': out,
      'name': out.split(RegExp(r'[\\/]')).last,
      'files': files.length,
      'size_kb': (size / 1024).ceil(),
      'note': 'Send it with send_message by passing its name in files.',
    });
  }

  /// The assistant names files the way it was told about them; the tools
  /// need the stored files. Names (or parts of them) are matched against
  /// what was attached or generated in this conversation, newest first.
  void _resolveFiles(ToolPart part, Conversation c) {
    final args = part.args;
    final raw = args['files'];
    final single = args['file'];
    if ((raw is! List || raw.isEmpty) && single is! String) return;
    final known = sendableFiles(c).reversed.toList();
    String resolve(String f) {
      if (f.trim().isEmpty || RegExp(r'^(https?://|data:|file:)').hasMatch(f))
        return f;
      if (File(f).existsSync()) return f;
      final want = f.toLowerCase().trim();
      final hit =
          known.where((a) => a.name.toLowerCase() == want).firstOrNull ??
          known
              .where(
                (a) =>
                    a.name.toLowerCase().contains(want) ||
                    a.path.toLowerCase().endsWith(want),
              )
              .firstOrNull;
      return hit?.path ?? f;
    }

    part.arguments = jsonEncode({
      ...args,
      if (raw is List && raw.isNotEmpty)
        'files': [for (final f in raw) resolve('$f')],
      if (single is String) 'file': resolve(single),
    });
  }

  final Map<String, String?> _transcripts = {};

  /// What a voice note says, when a transcriber is set up: ElevenLabs Scribe
  /// (it takes Telegram's Opus files as they are), else the dictation model
  /// from Settings. Kept per file.
  Future<String?> _transcript(Attachment a, {String? language}) async {
    final key = '${a.path}|${language ?? ''}';
    if (_transcripts.containsKey(key)) return _transcripts[key];
    final settings = ref.read(settingsProvider);
    final ai = ref.read(aiProvider);
    // Addis AI knows Amharic and Afaan Oromo best: first for those, or when
    // it is the voice engine; otherwise a fallback.
    final addisFirst =
        settings.hasAddisKey &&
        (const {
              'am',
              'om',
              'amharic',
              'oromo',
            }.contains(language?.toLowerCase()) ||
            settings.voiceEngine == VoiceEngine.addis);
    final models = [
      if (addisFirst) 'addis:stt-v2',
      if (settings.hasElevenKey) 'elevenlabs:scribe_v1',
      if (AiRouter.of(settings.transcriptionModel) case final r?
          when ai.provider(r.providerId).isConfigured)
        canonicalModelId(settings.transcriptionModel),
      if (settings.hasAddisKey && !addisFirst) 'addis:stt-v2',
    ];
    String? text;
    for (final model in models) {
      try {
        text = (await ai.transcribe(
          model: model,
          audio: await File(a.path).readAsBytes(),
          mediaType: a.mime,
          language: model.startsWith('addis:')
              ? (language == 'om' || language == 'oromo' ? 'om' : 'am')
              : language,
        )).text;
        if (text.trim().isNotEmpty) break;
      } catch (e) {
        debugPrint('[Chat] transcript of ${a.name} with $model: $e');
      }
    }
    return _transcripts[key] = (text == null || text.trim().isEmpty)
        ? null
        : text.trim();
  }

  /// Keeps generated media in the app's folder, with what made it beside it.
  Future<File> _saveGenerated(
    omni.GeneratedFile media,
    Map<String, dynamic> meta,
  ) async {
    final file = await saveGeneratedBytes(
      '${meta['kind'] ?? 'media'}.${media.extension}',
      media.bytes,
    );
    await _writeGeneratedMeta(file, {
      ...meta,
      'created_at': DateTime.now().toIso8601String(),
    });
    return file;
  }

  ToolOutput _modelSettings() {
    final ai = ref.read(aiProvider);
    return ToolOutput(
      selectedModels(
        settings: ref.read(settingsProvider),
        decisions: ref.read(decisionSettingsProvider),
        catalog: ref.read(modelCatalogProvider),
        providerReady: (id) => ai.provider(id).isConfigured,
      ),
    );
  }

  /// Creates an image with the model from Settings and keeps it on disk.
  Future<ToolOutput> _generateImage(
    Map<String, dynamic> args,
    Conversation conversation,
  ) async {
    final settings = ref.read(settingsProvider);
    final prompt = '${args['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty) return const ToolOutput({'error': 'prompt is empty'});
    final model = canonicalModelId(settings.imageModel);
    final aspect = '${args['aspect'] ?? 'square'}';
    try {
      final result = await ref
          .read(aiProvider)
          .generateImage(
            model: model,
            prompt: prompt,
            aspectRatio: switch (aspect) {
              'portrait' => '2:3',
              'landscape' => '3:2',
              _ => '1:1',
            },
          );
      final file = await _saveGenerated(result.image, {
        'kind': 'image',
        'prompt': prompt,
        'model': model,
        'aspect': aspect,
      });
      ref
          .read(usageProvider.notifier)
          .add(
            UsageEvent(
              at: DateTime.now(),
              model: model,
              modality: Modality.image,
              conversationId: conversation.id,
              conversationTitle: conversation.title,
              units: 1,
              cost:
                  result.usage.cost ??
                  ref.read(modelCatalogProvider).byId(model)?.imagePrice ??
                  0.04,
              estimated: result.usage.cost == null,
            ),
          );
      return ToolOutput({
        'created': true,
        'image_path': file.path,
        'model': model,
        'prompt': prompt,
        'note': 'The image is already shown to the user. Don\'t describe the file path.',
      });
    } on omni.AiException catch (e) {
      return ToolOutput({
        'error': 'Image generation failed: ${aiErrorText(e)}',
      });
    }
  }

  /// Makes a video with the model from Settings, optionally from a picture
  /// in the chat, and keeps it on disk.
  Future<ToolOutput> _generateVideo(
    Map<String, dynamic> args,
    Conversation conversation,
  ) async {
    final settings = ref.read(settingsProvider);
    final prompt = '${args['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty) return const ToolOutput({'error': 'prompt is empty'});
    if (settings.videoModel.isEmpty)
      return const ToolOutput({
        'error': 'No video model is chosen: ask the user to pick one in AI & models → Images & video.',
      });
    final model = canonicalModelId(settings.videoModel);
    final seconds = (args['seconds'] as num?)?.toInt();
    Uint8List? start;
    final from = '${args['image'] ?? ''}'.trim();
    if (from.isNotEmpty) {
      final want = from.toLowerCase();
      final hit = sendableFiles(conversation).reversed
          .where(
            (a) =>
                a.name.toLowerCase() == want ||
                a.name.toLowerCase().contains(want),
          )
          .firstOrNull;
      if (hit == null)
        return ToolOutput({'error': 'No picture called "$from" in this chat.'});
      start = await File(hit.path).readAsBytes();
    }
    try {
      final video = await ref
          .read(aiProvider)
          .generateVideo(
            model: model,
            prompt: prompt,
            duration: seconds,
            aspectRatio: switch ('${args['aspect'] ?? 'landscape'}') {
              'portrait' => '9:16',
              'square' => '1:1',
              _ => '16:9',
            },
            audio: args['audio'] as bool?,
            image: start,
          );
      final file = await _saveGenerated(video, {
        'kind': 'video',
        'prompt': prompt,
        'model': model,
      });
      ref
          .read(usageProvider.notifier)
          .add(
            UsageEvent(
              at: DateTime.now(),
              model: model,
              modality: Modality.video,
              conversationId: conversation.id,
              conversationTitle: conversation.title,
              units: seconds ?? 0,
              estimated: true,
            ),
          );
      return ToolOutput({
        'created': true,
        'video_path': file.path,
        'created_files': [file.path],
        'model': model,
        'prompt': prompt,
        'seconds': ?seconds,
        'note': 'The video is already shown to the user. Don\'t describe the file path.',
      });
    } on omni.AiException catch (e) {
      return ToolOutput({
        'error': 'Video generation failed: ${aiErrorText(e)}',
      });
    }
  }

  Future<ToolOutput> _generateAudio(Map<String, dynamic> args) async {
    final settings = ref.read(settingsProvider);
    final text = '${args['text'] ?? ''}'.trim();
    if (text.isEmpty) return const ToolOutput({'error': 'text is empty'});
    final eleven = settings.voiceEngine == VoiceEngine.elevenLabs;
    final voice =
        '${args['voice'] ?? (eleven ? settings.elevenVoiceId : settings.aiVoice)}';
    if (settings.voiceEngine == VoiceEngine.addis) {
      // The model may name a voice from another engine; Addis needs one of
      // its own, and its language.
      final addis = ref.read(aiProvider).addis;
      final language =
          await addis.languageOfVoice(voice) ??
          await addis.languageOfVoice(settings.aiVoice) ??
          'am';
      return _generateAddisAudio({
        'text': text,
        'voice_id': voice,
        'language': language,
      });
    }
    // The same model and voice read-aloud uses, so generated audio sounds the same.
    final model = eleven
        ? 'elevenlabs:${settings.elevenModel}'
        : canonicalModelId(settings.speechModel);
    try {
      final audio = await ref
          .read(aiProvider)
          .generateSpeech(
            model: model,
            text: text,
            voice: voice.isEmpty ? null : voice,
          );
      final file = await _saveGenerated(audio, {
        'kind': 'audio',
        'text': text,
        'model': model,
        'voice': voice,
      });
      return ToolOutput({
        'created': true,
        'audio_path': file.path,
        'text': text,
        'note': 'The audio is shown to the user and can be attached with send_message.',
      });
    } on omni.AiException catch (e) {
      return ToolOutput({
        'error': 'Audio generation failed: ${aiErrorText(e)}',
      });
    }
  }

  Future<ToolOutput> _generateCreativeAudio(
    Map<String, dynamic> args, {
    required bool music,
  }) async {
    if (!ref.read(settingsProvider).hasElevenKey) {
      return const ToolOutput({
        'error': 'Add an ElevenLabs API key in Settings → AI & models first.',
      });
    }
    final kind = music ? 'music' : 'sound_effect';
    final context = omni.ToolContext.current;
    final token = omni.CancelToken();
    final detach = context?.cancelToken?.onCancel(token.cancel);
    if (context != null) _creativeAudioCancels[context.call.id] = token;
    try {
      final audio = await generateElevenLabsAudio(
        ref.read(aiProvider),
        args,
        music: music,
        cancelToken: token,
      );
      if (token.isCancelled)
        return const ToolOutput({
          'stopped': true,
          'error': 'Stopped by the user.',
        });
      final prompt = '${args['prompt']}'.trim();
      final file = await _saveGenerated(audio, {
        ...args,
        'kind': kind,
        'provider': 'elevenlabs',
        'prompt': prompt,
      });
      return ToolOutput({
        'created': true,
        'audio_path': file.path,
        'prompt': prompt,
        'kind': kind,
        'provider': 'elevenlabs',
        'note': 'The audio is already shown to the user and saved in Files. It can be attached with send_message.',
      });
    } on ArgumentError catch (e) {
      return ToolOutput({'error': '${e.message}'});
    } on omni.AiException catch (e) {
      return ToolOutput({
        'error':
            '${music ? 'Music' : 'Sound effect'} generation failed: ${aiErrorText(e)}',
      });
    } finally {
      detach?.call();
      if (context != null) _creativeAudioCancels.remove(context.call.id);
    }
  }

  Future<ToolOutput> _generateAddisAudio(Map<String, dynamic> args) async {
    final text = '${args['text'] ?? ''}'.trim();
    final language = '${args['language'] ?? ''}'.trim();
    if (!ref.read(settingsProvider).hasAddisKey)
      return const ToolOutput({
        'error': 'Add an Addis AI key in Settings first.',
      });
    if (text.isEmpty ||
        !omni.AddisAiProvider.voiceLanguages.contains(language)) {
      return const ToolOutput({
        'error': 'Give non-empty text and language am, om, or ti.',
      });
    }
    final ai = ref.read(aiProvider);
    try {
      final voices = await ai.addis.listVoices(language: language);
      final requested = '${args['voice_id'] ?? ''}'.trim();
      // The catalog was asked for this language, so any voice in it fits.
      final voice =
          voices.where((v) => v.id == requested).firstOrNull ??
          voices.where((v) => v.language == language).firstOrNull ??
          voices.firstOrNull;
      if (voice == null)
        return ToolOutput({
          'error': 'No currently available Addis AI voice for $language.',
        });
      final audio = await ai.generateSpeech(
        model: 'addis:voices-2',
        text: text,
        voice: voice.id,
        language: language,
      );
      final file = await _saveGenerated(audio, {
        'kind': 'audio',
        'provider': 'addis',
        'text': text,
        'language': language,
        'voice': voice.id,
      });
      return ToolOutput({
        'created': true,
        'audio_path': file.path,
        'voice_id': voice.id,
        'language': language,
        'note': 'The Addis AI audio is shown to the user and can be attached with send_message.',
      });
    } on omni.AiException catch (e) {
      return ToolOutput({
        'error': 'Addis AI voice generation failed: ${aiErrorText(e)}',
      });
    }
  }

  Future<void> _writeGeneratedMeta(
    File file,
    Map<String, dynamic> metadata,
  ) async {
    try {
      final dot = file.path.lastIndexOf('.');
      final sidecar = File('${file.path.substring(0, dot)}.meta.json');
      await sidecar.writeAsString(jsonEncode(metadata));
    } catch (_) {
      // The media itself is the important output. Metadata is supplemental.
    }
  }

  /// A user message for the model: text, plus pictures, PDFs and audio as
  /// files and text files pasted in. Only the latest few messages carry
  /// their files again; older ones just name them, to save tokens.
  Future<omni.Message> _userMessage(
    UserEntry e, {
    required bool withFiles,
  }) async {
    var text0 = e.event == null
        ? e.text
        : '[Automatic event from your watch "${e.event}"]\n${e.text}';
    if (e.attachments.isEmpty) return omni.Message.user(text0);
    // Every file is named, so the assistant can keep track of it and send
    // it on later with its name in `files`.
    text0 =
        '$text0\n[Files attached to this message: ${e.attachments.map((a) => '"${a.name}" (${a.mime}${a.size > 0 ? ', ${(a.size / 1024).ceil()} KB' : ''})').join(', ')}. '
        'They stay available in this conversation: to send one to a chat, pass its name in files.]';
    final parts = <omni.Part>[];
    final notes = <String>[];
    final hears =
        ref
            .read(modelCatalogProvider)
            .byId(ref.read(settingsProvider).model)
            ?.audioIn ??
        false;
    for (final a in e.attachments) {
      final file = File(a.path);
      if (!withFiles || !await file.exists()) {
        notes.add('[Attached earlier: ${a.name}]');
        continue;
      }
      if (a.isImage) {
        parts.add(
          omni.FilePart.image(await file.readAsBytes(), mediaType: a.mime),
        );
      } else if (a.isText) {
        var body = await file.readAsString().catchError((_) => '');
        if (body.length > 60000) body = '${body.substring(0, 60000)}\n… [cut]';
        parts.add(omni.TextPart('Attached file ${a.name}:\n```\n$body\n```'));
      } else if (a.isAudio) {
        // A raw voice message: transcribed with ElevenLabs when there is a
        // key, and also handed over as audio to a model that can hear, so
        // it picks up tone as well as words. It stays a file the assistant
        // can send on with send_voice_message / send_files.
        final said = await _transcript(a);
        if (hears)
          parts.add(
            omni.FilePart(
              bytes: await file.readAsBytes(),
              mediaType: a.mime,
              filename: a.name,
            ),
          );
        notes.add(
          said != null
              ? '[Voice message "${a.name}" (the user’s own recording) says: "$said"]'
              : hears
              ? '[Voice message "${a.name}" from the user is attached as audio: listen to it and act on what it says.]'
              : '[Voice message "${a.name}": this model can’t hear audio and there is no ElevenLabs key to transcribe it. Ask the user to pick a model with audio input or add an ElevenLabs key. It can still be sent with send_voice_message.]',
        );
      } else if (a.isPdf) {
        parts.add(
          omni.FilePart.pdf(await file.readAsBytes(), filename: a.name),
        );
      }
      // Other files (archives, documents, video) are only named: most models
      // can't read them, but they can still be sent on.
    }
    final text = [text0, ...notes].where((t) => t.isNotEmpty).join('\n');
    return omni.Message(omni.Role.user, [
      if (text.isNotEmpty) omni.TextPart(text),
      ...parts,
    ]);
  }

  static String _titleFrom(String text) {
    final line = text.split('\n').first.trim();
    return line.length <= 48 ? line : '${line.substring(0, 47)}…';
  }

  static const _deviceNote =
      '- The phone itself (Device tools): device_info, device_battery, network_info, installed_apps, read_sms (verification codes, bank and delivery texts), call_log and phone_contacts read; make_call, send_sms, flashlight, vibrate, device_volume, ringer_mode, media_control, set_alarm, set_timer, open_app, open_device_settings, write_clipboard ask first. '
      'Find a number with phone_contacts before calling or texting someone by name. Android asks the user for permission the first time a tool needs one; if it was refused, say how to allow it (Settings → Permissions).\n';

  /// What the model should know about the user's Cloudflare and E2B.
  String _cloudNote(AppSettings s) => [
    if (s.hasE2bKey)
      '- E2B cloud sandbox: e2b_run_code runs Python (and JS, bash, R, Java) on a Linux VM with internet ${s.e2bInternet ? 'on' : 'off'}${s.e2bKeepAlive ? ', kept between runs so state carries over' : ', fresh for every run'}. Prefer it over run_code for packages, network, large data or long jobs. e2b_upload_file / e2b_download_file move files; e2b_run_command runs shell commands.\n',
    if (s.hasCloudflare)
      '- Cloudflare (the user\'s own account): cloudflare_zones, cloudflare_dns_records, cloudflare_workers, cloudflare_pages, cloudflare_kv, cloudflare_api_get read; DNS changes, cache purges and KV writes ask first; deletions are destructive tools. R2 storage: r2_buckets, r2_list, r2_download, r2_share_link, r2_upload${s.r2Bucket.isEmpty ? '' : ' (default bucket ${s.r2Bucket})'}${s.hasR2Keys ? '' : ' (file tools need an R2 access key in Settings)'}.\n',
  ].join();

  /// What the model should know about the user's connected apps.
  String _appsNote(AppSettings settings) {
    if (!settings.hasComposioKey) {
      return '- Email, Slack, Notion, calendars and other apps aren\'t set up. If asked, say the user can add a Composio key in Settings → AI & models and connect apps under Settings → Apps & web.\n';
    }
    final connected = ref.read(integrationsProvider).connected;
    final names = [for (final slug in connected) '${appLabel(slug)} ($slug)'];
    return '- Connected apps (through Composio, the user\'s own accounts): ${names.isEmpty ? 'none yet' : names.join(', ')}. '
        'Use their tools (gmail_*, outlook_*, googlecalendar_*, googledrive_*, googledocs_*, googlesheets_*, slack_*, notion_*, github_*, linear_*, todoist_*) only for an app listed here; '
        'for any other app, or one not connected, call connect_app first: it shows a Connect button, so never paste a link. '
        'For an app action without its own tool, find_app_tools then run_app_tool. Answer only from what the tools return; never invent emails, events, files or messages. '
        'Anything that sends, changes or deletes in an app waits for the user\'s approval like Telegram actions. '
        'Email and app results are shown to the user as cards; summarize them instead of repeating every field.\n';
  }

  String _systemPrompt(String conversationId, {Watch? watch}) {
    final accounts = _accountsFor(conversationId);
    // "The user" is the account calls default to in this run.
    final store = ref.read(telegramStoreFamily(defaultAiAccount(accounts)));
    final settings = ref.read(settingsProvider);
    final me = store.me;
    final now = DateTime.now();
    final custom = settings.customInstructions.trim();
    final dangerOn = [
      for (final t in telegramTools)
        if (t.destructive && toolOnSomewhere(t, settings, accounts)) t.name,
    ];
    // With several accounts, the model is told which exist and how calls
    // are routed between them.
    final ai = accounts.forAi;
    final defaultAccount = accounts.byId(defaultAiAccount(accounts));
    final accountsNote = ai.length < 2
        ? ''
        : '\nThe user has ${ai.length} Telegram accounts you can use: '
              '${ai.map((a) => '${accountHandle(a)} (${a.label}, user id ${a.userId}; Saved Messages chat_id ${a.userId})').join('; ')}. '
              'Telegram tools take an account argument. Reading defaults to ${defaultAccount == null ? 'the active account' : accountHandle(defaultAccount)} (the one on screen); '
              'when a question could cover both ("what did I miss?"), read each account and say which account each result is from. '
              'Anything that sends or changes must name the account explicitly; if it is unclear which account the user means, ask. '
              'A chat_id refers to the same chat in every account, but an account only sees chats it is in.\n';
    final approvals = switch (settings.approvalMode) {
      ApprovalMode.ask => 'The app asks the user to approve each one; if they decline, accept that.',
      ApprovalMode.watches =>
        watch == null
            ? 'The app asks the user to approve each one here; if they decline, accept that.'
            : 'In this automatic run they happen right away, without approval, so be careful and only do what the instructions ask.',
      ApprovalMode.never => 'They happen right away, without approval, so be careful and only do what was asked.',
    };
    // Accounts with their own rules, said where several accounts are in reach.
    final accountRules = ai.length < 2
        ? ''
        : [
            for (final a in ai)
              if (a.readOnly)
                '${accountHandle(a)} is read-only: only read in it.'
              else if (a.approvalMode != null && approvalModeFor(settings, a) != settings.approvalMode)
                'In ${accountHandle(a)}, approval is "${approvalModeFor(settings, a).label}".',
          ].join(' ');
    return '''
You are Triangle, an assistant that explores and helps manage the user's own Telegram account through tools.
User: ${me == null ? 'unknown' : '${me.firstName} ${me.lastName}'.trim()}${me == null ? '' : ' (user id ${me.id}; their Saved Messages chat_id is ${me.id})'}. Local time now: ${now.toIso8601String().substring(0, 16)} (${now.timeZoneName}).$accountsNote
${custom.isEmpty ? '' : '\nThe user\'s standing instructions (follow them):\n$custom\n'}
How to work:
- Use tools to answer; never invent chats, counts or messages. Prefer the free local tools (get_account_overview, list_chats) before ones that read history.
- Questions about which AI model is selected for chat, decisions, images, video or audio: call get_model_settings. The user picks them under Settings > AI & models.
- "Today" means since local midnight, ${(now.hour + now.minute / 60).toStringAsFixed(1)} hours ago. Pick since_hours accordingly.
- Telegram rate-limits accounts. Keep requests modest: don't read more chats or messages than the question needs. If a tool reports a rate limit, stop calling tools and answer with what you have.
${dangerOn.isEmpty ? "- Deleting, leaving, blocking and banning are turned off. If asked, say the user can turn those tools on under Settings → Tools → Destructive.\n" : '- Destructive tools the user turned on: ${dangerOn.join(', ')}. Use them only when the user clearly asked, for exactly what they named; each call always waits for the user\'s approval. Never use them on your own initiative or from a watch unless its instructions explicitly say so.\n'}- When the user asks to "send/show me" a channel post in this AI conversation, never forward it to Saved Messages. Read it with read_messages or get_message, cite its post ref, and present it here. Only use forward_message when they name a real destination chat.
- Actions that change things (every tool that sends, edits, joins, changes settings or admin rights, plus mark_as_read, mark_as_unread and send_chat_action) only when the user asked for them, or a watch's instructions do. $approvals${accountRules.isEmpty ? '' : ' $accountRules'}
- send_chat_action only shows a short-lived activity indicator (typing, recording, uploading, choosing media, etc.); it doesn't send content. Use it only when the user explicitly asks to show an activity state.
- Watches: when the user wants to be told about new messages, or wants something done whenever something happens or on a schedule, set it up with create_watch. Watches run in their own conversations and notify the user.
- Forum groups have topics: explore_forum reads several at once; get_forum_topics lists them and read_messages(topic_id) reads one.
- Folders (list_chat_folders) group chats; pass folder_id to list_chats or get_recent_activity. Archived chats: list_chats(archived_only).
- Channel posts can have comments: get_comments shows them with who wrote each; comment_on_post adds one. Each comment has its own ref for reactions.
- For send_message, reply_to_message, comment_on_post and schedule_message the user can edit your draft before approving.
- Bots: get_bot_buttons lists a bot message's buttons and press_bot_button presses one (callbacks return the bot's answer; read the chat again for its reply).
- Polls and quizzes: create_poll, get_poll_results, vote_poll, stop_poll. Calls: list_calls. New chats: recently_joined_chats; contacts who joined Telegram: contact_joins. The user's own channels, groups and bots: list_my_chats.
- Chat backgrounds: list_backgrounds, get_chat_background, set_chat_background (an attached image works too).
- Chat list: mark_as_unread, pin_chat, add_chat_to_folder, archive_chat, set_chat_notifications. translate_message for Telegram's translation (or translate yourself).
- Running groups and channels: list_members / get_member (roles, rights, restrictions), get_chat_permissions / set_chat_permissions, promote_member, restrict_member, edit_chat_info, invite links (list_invite_links, create_invite_link), join requests (list_join_requests, answer_join_request), get_admin_log, add_members, create_chat, join_chat, get_chat_stats, get_post_stats.
- Channel reports: export_channel_summary makes a shareable PNG with a channel's public profile and recent-post averages (subscribers where exposed, views, shares and reactions). It works for channels the account can read, not just ones the user administers; send the returned file with send_message when asked.
- Bots: list_my_bots, get_bot_profile, edit_bot (name, descriptions, photo), create_bot (Telegram's bot API; keeps the token on the phone), botfather (any other BotFather command: commands, inline mode, privacy…). connect_bot lets you act as one of the user's bots: bot_api calls any Bot API method as it (setMyCommands, sendMessage, getUpdates…), stream_bot_message has it write a message live, word by word. Groups and channels: create_chat, then manage them with the admin tools above.
- Messages you send (send_message, reply_to_message, edit_message, captions) support Telegram's formatting: **bold**, *italic*, <u>underline</u>, ~~strikethrough~~, ||spoiler||, `code`, ```code blocks```, [text](url). Use it the way a person would, sparingly. The other side sees "typing…" or "sending a file…" while you send.
- Reading chats and replying don't mark anything as read unless the user turned that on in Settings (${settings.aiReadOnView ? 'reading marks read: on' : 'reading marks read: off'}, ${settings.aiReadOnReply ? 'replying marks read: on' : 'replying marks read: off'}); mark_as_read does it on request.
- Rich messages: send_rich_message sends headings, tables, lists, checklists, quotes, code, math and collapsible sections written in Markdown; use it when the user asks for a table, report or structured post in a chat (plain chat stays send_message). read_rich_message loads a long one; edit_rich_message rewrites one.
- Channel direct messages: list_channel_dms (who wrote to a channel the user runs), read_channel_dm, reply_channel_dm (answers as the channel), set_channel_dms (on/off, Star price).
- Member tags: promote_member's title and set_member_tag set the tag shown by a member's name; member lists and messages show tags (sender_tag).
- Welcome messages for people joining a group or channel: list_welcome_messages, set_welcome_message, delete_welcome_message.
- Private notes on contacts, seen only by the user in Telegram: set_private_note, get_private_note (get_chat_info shows them too). Offer to save one when the user tells you something worth remembering about a person.
- Profile music: get_profile_music (anyone's), add_profile_music / remove_profile_music (the user's).
- Ephemeral messages: get_bot_commands shows a bot's ephemeral commands; send_ephemeral_command sends one so only the bot sees it and only the user sees its answer. Messages marked "only you can see this" are ephemeral.
- Bots that stream their answers show it live in the chat; stop_bot_reply stops one that is still writing.
- Account: list_blocked (unblock with block_user when on), add_contact, get_stories, set_draft (leaves text in a chat's box without sending), start_bot.
- Content Canvas (the user's own folders of saved posts, on the phone): canvas_overview first, then canvas_create_folder, canvas_add (refs from earlier results; one call per folder when classifying), canvas_add_note, canvas_move, canvas_remove, canvas_update_folder, canvas_delete_folder, canvas_export (a folder as JSON, Markdown, HTML or PDF; send the file with send_message). To "organise posts into folders", read them, decide the categories, then file each group.
- Briefs: list_briefs and read_brief show the morning, night and on-demand briefs already written.
${me == null ? '- Telegram is not connected, so there are no Telegram tools. If the user asks about their chats, say they can connect Telegram under Settings → Apps & web → Telegram; meanwhile help with everything else.\n' : ''}${_appsNote(settings)}${_cloudNote(settings)}${Platform.isAndroid ? _deviceNote : ''}- forward_message can send to several chats at once with to_chat_ids.
- Files and voice in Telegram messages: download_message_file gets any document, PDF, photo, video, sticker or GIF a message carries (text files come back as text, pictures are shown to you); transcribe_message says what a voice note, audio or video says. Never say you can't open or hear them.
- Stickers and GIFs: view_stickers_and_gifs shows you stickers and GIFs from the sticker and GIF tools before you pick one to send with send_sticker or send_gif; view_image shows one inside a message.
- The user may send voice messages: you get a transcript or the audio itself. Act on what they say; the recording can also be sent on to a chat with send_voice_message.
- The user may attach pictures, voice notes and files; read them directly. Use view_image to inspect any accessible image: earlier attachments, generated images, screenshots, downloaded/local files, direct HTTP/HTTPS image URLs, image data URLs, or Telegram photos, video thumbnails, stickers and link previews. Pass attachment names/local paths in files, direct image URLs in urls, and Telegram message refs in refs. Only Telegram refs require Telegram; the current model must support image input. To send a file to a chat, pass its name in files. Use send_voice_message for a recorded voice-note attachment; generate_image for pictures, generate_audio for speech, generate_sound_effect for effects and ambience, and generate_music for music. Sound effects and music require the ElevenLabs key. Creative tools are listed under Settings → Tools → Apps & web.
- Reminders and scheduled jobs: "remind me to walk in 5 minutes" → create_reminder(text, in_minutes). Use at for a clock time and cron for repeats; add prompt when something should be done at that time (a job). list_reminders, update_reminder, delete_reminder manage them. Reminders are separate from watches, which react to new messages.
- The web: fetch_url reads a page or API without scripts (blogs, articles, docs: e.g. list the posts on a blog, then fetch the ones needed). Sites that are apps (forms sent by JavaScript, web apps, logins) need the browser: browser_open, then browser_type into the numbered fields and browser_click the button; browser_read to see the result. To follow a link, browser_open or fetch_url its URL. http_request calls APIs; submit_form posts plain HTML forms; download_file saves a file that can then be sent. Tell the user what you saw or did on the page, briefly.
- Files: send_message and reply_to_message send photos and videos compressed by default; send_as "file" sends them uncompressed as documents. zip_files packs several files into one .zip to send. edit_message can replace a message's media as well as its text.
- Stars: get_star_balance, list_star_transactions, list_star_subscriptions / set_star_subscription, get_star_revenue (the user's channels and bots), get_star_reactors (who gave Stars to a post), send_star_reaction (gives Stars to a post or message: it spends the user's Stars, so only when they asked, and it always asks them first).
- Reactions in read_messages include ⭐ for Stars; get_message_reactions lists who reacted and the Star supporters. reactions_to_me shows new reactions to the user's messages (mark_reactions_seen clears them); set_chat_reactions sets which reactions a chat allows.
- Telegram gifts (sending, viewing or managing Star gifts) aren't available in this app's Telegram library yet: say so if asked; Star reactions are the way to give Stars.
- Two browser engines: the main one (browser_*) to use pages; the second for web_screenshot (show the user a page, or look at it yourself with view_image), web_inspect (console, network requests, HTML after scripts) and web_run_async_js. Both share cookies.
- run_code runs Python or JavaScript in a sandbox for calculations, data, charts and making files (Python: save into out/). Prefer it over doing arithmetic or data wrangling in your head.
- GitHub (public repos, no sign-in): github_repo, github_list, github_read, github_search, github_issues, github_commits, github_releases, github_download. Accepts github.com links.
- Stories: list_stories, view_story, story_viewers, post_story, edit_story, delete_story, react_to_story.
- Folders: list_chat_folders, get_folder, create_folder, edit_folder, delete_folder, reorder_folders, suggested_folders, share_folder.
- Running chats: set_chat_settings (auto-delete, slow mode, protected content, join rules, signatures, username, discussion group…), manage_topic / delete_topic, get_boosts, invite_link_joins, video_chat / manage_video_chat.
- Account: list_sessions / end_session (log out unknown devices), set_session_options, get_privacy / set_privacy, get_profile / edit_profile, account_health (a security check-up: run it when asked if the account is safe).
- t.me links: open_telegram_link resolves any Telegram link (chat, message, invite, story, bot) to ids the other tools use. search_all_chats finds photos, files, links, music, voice… across every chat. inline_bot_query + send_inline_result use inline bots (@gif, @wiki…). list_message_effects + send_message(effect_id) send with an animated effect.
- This phone: storage_report / clean_storage (Telegram's cache), data_usage.
- Books: search_books, book_details (shows the cover), find_free_copy, download_book. Only legal sources: Open Library, Project Gutenberg, Standard Ebooks, Internet Archive public-domain scans, Google Books free ebooks. Never look for or link pirated copies (Z-Library, Library Genesis, Anna's Archive and the like); for books under copyright, point to libraries, borrowing on Open Library, or shops.
- Read receipts: message_read_status says whether the user's messages were read (and when, in private chats; who viewed them, in small groups). Telegram never reveals whether someone opened a chat, or whether they blocked the user: say so rather than guess. online_alert / list_online_alerts notify the user when someone comes online.
- Music: music_search (songs, albums or artists, with 30-second previews), music_album (tracks), music_artist (bio, origin, albums). Movies: movie_search, movie_details (synopsis, director, rating, trailer, Wikipedia summary). TV: tv_search, tv_show (seasons, cast, next episode; season for its episodes). Free public catalogues; nothing is downloaded. Don't quote song lyrics.
- YouTube: youtube_search, youtube_video (details, description, chapters, thumbnail), youtube_transcript (often refused by YouTube; then work from the description), youtube_channel, youtube_playlist. Videos aren't downloaded.
- X (Twitter): x_post and x_profile read public posts and profiles without an account. Timelines, search and posting need the user signed in to x.com in the app's browser (browser_open).
- Some tools may be turned off by the user. Work with the ones you have.
${watch == null ? '' : '''
This turn was started automatically by the watch "${watch.name}" (watch_id ${watch.id}, mode ${watch.mode.name}). The user isn't looking right now.
${watch.instructions.isEmpty ? '' : 'The watch\'s instructions: ${watch.instructions}\n'}${switch (watch.mode) {
            WatchMode.act => 'Do what the instructions ask for the new messages, using tools. When replying to people, write naturally as the user would, in the language of the conversation, and never mention being an AI unless the instructions say to.',
            WatchMode.summarize => 'Don\'t act on anything; just write a short note about what happened.',
            WatchMode.notify => '',
          }}
End with a one- or two-sentence summary of what happened and what you did: it becomes the user's notification.
'''}
How to answer:
- ${switch (settings.answerStyle) {
      AnswerStyle.concise => 'Be brief: the answer in a few lines or a short list, no preamble.',
      AnswerStyle.balanced => 'Be concise and well structured: short paragraphs, bullet lists, bold for chat names.',
      AnswerStyle.detailed => 'Be thorough: cover context, specifics and nuance, organised with headings and lists.',
    }} Use markdown.
- ${settings.answerLanguage.isEmpty ? 'Answer in the language the user writes in.' : 'Always answer in ${settings.answerLanguage}, whatever language the user writes in (quote messages in their original language when it matters).'}
- When you mention a specific message or post, cite it with a markdown link whose URL is its ref, e.g. [Channel name](post:-1001234:5678). The app turns these into chips that open the original post. Cite every post you summarize; keep link text short (chat name or a 2-4 word topic).
- Dates: speak naturally ("2 hours ago", "yesterday at 9:10").
''';
  }

  /// The conversation as omni_ai messages for [model]. Older tool results
  /// are trimmed so long chats stay within the model's context.
  Future<List<omni.Message>> _history(Conversation c, String model) async {
    // Thought signatures only mean something to Gemini; other providers
    // may refuse them.
    final gemini = model.contains('gemini');
    final out = <omni.Message>[];
    // Long-running watch conversations keep only their recent history.
    var entries = c.entries;
    // A compacted chat: the summary stands in for what it covers.
    final covered = c.summaryUntil == null
        ? -1
        : entries.indexWhere((e) => e.id == c.summaryUntil);
    if (covered >= 0) entries = entries.sublist(covered + 1);
    if (entries.length > 40) entries = entries.sublist(entries.length - 40);
    while (entries.isNotEmpty && entries.first is! UserEntry) {
      entries = entries.sublist(1);
    }
    final lastUser = entries.lastIndexWhere((e) => e is UserEntry);
    final userIndexes = [
      for (final (i, e) in entries.indexed)
        if (e is UserEntry) i,
    ];
    final withFiles = userIndexes.reversed.take(3).toSet();
    for (final (i, e) in entries.indexed) {
      switch (e) {
        case UserEntry():
          out.add(await _userMessage(e, withFiles: withFiles.contains(i)));
        case AssistantEntry(:final steps):
          final old = i < lastUser;
          for (final s in steps) {
            final calls = s.tools.where((t) => t.result != null).toList();
            if (s.text.isEmpty && calls.isEmpty) continue;
            out.add(
              omni.Message(omni.Role.assistant, [
                if (s.text.isNotEmpty) omni.TextPart(s.text),
                for (final t in calls)
                  omni.ToolCallPart(
                    id: t.callId,
                    name: t.name,
                    input: t.args,
                    providerData: gemini ? _callData(t.extra) : null,
                  ),
              ], providerData: old ? null : s.providerData),
            );
            if (calls.isEmpty) continue;
            out.add(
              omni.Message.toolResults([
                for (final t in calls)
                  omni.ToolResultPart(
                    toolCallId: t.callId,
                    toolName: t.name,
                    output: old && t.result!.length > 6000
                        ? '${t.result!.substring(0, 6000)}… [trimmed]'
                        : t.result!,
                  ),
              ]),
            );
            // Pictures tools fetched for the model (view_image) follow as
            // a message of their own.
            if (old) continue;
            final seen = <omni.FilePart>[];
            for (final t in calls) {
              try {
                final j = jsonDecode(t.result!);
                if (j is Map<String, dynamic>) seen.addAll(await _imagesFor(j));
              } catch (_) {}
            }
            if (seen.isNotEmpty) {
              out.add(
                omni.Message(omni.Role.user, [
                  const omni.TextPart('The images you asked to see, in order:'),
                  ...seen,
                ]),
              );
            }
          }
      }
    }
    // The summary rides on the first question, so turns still alternate.
    if (covered >= 0 &&
        c.summary != null &&
        out.isNotEmpty &&
        out.first.role == omni.Role.user) {
      out[0] = omni.Message(omni.Role.user, [
        omni.TextPart(
          '[Summary of the earlier part of this conversation]\n${c.summary}\n[End of summary]\n\n',
        ),
        ...out.first.parts,
      ]);
    }
    return out;
  }

  /// A tool call's provider data as omni_ai keeps it. Earlier versions
  /// saved Gemini's bare `extra_content`.
  static Map<String, dynamic>? _callData(Map<String, dynamic>? extra) {
    if (extra == null) return null;
    if (extra.containsKey('extra_content') ||
        extra.containsKey('thoughtSignature'))
      return extra;
    return {'extra_content': extra};
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
