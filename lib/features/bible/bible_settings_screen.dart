import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import 'bible.dart';

/// Settings → More apps → Bible, on a page of its own.
class BibleSettingsScreen extends StatelessWidget {
  const BibleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Bible')), body: const BibleSettingsView());
}

/// The YouVersion app key, the version the assistant reads from, and the
/// language versions are listed in.
class BibleSettingsView extends ConsumerStatefulWidget {
  const BibleSettingsView({super.key});

  @override
  ConsumerState<BibleSettingsView> createState() => _BibleSettingsViewState();
}

class _BibleSettingsViewState extends ConsumerState<BibleSettingsView> {
  List<BibleVersion>? _versions;
  bool _everything = false;
  String? _error;
  bool _loading = false;
  String _q = '';

  Future<void> _loadVersions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final v = await ref.read(bibleServiceProvider).versions(everything: _everything);
      if (mounted) setState(() => _versions = v);
    } catch (e) {
      if (mounted) setState(() => _error = BibleService.explain(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editToken() async {
    final s = ref.read(bibleSettingsProvider);
    final text = TextEditingController(text: s.token);
    final saved = await showFormSheet<bool>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('YouVersion app key', style: context.text.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Sign in at platform.youversion.com, register an app and copy its App Key. It is kept encrypted on this phone.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.m),
          TextField(controller: text, autofocus: true, obscureText: true, decoration: const InputDecoration(labelText: 'Token')),
          const SizedBox(height: Space.m),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://platform.youversion.com'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Get a token'),
              ),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
    if (saved == true) {
      await ref.read(bibleSettingsProvider.notifier).setToken(text.text);
      if (ref.read(bibleSettingsProvider).hasToken) await _loadVersions();
    }
  }

  @override
  void initState() {
    super.initState();
    ref.read(bibleSettingsProvider.notifier).ready.then((_) {
      if (mounted && ref.read(bibleSettingsProvider).hasToken) _loadVersions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(bibleSettingsProvider);
    final shown = (_versions ?? const <BibleVersion>[])
        .where((b) => _q.isEmpty || '${b.abbreviation} ${b.short} ${b.title} ${b.name}'.toLowerCase().contains(_q))
        .toList();
    Widget card(List<Widget> children) => Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: Column(children: children)),
    );
    return ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Text(
            'The assistant reads the Bible from YouVersion: verses and passages, whole chapters you can page through, '
            'translations side by side, verse search and the verse of the day. Ask "read Psalm 23" or "compare John 1:1 '
            'in KJV and NIV". Each version must be licensed to your YouVersion app; accept a publisher\'s license '
            '(NIV, NLT…) on platform.youversion.com to read it here.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.l),
          card([
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: lead(Icon(s.hasToken ? Icons.key_rounded : Icons.key_off_outlined, color: s.hasToken ? AppColors.success : AppColors.warning)),
              title: const Text('App key'),
              subtitle: Text(s.hasToken ? 'Saved' : 'Needed: free from platform.youversion.com', style: context.text.bodySmall),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _editToken,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: lead(const Icon(Icons.translate_rounded)),
              title: const Text('Language'),
              subtitle: Text('Versions listed in "${s.language}"', style: context.text.bodySmall),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final picked = await showFormSheet<String>(
                  context,
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Language', style: context.text.titleMedium),
                      const SizedBox(height: Space.m),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (code, name) in const [
                            ('en', 'English'),
                            ('am', 'Amharic'),
                            ('om', 'Afaan Oromo'),
                            ('ti', 'Tigrinya'),
                            ('es', 'Spanish'),
                            ('fr', 'French'),
                            ('de', 'German'),
                            ('pt', 'Portuguese'),
                            ('ar', 'Arabic'),
                            ('sw', 'Swahili'),
                            ('*', 'All'),
                          ])
                            ChoiceChip(
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                              label: Text(name),
                              selected: s.language == code,
                              onSelected: (_) => Navigator.pop(context, code),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
                if (picked != null) {
                  await ref.read(bibleSettingsProvider.notifier).setLanguage(picked);
                  if (s.hasToken) await _loadVersions();
                }
              },
            ),
          ]),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(child: Text('DEFAULT VERSION', style: context.text.labelSmall)),
              if (s.versionId != null)
                TextButton(onPressed: () => ref.read(bibleSettingsProvider.notifier).setVersion(null, ''), child: const Text('Clear')),
            ],
          ),
          Text(
            s.versionId == null ? 'None: the first version in your language is used.' : 'Using ${s.versionLabel} (id ${s.versionId}).',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.s),
          if (!s.hasToken)
            Text('Add the token to choose a version.', style: context.text.bodySmall?.copyWith(color: AppColors.text3))
          else if (_loading)
            const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: TextStyle(color: AppColors.danger))
          else if (_versions != null) ...[
            TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(isDense: true, hintText: 'Search versions, e.g. NIV', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Also show versions I can\'t read yet'),
              subtitle: Text(
                'Every version on YouVersion. Ones not licensed to your app are greyed out until you accept their license on platform.youversion.com.',
                style: context.text.bodySmall,
              ),
              value: _everything,
              onChanged: (v) {
                setState(() => _everything = v);
                _loadVersions();
              },
            ),
            Text(
              '${shown.where((b) => b.licensed).length} readable${_everything ? ' · ${shown.where((b) => !b.licensed).length} need a license' : ''}',
              style: context.text.labelSmall,
            ),
            const SizedBox(height: Space.s),
            card([
              for (final (i, b) in shown.take(80).indexed) ...[
                if (i > 0) const Divider(height: 1, indent: Space.l),
                RadioListTile<int>(
                  value: b.id,
                  groupValue: s.versionId,
                  onChanged: b.licensed ? (_) => ref.read(bibleSettingsProvider.notifier).setVersion(b.id, b.short) : null,
                  title: Text('${b.short} · ${b.name}'),
                  subtitle: Text(
                    [
                      '${b.books.length} books',
                      b.languageTag,
                      if (b.publisherName != null) b.publisherName!,
                      if (!b.licensed) 'needs its license accepted',
                    ].join(' · '),
                    style: context.text.bodySmall?.copyWith(color: b.licensed ? null : AppColors.warning),
                  ),
                ),
              ],
              if (shown.isEmpty) Padding(padding: const EdgeInsets.all(Space.l), child: Text('No versions match.', style: context.text.bodySmall)),
            ]),
          ],
        ],
    );
  }
}
