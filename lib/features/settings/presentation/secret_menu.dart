import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../account/storage_screen.dart';
import '../../ai/data/ai.dart';
import '../../assistant/notifications.dart';
import '../../assistant/presentation/watches_screen.dart';
import '../../assistant/watch_engine.dart';
import '../../assistant/watches.dart';
import '../../auth/data/auth_controller.dart';
import '../../chat/data/chat_controller.dart';
import '../../usage/usage.dart';
import '../data/settings.dart';
import 'model_picker_screen.dart';

const _repo = 'https://github.com/dagmawibabi/teleai';

/// The hidden menu behind a long press on the logo at the foot of Settings:
/// a few stats, some toys, hidden tips and the tools for a bug report.
Future<void> showSecretMenu(BuildContext context, {required void Function(Widget page) open}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => _SecretMenu(
        open: (page) {
          Navigator.of(sheet).pop();
          open(page);
        },
      ),
    );

/// Things the app does that nothing on screen mentions.
const _tips = [
  'Type /tool in the chat to run any tool yourself, no AI involved.',
  'Double-tap the jump-to-bottom arrow to move it to the right edge.',
  'Long-press the jump-to-bottom arrow to hide it for the rest of the chat.',
  'Long-press the mic to record a voice note instead of dictating.',
  'Long-press a model in the picker to see everything known about it.',
  'Tap a chat\'s name at the top of the chat to rename it.',
  'Share selected text from any app to Triangle and it opens Ask Triangle.',
  'Set Triangle as your phone\'s assistant and a long-press on home calls it up.',
  'You found this menu by long-pressing a triangle. There may be more triangles.',
];

class _SecretMenu extends ConsumerStatefulWidget {
  const _SecretMenu({required this.open});
  final void Function(Widget page) open;

  @override
  ConsumerState<_SecretMenu> createState() => _SecretMenuState();
}

class _SecretMenuState extends ConsumerState<_SecretMenu> {
  final _random = Random();
  int _taps = 0;
  double _turns = 0;
  late int _tip = _random.nextInt(_tips.length);
  String? _tdlib;

  void _buzz() {
    if (ref.read(settingsProvider).haptics) HapticFeedback.lightImpact();
  }

  /// Every tap spins the logo a third of a turn; the seventh flips the
  /// rainbow logo.
  void _tapLogo() {
    setState(() {
      _taps++;
      _turns += 1 / 3;
    });
    _buzz();
    if (_taps % 7 != 0) return;
    HapticFeedback.heavyImpact();
    final on = !ref.read(settingsProvider).rainbowLogo;
    ref.read(settingsProvider.notifier).setRainbowLogo(on);
    showSnack(
      context,
      on ? 'Rainbow mode unlocked' : 'Back to monochrome',
      icon: Icons.auto_awesome_rounded,
    );
  }

  void _nextTip() {
    setState(() {
      var next = _tip;
      while (_tips.length > 1 && next == _tip) {
        next = _random.nextInt(_tips.length);
      }
      _tip = next;
    });
    _buzz();
  }

  Future<void> _surpriseAccent() async {
    final current = ref.read(settingsProvider).accent;
    final others = AccentChoice.values.where((a) => a != current).toList();
    final pick = others[_random.nextInt(others.length)];
    await ref.read(settingsProvider.notifier).setAccent(pick);
    _buzz();
    if (mounted) showSnack(context, 'Accent: ${pick.label}', icon: Icons.palette_outlined);
  }

