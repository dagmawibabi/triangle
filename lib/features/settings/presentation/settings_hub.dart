import '../../assistant/presentation/watches_screen.dart';
import '../../assistant/activity_log.dart';
import '../../assistant/presentation/activity_log_screen.dart';
import '../../assistant/presentation/default_assistant_screen.dart';
import '../../routines/routines.dart';
import '../../routines/routines_screen.dart';
import '../../vault/vault.dart';
import '../../vault/vault_screen.dart';
import 'more_apps_screen.dart';
import '../../finance/finance_screen.dart';
import '../../calls/call_history_screen.dart';
import '../../usage/spend_limits.dart';
import '../../usage/spend_limits_screen.dart';
import '../../lock/app_lock.dart';
import '../../lock/app_lock_settings.dart';
import '../../brief/brief_prefs.dart';
import '../../brief/brief_screen.dart';
import '../../brief/brief_settings_screen.dart';
import '../../brief/brief_widget.dart';
import '../../brief/widget_customizer_screen.dart';
import '../../telegram/presentation/scheduled_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../ai/data/ai.dart';
import '../../integrations/integrations_store.dart';
import '../../assistant/watch_engine.dart';
import '../../assistant/watches.dart';
import '../../auth/data/auth_controller.dart';
import '../../auth/presentation/welcome_screen.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/presentation/chat_profile_screen.dart';
import '../../telegram/presentation/tg_avatar.dart';
import '../../usage/usage.dart';
import '../../usage/usage_screen.dart';
import '../data/settings.dart';
import 'settings_screen.dart';
import 'capability_settings.dart';
import 'tools_screen.dart';
import 'system_check_screen.dart';
import 'approvals_screen.dart';
import 'data_screen.dart';
import 'permissions_screen.dart';
import 'watch_timing_screen.dart';
import '../../account/security_screen.dart';
import '../../account/storage_screen.dart';
import '../../telegram/data/content_filters.dart';
import '../../telegram/presentation/block_mute_screen.dart';
import '../../telegram/presentation/folders_screen.dart';
import '../../screen/screen_control_screen.dart';
import '../../device/device.dart';

