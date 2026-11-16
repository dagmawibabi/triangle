import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:omni_ai/omni_ai.dart' show VapiCall, VapiPhoneNumber, VapiAssistant;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

import '../../../app/theme.dart';
import '../../../core/files/generated_files.dart' show saveGeneratedBytes;
import '../../../core/widgets/code_highlight.dart' show HighlightedCode, codeTextStyle;
import '../../../core/widgets/net_image.dart';
import '../../ai/data/ai.dart';
import '../../calls/vapi.dart';
import '../../calls/vapi_ui.dart' show VapiSettingsScreen;
import '../../chat/presentation/widgets/app_result_cards.dart' show showEmail;
import '../../chat/presentation/widgets/dev/dev_card_kit.dart';
import '../../integrations/app_results.dart';
import '../../integrations/code_editor_screen.dart';
import '../../integrations/e2b_session.dart';
import '../../integrations/integrations_store.dart';
import '../../settings/data/settings.dart';
import '../../telegram/data/telegram_tools.dart';
import 'manage_kit.dart';

// Full pages for the connected apps and services: GitHub, Gmail, Google
// Calendar and Notion (through Composio), the E2B sandbox and Vapi phone
// calls. Everything loads behind skeletons, refreshes by pulling, and
// changes ask first.

List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// The page for a connected Composio app, if it has one.
Widget? appManagerFor(String slug) => switch (slug) {
  'github' => const GitHubManagerScreen(),
  'gmail' => const GmailManagerScreen(),
  'googlecalendar' => const CalendarManagerScreen(),
  'notion' => const NotionManagerScreen(),
  _ => null,
};

// ---- reaching Composio directly ------------------------------------------------------

/// Runs a Composio action the app has no built-in tool for (repositories,
/// workflow runs…). When the slug is unknown, the closest action found by
/// [find] is used instead.
Future<Object?> _composio(WidgetRef ref, String slug, Map<String, dynamic> args, {String? find}) async {
  if (devCacheOnly) throw const DevNoCache();
  final client = await ref.read(integrationsProvider.notifier).client();
  if (client == null) throw 'Add a Composio key in Settings → Apps & web.';
  try {
    return AppResults.parse(await client.execute(slug, args));
  } catch (e) {
    if (find == null || !RegExp(r'not.?found|unknown|invalid.*(action|tool)|no such', caseSensitive: false).hasMatch('$e')) rethrow;
    final toolkit = slug.split('_').first.toLowerCase();
    final found = await client.findActions(toolkit: toolkit, query: find, limit: 1);
    if (found.isEmpty) rethrow;
    return AppResults.parse(await client.execute(found.first.slug, args));
  }
}

/// The first list of records under [v] whose items have [key].
List<Map<String, dynamic>> _deepList(Object? v, String key, [int depth = 0]) {
  if (depth > 8 || v == null) return const [];
  if (v is List) {
    final maps = [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)];
    if (maps.isNotEmpty && maps.first.containsKey(key)) return maps;
    for (final x in v) {
      final r = _deepList(x, key, depth + 1);
      if (r.isNotEmpty) return r;
    }
  }
  if (v is Map) {
    for (final x in v.values) {
      final r = _deepList(x, key, depth + 1);
      if (r.isNotEmpty) return r;
    }
  }
  return const [];
}

/// The first record under [v] that has [key].
Map<String, dynamic>? _deepMap(Object? v, String key, [int depth = 0]) {
  if (depth > 8 || v == null) return null;
  if (v is Map) {
    if (v.containsKey(key)) return Map<String, dynamic>.from(v);
    for (final x in v.values) {
      final r = _deepMap(x, key, depth + 1);
      if (r != null) return r;
    }
  }
  if (v is List) {
    for (final x in v) {
      final r = _deepMap(x, key, depth + 1);
      if (r != null) return r;
    }
  }
  return null;
}

Future<Map<String, dynamic>> _soft(Future<Map<String, dynamic>> f) async {
  try {
    return await f;
  } catch (_) {
    return const {};
  }
}

Widget _avatar(String? url, String name, {double size = 46}) => ClipOval(
  child: url == null
      ? Container(
          width: size,
          height: size,
          color: Colors.white24,
          alignment: Alignment.center,
          child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
        )
      : NetImage(url, width: size, height: size),
);

Widget _head(Widget lead, String title, String sub) => Row(
  children: [
    lead,
    const SizedBox(width: Space.m),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ],
      ),
    ),
  ],
);

Widget _hero(Widget head, List<Widget> stats) => Column(
  mainAxisAlignment: MainAxisAlignment.end,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [head, const SizedBox(height: Space.m), Row(children: [for (final (i, s) in stats.indexed) ...[if (i > 0) const SizedBox(width: Space.s), s]])],
);

Widget _fab(String label, IconData icon, VoidCallback onTap) =>
    FloatingActionButton.extended(backgroundColor: AppColors.text, foregroundColor: AppColors.bg, onPressed: onTap, icon: Icon(icon), label: Text(label));

void _toast(BuildContext context, Object e) {
  if (context.mounted && !cancelled(e)) showSnack(context, '$e'.replaceFirst('Exception: ', ''), icon: Icons.error_outline_rounded);
}

/// A small form in a sheet: [fields] as (label, hint, lines), then [onSubmit].
Future<void> _form(BuildContext context, {required DevBrand brand, required String title, required List<(String, String, int)> fields, required String action, required Future<void> Function(List<String> values) onSubmit}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _Form(brand: brand, title: title, fields: fields, action: action, onSubmit: onSubmit),
    );

class _Form extends StatefulWidget {
  const _Form({required this.brand, required this.title, required this.fields, required this.action, required this.onSubmit});
  final DevBrand brand;
  final String title;
  final List<(String, String, int)> fields;
  final String action;
  final Future<void> Function(List<String> values) onSubmit;
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final _c = [for (final _ in widget.fields) TextEditingController()];
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit([for (final c in _c) c.text.trim()]);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, MediaQuery.viewInsetsOf(context).bottom + Space.l),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [DevMark(widget.brand, size: 26), const SizedBox(width: Space.m), Text(widget.title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700))]),
        const SizedBox(height: Space.m),
        for (final (i, (label, hint, lines)) in widget.fields.indexed) ...[
          TextField(
            controller: _c[i],
            autofocus: i == 0,
            minLines: lines,
            maxLines: lines > 1 ? lines + 4 : 1,
            decoration: InputDecoration(labelText: label, hintText: hint, isDense: lines == 1, alignLabelWithHint: lines > 1),
          ),
          const SizedBox(height: Space.s),
        ],
        const SizedBox(height: Space.s),
        FilledButton.icon(
          onPressed: _busy ? null : _go,
          icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded, size: 18),
          label: Text(widget.action),
        ),
      ],
    ),
  );
}

// ---- GitHub ----------------------------------------------------------------------------

const _ghLanguage = {
  'Dart': Color(0xFF00B4AB), 'TypeScript': Color(0xFF3178C6), 'JavaScript': Color(0xFFF1E05A), 'Python': Color(0xFF3572A5),
  'Go': Color(0xFF00ADD8), 'Rust': Color(0xFFDEA584), 'Java': Color(0xFFB07219), 'Kotlin': Color(0xFFA97BFF), 'Swift': Color(0xFFF05138),
  'Svelte': Color(0xFFFF3E00), 'HTML': Color(0xFFE34C26), 'CSS': Color(0xFF563D7C), 'C++': Color(0xFFF34B7D), 'C': Color(0xFF555555),
};

/// owner, repo and number from an issue or pull request link.
(String, String, int)? _ghRef(Object? url) {
  final m = RegExp(r'github\.com/([^/]+)/([^/]+)/(?:issues|pull)/(\d+)').firstMatch('$url');
  return m == null ? null : (m[1]!, m[2]!, int.parse(m[3]!));
}

Color _ghState(Map i) => i['merged'] == true ? const Color(0xFF8957E5) : (i['state'] == 'open' ? AppColors.success : AppColors.danger);

IconData _ghIcon(Map i) => i['pull'] == true
    ? (i['merged'] == true ? Icons.merge_rounded : Icons.call_split_rounded)
    : (i['state'] == 'open' ? Icons.adjust_rounded : Icons.check_circle_outline_rounded);

class GitHubManagerScreen extends ConsumerWidget {
  const GitHubManagerScreen({super.key});

