import '../../assistant/presentation/watches_screen.dart';
import '../../assistant/activity_log.dart';
import '../../assistant/presentation/activity_log_screen.dart';
import '../../assistant/presentation/default_assistant_screen.dart';
import '../../routines/routines.dart';
import '../../routines/routines_screen.dart';
import '../../vault/vault.dart';
import '../../vault/vault_screen.dart';
import 'more_apps_screen.dart';
import '../../development/development_screen.dart';
import '../../finance/finance_screen.dart';
import '../../calls/call_history_screen.dart';
import '../../usage/spend_limits.dart';
import '../../usage/spend_limits_screen.dart';
import '../../lock/app_lock.dart';
import '../../lock/app_lock_settings.dart';
import '../../brief/brief_screen.dart';
import '../../brief/brief_widget.dart';
import '../../brief/widget_customizer_screen.dart';
import '../../telegram/presentation/scheduled_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../ai/data/ai.dart';
import '../../integrations/integrations_store.dart';
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
import '../../account/security_screen.dart';
import '../../account/storage_screen.dart';
import 'cache_screen.dart';
import '../../telegram/data/content_filters.dart';
import '../../telegram/presentation/block_mute_screen.dart';
import '../../screen/screen_control_screen.dart';
import '../../device/device.dart';
import '../../components/components_screen.dart';
import '../../calls/vapi_ui.dart';
import '../../calls/vapi.dart' show VapiStore;
import '../../development/manage/app_managers.dart' show VapiManagerScreen;
import 'theme_toggle.dart';
import 'folders_hub_screen.dart';
import 'secret_menu.dart';