/// Settings at a glance: who's signed in, then a few groups that each open
/// a page of their own.
class SettingsHub extends ConsumerWidget {
  const SettingsHub({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// A small, deliberately hidden home for project details and the less
  /// essential personality switches. Keeping it behind the footer mark makes
  /// the main settings page useful at a glance without losing the nice bits.
  Future<void> _showAboutSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => Consumer(
        builder: (sheetContext, sheetRef, _) {
          void open(Widget page) {
            Navigator.of(sheetContext).pop();
            _open(context, page);
          }

          Future<void> resetNetworkCounters() async {
            final ok = await showDialog<bool>(
              context: sheetContext,
              builder: (dialog) => AlertDialog(
                title: const Text('Reset TDLib network counters?'),
                content: const Text(
                  'This only resets the data-use totals shown on this phone. It does not delete chats, media, or your Telegram account.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            );
            if (ok != true) return;
            try {
              await sheetRef
                  .read(telegramClientProvider)
                  .send<td.Ok>(const td.ResetNetworkStatistics());
              if (sheetContext.mounted)
                showSnack(sheetContext, 'TDLib network counters reset');
            } catch (e) {
              if (sheetContext.mounted)
                showSnack(sheetContext, 'Couldn\'t reset counters: $e');
            }
          }

          Future<void> checkTdlib() async {
            try {
              await sheetRef
                  .read(telegramClientProvider)
                  .send<td.TdObject>(const td.GetOption(name: 'version'));
              if (sheetContext.mounted)
                showSnack(sheetContext, 'TDLib is responding');
            } catch (e) {
              if (sheetContext.mounted)
                showSnack(sheetContext, 'TDLib check failed: $e');
            }
          }

          return Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 42),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Triangle', style: context.text.titleLarge),
                            Text(
                              'Version ${AppConfig.version} · Telegram, with an assistant',
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.l),
                  Text('JUST FOR FUN', style: context.text.labelSmall),
                  const SizedBox(height: Space.xs),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(Radii.l),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: sheetRef.watch(settingsProvider).rainbowLogo
                              ? const RainbowBrandMark(size: 26)
                              : const BrandMark(size: 26),
                          title: const Text('Rainbow logo'),
                          subtitle: Text('The mark and voice mode cycle through colours', style: context.text.bodySmall),
                          value: sheetRef.watch(settingsProvider).rainbowLogo,
                          onChanged: sheetRef.read(settingsProvider.notifier).setRainbowLogo,
                        ),
                        const Divider(indent: 56),
                        SwitchListTile(
                          secondary: lead(const Icon(Icons.vibration_rounded)),
                          title: const Text('Haptic taps'),
                          subtitle: Text('A light buzz when you send or approve', style: context.text.bodySmall),
                          value: sheetRef.watch(settingsProvider).haptics,
                          onChanged: (v) {
                            if (v) HapticFeedback.mediumImpact();
                            sheetRef.read(settingsProvider.notifier).setHaptics(v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  Text('PROJECT', style: context.text.labelSmall),
                  const SizedBox(height: Space.xs),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(Radii.l),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: lead(const Icon(Icons.info_outline_rounded)),
                          title: const Text('Project details'),
                          subtitle: Text(
                            'Triangle ${AppConfig.version} · Flutter and TDLib',
                            style: context.text.bodySmall,
                          ),
                          onTap: () => showAboutDialog(
                            context: sheetContext,
                            applicationName: 'Triangle',
                            applicationVersion: AppConfig.version,
                            applicationLegalese:
                                'An independent Telegram assistant client.',
                            children: const [
                              Text(
                                'Built to keep AI actions visible, reviewable and under your control.',
                              ),
                            ],
                          ),
                        ),
                        const Divider(indent: 56),
                        ListTile(
                          leading: lead(const Icon(Icons.code_rounded)),
                          title: const Text('Triangle on GitHub'),
                          subtitle: Text(
                            'github.com/dagmawibabi/triangle',
                            style: context.text.bodySmall,
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse('https://github.com/dagmawibabi/triangle'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        const Divider(indent: 56),
                        ListTile(
                          leading: lead(const Icon(Icons.bug_report_outlined)),
                          title: const Text('Report an issue'),
                          subtitle: Text(
                            'Open the project issue tracker',
                            style: context.text.bodySmall,
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://github.com/dagmawibabi/triangle/issues',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  Text('TDLIB CONTROLS', style: context.text.labelSmall),
                  const SizedBox(height: Space.xs),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(Radii.l),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: lead(const Icon(Icons.health_and_safety_outlined)),
                          title: const Text('Run TDLib health check'),
                          subtitle: Text(
                            'Checks whether the Telegram client is responding',
                            style: context.text.bodySmall,
                          ),
                          trailing: const Icon(Icons.play_arrow_rounded),
                          onTap: checkTdlib,
                        ),
                        const Divider(indent: 56),
                        ListTile(
                          leading: lead(const Icon(Icons.restart_alt_rounded)),
                          title: const Text('Reset TDLib network counters'),
                          subtitle: Text(
                            'Starts local data-use totals from zero',
                            style: context.text.bodySmall,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: resetNetworkCounters,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  Text('RUNTIME & LOGS', style: context.text.labelSmall),
                  const SizedBox(height: Space.xs),
                  ValueListenableBuilder<WatchStatus>(
                    valueListenable: sheetRef.read(watchEngineProvider).status,
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
                            status.listening
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                          _RuntimeRow(
                            'Background service',
                            status.background ? 'Running' : 'Not running',
                            status.background
                                ? AppColors.success
                                : AppColors.text3,
                          ),
                          _RuntimeRow(
                            'Messages heard',
                            '${status.heard} · ${status.matched} matched',
                            AppColors.text2,
                          ),
                          _RuntimeRow(
                            'Open watched chats',
                            '${status.opened}',
                            AppColors.text2,
                          ),
                          if (status.last != null)
                            _RuntimeRow(
                              'Last activity',
                              status.last!,
                              AppColors.text2,
                            ),
                          if (status.error != null)
                            _RuntimeRow(
                              'Latest error',
                              status.error!,
                              AppColors.danger,
                            ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: lead(const Icon(Icons.monitor_heart_outlined)),
                            title: const Text('Open watcher diagnostics'),
                            subtitle: const Text(
                              'Live status, matches and background readiness',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => open(const WatchesScreen()),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: lead(const Icon(Icons.storage_outlined)),
                            title: const Text('Storage and TDLib logs'),
                            subtitle: const Text(
                              'Inspect cache, local files and Telegram log size',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => open(const StorageScreen()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This ends Triangle\'s session for the Telegram account on screen; your other accounts stay signed in. '
          'Signing out of your only account also removes your conversations from this device. '
          'Nothing in your Telegram account is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final store = ref.watch(telegramStoreProvider);
    final cat = ref.watch(modelCatalogProvider);
    final watches = ref
        .watch(watchStoreProvider)
        .where((w) => w.enabled)
        .length;
    final usage = ref.watch(usageProvider);
    final today = DateTime.now();
    final spentToday = usage
        .where(
          (e) => e.at.isAfter(DateTime(today.year, today.month, today.day)),
        )
        .fold<double>(0, (n, e) => n + e.cost);
    final allTools = [for (final g in ToolGroup.values) ...toolsIn(g)];
    final toolsOn = allTools.where((t) => t.isOn(s)).length;
    final services = [s.hasComposioKey, s.hasExaKey, s.hasCloudflare, s.hasE2bKey].where((x) => x).length;
    final connectedApps = ref.watch(integrationsProvider).connected.length;
    final me = store.me;
    final telegram = ref.watch(telegramConnectedProvider);
    final username = me == null ? null : store.username(me.usernames);

    Widget tile(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap, {
      Color? tint,
    }) => ListTile(
      leading: lead(Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (tint ?? AppColors.activeAccent).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Radii.m),
        ),
        child: Icon(icon, size: 20, color: tint ?? AppColors.activeAccent),
      )),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: context.text.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
      onTap: onTap,
    );

    Widget group(String label, List<Widget> tiles) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.xs,
            Space.l,
            Space.xs,
            Space.xs,
          ),
          child: Text(label.toUpperCase(), style: context.text.labelSmall),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final (i, t) in tiles.indexed) ...[
                  if (i > 0) const Divider(indent: 68),
                  t,
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            tooltip: 'System check',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => _open(context, const SystemCheckScreen()),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.l,
              Space.s,
              Space.l,
              Space.xxl,
            ),
            children: [
              Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.xl),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.xl),
                  onTap: me == null
                      ? (telegram ? null : () => _open(context, const AppsWebScreen()))
                      : () async {
                          final chat = await ref
                              .read(telegramClientProvider)
                              .send<td.Chat>(
                                td.CreatePrivateChat(
                                  userId: me.id,
                                  force: false,
                                ),
                                limited: true,
                              );
                          if (context.mounted)
                            _open(
                              context,
                              ChatProfileScreen(chatId: chat.id, self: true),
                            );
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Row(
                      children: [
                        if (me != null)
                          TgAvatar(
                            userId: me.id,
                            title: '${me.firstName} ${me.lastName}',
                            size: 56,
                          )
                        else
                          const BrandMark(size: 56),
                        const SizedBox(width: Space.l),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                me == null
                                    ? 'Triangle'
                                    : '${me.firstName} ${me.lastName}'.trim(),
                                style: context.text.titleLarge,
                              ),
                              Text(
                                !telegram
                                    ? 'Telegram not connected · tap to connect'
                                    : [
                                        if (username != null) '@$username',
                                        if (me != null && me.phoneNumber.isNotEmpty)
                                          '+${me.phoneNumber}',
                                      ].join(' · '),
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.text3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              group('Assistant', [
                tile(
                  SettingsSection.ai.icon,
                  SettingsSection.ai.title,
                  s.hasAnyKey
                      ? '${cat.byId(s.model)?.name ?? modelLabel(s.model)} · ${s.voiceEngine.label} voice'
                      : 'Add an AI provider API key to start',
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.ai),
                  ),
                  tint: s.hasAnyKey ? null : AppColors.warning,
                ),
                tile(
                  SettingsSection.assistant.icon,
                  SettingsSection.assistant.title,
                  SettingsSection.assistant.subtitle,
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.assistant),
                  ),
                ),
                tile(
                  SettingsSection.proactivity.icon,
                  SettingsSection.proactivity.title,
                  !s.proactive
                      ? 'Paused'
                      : '${s.notifications ? 'Notifications on' : 'Notifications off'} · ${s.keepAlive || s.backgroundAlways ? 'runs in background' : 'only while open'}',
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.proactivity),
                  ),
                ),
                tile(
                  Icons.timer_outlined,
                  'Response timing',
                  _watchTimingLabel(s.watchResponseDelaySeconds),
                  () => _open(context, const WatchTimingScreen()),
                ),
                tile(
                  Icons.assistant_outlined,
                  'Default assistant',
                  'Open Triangle by long-pressing home',
                  () => _open(context, const DefaultAssistantScreen()),
                ),
                if (Device.supported)
                  tile(
                    Icons.touch_app_outlined,
                    'Screen control',
                    'Let the assistant read and use other apps',
                    () => _open(context, const ScreenControlScreen()),
                  ),
              ]),
              group('Tools & apps', [
                tile(
                  Icons.handyman_outlined,
                  'Tools',
                  s.readOnlyMode
                      ? 'Read-only mode · $toolsOn of ${allTools.length} on'
                      : 'Telegram, apps & web, device · $toolsOn of ${allTools.length} on',
                  () => _open(context, const ToolsScreen()),
                ),
                tile(
                  Icons.hub_outlined,
                  'Apps & web',
                  services == 0
                      ? 'Composio apps, Exa, Cloudflare, E2B'
                      : '${s.hasComposioKey ? '$connectedApps apps connected · ' : ''}$services of 4 services set up',
                  () => _open(context, const AppsWebScreen()),
                ),
                tile(
                  Icons.extension_outlined,
                  'MCP & Skills',
                  'Discover, install, manage, and choose assistant tools',
                  () => _open(context, const McpSkillsSettingsScreen()),
                ),
                tile(
                  Icons.apps_rounded,
                  'More apps',
                  'Markets & travel, Bible, Reddit & Hacker News, books & radio, YouTube, research papers',
                  () => _open(context, const MoreAppsScreen()),
                ),
              ]),
              group('Your data', [
                tile(
                  Icons.account_balance_wallet_outlined,
                  'Finance',
                  'Bank & wallet texts, accounts, transactions, budgets',
                  () => _open(context, const FinanceScreen()),
                ),
                tile(
                  Icons.call_outlined,
                  'Call history',
                  'Talk time, missed calls, who you call and when',
                  () => _open(context, const CallHistoryScreen()),
                ),
                tile(
                  Icons.shield_outlined,
                  'Vault',
                  () {
                    final n = ref.watch(vaultProvider).length;
                    return n == 0 ? 'Your numbers, addresses and details, for the assistant' : '$n item${n == 1 ? '' : 's'} · encrypted on this phone';
                  }(),
                  () => _open(context, const VaultScreen()),
                ),
              ]),
              group('Automation', [
                tile(
                  Icons.visibility_outlined,
                  'Watches',
                  telegram ? '$watches on · Telegram, phone, schedules and apps' : '$watches on · phone, schedules and apps',
                  () => _open(context, const WatchesScreen()),
                ),
                tile(
                  Icons.account_tree_outlined,
                  'Routines',
                  () {
                    final all = ref.watch(routineStoreProvider);
                    final on = all.where((r) => r.enabled).length;
                    return all.isEmpty ? 'Build step-by-step automations' : '${all.length} routine${all.length == 1 ? '' : 's'} · $on on';
                  }(),
                  () => _open(context, const RoutinesScreen()),
                ),
                tile(
                  Icons.wb_twilight_rounded,
                  'Briefs',
                  s.briefsScheduled
                      ? [if (s.briefMorningOn) 'Morning ${s.briefMorning}', if (s.briefNightOn) 'night ${s.briefNight}'].join(' · ')
                      : 'On demand only',
                  () => _open(context, const BriefScreen()),
                ),
                tile(
                  Icons.tune_rounded,
                  'Brief settings',
                  () {
                    final p = ref.watch(briefPrefsProvider);
                    final chats = p.scope == BriefScope.chosen
                        ? '${p.chosen.length} chosen chats'
                        : 'All chats${p.excluded.isEmpty ? '' : ' but ${p.excluded.length}'}';
                    return '$chats · ${p.tone.label.toLowerCase()} · ${p.length.label.toLowerCase()}';
                  }(),
                  () => _open(context, const BriefSettingsScreen()),
                ),
              ]),
              group('Safety & control', [
                SwitchListTile(
                  secondary: lead(Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.activeAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(Radii.m),
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                      color: AppColors.activeAccent,
                    ),
                  )),
                  title: const Text('Read-only mode'),
                  subtitle: Text(
                    'Only tools that read: nothing is sent, changed or deleted',
                    style: context.text.bodySmall,
                  ),
                  value: s.readOnlyMode,
                  onChanged: ref
                      .read(settingsProvider.notifier)
                      .setReadOnlyMode,
                ),
                tile(
                  Icons.front_hand_outlined,
                  'Approvals',
                  s.readOnlyMode
                      ? 'Read-only: nothing is sent'
                      : s.approvalMode.label,
                  () => _open(context, const ApprovalsScreen()),
                ),
                tile(
                  Icons.history_rounded,
                  'Activity log',
                  () {
                    final log = ref.watch(activityLogProvider);
                    final now = DateTime.now();
                    final today = log.where((e) => e.at.isAfter(DateTime(now.year, now.month, now.day)) && e.outcome == ActivityOutcome.done).length;
                    return log.isEmpty ? 'Everything the assistant sends, changes or deletes, with Undo' : '$today action${today == 1 ? '' : 's'} today · ${log.length} logged';
                  }(),
                  () => _open(context, const ActivityLogScreen()),
                ),
                tile(
                  Icons.savings_outlined,
                  'Spending limits',
                  () {
                    final l = ref.watch(spendLimitsProvider);
                    if (!l.any) return 'No limits';
                    return [
                      if (l.daily != null) '${formatUsd(l.daily!)}/day',
                      if (l.monthly != null) '${formatUsd(l.monthly!)}/month',
                      if (l.perWatchDaily != null) '${formatUsd(l.perWatchDaily!)} per watch/day',
                    ].join(' · ');
                  }(),
                  () => _open(context, const SpendLimitsScreen()),
                ),
                tile(
                  Icons.insights_outlined,
                  'Usage & cost',
                  spentToday > 0
                      ? '${usd(spentToday)} today'
                      : 'Tokens and spend by chat, model and modality',
                  () => _open(context, const UsageScreen()),
                ),
                tile(
                  Icons.lock_outline_rounded,
                  'App lock',
                  () {
                    final l = ref.watch(appLockProvider);
                    if (!l.enabled) return 'Off';
                    return '${l.biometrics && l.biometricsAvailable ? 'Fingerprint or passcode' : 'Passcode'} · ${lockAfterLabel(l.lockAfter).toLowerCase()}';
                  }(),
                  () => _open(context, const AppLockSettingsScreen()),
                ),
                tile(
                  Icons.verified_user_outlined,
                  'Permissions',
                  'Background, notifications, and the phone\'s texts, calls and contacts',
                  () => _open(context, const PermissionsScreen()),
                ),
              ]),
              group('Experience', [
                tile(
                  SettingsSection.appearance.icon,
                  SettingsSection.appearance.title,
                  '${s.themeMode.label} theme · ${s.accent.label} accent · ${s.chatFontSize.toStringAsFixed(0)} pt',
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.appearance),
                  ),
                ),
                tile(
                  Icons.widgets_outlined,
                  'Home-screen widget',
                  () {
                    final l = ref.watch(widgetLookProvider);
                    return '${l.theme.label} · ${l.fontSize.toStringAsFixed(1)} sp text · ${l.content.label}';
                  }(),
                  () => _open(context, const WidgetCustomizerScreen()),
                ),
              ]),
              group('Telegram', [
                if (!telegram)
                  tile(
                    Icons.send_rounded,
                    'Connect Telegram',
                    'Ask about your chats, reply, run channels; briefs and watches follow your chats',
                    () => _open(context, const AppsWebScreen()),
                  )
                else ...[
                  tile(
                    Icons.send_rounded,
                    'Telegram account',
                    'Connection, presence, read receipts, downloads',
                    () => _open(context, const AppsWebScreen()),
                  ),
                tile(
                  Icons.schedule_send_outlined,
                  'Scheduled messages',
                  'Everything waiting to go out, by date or chat',
                  () => _open(context, const ScheduledScreen()),
                ),
                tile(
                  SettingsSection.media.icon,
                  SettingsSection.media.title,
                  [
                        if (s.autoPhotos) 'photos',
                        if (s.autoVoice) 'voice',
                        if (s.autoMusic) 'music',
                      ].isEmpty
                      ? 'Nothing downloads on its own'
                      : 'Auto: ${[if (s.autoPhotos) 'photos', if (s.autoVoice) 'voice', if (s.autoMusic) 'music'].join(', ')}',
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.media),
                  ),
                ),
                tile(
                  Icons.shield_outlined,
                  'Privacy & security',
                  'Check-up, logged-in devices, who sees what',
                  () => _open(context, const SecurityScreen()),
                ),
                tile(
                  Icons.block_rounded,
                  'Block & mute',
                  () {
                    final f = ref.watch(contentFiltersProvider);
                    final people = ref.watch(blockedSendersProvider).length;
                    final parts = [
                      if (people > 0) '$people blocked account${people == 1 ? '' : 's'}',
                      if (f.blockedChats.isNotEmpty) '${f.blockedChats.length} blocked chat${f.blockedChats.length == 1 ? '' : 's'}',
                      if (f.mutedWords.isNotEmpty) '${f.mutedWords.length} muted word${f.mutedWords.length == 1 ? '' : 's'}',
                    ];
                    return parts.isEmpty ? 'Hide blocked accounts, channels, groups and muted words' : parts.join(' · ');
                  }(),
                  () => _open(context, const BlockMuteScreen()),
                ),
                tile(
                  Icons.folder_copy_outlined,
                  'Chat folders',
                  'Create, reorder, edit and delete folders',
                  () => _open(context, const FoldersScreen()),
                ),
                tile(
                  Icons.storage_rounded,
                  'Storage & data',
                  'What Telegram takes on this phone; clear the cache; data use',
                  () => _open(context, const StorageScreen()),
                ),
                tile(
                  SettingsSection.account.icon,
                  SettingsSection.account.title,
                  SettingsSection.account.subtitle,
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.account),
                  ),
                ),
                ],
              ]),
              group('Account & app', [
                tile(
                  Icons.settings_backup_restore_rounded,
                  'Data & backup',
                  'Export or import your profile; clear all data',
                  () => _open(context, const DataScreen()),
                ),
                tile(
                  Icons.auto_stories_outlined,
                  'Show the introduction again',
                  'The welcome pages',
                  () => _open(context, const WelcomeScreen(replay: true)),
                ),
              ]),
              const SizedBox(height: Space.l),
              if (telegram)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _signOut(context, ref),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out of Telegram'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.danger),
                  ),
                ),
              ),
              const SizedBox(height: Space.l),
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _showAboutSheet(context, ref),
                      child: s.rainbowLogo
                          ? const RainbowBrandMark(size: 36)
                          : const BrandMark(size: 36),
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      '${AppConfig.appName} ${AppConfig.version}',
                      style: context.text.labelSmall,
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
}

String _watchTimingLabel(int seconds) {
  if (seconds == 0) {
    return 'Replies immediately after a matching message';
  }
  if (seconds < 60) {
    return 'Waits $seconds second${seconds == 1 ? '' : 's'} after the last message';
  }
  if (seconds < 60 * 60) {
    final minutes = seconds ~/ 60;
    return 'Waits $minutes minute${minutes == 1 ? '' : 's'} after the last message';
  }
  final hours = seconds ~/ (60 * 60);
  return 'Waits $hours hour${hours == 1 ? '' : 's'} after the last message';
}

/// One compact, readable line in the hidden runtime panel. It deliberately
/// shows status rather than raw logs: the linked screens contain the deeper
/// diagnostics and storage figures when someone needs them.
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