  static Widget _search(String q, String empty) => ManagedList(
    load: (context, ref) => loadList(context, ref, 'github_search_issues_and_pull_requests', {'q': q, 'per_page': 50}, 'issues'),
    searchHint: 'Search titles and repositories',
    matches: (i, s) => '${i['title']} ${i['repo'] ?? ''}'.toLowerCase().contains(s),
    empty: empty,
    itemBuilder: (context, i, reload) => _IssueTile(issue: i, reload: reload),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) => ManageScaffold(
    brand: DevBrand.github,
    title: 'GitHub',
    colors: const [Color(0xFF2D333B), Color(0xFF0D1117)],
    actions: [IconButton(tooltip: 'Open github.com', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://github.com'))],
    hero: HeroLoader(
      load: (context, ref) async {
        final r = await Future.wait([
          _composio(ref, 'GITHUB_GET_THE_AUTHENTICATED_USER', {}, find: 'get the authenticated user').then<Map<String, dynamic>>((v) => _deepMap(v, 'login') ?? {}).catchError((_) => <String, dynamic>{}),
          _soft(devRun(context, ref, 'github_list_notifications', {'per_page': 50})),
          _soft(devRun(context, ref, 'github_search_issues_and_pull_requests', {'q': 'is:pr is:open review-requested:@me archived:false', 'per_page': 30})),
        ]);
        return {'user': r[0], 'notifications': r[1]['notifications'], 'reviews': r[2]['issues']};
      },
      builder: (context, d) {
        final u = _m(d['user']);
        return _hero(
          _head(_avatar(u['avatar_url'] as String?, '${u['login'] ?? 'G'}'), '${u['name'] ?? u['login'] ?? 'GitHub'}', '@${u['login'] ?? ''}${u['public_repos'] == null ? '' : ' · ${u['public_repos']} repos'}'),
          [
            HeroStat('${_l(d['notifications']).where((n) => n['unread'] == true).length}', 'unread'),
            HeroStat('${_l(d['reviews']).length}', 'reviews for you', color: _l(d['reviews']).isNotEmpty ? const Color(0xFFFFD27A) : null),
            HeroStat('${u['followers'] ?? '–'}', 'followers'),
          ],
        );
      },
    ),
    tabs: [
      ManageTab(
        'Inbox',
        Icons.notifications_none_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'github_list_notifications', {'per_page': 50, 'all': false}, 'notifications'),
          empty: 'Inbox zero.',
          searchHint: 'Search notifications',
          matches: (n, q) => '${n['title']} ${n['repo']}'.toLowerCase().contains(q),
          header: (context, items) => Consumer(
            builder: (context, ref, _) => Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: Align(
                alignment: Alignment.centerRight,
                child: ActionButton(
                  label: 'Mark all read',
                  icon: Icons.done_all_rounded,
                  done: 'All read',
                  onRun: () => devRun(context, ref, 'github_mark_notifications_as_read', {}, confirmTitle: 'Mark every notification read?', confirmLabel: 'Mark read'),
                ),
              ),
            ),
          ),
          itemBuilder: (context, n, _) => ManageTile(
            leading: TileIcon(
              switch ('${n['type']}') {
                'PullRequest' => Icons.call_split_rounded,
                'Issue' => Icons.adjust_rounded,
                'Release' => Icons.sell_outlined,
                'Discussion' => Icons.forum_outlined,
                'CheckSuite' => Icons.rule_rounded,
                _ => Icons.notifications_none_rounded,
              },
              color: n['unread'] == true ? AppColors.accent : AppColors.text3,
            ),
            title: '${n['title']}',
            subtitle: '${n['repo']} · ${'${n['reason']}'.replaceAll('_', ' ')} · ${ago(n['updated'])}',
            trailing: n['unread'] == true ? Container(width: 9, height: 9, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)) : null,
            onTap: () => _ghRef(n['url']) != null ? _issueSheet(context, {'title': n['title'], 'url': n['url'], 'pull': n['type'] == 'PullRequest', 'repo': n['repo']}) : openUrl('${n['url'] ?? 'https://github.com/notifications'}'),
          ),
        ),
      ),
      ManageTab('Pull requests', Icons.call_split_rounded, (context) => _search('is:pr is:open involves:@me archived:false', 'No open pull requests involving you.')),
      ManageTab('Reviews', Icons.rate_review_outlined, (context) => _search('is:pr is:open review-requested:@me archived:false', 'Nobody is waiting on your review.')),
      ManageTab('Issues', Icons.adjust_rounded, (context) => _search('is:issue is:open involves:@me archived:false', 'No open issues involving you.')),
      ManageTab(
        'Repositories',
        Icons.book_outlined,
        (context) => ManagedList(
          load: (context, ref) async => _deepList(
            await _composio(ref, 'GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER', {'sort': 'updated', 'per_page': 60}, find: 'list repositories for the authenticated user'),
            'full_name',
          ),
          searchHint: 'Search repositories',
          matches: (r, q) => '${r['full_name']} ${r['description'] ?? ''}'.toLowerCase().contains(q),
          itemBuilder: (context, r, _) => _RepoTile(repo: r),
        ),
      ),
    ],
  );
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue, required this.reload});
  final Map<String, dynamic> issue;
  final VoidCallback reload;

  @override
  Widget build(BuildContext context) {
    final i = issue;
    return ManageTile(
      leading: TileIcon(_ghIcon(i), color: _ghState(i)),
      title: '${i['title']}',
      subtitle: [
        if (i['repo'] != null) '${i['repo']}',
        if (i['number'] != null) '${i['number']}',
        if (i['author'] != null) 'by ${i['author']}',
        if (i['updated'] != null) ago(i['updated']),
      ].join(' · '),
      trailing: (i['comments'] is num && (i['comments'] as num) > 0)
          ? Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppColors.text3), const SizedBox(width: 3), Text('${i['comments']}', style: context.text.labelSmall)])
          : null,
      onTap: () => _issueSheet(context, i, onChanged: reload),
    );
  }
}

/// An issue or pull request in a sheet: its description, labels, and
/// Comment, Close and Merge.
void _issueSheet(BuildContext context, Map<String, dynamic> issue, {VoidCallback? onChanged}) {
  final ref0 = _ghRef(issue['url']);
  showDevSheet(
    context,
    brand: DevBrand.github,
    title: '${issue['title']}',
    subtitle: [if (issue['repo'] != null) '${issue['repo']}', if (ref0 != null) '#${ref0.$3}'].join(' '),
    builder: (context, scroll) => Consumer(
      builder: (context, ref, _) {
        final i = issue;
        final open = i['state'] == null || i['state'] == 'open';
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: Space.x4),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (i['state'] != null) Pill(i['merged'] == true ? 'merged' : '${i['state']}', color: _ghState(i), icon: _ghIcon(i)),
                  if (i['pull'] == true) Pill('pull request', color: AppColors.text2),
                  if (i['author'] != null) Pill('by ${i['author']}', color: AppColors.text2, icon: Icons.person_outline_rounded),
                  for (final l in (i['labels'] as List? ?? const [])) Pill('$l', color: AppColors.accent),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  FilledButton.icon(onPressed: () => openUrl('${i['url']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open')),
                  if (ref0 != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      label: const Text('Comment'),
                      onPressed: () => _form(
                        context,
                        brand: DevBrand.github,
                        title: 'Comment',
                        fields: const [('Comment', 'Markdown works', 4)],
                        action: 'Post',
                        onSubmit: (v) async {
                          if (v[0].isEmpty) throw 'Write something first.';
                          await devRun(context, ref, 'github_create_an_issue_comment', {'owner': ref0.$1, 'repo': ref0.$2, 'issue_number': ref0.$3, 'body': v[0]},
                              confirmTitle: 'Post this comment?', confirmMessage: v[0], confirmLabel: 'Post');
                          if (context.mounted) showSnack(context, 'Comment posted');
                        },
                      ),
                    ),
                  if (ref0 != null && open && i['pull'] != true)
                    ActionButton(
                      label: 'Close',
                      icon: Icons.check_circle_outline_rounded,
                      done: 'Closed',
                      onRun: () async {
                        await devRun(context, ref, 'github_close_issue', {'owner': ref0.$1, 'repo': ref0.$2, 'issue_number': ref0.$3}, confirmTitle: 'Close this issue?', confirmLabel: 'Close');
                        onChanged?.call();
                      },
                    ),
                  if (ref0 != null && open && i['pull'] == true)
                    ActionButton(
                      label: 'Merge',
                      icon: Icons.merge_rounded,
                      danger: true,
                      done: 'Merged',
                      onRun: () async {
                        await devRun(context, ref, 'github_merge_a_pull_request', {'owner': ref0.$1, 'repo': ref0.$2, 'pull_number': ref0.$3},
                            confirmTitle: 'Merge this pull request?', confirmMessage: '${i['title']}', confirmLabel: 'Merge');
                        onChanged?.call();
                      },
                    ),
                ],
              ),
            ),
            const SheetLabel('Description'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: '${i['body'] ?? ''}'.trim().isEmpty
                  ? Text('No description.', style: context.text.bodySmall)
                  : MarkdownBody(data: '${i['body']}', selectable: true, onTapLink: (_, href, _) => href == null ? null : openUrl(href)),
            ),
          ],
        );
      },
    ),
  );
}

class _RepoTile extends StatelessWidget {
  const _RepoTile({required this.repo});
  final Map<String, dynamic> repo;

  @override
  Widget build(BuildContext context) {
    final r = repo;
    final lang = r['language'] as String?;
    return ManageTile(
      leading: TileIcon(r['private'] == true ? Icons.lock_outline_rounded : Icons.book_outlined, color: r['fork'] == true ? AppColors.text3 : AppColors.accent),
      title: '${r['full_name']}',
      subtitle: [
        if ('${r['description'] ?? ''}'.isNotEmpty) '${r['description']}',
        [if (lang != null) '● $lang', '★ ${r['stargazers_count'] ?? 0}', if (r['pushed_at'] != null) 'pushed ${ago(r['pushed_at'])}'].join('  '),
      ].join('\n'),
      trailing: lang == null ? null : Container(width: 10, height: 10, decoration: BoxDecoration(color: _ghLanguage[lang] ?? AppColors.text3, shape: BoxShape.circle)),
      onTap: () => _repoSheet(context, r),
    );
  }
}