/// Settings at a glance: who's signed in, then a few groups that each open
/// a page of their own.
class SettingsHub extends ConsumerWidget {
  const SettingsHub({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// The secret menu behind a long press on the footer logo.
  Future<void> _showAboutSheet(BuildContext context, WidgetRef ref) =>
      showSecretMenu(context, open: (page) => _open(context, page));

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
    final services = [s.hasComposioKey, s.hasExaKey, s.hasE2bKey].where((x) => x).length;
    final devServices = [s.hasVercelToken, s.hasResendKey, s.hasMongoUri, s.hasCloudflare].where((x) => x).length;
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

    Widget toggle(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
      secondary: lead(Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.activeAccent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Radii.m),
        ),
        child: Icon(icon, size: 20, color: AppColors.activeAccent),
      )),
      title: Text(title),
      subtitle: Text(subtitle, style: context.text.bodySmall),
      value: value,
      onChanged: onChanged,
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
          const ThemeToggleButton(),
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
                      ? (telegram ? null : () => _open(context, const AppsWebScreen(tab: AppsWebTab.telegram)))
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
                      ? '${cat.byId(s.model)?.name ?? modelLabel(s.model)} · images, video, decisions'
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
                  SettingsSection.voice.icon,
                  SettingsSection.voice.title,
                  '${s.voiceEngine.label} voice · ${s.dictationEngine.label} dictation',
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.voice),
                  ),
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
              group('Tools & integrations', [
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
                      ? 'Composio apps, Exa web search, E2B sandboxes'
                      : '${s.hasComposioKey ? '$connectedApps apps connected · ' : ''}$services of 3 services set up',
                  () => _open(context, const AppsWebScreen()),
                ),
                tile(
                  Icons.extension_outlined,
                  'MCP & Skills',
                  'Discover, install, manage, and choose assistant tools',
                  () => _open(context, const McpSkillsSettingsScreen()),
                ),
                tile(
                  Icons.terminal_rounded,
                  'Development',
                  devServices == 0
                      ? 'Vercel, Resend, MongoDB and Cloudflare with your own keys'
                      : '$devServices of 4 set up · ${[if (s.hasVercelToken) 'Vercel', if (s.hasResendKey) 'Resend', if (s.hasMongoUri) 'MongoDB', if (s.hasCloudflare) 'Cloudflare'].join(', ')}',
                  () => _open(context, const DevelopmentScreen()),
                ),
                tile(
                  Icons.phone_in_talk_outlined,
                  'Phone calls',
                  VapiStore.ready ? 'Your calls, numbers and assistants · Vapi' : 'Let the assistant phone people for you with a Vapi voice agent',
                  () => _open(context, VapiStore.ready ? const VapiManagerScreen() : const VapiSettingsScreen()),
                ),
                tile(
                  Icons.bar_chart_rounded,
                  'Components',
                  'Charts, stat tiles, tables and more the assistant can draw in chats',
                  () => _open(context, const ComponentsScreen()),
                ),
                tile(
                  Icons.apps_rounded,
                  'More apps',
                  'Markets & travel, Bible, Reddit & Hacker News, books & radio, YouTube, research papers',
                  () => _open(context, const MoreAppsScreen()),
                ),
              ]),
              group('Automation', [
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
                  Icons.radar_rounded,
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
              ]),
              group('Your data', [
                tile(
                  Icons.account_balance_wallet_outlined,
                  'Finance',
                  'Bank & wallet texts, accounts, transactions, budgets',
                  () => _open(context, const FinanceScreen()),
                ),
                tile(
                  Icons.phone_callback_outlined,
                  'Call history',
                  'Talk time, missed calls, who you call and when',
                  () => _open(context, const CallHistoryScreen()),
                ),
                tile(
                  Icons.enhanced_encryption_outlined,
                  'Vault',
                  () {
                    final n = ref.watch(vaultProvider).length;
                    return n == 0 ? 'Your numbers, addresses and details, for the assistant' : '$n item${n == 1 ? '' : 's'} · encrypted on this phone';
                  }(),
                  () => _open(context, const VaultScreen()),
                ),
                tile(
                  Icons.cached_rounded,
                  'Cache',
                  'Podcasts, radio, web pages, pictures and Telegram files kept to load faster; clear any of it',
                  () => _open(context, const CacheScreen()),
                ),
                tile(
                  Icons.settings_backup_restore_rounded,
                  'Data & backup',
                  'Export or import your profile; delete chats, briefs or everything',
                  () => _open(context, const DataScreen()),
                ),
              ]),
              group('Privacy & safety', [
                toggle(
                  Icons.edit_off_outlined,
                  'Read-only mode',
                  'Only tools that read: nothing is sent, changed or deleted',
                  s.readOnlyMode,
                  ref.read(settingsProvider.notifier).setReadOnlyMode,
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
              group('Cost', [
                tile(
                  Icons.insights_outlined,
                  'Usage & cost',
                  spentToday > 0
                      ? '${usd(spentToday)} today'
                      : 'Tokens and spend by chat, model and modality',
                  () => _open(context, const UsageScreen()),
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
              ]),
              group('Appearance', [
                tile(
                  SettingsSection.appearance.icon,
                  'Theme',
                  '${s.themeMode.label} theme · ${s.accent.label} accent · ${s.use24h ? '24-hour' : '12-hour'} clock',
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.appearance),
                  ),
                ),
                tile(
                  SettingsSection.chat.icon,
                  SettingsSection.chat.title,
                  '${s.chatFontSize.toStringAsFixed(0)} pt ${s.chatFont.label.toLowerCase()} · ${s.codeTheme.label} code · ${s.answerStyle.label.toLowerCase()} answers',
                  () => _open(
                    context,
                    const SettingsScreen(section: SettingsSection.chat),
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
                toggle(
                  Icons.vibration_rounded,
                  'Haptics',
                  'A light buzz when you send or approve',
                  s.haptics,
                  (v) {
                    if (v) HapticFeedback.mediumImpact();
                    ref.read(settingsProvider.notifier).setHaptics(v);
                  },
                ),
              ]),
              group('Telegram', [
                if (!telegram)
                  tile(
                    Icons.send_rounded,
                    'Connect Telegram',
                    'Ask about your chats, reply, run channels; briefs and watches follow your chats',
                    () => _open(context, const AppsWebScreen(tab: AppsWebTab.telegram)),
                  )
                else ...[
                  tile(
                    Icons.send_rounded,
                    'Telegram account',
                    'Connection, online status, read receipts, sign out',
                    () => _open(context, const AppsWebScreen(tab: AppsWebTab.telegram)),
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
                    Icons.schedule_send_outlined,
                    'Scheduled messages',
                    'Everything waiting to go out, by date or chat',
                    () => _open(context, const ScheduledScreen()),
                  ),
                  tile(
                    Icons.storage_rounded,
                    'Storage & data',
                    'What Telegram takes on this phone; clear the cache; data use',
                    () => _open(context, const StorageScreen()),
                  ),
                ],
                tile(
                  Icons.folder_copy_outlined,
                  'Folders',
                  telegram ? 'Telegram folders, your own, and what the drawer shows' : 'Your own folders and what the drawer shows',
                  () => _open(context, const FoldersHubScreen()),
                ),
              ]),
              group('About', [
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