  Future<void> _checkTdlib() async {
    final watch = Stopwatch()..start();
    try {
      final r = await ref
          .read(telegramClientProvider)
          .send<td.TdObject>(const td.GetOption(name: 'version'));
      watch.stop();
      final version = r is td.OptionValueString ? r.value : '?';
      setState(() => _tdlib = 'TDLib $version · ${watch.elapsedMilliseconds} ms');
      if (mounted) showSnack(context, 'TDLib $version answered in ${watch.elapsedMilliseconds} ms');
    } catch (e) {
      if (mounted) showSnack(context, 'TDLib check failed: $e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _resetNetworkCounters() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset TDLib network counters?'),
        content: const Text(
          'This only resets the data-use totals shown on this phone. It does not delete chats, media, or your Telegram account.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(telegramClientProvider).send<td.Ok>(const td.ResetNetworkStatistics());
      if (mounted) showSnack(context, 'TDLib network counters reset');
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t reset counters: $e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _testNotification() async {
    try {
      await ref.read(appNotifierProvider).show(
        'Triangle',
        'Notifications work. This one was a test from the secret menu.',
      );
      if (mounted) showSnack(context, 'Test notification sent');
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t notify: $e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _refreshModels() async {
    showSnack(context, 'Refreshing the model lists…', icon: Icons.refresh_rounded);
    await ref.read(modelCatalogProvider.notifier).refresh();
    if (!mounted) return;
    final cat = ref.read(modelCatalogProvider);
    showSnack(
      context,
      cat.error == null ? '${cat.models.length} models listed' : 'Couldn\'t refresh: ${cat.error}',
      icon: cat.error == null ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
    );
  }

  /// What a bug report needs, with no keys, chats or names in it.
  Future<void> _copyDebugInfo() async {
    final s = ref.read(settingsProvider);
    final cat = ref.read(modelCatalogProvider);
    final status = ref.read(watchEngineProvider).status.value;
    final keyed = [for (final r in AiRouter.values) if (hasKeyFor(s, r)) r.short];
    final info = [
      '${AppConfig.appName} ${AppConfig.version}',
      'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Dart: ${Platform.version.split(' ').first}',
      'Telegram connected: ${ref.read(telegramConnectedProvider)}',
      ?_tdlib,
      'Chat model: ${s.model}',
      'AI services with keys: ${keyed.isEmpty ? 'none' : keyed.join(', ')}',
      'Models listed: ${cat.models.length}${cat.fetchedAt == null ? '' : ' (fetched ${cat.fetchedAt!.toLocal()})'}',
      if (cat.providerErrors.isNotEmpty)
        'Model list errors: ${cat.providerErrors.entries.map((e) => '${e.key}: ${e.value}').join('; ')}',
      'Watches on: ${ref.read(watchStoreProvider).where((w) => w.enabled).length}',
      'Watcher: ${status.listening ? 'listening' : 'starting'}, background ${status.background ? 'running' : 'off'}',
      if (status.error != null) 'Watcher error: ${status.error}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: info));
    if (mounted) showSnack(context, 'Debug info copied', icon: Icons.content_copy_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final telegram = ref.watch(telegramConnectedProvider);
    final history = ref.watch(chatControllerProvider.select((c) => c.history));
    final usage = ref.watch(usageProvider);

    // By the numbers.
    final ai = usage.where((e) => e.tool == null).toList();
    final tokens = ai.fold<int>(0, (n, e) => n + e.tokens);
    final spent = usage.fold<double>(0, (n, e) => n + e.cost);
    final byModel = <String, int>{};
    for (final e in ai) {
      byModel[e.model] = (byModel[e.model] ?? 0) + 1;
    }
    final favourite = byModel.isEmpty
        ? null
        : (byModel.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final firstSeen = [
      ...history.map((h) => h.updatedAt),
      ...usage.map((e) => e.at),
    ].fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final days = firstSeen == null ? 0 : DateTime.now().difference(firstSeen).inDays;

    Widget card(List<Widget> children) => Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.l),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const Divider(indent: 56),
              c,
            ],
          ],
        ),
      ),
    );

    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, Space.xs, Space.xs),
      child: Text(text, style: context.text.labelSmall),
    );

    Widget action(IconData icon, String title, String subtitle, VoidCallback onTap, {IconData trailing = Icons.chevron_right_rounded}) =>
        ListTile(
          leading: lead(Icon(icon)),
          title: Text(title),
          subtitle: Text(subtitle, style: context.text.bodySmall),
          trailing: Icon(trailing, size: 20, color: AppColors.text3),
          onTap: onTap,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _tapLogo,
                child: AnimatedRotation(
                  turns: _turns,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutBack,
                  child: s.rainbowLogo ? const RainbowBrandMark(size: 42) : const BrandMark(size: 42),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Triangle', style: context.text.titleLarge),
                    Text(
                      'Version ${AppConfig.version} · you found the secret menu',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),

          label('BY THE NUMBERS'),
          Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(Radii.l),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Stat('${history.length}', history.length == 1 ? 'chat' : 'chats'),
                    _Stat('${ai.length}', 'AI calls'),
                    _Stat(ModelInfo.tokens(tokens), 'tokens'),
                    _Stat(spent == 0 ? '\$0' : ModelInfo.usd(spent), 'spent'),
                  ],
                ),
                if (favourite != null || firstSeen != null) ...[
                  const SizedBox(height: Space.m),
                  if (favourite != null)
                    _RuntimeRow('Favourite model', modelLabel(favourite).split('/').last, AppColors.accent),
                  if (firstSeen != null)
                    _RuntimeRow(
                      'Together since',
                      '${MaterialLocalizations.of(context).formatMediumDate(firstSeen)} · $days day${days == 1 ? '' : 's'}',
                      AppColors.text2,
                    ),
                ],
              ],
            ),
          ),

          label('JUST FOR FUN'),
          card([
            SwitchListTile(
              secondary: s.rainbowLogo ? const RainbowBrandMark(size: 26) : const BrandMark(size: 26),
              title: const Text('Rainbow logo'),
              subtitle: Text('The mark and voice mode cycle through colours', style: context.text.bodySmall),
              value: s.rainbowLogo,
              onChanged: ref.read(settingsProvider.notifier).setRainbowLogo,
            ),
            action(
              Icons.casino_outlined,
              'Surprise accent',
              'Now ${s.accent.label}. Roll for another colour',
              _surpriseAccent,
              trailing: Icons.shuffle_rounded,
            ),
          ]),

          label('HIDDEN TIP'),
          Material(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(Radii.l),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.l),
              onTap: _nextTip,
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 20, color: AppColors.accent),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _tips[_tip],
                          key: ValueKey(_tip),
                          style: context.text.bodyMedium,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    Text('next', style: context.text.labelSmall?.copyWith(color: AppColors.accent)),
                  ],
                ),
              ),
            ),
          ),

          label('DEVELOPER'),
          card([
            action(
              Icons.content_copy_rounded,
              'Copy debug info',
              'Version, OS, model and service status for a bug report. No keys or chats',
              _copyDebugInfo,
              trailing: Icons.copy_rounded,
            ),
            action(
              Icons.notifications_active_outlined,
              'Send a test notification',
              'Checks that Triangle can reach you',
              _testNotification,
              trailing: Icons.play_arrow_rounded,
            ),
            action(
              Icons.refresh_rounded,
              'Refresh model lists',
              'Fetch every AI service\'s models again',
              _refreshModels,
              trailing: Icons.play_arrow_rounded,
            ),
            action(
              Icons.bug_report_outlined,
              'Report an issue',
              'Open the project\'s issue tracker',
              () => launchUrl(Uri.parse('$_repo/issues'), mode: LaunchMode.externalApplication),
              trailing: Icons.open_in_new_rounded,
            ),
          ]),

          if (telegram) ...[
            label('TDLIB'),
            card([
              action(
                Icons.health_and_safety_outlined,
                'Run TDLib health check',
                _tdlib ?? 'Checks the Telegram client is responding, and how fast',
                _checkTdlib,
                trailing: Icons.play_arrow_rounded,
              ),
              action(
                Icons.restart_alt_rounded,
                'Reset TDLib network counters',
                'Starts local data-use totals from zero',
                _resetNetworkCounters,
              ),
            ]),
          ],

          label('RUNTIME & LOGS'),
          ValueListenableBuilder<WatchStatus>(
            valueListenable: ref.read(watchEngineProvider).status,
            builder: (_, status, _) => Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.l),
              ),
              child: Column(
                children: [
                  _RuntimeRow(
                    'Watcher engine',
                    status.listening ? 'Listening' : 'Starting',
                    status.listening ? AppColors.success : AppColors.warning,
                  ),
                  _RuntimeRow(
                    'Background service',
                    status.background ? 'Running' : 'Not running',
                    status.background ? AppColors.success : AppColors.text3,
                  ),
                  _RuntimeRow('Messages heard', '${status.heard} · ${status.matched} matched', AppColors.text2),
                  _RuntimeRow('Open watched chats', '${status.opened}', AppColors.text2),
                  if (status.last != null) _RuntimeRow('Last activity', status.last!, AppColors.text2),
                  if (status.error != null) _RuntimeRow('Latest error', status.error!, AppColors.danger),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: lead(const Icon(Icons.monitor_heart_outlined)),
                    title: const Text('Open watcher diagnostics'),
                    subtitle: const Text('Live status, matches and background readiness'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => widget.open(const WatchesScreen()),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: lead(const Icon(Icons.storage_outlined)),
                    title: Text(telegram ? 'Storage and TDLib logs' : 'Storage'),
                    subtitle: Text(
                      telegram ? 'Inspect cache, local files and Telegram log size' : 'Inspect cache and local files',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => widget.open(const StorageScreen()),
                  ),
                ],
              ),
            ),
          ),

          label('PROJECT'),
          card([
            action(
              Icons.info_outline_rounded,
              'About Triangle',
              'Triangle ${AppConfig.version} · Flutter and TDLib',
              () => showAboutDialog(
                context: context,
                applicationName: 'Triangle',
                applicationVersion: AppConfig.version,
                applicationIcon: const BrandMark(size: 40),
                applicationLegalese: 'An independent assistant for Telegram, your phone and the web.',
                children: const [
                  SizedBox(height: Space.m),
                  Text('Built to keep AI actions visible, reviewable and under your control.'),
                ],
              ),
            ),
            action(
              Icons.code_rounded,
              'Triangle on GitHub',
              _repo.replaceFirst('https://', ''),
              () => launchUrl(Uri.parse(_repo), mode: LaunchMode.externalApplication),
              trailing: Icons.open_in_new_rounded,
            ),
          ]),
        ],
      ),
    );
  }
}

/// One figure in the By the numbers row.
class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: context.text.titleLarge?.copyWith(fontFeatures: tabularFigures),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: context.text.labelSmall),
      ],
    ),
  );
}

/// One compact, readable line of status. It shows status rather than raw
/// logs: the linked screens hold the deeper diagnostics.
class _RuntimeRow extends StatelessWidget {
  const _RuntimeRow(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.s),
        SizedBox(width: 128, child: Text(label, style: context.text.bodySmall)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}