/// A repository in a sheet: stats, recent workflow runs and commits.
void _repoSheet(BuildContext context, Map<String, dynamic> r) {
  final owner = '${_m(r['owner'])['login'] ?? '${r['full_name']}'.split('/').first}';
  final name = '${r['name'] ?? '${r['full_name']}'.split('/').last}';
  showDevSheet(
    context,
    brand: DevBrand.github,
    title: '${r['full_name']}',
    subtitle: '${r['description'] ?? ''}',
    builder: (context, scroll) => Consumer(
      builder: (context, ref, _) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          StatTiles([
            ('stars', compact(r['stargazers_count'] ?? 0)),
            ('forks', compact(r['forks_count'] ?? 0)),
            ('open issues', compact(r['open_issues_count'] ?? 0)),
            ('branch', '${r['default_branch'] ?? 'main'}'),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Row(
              children: [
                Expanded(child: FilledButton.icon(onPressed: () => openUrl('${r['html_url']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open'))),
                const SizedBox(width: Space.s),
                Expanded(child: OutlinedButton.icon(onPressed: () => openUrl('${r['html_url']}/actions'), icon: const Icon(Icons.play_circle_outline_rounded, size: 18), label: const Text('Actions'))),
              ],
            ),
          ),
          const SheetLabel('Workflow runs'),
          Loaded<List<Map<String, dynamic>>>(
            load: () async => _deepList(await _composio(ref, 'GITHUB_LIST_WORKFLOW_RUNS_FOR_A_REPOSITORY', {'owner': owner, 'repo': name, 'per_page': 10}, find: 'list workflow runs for a repository'), 'run_number'),
            builder: (context, runs, _) => runs.isEmpty
                ? Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: Text('No workflow runs.', style: context.text.bodySmall))
                : SheetGroup(
                    children: [
                      for (final run in runs)
                        ListTile(
                          dense: true,
                          onTap: () => openUrl('${run['html_url']}'),
                          leading: Icon(
                            run['status'] != 'completed'
                                ? Icons.pending_outlined
                                : (run['conclusion'] == 'success' ? Icons.check_circle_rounded : (run['conclusion'] == 'failure' ? Icons.cancel_rounded : Icons.remove_circle_outline_rounded)),
                            color: run['status'] != 'completed'
                                ? AppColors.warning
                                : (run['conclusion'] == 'success' ? AppColors.success : (run['conclusion'] == 'failure' ? AppColors.danger : AppColors.text3)),
                          ),
                          title: Text('${run['display_title'] ?? run['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${run['name']} #${run['run_number']} · ${run['head_branch'] ?? ''} · ${ago(run['created_at'])}'),
                        ),
                    ],
                  ),
          ),
          const SheetLabel('Recent commits'),
          Loaded<List<Map<String, dynamic>>>(
            load: () async => _deepList(await _composio(ref, 'GITHUB_LIST_COMMITS', {'owner': owner, 'repo': name, 'per_page': 10}, find: 'list commits'), 'sha'),
            builder: (context, commits, _) => SheetGroup(
              children: [
                for (final c in commits)
                  ListTile(
                    dense: true,
                    onTap: () => openUrl('${c['html_url']}'),
                    leading: Text('${c['sha']}'.substring(0, 7), style: codeTextStyle.copyWith(fontSize: 12, color: AppColors.accent)),
                    title: Text('${_m(c['commit'])['message'] ?? ''}'.split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_m(_m(c['commit'])['author'])['name'] ?? ''} · ${ago(_m(_m(c['commit'])['author'])['date'])}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ---- Gmail -----------------------------------------------------------------------------

class GmailManagerScreen extends ConsumerWidget {
  const GmailManagerScreen({super.key});

  static Widget _box(String query, String empty) => ManagedList(
    load: (context, ref) => loadList(context, ref, 'gmail_fetch_emails', {'query': query, 'max_results': 30}, 'emails'),
    searchHint: 'Search loaded mail',
    matches: (e, q) => '${e['subject']} ${e['from']} ${e['snippet']}'.toLowerCase().contains(q),
    empty: empty,
    itemBuilder: (context, e, reload) => _MailTile(email: e, reload: reload),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) => ManageScaffold(
    brand: DevBrand.gmail,
    title: 'Gmail',
    colors: const [Color(0xFFB3261E), Color(0xFF3B0D0A)],
    actions: [IconButton(tooltip: 'Open Gmail', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://mail.google.com'))],
    fab: _fab('Compose', Icons.edit_rounded, () => _compose(context, ref)),
    hero: HeroLoader(
      load: (context, ref) async {
        final r = await Future.wait([
          _soft(devRun(context, ref, 'gmail_get_profile', {})),
          _soft(devRun(context, ref, 'gmail_list_labels', {'include_details': true})),
        ]);
        final labels = _deepList(r[1], 'messagesUnread');
        return {'profile': _deepMap(r[0], 'emailAddress') ?? {}, 'inbox': labels.where((l) => l['id'] == 'INBOX').firstOrNull ?? {}, 'starred': labels.where((l) => l['id'] == 'STARRED').firstOrNull ?? {}};
      },
      builder: (context, d) {
        final p = _m(d['profile']);
        final inbox = _m(d['inbox']);
        return _hero(
          _head(const DevMark(DevBrand.gmail, size: 46), '${p['emailAddress'] ?? 'Gmail'}', '${compact(p['messagesTotal'] ?? 0)} messages · ${compact(p['threadsTotal'] ?? 0)} threads'),
          [
            HeroStat('${inbox['messagesUnread'] ?? '–'}', 'unread', color: (inbox['messagesUnread'] as num? ?? 0) > 0 ? const Color(0xFFFFC2BC) : null),
            HeroStat(compact(inbox['messagesTotal'] ?? 0), 'in inbox'),
            HeroStat(compact(_m(d['starred'])['messagesTotal'] ?? 0), 'starred'),
          ],
        );
      },
    ),
    tabs: [
      ManageTab('Inbox', Icons.inbox_rounded, (context) => _box('in:inbox', 'Your inbox is empty.')),
      ManageTab('Unread', Icons.mark_email_unread_outlined, (context) => _box('is:unread in:inbox', 'Nothing unread.')),
      ManageTab('Starred', Icons.star_outline_rounded, (context) => _box('is:starred', 'No starred mail.')),
      ManageTab('Sent', Icons.send_outlined, (context) => _box('in:sent', 'Nothing sent.')),
      ManageTab(
        'Labels',
        Icons.label_outline_rounded,
        (context) => ManagedList(
          load: (context, ref) async => _deepList(await devRun(context, ref, 'gmail_list_labels', {'include_details': true}), 'id')
              .where((l) => l['type'] == 'user' || const {'IMPORTANT', 'SPAM', 'TRASH', 'DRAFT'}.contains(l['id']))
              .toList(),
          itemBuilder: (context, l, _) => ManageTile(
            leading: TileIcon(Icons.label_outline_rounded, color: DevBrand.gmail.color),
            title: '${l['name']}',
            subtitle: [if (l['messagesTotal'] != null) '${l['messagesTotal']} messages', if ((l['messagesUnread'] as num? ?? 0) > 0) '${l['messagesUnread']} unread'].join(' · '),
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            onTap: () => showDevSheet(
              context,
              brand: DevBrand.gmail,
              title: '${l['name']}',
              builder: (context, scroll) => Consumer(
                builder: (context, ref, _) => Loaded<List<Map<String, dynamic>>>(
                  load: () => loadList(context, ref, 'gmail_fetch_emails', {'label_ids': [l['id']], 'max_results': 30}, 'emails'),
                  builder: (context, emails, reload) => ListView(
                    controller: scroll,
                    padding: const EdgeInsets.only(top: Space.m),
                    children: [for (final e in emails) _MailTile(email: e, reload: reload)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  void _compose(BuildContext context, WidgetRef ref) => _form(
    context,
    brand: DevBrand.gmail,
    title: 'New email',
    fields: const [('To', 'name@example.com', 1), ('Subject', '', 1), ('Message', '', 6)],
    action: 'Send',
    onSubmit: (v) async {
      if (!v[0].contains('@') || v[2].isEmpty) throw 'Fill in To and the message.';
      await devRun(context, ref, 'gmail_send_email', {'recipient_email': v[0], 'subject': v[1], 'body': v[2]},
          confirmTitle: 'Send to ${v[0]}?', confirmMessage: v[1], confirmLabel: 'Send');
      if (context.mounted) showSnack(context, 'Sent');
    },
  );
}

class _MailTile extends ConsumerWidget {
  const _MailTile({required this.email, required this.reload});
  final Map<String, dynamic> email;
  final VoidCallback reload;

  static String _sender(String from) {
    final m = RegExp(r'^\s*"?([^"<]+?)"?\s*<').firstMatch(from);
    return (m?[1] ?? from).trim();
  }

  Future<void> _modify(BuildContext context, WidgetRef ref, {List<String> add = const [], List<String> remove = const [], required String what}) async {
    try {
      await devRun(context, ref, 'gmail_batch_modify_messages', {'messageIds': [email['id']], 'addLabelIds': add, 'removeLabelIds': remove},
          confirmTitle: '$what?', confirmMessage: '${email['subject']}', confirmLabel: what);
      if (context.mounted) showSnack(context, 'Done');
      reload();
    } catch (e) {
      if (context.mounted) _toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = email;
    final unread = e['unread'] == true;
    final sender = _sender('${e['from']}');
    final hue = _monoHue(sender);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xs),
      child: Material(
        color: unread ? AppColors.surface : AppColors.bg,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () => showEmail(context, 'gmail', e),
          onLongPress: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            backgroundColor: AppColors.surface,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(title: Text('${e['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(sender)),
                  ListTile(
                    leading: Icon(unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined),
                    title: Text(unread ? 'Mark read' : 'Mark unread'),
                    onTap: () {
                      Navigator.pop(sheet);
                      unread ? _modify(context, ref, remove: ['UNREAD'], what: 'Mark read') : _modify(context, ref, add: ['UNREAD'], what: 'Mark unread');
                    },
                  ),
                  ListTile(
                    leading: Icon(e['starred'] == true ? Icons.star_rounded : Icons.star_outline_rounded),
                    title: Text(e['starred'] == true ? 'Unstar' : 'Star'),
                    onTap: () {
                      Navigator.pop(sheet);
                      e['starred'] == true ? _modify(context, ref, remove: ['STARRED'], what: 'Unstar') : _modify(context, ref, add: ['STARRED'], what: 'Star');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('Archive'),
                    onTap: () {
                      Navigator.pop(sheet);
                      _modify(context, ref, remove: ['INBOX'], what: 'Archive');
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                    title: Text('Move to trash', style: TextStyle(color: AppColors.danger)),
                    onTap: () async {
                      Navigator.pop(sheet);
                      try {
                        await devRun(context, ref, 'gmail_move_to_trash', {'message_id': e['id']}, confirmTitle: 'Move to trash?', confirmMessage: '${e['subject']}', confirmLabel: 'Trash');
                        reload();
                      } catch (err) {
                        if (context.mounted) _toast(context, err);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 19, backgroundColor: hue.withValues(alpha: 0.2), child: Text(sender.isEmpty ? '?' : sender.characters.first.toUpperCase(), style: TextStyle(color: hue, fontWeight: FontWeight.w800))),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500))),
                          Text(ago(e['date']), style: context.text.labelSmall?.copyWith(color: unread ? AppColors.accent : AppColors.text3, fontWeight: unread ? FontWeight.w700 : null)),
                        ],
                      ),
                      Text('${e['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w400, fontSize: 13.5)),
                      Text('${e['snippet'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    if (e['starred'] == true) Icon(Icons.star_rounded, size: 17, color: AppColors.warning),
                    if ((e['attachments'] as List?)?.isNotEmpty == true) Icon(Icons.attach_file_rounded, size: 16, color: AppColors.text3),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _monoHue(String s) {
  const hues = [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF14B8A6)];
  return hues[s.codeUnits.fold<int>(0, (a, b) => a + b) % hues.length];
}

// ---- Google Calendar -------------------------------------------------------------------

DateTime? _evDate(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
  return switch (diff) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => DateFormat('EEEE, d MMMM').format(d),
  };
}

String _evTime(Map e) {
  final s = _evDate(e['start']);
  final end = _evDate(e['end']);
  if (s == null) return '';
  if (e['all_day'] == true) return 'All day';
  return '${DateFormat.Hm().format(s)}${end == null ? '' : ' – ${DateFormat.Hm().format(end)}'}';
}

Future<List<Map<String, dynamic>>> _events(BuildContext context, WidgetRef ref, {int days = 14, DateTime? from}) async {
  final start = from ?? DateTime.now().subtract(const Duration(hours: 2));
  final list = await loadList(context, ref, 'googlecalendar_events_list', {
    'calendarId': 'primary',
    'timeMin': start.toUtc().toIso8601String(),
    'timeMax': start.add(Duration(days: days)).toUtc().toIso8601String(),
    'singleEvents': true,
    'maxResults': 150,
  }, 'events');
  list.sort((a, b) => '${_evDate(a['start'])}'.compareTo('${_evDate(b['start'])}'));
  return list;
}

class CalendarManagerScreen extends ConsumerWidget {
  const CalendarManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ManageScaffold(
    brand: DevBrand.calendar,
    title: 'Calendar',
    colors: const [Color(0xFF1967D2), Color(0xFF0B2A5B)],
    actions: [IconButton(tooltip: 'Open Google Calendar', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://calendar.google.com'))],
    fab: _fab('Quick add', Icons.add_rounded, () => _quickAdd(context, ref)),
    hero: HeroLoader(
      load: (context, ref) async => {'events': await _events(context, ref, days: 7)},
      builder: (context, d) {
        final events = _l(d['events']);
        final now = DateTime.now();
        final today = events.where((e) => _evDate(e['start'])?.day == now.day && _evDate(e['start'])?.month == now.month).length;
        final next = events.where((e) => e['all_day'] != true && (_evDate(e['start'])?.isAfter(now) ?? false)).firstOrNull;
        return _hero(
          _head(const DevMark(DevBrand.calendar, size: 46), DateFormat('EEEE, d MMMM').format(now), next == null ? 'Nothing else coming up' : 'Next: ${next['title']} ${ago(next['start'])}'),
          [HeroStat('$today', 'today'), HeroStat('${events.length}', 'this week'), HeroStat(next == null ? '–' : DateFormat.Hm().format(_evDate(next['start'])!), 'next starts')],
        );
      },
    ),
    tabs: [
      ManageTab(
        'Agenda',
        Icons.view_agenda_outlined,
        (context) => ManagedList(
          load: (context, ref) async {
            // A day heading before each day's first event.
            final out = <Map<String, dynamic>>[];
            String? last;
            for (final e in await _events(context, ref)) {
              final d = _evDate(e['start']);
              final label = d == null ? '' : _dayLabel(d);
              if (label != last) out.add({'_day': label});
              last = label;
              out.add(e);
            }
            return out;
          },
          searchHint: 'Search events',
          matches: (e, q) => e['_day'] == null && '${e['title']} ${e['location'] ?? ''}'.toLowerCase().contains(q),
          empty: 'Nothing in the next two weeks.',
          itemBuilder: (context, e, reload) => e['_day'] != null
              ? Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s), child: Text('${e['_day']}'.toUpperCase(), style: context.text.labelSmall?.copyWith(color: DevBrand.calendar.color, fontWeight: FontWeight.w800)))
              : _EventTile(event: e, reload: reload),
        ),
      ),
      ManageTab('Today', Icons.today_rounded, (context) => const _DayView()),
      ManageTab(
        'Calendars',
        Icons.calendar_month_outlined,
        (context) => ManagedList(
          load: (context, ref) async => _deepList(await devRun(context, ref, 'googlecalendar_list_calendars', {'max_results': 50}), 'accessRole'),
          itemBuilder: (context, c, _) {
            final color = Color(int.tryParse('${c['backgroundColor'] ?? '#4285F4'}'.replaceFirst('#', 'FF'), radix: 16) ?? 0xFF4285F4);
            return ManageTile(
              leading: TileIcon(Icons.calendar_month_rounded, color: color),
              title: '${c['summaryOverride'] ?? c['summary']}',
              subtitle: [if (c['primary'] == true) 'primary', '${c['accessRole']}', if (c['timeZone'] != null) '${c['timeZone']}'].join(' · '),
            );
          },
        ),
      ),
    ],
  );

  void _quickAdd(BuildContext context, WidgetRef ref) => _form(
    context,
    brand: DevBrand.calendar,
    title: 'Quick add',
    fields: const [('Event', 'Lunch with Sara tomorrow at 1pm', 1)],
    action: 'Add',
    onSubmit: (v) async {
      if (v[0].isEmpty) throw 'Describe the event.';
      await devRun(context, ref, 'googlecalendar_quick_add', {'text': v[0]}, confirmTitle: 'Add “${v[0]}”?', confirmLabel: 'Add');
      if (context.mounted) showSnack(context, 'Added to your calendar');
    },
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.reload});
  final Map<String, dynamic> event;
  final VoidCallback reload;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final now = DateTime.now();
    final start = _evDate(e['start']);
    final end = _evDate(e['end']);
    final live = start != null && end != null && now.isAfter(start) && now.isBefore(end);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l), side: BorderSide(color: live ? DevBrand.calendar.color : AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _eventSheet(context, e, onChanged: reload),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: DevBrand.calendar.color.withValues(alpha: end != null && end.isBefore(now) ? 0.3 : 1)),
                Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: SizedBox(
                    width: 62,
                    child: Text(_evTime(e).replaceFirst(' – ', '\n'), style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures, fontWeight: FontWeight.w700)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, Space.m, Space.m, Space.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('${e['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                            if (live) Pill('now', color: DevBrand.calendar.color, pulse: true),
                          ],
                        ),
                        if (e['location'] != null) Text('${e['location']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                        if (e['meet'] != null || e['attendees'] != null)
                          Text([if (e['meet'] != null) 'Video call', if (e['attendees'] != null) '${e['attendees']} people'].join(' · '), style: context.text.labelSmall),
                      ],
                    ),
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

/// Today as hours with the events placed on them, and a line at now.
class _DayView extends ConsumerWidget {
  const _DayView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    const hour = 56.0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 96),
      children: [
        Loaded<List<Map<String, dynamic>>>(
          load: () => _events(context, ref, days: 1, from: midnight),
          builder: (context, events, reload) {
            final timed = [for (final e in events) if (e['all_day'] != true && _evDate(e['start']) != null) e];
            final allDay = [for (final e in events) if (e['all_day'] == true) e];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in allDay) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Pill('All day · ${e['title']}', color: DevBrand.calendar.color)),
                SizedBox(
                  height: hour * 24,
                  child: Stack(
                    children: [
                      for (var h = 0; h < 24; h++)
                        Positioned(
                          top: h * hour,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(width: 44, child: Text('${h.toString().padLeft(2, '0')}:00', style: context.text.labelSmall)),
                              Expanded(child: Container(height: 1, color: AppColors.line)),
                            ],
                          ),
                        ),
                      for (final e in timed)
                        () {
                          final s = _evDate(e['start'])!;
                          final end = _evDate(e['end']) ?? s.add(const Duration(hours: 1));
                          final top = s.difference(midnight).inMinutes / 60 * hour;
                          final height = (end.difference(s).inMinutes / 60 * hour).clamp(26.0, hour * 24);
                          return Positioned(
                            top: top.clamp(0, hour * 24 - 26),
                            left: 50,
                            right: 0,
                            height: height,
                            child: Material(
                              color: DevBrand.calendar.color.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(Radii.s),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(Radii.s),
                                onTap: () => _eventSheet(context, e, onChanged: reload),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 3),
                                  decoration: BoxDecoration(border: Border(left: BorderSide(color: DevBrand.calendar.color, width: 3))),
                                  child: Text('${e['title']} · ${_evTime(e)}', maxLines: height > 40 ? 2 : 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                          );
                        }(),
                      Positioned(
                        top: now.difference(midnight).inMinutes / 60 * hour,
                        left: 40,
                        right: 0,
                        child: Row(children: [Container(width: 9, height: 9, decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)), Expanded(child: Container(height: 2, color: AppColors.danger))]),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// An event in a sheet: when, where, the call link, who, the description,
/// and Delete.
void _eventSheet(BuildContext context, Map<String, dynamic> e, {VoidCallback? onChanged}) => showDevSheet(
  context,
  brand: DevBrand.calendar,
  title: '${e['title']}',
  subtitle: _evDate(e['start']) == null ? null : '${_dayLabel(_evDate(e['start'])!)} · ${_evTime(e)}',
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              if (e['meet'] != null) FilledButton.icon(onPressed: () => openUrl('${e['meet']}'), icon: const Icon(Icons.videocam_rounded, size: 18), label: const Text('Join call')),
              if (e['location'] != null)
                OutlinedButton.icon(
                  onPressed: () => openUrl('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${e['location']}')}'),
                  icon: const Icon(Icons.place_outlined, size: 18),
                  label: const Text('Map'),
                ),
              if (e['link'] != null) OutlinedButton.icon(onPressed: () => openUrl('${e['link']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open')),
              if (e['id'] != null)
                ActionButton(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  danger: true,
                  done: 'Deleted',
                  onRun: () async {
                    await devRun(context, ref, 'googlecalendar_delete_event', {'event_id': e['id']}, confirmTitle: 'Delete “${e['title']}”?', confirmLabel: 'Delete');
                    onChanged?.call();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
        const SheetLabel('Details'),
        SheetGroup(
          children: [
            CopyRow(label: 'When', value: _evDate(e['start']) == null ? '' : '${_dayLabel(_evDate(e['start'])!)}, ${_evTime(e)}', mono: false),
            if (e['location'] != null) CopyRow(label: 'Where', value: '${e['location']}', mono: false),
            if (e['organizer'] != null) CopyRow(label: 'Organizer', value: '${e['organizer']}', mono: false),
            if (e['attendees'] != null) CopyRow(label: 'Guests', value: '${e['attendees']}', mono: false),
            if (e['meet'] != null) CopyRow(label: 'Call', value: '${e['meet']}'),
            if (e['status'] != null) CopyRow(label: 'Status', value: '${e['status']}', mono: false),
          ],
        ),
        if ('${e['description'] ?? ''}'.trim().isNotEmpty) ...[
          const SheetLabel('Description'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: SelectableText('${e['description']}', style: context.text.bodyMedium?.copyWith(height: 1.5))),
        ],
      ],
    ),
  ),
);

// ---- Notion ----------------------------------------------------------------------------

Future<List<Map<String, dynamic>>> _notion(BuildContext context, WidgetRef ref) async {
  final pages = await loadList(context, ref, 'notion_search_notion_page', {'query': '', 'page_size': 100, 'direction': 'descending', 'timestamp': 'last_edited_time'}, 'pages');
  pages.sort((a, b) => '${b['edited'] ?? ''}'.compareTo('${a['edited'] ?? ''}'));
  return [for (final p in pages) if (p['archived'] != true) p];
}

class NotionManagerScreen extends ConsumerWidget {
  const NotionManagerScreen({super.key});

  static Widget _list(bool Function(Map<String, dynamic>) keep, String empty) => ManagedList(
    load: (context, ref) async => [for (final p in await _notion(context, ref)) if (keep(p)) p],
    searchHint: 'Search titles',
    matches: (p, q) => '${p['title']}'.toLowerCase().contains(q),
    empty: empty,
    itemBuilder: (context, p, reload) => ManageTile(
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
        child: p['icon'] != null
            ? Text('${p['icon']}', style: const TextStyle(fontSize: 22))
            : Icon(p['kind'] == 'database' ? Icons.table_chart_outlined : Icons.description_outlined, color: AppColors.text2),
      ),
      title: '${p['title']}',
      subtitle: '${p['kind'] == 'database' ? 'Database' : 'Page'} · edited ${ago(p['edited'])}',
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
      onTap: () => _notionSheet(context, p, onChanged: reload),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) => ManageScaffold(
    brand: DevBrand.notion,
    title: 'Notion',
    colors: const [Color(0xFF3F3F3F), Color(0xFF191919)],
    actions: [IconButton(tooltip: 'Open Notion', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://www.notion.so'))],
    hero: HeroLoader(
      load: (context, ref) async => {'pages': await _notion(context, ref)},
      builder: (context, d) {
        final pages = _l(d['pages']);
        final dbs = pages.where((p) => p['kind'] == 'database').length;
        final week = pages.where((p) => DateTime.tryParse('${p['edited']}')?.isAfter(DateTime.now().subtract(const Duration(days: 7))) ?? false).length;
        return _hero(
          _head(const DevMark(DevBrand.notion, size: 46), 'Workspace', pages.isEmpty ? 'Share pages with the Composio integration to see them' : 'Last edit ${ago(pages.first['edited'])}'),
          [HeroStat('${pages.length - dbs}', 'pages'), HeroStat('$dbs', 'databases'), HeroStat('$week', 'edited this week')],
        );
      },
    ),
    tabs: [
      ManageTab('Recent', Icons.history_rounded, (context) => _list((_) => true, 'Nothing shared with the integration yet.')),
      ManageTab('Pages', Icons.description_outlined, (context) => _list((p) => p['kind'] != 'database', 'No pages.')),
      ManageTab('Databases', Icons.table_chart_outlined, (context) => _list((p) => p['kind'] == 'database', 'No databases.')),
    ],
  );
}

/// A page (read as Markdown) or a database (its rows) in a sheet.
void _notionSheet(BuildContext context, Map<String, dynamic> p, {VoidCallback? onChanged}) => showDevSheet(
  context,
  brand: DevBrand.notion,
  title: '${p['icon'] == null ? '' : '${p['icon']} '}${p['title']}',
  subtitle: 'edited ${ago(p['edited'])}',
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Row(
            children: [
              if (p['url'] != null) Expanded(child: FilledButton.icon(onPressed: () => openUrl('${p['url']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open in Notion'))),
              if (p['kind'] != 'database') ...[
                const SizedBox(width: Space.s),
                ActionButton(
                  label: 'Archive',
                  icon: Icons.archive_outlined,
                  danger: true,
                  done: 'Archived',
                  onRun: () async {
                    await devRun(context, ref, 'notion_archive_notion_page', {'page_id': p['id'], 'archive': true}, confirmTitle: 'Archive “${p['title']}”?', confirmLabel: 'Archive');
                    onChanged?.call();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        if (p['kind'] == 'database')
          Loaded<List<Map<String, dynamic>>>(
            load: () => loadList(context, ref, 'notion_query_database', {'database_id': p['id'], 'page_size': 50}, 'pages'),
            builder: (context, rows, _) => SheetGroup(
              children: [
                if (rows.isEmpty) Padding(padding: const EdgeInsets.all(Space.l), child: Text('No rows.', style: context.text.bodySmall)),
                for (final r in rows)
                  ListTile(
                    dense: true,
                    leading: Text('${r['icon'] ?? '📄'}', style: const TextStyle(fontSize: 18)),
                    title: Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('edited ${ago(r['edited'])}'),
                    onTap: () => _notionSheet(context, r),
                  ),
              ],
            ),
          )
        else
          Loaded<Map<String, dynamic>>(
            load: () => devRun(context, ref, 'notion_get_page_markdown', {'page_id': p['id']}),
            builder: (context, j, _) {
              final text = '${_m(j['document'])['text'] ?? _deepMap(j, 'markdown')?['markdown'] ?? ''}';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                child: text.trim().isEmpty
                    ? Text('This page is empty.', style: context.text.bodySmall)
                    : MarkdownBody(data: text, selectable: true, onTapLink: (_, href, _) => href == null ? null : openUrl(href)),
              );
            },
          ),
      ],
    ),
  ),
);

// ---- E2B -------------------------------------------------------------------------------

class E2bManagerScreen extends ConsumerWidget {
  const E2bManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(e2bSessionProvider);
    return ManageScaffold(
      brand: DevBrand.e2b,
      title: 'E2B',
      colors: const [Color(0xFF7A3E00), Color(0xFF1A0E00)],
      actions: [IconButton(tooltip: 'Open the E2B dashboard', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://e2b.dev/dashboard'))],
      fab: _fab('Code editor', Icons.code_rounded, () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CodeEditorScreen()))),
      hero: ValueListenableBuilder(
        valueListenable: session.changes,
        builder: (context, _, _) {
          final box = session.current;
          final runs = session.history.fold<int>(0, (s, e) => s + e.runs);
          return _hero(
            _head(const DevMark(DevBrand.e2b, size: 46), box == null ? 'No sandbox running' : 'Sandbox running', box == null ? 'One starts with the first run' : '${box.id} · ${box.template}'),
            [
              HeroStat(box == null ? 'Off' : 'On', 'this app', color: box == null ? null : const Color(0xFF86EFAC)),
              HeroStat('${session.history.length}', 'sandboxes made'),
              HeroStat('$runs', 'runs'),
            ],
          );
        },
      ),
      tabs: [
        ManageTab(
          'Sandboxes',
          Icons.dns_outlined,
          (context) => ManagedList(
            load: (context, ref) => loadList(context, ref, 'e2b_sandboxes', {}, 'sandboxes'),
            empty: 'Nothing running on your E2B account.',
            header: (context, _) => const _SandboxControls(),
            itemBuilder: (context, b, reload) => Consumer(
              builder: (context, ref, _) => ManageTile(
                leading: TileIcon(Icons.memory_rounded, color: b['state'] == 'running' ? AppColors.success : AppColors.warning),
                title: '${b['id']}',
                subtitle: [
                  '${b['template']}',
                  '${b['state']}',
                  if (b['cpus'] != null) '${b['cpus']} CPU · ${b['memory_mb']} MB',
                  if (b['ends'] != null) 'ends ${ago(b['ends'])}',
                ].join(' · '),
                trailing: IconButton(
                  tooltip: 'Shut down',
                  icon: Icon(Icons.power_settings_new_rounded, color: AppColors.danger),
                  onPressed: () async {
                    try {
                      await devRun(context, ref, 'e2b_kill_sandbox', {'sandbox_id': b['id']}, confirmTitle: 'Shut down ${b['id']}?', confirmMessage: 'Its files and state are lost.', confirmLabel: 'Shut down');
                      reload();
                    } catch (e) {
                      if (context.mounted) _toast(context, e);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        ManageTab('Files', Icons.folder_open_rounded, (context) => const _E2bFiles()),
        ManageTab('Terminal', Icons.terminal_rounded, (context) => const _E2bTerminal()),
        ManageTab(
          'History',
          Icons.history_rounded,
          (context) => ValueListenableBuilder(
            valueListenable: session.changes,
            builder: (context, _, _) => ListView(
              padding: const EdgeInsets.only(top: Space.m, bottom: 96),
              children: [
                if (session.history.isEmpty) Padding(padding: const EdgeInsets.all(Space.x4), child: Text('Sandboxes this app starts are listed here.', textAlign: TextAlign.center, style: context.text.bodySmall)),
                for (final e in session.history.take(80))
                  ManageTile(
                    leading: TileIcon(e.live ? Icons.play_circle_outline_rounded : Icons.stop_circle_outlined, color: e.live ? AppColors.success : AppColors.text3),
                    title: e.id,
                    subtitle: [
                      '${e.runs} run${e.runs == 1 ? '' : 's'}',
                      'started ${ago(e.started.toIso8601String())}',
                      if (e.ended != null) '${e.endReason ?? 'stopped'} after ${span(e.ended!.difference(e.started))}',
                      if (e.by.isNotEmpty) 'by ${e.by}',
                    ].join(' · '),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SandboxControls extends ConsumerWidget {
  const _SandboxControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.read(e2bSessionProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
      child: Row(
        children: [
          Expanded(child: ActionButton(label: s.current == null ? 'Start' : 'Restart', icon: Icons.restart_alt_rounded, filled: true, done: 'Ready', onRun: () async => s.current == null ? await s.start() : await s.restart())),
          const SizedBox(width: Space.s),
          if (s.current != null) Expanded(child: ActionButton(label: 'Shut down', icon: Icons.power_settings_new_rounded, danger: true, done: 'Stopped', onRun: () => s.stop(null, 'shut down from the E2B page'))),
        ],
      ),
    );
  }
}

/// The sandbox's files, a folder at a time; a file downloads and opens.
class _E2bFiles extends ConsumerStatefulWidget {
  const _E2bFiles();
  @override
  ConsumerState<_E2bFiles> createState() => _E2bFilesState();
}

class _E2bFilesState extends ConsumerState<_E2bFiles> with AutomaticKeepAliveClientMixin {
  String _path = '/home/user';
  int _v = 0;

  @override
  bool get wantKeepAlive => true;

  void _go(String path) => setState(() {
    _path = path;
    _v++;
  });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.only(top: Space.m, bottom: 96),
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            children: [
              ActionChip(label: const Text('/'), onPressed: () => _go('/')),
              for (final (i, p) in parts.indexed) ...[
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                ActionChip(label: Text(p), onPressed: () => _go('/${parts.take(i + 1).join('/')}')),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        Loaded<List<Map<String, dynamic>>>(
          key: ValueKey(_v),
          load: () => loadList(context, ref, 'e2b_list_files', {'path': _path}, 'files'),
          builder: (context, files, reload) => Column(
            children: [
              if (files.isEmpty) Padding(padding: const EdgeInsets.all(Space.xl), child: Text('Empty folder. Start the sandbox if it isn\'t running.', style: context.text.bodySmall)),
              for (final f in [...files.where((f) => f['dir'] == true), ...files.where((f) => f['dir'] != true)])
                ManageTile(
                  leading: TileIcon(f['dir'] == true ? Icons.folder_rounded : Icons.insert_drive_file_outlined, color: f['dir'] == true ? DevBrand.e2b.color : AppColors.text2, size: 36),
                  title: '${f['name']}',
                  subtitle: [if (f['dir'] != true) bytes(f['size']), ago(f['modified'])].where((x) => x.isNotEmpty).join(' · '),
                  trailing: Icon(f['dir'] == true ? Icons.chevron_right_rounded : Icons.visibility_outlined, color: AppColors.text3),
                  onTap: () {
                    final full = '${_path == '/' ? '' : _path}/${f['name']}';
                    if (f['dir'] == true) return _go(full);
                    showE2bFile(context, full, f);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shell commands in the sandbox, with their output kept above the prompt.
class _E2bTerminal extends ConsumerStatefulWidget {
  const _E2bTerminal();
  @override
  ConsumerState<_E2bTerminal> createState() => _E2bTerminalState();
}

class _E2bTerminalState extends ConsumerState<_E2bTerminal> with AutomaticKeepAliveClientMixin {
  final _input = TextEditingController();
  final _out = <(String, String, int?)>[];
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final cmd = _input.text.trim();
    if (cmd.isEmpty || _busy) return;
    if (ref.read(settingsProvider).readOnlyMode) return _toast(context, 'Read-only mode is on: nothing can be run.');
    setState(() => _busy = true);
    _input.clear();
    // Typed here by the person, so it runs without another question.
    final r = await ref.read(toolRunnerProvider).run('e2b_run_command', {'command': cmd});
    if (!mounted) return;
    final j = r.json;
    setState(() {
      _out.add((cmd, j['error'] != null ? '${j['error']}' : [if ('${j['stdout'] ?? ''}'.isNotEmpty) '${j['stdout']}'.trimRight(), if ('${j['stderr'] ?? ''}'.isNotEmpty) '${j['stderr']}'.trimRight()].join('\n'), (j['exit_code'] as num?)?.toInt()));
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 0),
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: const Color(0xFF0B0B0F), borderRadius: BorderRadius.circular(Radii.m)),
            child: _out.isEmpty && !_busy
                ? Text('Run shell commands in the sandbox, e.g. ls -la, pip install pandas, python -V.', style: codeTextStyle.copyWith(fontSize: 12, color: Colors.white54))
                : ListView(
                    reverse: true,
                    children: [
                      for (final (cmd, out, code) in [..._out.reversed])
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.s),
                          child: SelectableText.rich(
                            TextSpan(
                              style: codeTextStyle.copyWith(fontSize: 12, height: 1.4, color: const Color(0xFFD4D4D8)),
                              children: [
                                const TextSpan(text: r'$ ', style: TextStyle(color: Color(0xFF4ADE80))),
                                TextSpan(text: '$cmd\n', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                                TextSpan(text: out.isEmpty ? '' : '$out\n'),
                                if (code != null && code != 0) TextSpan(text: 'exit $code', style: const TextStyle(color: Color(0xFFFF6B6B))),
                              ],
                            ),
                          ),
                        ),
                    ].reversed.toList(),
                  ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
            child: TextField(
              controller: _input,
              autocorrect: false,
              enableSuggestions: false,
              style: codeTextStyle.copyWith(fontSize: 13.5),
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                isDense: true,
                prefixText: r'$ ',
                hintText: 'command',
                suffixIcon: IconButton(icon: const Icon(Icons.keyboard_return_rounded), onPressed: _run),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Vapi ------------------------------------------------------------------------------

Color _callColor(VapiCall c) => c.isLive
    ? AppColors.success
    : c.isScheduled
    ? AppColors.accent
    : ('${c.successEvaluation}' == 'true'
          ? AppColors.success
          : ('${c.successEvaluation}' == 'false' ? AppColors.danger : AppColors.text2));

class VapiManagerScreen extends ConsumerWidget {
  const VapiManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(aiProvider).vapi.client;
    return ManageScaffold(
      brand: DevBrand.parcels,
      title: 'Phone calls',
      colors: const [Color(0xFF14532D), Color(0xFF052E16)],
      actions: [
        IconButton(tooltip: 'Call settings', icon: const Icon(Icons.tune_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VapiSettingsScreen()))),
        IconButton(tooltip: 'Open the Vapi dashboard', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://dashboard.vapi.ai')),
      ],
      fab: _fab('New call', Icons.add_call, () => _newCall(context, ref)),
      hero: HeroLoader(
        load: (context, ref) async {
          await VapiStore.load();
          final calls = await _vapiCalls();
          return {'calls': calls};
        },
        builder: (context, d) {
          final calls = (d['calls'] as List).cast<VapiCall>();
          final cost = calls.fold<double>(0, (s, c) => s + (c.cost ?? 0));
          final judged = calls.where((c) => c.successEvaluation != null).toList();
          final ok = judged.where((c) => '${c.successEvaluation}' == 'true').length;
          return _hero(
            _head(Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white)),
                VapiStore.onBehalfOf.isEmpty ? 'Phone calls' : 'Calling for ${VapiStore.onBehalfOf}', 'Voice ${VapiStore.voice} · up to ${VapiStore.maxMinutes} min'),
            [
              HeroStat('${calls.length}', 'calls'),
              HeroStat(judged.isEmpty ? '–' : '${(ok * 100 / judged.length).round()}%', 'succeeded', color: const Color(0xFF86EFAC)),
              HeroStat('\$${cost.toStringAsFixed(2)}', 'spent'),
            ],
          );
        },
      ),
      tabs: [
        ManageTab(
          'Calls',
          Icons.call_rounded,
          (context) => ManagedList(
            load: (context, ref) async => [for (final c in await _vapiCalls()) {'_call': c, 'who': c.customerName ?? c.customerNumber ?? c.name ?? 'Call'}],
            searchHint: 'Search by name or number',
            matches: (m, q) => '${m['who']} ${(m['_call'] as VapiCall).summary ?? ''}'.toLowerCase().contains(q),
            empty: 'No calls yet. Tap New call, or ask the assistant to phone someone.',
            itemBuilder: (context, m, _) {
              final c = m['_call'] as VapiCall;
              final d = c.duration;
              return ManageTile(
                leading: TileIcon(c.isLive ? Icons.phone_in_talk_rounded : (c.isScheduled ? Icons.schedule_rounded : Icons.call_end_rounded), color: _callColor(c)),
                title: '${m['who']}',
                subtitle: [
                  if (c.summary != null) c.summary!.split('\n').first else (c.outcome ?? c.status),
                  [if (d != null) span(d), if (c.cost != null) '\$${c.cost!.toStringAsFixed(2)}', if (c.createdAt != null) ago(c.createdAt!.toIso8601String())].join(' · '),
                ].join('\n'),
                trailing: c.isLive ? Pill('live', color: AppColors.success, pulse: true) : null,
                onTap: () => _callSheet(context, c),
              );
            },
          ),
        ),
        ManageTab(
          'Numbers',
          Icons.dialpad_rounded,
          (context) => ManagedList(
            load: (context, ref) async {
              if (devCacheOnly) throw const DevNoCache();
              await VapiStore.load();
              return [for (final n in await client.listPhoneNumbers()) {'_n': n}];
            },
            empty: 'No numbers. Add one at dashboard.vapi.ai → Phone numbers.',
            itemBuilder: (context, m, reload) {
              final n = m['_n'] as VapiPhoneNumber;
              final chosen = VapiStore.phoneNumberId == n.id;
              return ManageTile(
                leading: TileIcon(Icons.dialpad_rounded, color: chosen ? AppColors.success : AppColors.text2),
                title: n.number ?? n.sipUri ?? n.id,
                subtitle: [if (n.name != null) n.name!, if (n.provider != null) n.provider!, if (n.status != null) n.status!].join(' · '),
                trailing: chosen
                    ? Pill('calls from here', color: AppColors.success)
                    : TextButton(
                        onPressed: () async {
                          final ai = ProviderScope.containerOf(context).read(aiProvider);
                          await VapiStore.save(phoneNumberId: n.id);
                          VapiStore.apply(ai);
                          reload();
                        },
                        child: const Text('Use'),
                      ),
              );
            },
          ),
        ),
        ManageTab(
          'Assistants',
          Icons.support_agent_rounded,
          (context) => ManagedList(
            load: (context, ref) async {
              if (devCacheOnly) throw const DevNoCache();
              return [for (final a in await client.listAssistants()) {'_a': a}];
            },
            empty: 'No saved assistants. The app makes a fresh agent for each call.',
            itemBuilder: (context, m, _) {
              final a = m['_a'] as VapiAssistant;
              return ManageTile(
                leading: TileIcon(Icons.support_agent_rounded, color: AppColors.accent),
                title: a.name ?? a.id,
                subtitle: [if (a.firstMessage != null) '“${a.firstMessage}”', if (a.createdAt != null) 'made ${ago(a.createdAt!.toIso8601String())}'].join('\n'),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Places a call through the same tool the assistant uses (it asks first).
  void _newCall(BuildContext context, WidgetRef ref) => _form(
    context,
    brand: DevBrand.parcels,
    title: 'New phone call',
    fields: const [('Number', '+251911234567', 1), ('Who', 'e.g. Bole Pharmacy', 1), ('What the agent should do', 'Ask if they have amoxicillin 500mg in stock and until when they are open', 4)],
    action: 'Call',
    onSubmit: (v) async {
      if (v[0].isEmpty || v[2].isEmpty) throw 'Give the number and what to do.';
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Call ${v[1].isEmpty ? v[0] : v[1]}?'),
          content: Text('An AI voice agent phones ${v[0]} and: ${v[2]}\n\nThis reaches a real person and costs money on your Vapi account.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Call')),
          ],
        ),
      );
      if (ok != true) return;
      final tools = await ref.read(aiProvider).vapi.tools();
      final tool = tools.firstWhere((t) => t.name == 'place_phone_call');
      final r = await tool.execute!({'to': v[0], if (v[1].isNotEmpty) 'to_name': v[1], 'goal': v[2]});
      final id = r is Map ? '${r['id'] ?? ''}' : '';
      if (id.isNotEmpty && context.mounted) unawaited(_vapiCall(id).then((c) => context.mounted ? _callSheet(context, c) : null));
    },
  );
}


// ---- Vapi calls, read safely --------------------------------------------------------------

/// GET [path] on Vapi with the saved key, as JSON.
Future<Object?> _vapiGet(String path, [Map<String, String>? query]) async {
  if (devCacheOnly) throw const DevNoCache();
  await VapiStore.load();
  if (!VapiStore.ready) throw 'Add a Vapi key in Settings → Phone calls.';
  final res = await http
      .get(Uri.parse('https://api.vapi.ai$path').replace(queryParameters: query), headers: {'Authorization': 'Bearer ${VapiStore.key.trim()}'})
      .timeout(const Duration(seconds: 30));
  final body = utf8.decode(res.bodyBytes, allowMalformed: true);
  Object? j;
  try {
    j = jsonDecode(body);
  } catch (_) {
    j = body;
  }
  if (res.statusCode >= 300) {
    throw 'Vapi: ${j is Map ? (j['message'] ?? j['error'] ?? res.statusCode) : 'HTTP ${res.statusCode}'}';
  }
  return j;
}

/// [j] with the parts the call parser expects to be objects made so:
/// a string where an object belongs (a recording given as a link, an
/// analysis given as text) is moved to where it can still be read.
Map<String, dynamic> vapiSafeCall(Map j) {
  final out = Map<String, dynamic>.from(j);
  Map<String, dynamic> obj(Map<String, dynamic> m, String key, void Function(Object v) keep) {
    final v = m[key];
    if (v is Map) return m[key] = Map<String, dynamic>.from(v);
    m.remove(key);
    if (v != null) keep(v);
    return <String, dynamic>{};
  }

  obj(out, 'customer', (v) => out['customer'] = {'number': '$v'});
  obj(out, 'monitor', (_) {});
  final analysis = obj(out, 'analysis', (v) => out['summary'] ??= '$v');
  if (analysis.isNotEmpty) out['analysis'] = analysis;
  final artifact = obj(out, 'artifact', (_) {});
  final recording = obj(artifact, 'recording', (v) => artifact['recordingUrl'] ??= '$v');
  obj(recording, 'mono', (v) => recording['combinedUrl'] ??= '$v');
  if (recording.isNotEmpty) artifact['recording'] = recording;
  if (artifact['messages'] is! List) artifact.remove('messages');
  if (out['messages'] is! List) out.remove('messages');
  out['artifact'] = artifact;
  if (out['cost'] is! num) out.remove('cost');
  return out;
}

Future<List<VapiCall>> _vapiCalls({int limit = 100}) async {
  final j = await _vapiGet('/call', {'limit': '$limit'});
  final list = j is List ? j : (j is Map ? (j['results'] ?? j['data']) : null);
  final out = <VapiCall>[];
  for (final c in (list is List ? list : const []).whereType<Map>()) {
    try {
      out.add(VapiCall.fromJson(vapiSafeCall(c)));
    } catch (_) {
      // One unreadable call doesn't hide the rest.
    }
  }
  return out;
}

Future<VapiCall> _vapiCall(String id) async {
  final j = await _vapiGet('/call/${Uri.encodeComponent(id)}');
  if (j is! Map) throw 'Vapi sent something unexpected for call $id.';
  return VapiCall.fromJson(vapiSafeCall(j));
}

/// A call in a sheet, following it live while it runs: status, summary,
/// the transcript, the recording, and Hang up or Say something.
Future<void> _callSheet(BuildContext context, VapiCall call) => showDevSheet(
  context,
  brand: DevBrand.parcels,
  title: call.customerName ?? call.customerNumber ?? call.name ?? 'Call',
  subtitle: call.customerNumber,
  builder: (context, scroll) => _CallSheet(call: call, scroll: scroll),
);

class _CallSheet extends ConsumerStatefulWidget {
  const _CallSheet({required this.call, required this.scroll});
  final VapiCall call;
  final ScrollController scroll;
  @override
  ConsumerState<_CallSheet> createState() => _CallSheetState();
}

class _CallSheetState extends ConsumerState<_CallSheet> {
  late VapiCall _c = widget.call;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final c = await _vapiCall(_c.id);
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    _timer?.cancel();
    // Live and just-ended calls change: the analysis lands a little after.
    if (mounted && (_c.isLive || _c.isScheduled || (_c.isEnded && !_c.hasAnalysis))) _timer = Timer(const Duration(seconds: 3), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final client = ref.read(aiProvider).vapi.client;
    final d = c.duration;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: _callColor(c).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.l)),
            child: Row(
              children: [
                Icon(c.isLive ? Icons.phone_in_talk_rounded : (c.isScheduled ? Icons.schedule_rounded : Icons.call_end_rounded), color: _callColor(c), size: 30),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.isLive ? 'On the call' : (c.outcome ?? c.status), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: _callColor(c))),
                      Text([if (d != null) span(d), if (c.cost != null) '\$${c.cost!.toStringAsFixed(2)}', if (c.createdAt != null) ago(c.createdAt!.toIso8601String())].join(' · '), style: context.text.bodySmall),
                    ],
                  ),
                ),
                if (c.isLive) Pill('live', color: AppColors.success, pulse: true),
              ],
            ),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0), child: Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger))),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              if (c.isLive) ...[
                ActionButton(
                  label: 'Hang up',
                  icon: Icons.call_end_rounded,
                  danger: true,
                  done: 'Ending the call',
                  onRun: () async {
                    await client.endCall(c);
                    await _refresh();
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                  label: const Text('Say something'),
                  onPressed: () => _form(
                    context,
                    brand: DevBrand.parcels,
                    title: 'The agent says',
                    fields: const [('Words', 'Sorry, one more question…', 2)],
                    action: 'Say it',
                    onSubmit: (v) => client.say(c, v[0]),
                  ),
                ),
              ],
              if (c.recordingUrl != null) FilledButton.icon(onPressed: () => openUrl(c.recordingUrl!), icon: const Icon(Icons.play_arrow_rounded, size: 18), label: const Text('Recording')),
              OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
            ],
          ),
        ),
        if (c.summary != null) ...[
          const SheetLabel('Summary'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: SelectableText(c.summary!, style: context.text.bodyMedium?.copyWith(height: 1.5))),
        ],
        if (c.structuredData != null) ...[
          const SheetLabel('What it found out'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: c.structuredData is Map || c.structuredData is List ? JsonTree(value: c.structuredData, openDepth: 2) : SelectableText('${c.structuredData}')),
        ],
        SheetLabel('Transcript · ${c.lines.length} lines'),
        if (c.lines.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: Text(c.transcript ?? (c.isLive ? 'Listening…' : 'No transcript.'), style: context.text.bodySmall))
        else
          for (final l in c.lines)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: Align(
                alignment: l.role == 'assistant' ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                  decoration: BoxDecoration(
                    color: l.role == 'assistant' ? AppColors.surface2 : AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(Radii.l),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.role == 'assistant' ? 'Agent' : (c.customerName ?? 'Them'), style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                      SelectableText(l.text, style: context.text.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
        const SheetLabel('Details'),
        SheetGroup(
          children: [
            CopyRow(label: 'Call ID', value: c.id),
            if (c.customerNumber != null) CopyRow(label: 'Number', value: c.customerNumber!),
            CopyRow(label: 'Status', value: c.status, mono: false),
            if (c.endedReason != null) CopyRow(label: 'Ended', value: c.endedReason!, mono: false),
            if (c.successEvaluation != null) CopyRow(label: 'Success', value: c.successEvaluation!, mono: false),
          ],
        ),
      ],
    );
  }
}

// ---- E2B file viewer ---------------------------------------------------------------------

const _textExt = {
  'txt', 'md', 'py', 'js', 'ts', 'json', 'csv', 'tsv', 'html', 'css', 'sh', 'r', 'java', 'dart', 'yaml', 'yml', 'toml', 'xml', 'log',
  'ini', 'cfg', 'sql', 'c', 'cpp', 'h', 'go', 'rs', 'rb', 'php', 'kt', 'swift', 'env', 'ipynb', 'jsx', 'tsx', 'svg',
};
const _imageExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

String _ext(String path) => path.contains('.') ? path.split('.').last.toLowerCase() : '';

/// The editor's and highlighter's name for a file's language.
String _lang(String ext) => switch (ext) {
  'py' || 'ipynb' => 'python',
  'js' || 'jsx' || 'ts' || 'tsx' => 'javascript',
  'sh' || 'env' => 'bash',
  'r' => 'r',
  'java' || 'kt' => 'java',
  'html' || 'svg' || 'xml' => 'html',
  _ => ext,
};

/// A sandbox file in a sheet: text and code highlighted with line numbers
/// (copy it, open it in the editor), images shown, anything else
/// described; and Download to keep it.
void showE2bFile(BuildContext context, String path, Map<String, dynamic> f) => showDevSheet(
  context,
  brand: DevBrand.e2b,
  title: '${f['name']}',
  subtitle: [path, if (f['size'] != null) bytes(f['size'])].join(' · '),
  builder: (context, scroll) => _FileView(path: path, scroll: scroll),
);

class _FileView extends ConsumerStatefulWidget {
  const _FileView({required this.path, required this.scroll});
  final String path;
  final ScrollController scroll;
  @override
  ConsumerState<_FileView> createState() => _FileViewState();
}

class _FileViewState extends ConsumerState<_FileView> {
  Uint8List? _bytes;
  String? _text;
  String? _error;
  bool _wrap = false;
  static const _max = 2 << 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await ref.read(e2bSessionProvider).withSandbox((c, box) => c.readFile(box, widget.path, maxBytes: _max));
      String? text;
      final ext = _ext(widget.path);
      if (!_imageExt.contains(ext) && (_textExt.contains(ext) || !b.take(4000).contains(0))) {
        try {
          text = utf8.decode(b);
        } catch (_) {
          text = _textExt.contains(ext) ? utf8.decode(b, allowMalformed: true) : null;
        }
      }
      if (mounted) {
        setState(() {
          _bytes = b;
          _text = text;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _download() async {
    final b = _bytes;
    if (b == null) return;
    final file = await saveGeneratedBytes(widget.path.split('/').last, b, folder: 'downloads');
    await OpenFilex.open(file.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(Space.l), child: Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)));
    }
    final b = _bytes;
    if (b == null) return const SkeletonPage();
    final ext = _ext(widget.path);
    final text = _text;
    final lines = text?.split('\n') ?? const <String>[];
    final theme = ref.watch(settingsProvider.select((s) => s.codeTheme));
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (text != null) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    showSnack(context, 'Copied');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
                if (const {'py', 'js', 'ts', 'sh', 'r', 'java', 'ipynb'}.contains(ext))
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CodeEditorScreen(code: text, language: _lang(ext)))),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Open in editor'),
                  ),
                IconButton(tooltip: _wrap ? 'No wrapping' : 'Wrap lines', onPressed: () => setState(() => _wrap = !_wrap), icon: Icon(_wrap ? Icons.wrap_text_rounded : Icons.notes_rounded)),
              ],
              FilledButton.icon(onPressed: _download, icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Download')),
            ],
          ),
        ),
        if (_imageExt.contains(ext))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: ClipRRect(borderRadius: BorderRadius.circular(Radii.m), child: Container(color: Colors.white, child: Image.memory(b, fit: BoxFit.contain))),
          )
        else if (text != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: Space.l),
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
            child: _codeView(text, lines.length, ext, theme),
          )
        else
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 44, color: AppColors.text3),
                const SizedBox(height: Space.s),
                Text('${bytes(b.length)} of binary data. Download it to open it with another app.', textAlign: TextAlign.center, style: context.text.bodySmall),
              ],
            ),
          ),
        if (text != null && b.length >= _max) Padding(padding: const EdgeInsets.all(Space.l), child: Text('Showing the first 2 MB.', style: context.text.labelSmall)),
      ],
    );
  }

  Widget _codeView(String text, int count, String ext, CodeThemeChoice theme) {
    final numbers = Text(
      [for (var i = 1; i <= count; i++) '$i'].join('\n'),
      textAlign: TextAlign.right,
      style: codeTextStyle.copyWith(fontSize: 12.5, height: 1.45, color: AppColors.text3),
    );
    final Widget code = text.length > 200000
        ? SelectableText(text, style: codeTextStyle.copyWith(fontSize: 12.5, height: 1.45))
        : HighlightedCode(code: text, language: _lang(ext), theme: theme);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_wrap) ...[numbers, const SizedBox(width: Space.m)],
        Expanded(child: _wrap ? code : SingleChildScrollView(scrollDirection: Axis.horizontal, child: code)),
      ],
    );
  }
}
