import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../auth/data/auth_controller.dart';
import '../canvas/canvas_store.dart';
import '../chat/data/chat_controller.dart';
import '../chat/data/chat_repository.dart';
import '../chat/domain/chat_models.dart';
import '../chat/presentation/widgets/rich_results.dart';
import '../integrations/integrations_store.dart';
import '../settings/data/settings.dart';
import '../telegram/data/telegram_tools.dart';
import '../telegram/presentation/content_canvas_screen.dart';
import '../telegram/presentation/search_screen.dart';

/// Where results come from.
enum _Source {
  all('All', Icons.all_inclusive_rounded),
  chats('Conversations', Icons.forum_outlined),
  canvas('Canvas', Icons.dashboard_customize_outlined),
  files('Files', Icons.folder_copy_outlined),
  email('Email', Icons.mail_outline_rounded),
  web('Web', Icons.travel_explore_rounded),
  telegram('Telegram', Icons.send_rounded);

  const _Source(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _Hit {
  const _Hit({required this.source, required this.title, required this.subtitle, required this.onTap, this.when});
  final _Source source;
  final String title;
  final String subtitle;
  final DateTime? when;
  final VoidCallback onTap;
}

/// Search everywhere: this phone's AI conversations, the Content Canvas and
/// files as you type, and your email, the web and Telegram when you press
/// search (those need their app, key or account connected). Telegram's own
/// search, by kind of media, is a tap away.
class EverywhereSearchScreen extends ConsumerStatefulWidget {
  const EverywhereSearchScreen({super.key});

  @override
  ConsumerState<EverywhereSearchScreen> createState() => _EverywhereSearchScreenState();
}

class _EverywhereSearchScreenState extends ConsumerState<EverywhereSearchScreen> {
  final _query = TextEditingController();
  _Source _source = _Source.all;
  Timer? _debounce;
  List<_Hit> _local = const [];
  final Map<_Source, ToolPart?> _remote = {};
  final Set<_Source> _loading = {};
  List<Conversation>? _conversations;
  List<File>? _files;
  int _run = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  bool get _hasEmail => ref.read(integrationsProvider).connected.any((a) => a == 'gmail' || a == 'outlook');

  List<_Source> get _sources => [
    _Source.all,
    _Source.chats,
    _Source.canvas,
    _Source.files,
    if (_hasEmail) _Source.email,
    if (ref.read(settingsProvider).hasExaKey) _Source.web,
    if (ref.read(telegramConnectedProvider)) _Source.telegram,
  ];

  Future<void> _loadLocal() async {
    if (_conversations == null) {
      final repo = ref.read(chatRepositoryProvider);
      final list = await repo.list();
      final out = <Conversation>[];
      for (final s in list.take(150)) {
        final c = await repo.load(s.id);
        if (c != null) out.add(c);
      }
      _conversations = out;
    }
    if (_files == null) {
      final root = (await getApplicationSupportDirectory()).path;
      final out = <File>[];
      for (final d in ['generated', 'sandbox', 'downloads', 'telegram', 'exports', 'screenshots']) {
        final dir = Directory('$root/$d');
        if (!await dir.exists()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File && !e.path.endsWith('.meta.json') && !e.path.endsWith('.tmp')) out.add(e);
        }
      }
      _files = out;
    }
  }

  static String _around(String text, String q, [int span = 70]) {
    final i = text.toLowerCase().indexOf(q);
    if (i < 0) return text.length > span * 2 ? '${text.substring(0, span * 2)}…' : text;
    final a = (i - span).clamp(0, text.length);
    final b = (i + q.length + span).clamp(0, text.length);
    return '${a > 0 ? '…' : ''}${text.substring(a, b).replaceAll('\n', ' ')}${b < text.length ? '…' : ''}';
  }

  Future<void> _searchLocal() async {
    final q = _query.text.trim().toLowerCase();
    final run = ++_run;
    if (q.length < 2) {
      setState(() => _local = const []);
      return;
    }
    await _loadLocal();
    if (!mounted || run != _run) return;
    final hits = <_Hit>[];
    for (final c in _conversations!) {
      String? found;
      if (c.title.toLowerCase().contains(q)) found = c.title;
      for (final e in c.entries) {
        if (found != null) break;
        final text = switch (e) {
          UserEntry(:final text) => text,
          AssistantEntry(:final steps) => steps.map((s) => s.text).join('\n'),
        };
        if (text.toLowerCase().contains(q)) found = _around(text, q);
      }
      if (found != null) {
        hits.add(
          _Hit(
            source: _Source.chats,
            title: c.title.isEmpty ? 'Conversation' : c.title,
            subtitle: found,
            when: c.updatedAt,
            onTap: () {
              ref.read(chatControllerProvider.notifier).open(c.id);
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        );
      }
    }
    final canvas = ref.read(canvasProvider);
    for (final i in canvas.items) {
      final text = [i.title, i.post?.text ?? i.text, i.note, i.source, i.post?.chatTitle ?? '', ...i.tags].join(' ');
      if (!text.toLowerCase().contains(q)) continue;
      final folder = canvas.folder(i.folderId);
      hits.add(
        _Hit(
          source: _Source.canvas,
          title: i.title.isNotEmpty ? i.title : (i.post?.chatTitle ?? 'Note'),
          subtitle: '${folder == null ? '' : '${canvas.pathOf(folder)} · '}${_around(i.post?.text ?? i.text, q)}',
          when: i.addedAt,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ContentCanvasScreen(folderId: i.folderId))),
        ),
      );
    }
    for (final f in _files!) {
      final name = f.path.split(RegExp(r'[\\/]')).last;
      var hit = name.toLowerCase().contains(q);
      // Generated files describe themselves in a sidecar (the prompt, the text).
      if (!hit) {
        final dot = f.path.lastIndexOf('.');
        final side = File('${f.path.substring(0, dot < 0 ? f.path.length : dot)}.meta.json');
        if (side.existsSync()) {
          try {
            hit = jsonEncode(jsonDecode(side.readAsStringSync())).toLowerCase().contains(q);
          } catch (_) {}
        }
      }
      if (!hit) continue;
      hits.add(
        _Hit(
          source: _Source.files,
          title: name,
          subtitle: f.parent.path.split(RegExp(r'[\\/]')).last,
          when: f.statSync().modified,
          onTap: () => OpenFilex.open(f.path),
        ),
      );
    }
    hits.sort((a, b) => (b.when ?? DateTime(0)).compareTo(a.when ?? DateTime(0)));
    setState(() => _local = hits);
  }

  /// Email and the web are asked only when the user presses search.
  Future<void> _searchRemote() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    final runner = ref.read(toolRunnerProvider);
    final connected = ref.read(integrationsProvider).connected;
    Future<void> ask(_Source s, String tool, Map<String, dynamic> args) async {
      setState(() => _loading.add(s));
      final r = await runner.run(tool, args);
      if (!mounted) return;
      setState(() {
        _loading.remove(s);
        _remote[s] = ToolPart(
          callId: '${s.name}${DateTime.now().millisecondsSinceEpoch}',
          name: tool,
          arguments: jsonEncode(args),
          status: r.json['error'] == null ? ToolStatus.done : ToolStatus.error,
          result: r.encode(),
        );
      });
    }

    await Future.wait([
      if (connected.contains('gmail') && (_source == _Source.all || _source == _Source.email))
        ask(_Source.email, 'gmail_fetch_emails', {'query': q, 'max_results': 10}),
      if (!connected.contains('gmail') && connected.contains('outlook') && (_source == _Source.all || _source == _Source.email))
        ask(_Source.email, 'outlook_search_messages', {'query': q, 'size': 10}),
      if (ref.read(settingsProvider).hasExaKey && (_source == _Source.all || _source == _Source.web))
        ask(_Source.web, 'web_search', {'query': q, 'limit': 6}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final telegram = ref.watch(telegramConnectedProvider);
    final q = _query.text.trim();
    final local = _local.where((h) => _source == _Source.all || h.source == _source).toList();
    final email = _remote[_Source.email];
    final web = _remote[_Source.web];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), _searchLocal);
            setState(() {});
          },
          onSubmitted: (_) {
            _searchLocal();
            _searchRemote();
          },
          decoration: const InputDecoration(
            hintText: 'Search conversations, canvas, files, email…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              _searchLocal();
              _searchRemote();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in _sources) ...[
                  ChoiceChip(
                    // Coloured here: the chip theme's default is dark on
                    // the dark theme, and the checkmark would hide it.
                    showCheckmark: false,
                    avatar: Icon(s.icon, size: 16, color: _source == s ? AppColors.accent : AppColors.text2),
                    label: Text(s.label),
                    selected: _source == s,
                    onSelected: (_) {
                      setState(() => _source = s);
                      if (s == _Source.email || s == _Source.web) _searchRemote();
                    },
                  ),
                  const SizedBox(width: Space.s),
                ],
              ],
            ),
          ),
          if (telegram && (_source == _Source.all || _source == _Source.telegram))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: lead(const Icon(Icons.send_rounded, color: Color(0xFF2AABEE))),
              title: Text(q.isEmpty ? 'Search Telegram' : 'Search Telegram for “$q”'),
              subtitle: Text('Every chat: messages, photos, files, links, voice', style: context.text.bodySmall),
              trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchScreen(initialQuery: q))),
            ),
          if (q.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x4),
              child: Text(
                'Conversations, the canvas and files are searched as you type. Press search to also look in '
                '${[if (_hasEmail) 'your email', if (ref.read(settingsProvider).hasExaKey) 'the web', if (telegram) 'Telegram'].join(', ').ifEmpty('connected apps')}.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ),
          for (final (s, part) in [(_Source.email, email), (_Source.web, web)])
            if (_source == _Source.all || _source == s) ...[
              if (_loading.contains(s))
                const Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              if (part != null && !_loading.contains(s)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, Space.xs, Space.s),
                  child: Text(s.label.toUpperCase(), style: context.text.labelSmall),
                ),
                richResultFor(part) ?? _WebResults(part: part),
              ],
            ],
          if (local.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, Space.xs, Space.s),
              child: Text('ON THIS PHONE · ${local.length}', style: context.text.labelSmall),
            ),
            for (final h in local.take(80))
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
                leading: lead(Icon(h.source.icon, color: AppColors.text2)),
                title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(h.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                trailing: h.when == null ? null : Text(DateFormat('d MMM').format(h.when!), style: context.text.labelSmall),
                onTap: h.onTap,
              ),
          ] else if (q.length >= 2)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Center(child: Text('Nothing on this phone matches.', style: context.text.bodySmall)),
            ),
        ],
      ),
    );
  }
}

/// Exa's results, or a tool's error.
class _WebResults extends StatelessWidget {
  const _WebResults({required this.part});
  final ToolPart part;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> j;
    try {
      j = Map<String, dynamic>.from(jsonDecode(part.result ?? '{}') as Map);
    } catch (_) {
      j = const {};
    }
    if (j['error'] != null) return Text('${j['error']}', style: context.text.bodySmall?.copyWith(color: AppColors.warning));
    return Column(
      children: [
        for (final r in (j['results'] as List? ?? const []).whereType<Map>())
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
            leading: lead(Icon(Icons.public_rounded, color: AppColors.text2)),
            title: Text('${r['title'] ?? r['url']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${Uri.tryParse('${r['url']}')?.host ?? ''}${r['highlights'] is List && (r['highlights'] as List).isNotEmpty ? ' · ${(r['highlights'] as List).first}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
            onTap: () => launchUrl(Uri.parse('${r['url']}'), mode: LaunchMode.externalApplication),
          ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
