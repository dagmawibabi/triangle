import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../auth/data/auth_controller.dart';
import '../auth/presentation/telegram_sign_in_screen.dart';
import '../settings/presentation/tools_screen.dart';
import '../telegram/data/account_tools.dart';
import '../telegram/data/telegram_store.dart';

import '../settings/data/settings.dart';
import '../telegram/presentation/chat_actions.dart' show confirmAction;
import 'account_switcher.dart';
import 'security_screen.dart';
import 'storage_screen.dart';
import '../telegram/presentation/folders_screen.dart';
import '../telegram/presentation/scheduled_screen.dart';

/// Settings → Telegram → Accounts: every signed-in account, and adding one.
class AccountsSection extends ConsumerWidget {
  const AccountsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
          child: Text('ACCOUNTS · ${accounts.signedIn.length}/$maxAccounts', style: context.text.labelSmall),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final a in accounts.signedIn)
                  ListTile(
                    leading: AccountAvatar(account: a, size: 36),
                    title: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [
                        if (a.id == accounts.activeId) 'On screen',
                        if (accounts.hasSeveral) a.aiAccess ? 'Assistant can use it' : 'Assistant can\'t use it',
                        if (a.customTools) 'Own tools',
                      ].join(' · '),
                      style: context.text.bodySmall,
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => AccountDetailScreen(accountId: a.id)),
                    ),
                  ),
                ListTile(
                  enabled: accounts.canAdd,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.surface3,
                    child: Icon(Icons.add_rounded, color: AppColors.text2),
                  ),
                  title: const Text('Add account'),
                  subtitle: Text(
                    accounts.canAdd
                        ? 'Sign in another Telegram account and switch between them'
                        : 'Up to $maxAccounts accounts',
                    style: context.text.bodySmall,
                  ),
                  onTap: () => TelegramSignInScreen.addAccount(context, ref),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One account: switch to it, what the assistant may do in it, sign out.
class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final account = accounts.byId(accountId);
    if (account == null || !account.signedIn) {
      // Signed out meanwhile.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }
    final store = ref.watch(accountStoreProvider(accountId));
    final settings = ref.watch(settingsProvider);
    final ctl = ref.read(accountsProvider.notifier);
    final active = accounts.activeId == accountId;
    // Every tool: Telegram, apps & web and device ones can all be set per
    // account.
    final telegramTools = [for (final g in ToolGroup.values) ...toolsIn(g)];
    final on = telegramTools.where((t) => toolOnFor(t, settings, account)).length;
    final me = store.me;

    Widget card(List<Widget> children) => Container(
      margin: const EdgeInsets.only(top: Space.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(account.label)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
            children: [
              Row(
                children: [
                  AccountAvatar(account: account, size: 56),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account.label, style: context.text.titleLarge),
                        Text(
                          [
                            if (account.username != null) '@${account.username}',
                            if (me != null && me.phoneNumber.isNotEmpty) '+${me.phoneNumber}',
                            store.chatsLoaded ? '${store.chats.values.where((c) => c.isListed).length} chats' : 'Loading chats…',
                          ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              FilledButton.icon(
                onPressed: active
                    ? null
                    : () {
                        ctl.switchTo(accountId);
                        Navigator.of(context).maybePop();
                      },
                icon: Icon(active ? Icons.check_rounded : Icons.swap_horiz_rounded),
                label: Text(active ? 'On screen now' : 'Switch to this account'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, 0),
                child: Text('ASSISTANT', style: context.text.labelSmall),
              ),
              card([
                SwitchListTile(
                  title: const Text('Assistant can use this account'),
                  subtitle: Text(
                    accounts.hasSeveral
                        ? 'Its Telegram tools can read and, with your approval, act in this account. Actions always name the account.'
                        : 'Applies once more than one account is signed in.',
                    style: context.text.bodySmall,
                  ),
                  value: account.aiAccess,
                  onChanged: (v) {
                    if (!v && accounts.forAi.length == 1 && account.aiAccess) {
                      showSnack(context, 'Turn on another account first, or turn off the Telegram tools instead.');
                      return;
                    }
                    ctl.setAiAccess(accountId, v);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Tools'),
                  subtitle: Text(
                    account.customTools
                        ? 'Own settings · $on/${telegramTools.length} on'
                        : 'Same as all accounts · $on/${telegramTools.length} on',
                    style: context.text.bodySmall,
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ToolsScreen(accountId: accountId)),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Read-only'),
                  subtitle: Text(
                    'The assistant may only read here: no sending, editing, reacting or joining, in chats or watches.',
                    style: context.text.bodySmall,
                  ),
                  value: account.readOnly,
                  onChanged: (v) => ctl.setReadOnly(accountId, v),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Approvals'),
                  subtitle: Text(
                    account.approvalMode == null
                        ? 'Same as Settings · ${settings.approvalMode.label}'
                        : '${approvalModeFor(settings, account).label} · just for this account',
                    style: context.text.bodySmall,
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                  onTap: account.readOnly
                      ? null
                      : () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheet) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                                  child: Text(
                                    'When the assistant must wait for your tap before acting in ${account.label}. '
                                    'Deleting and spending Stars always ask.',
                                    style: context.text.bodySmall,
                                  ),
                                ),
                                for (final mode in <ApprovalMode?>[null, ...ApprovalMode.values])
                                  ListTile(
                                    leading: Icon(
                                      account.approvalMode == mode?.name ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: AppColors.accent,
                                    ),
                                    title: Text(mode == null ? 'Same as Settings (${settings.approvalMode.label})' : mode.label),
                                    subtitle: mode == null ? null : Text(mode.explanation, style: context.text.bodySmall),
                                    onTap: () {
                                      ctl.setApprovalMode(accountId, mode?.name);
                                      Navigator.pop(sheet);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, 0),
                child: Text('MANAGE', style: context.text.labelSmall),
              ),
              card([
                // These pages work on the account on screen: switched to first.
                for (final (icon, title, page) in <(IconData, String, Widget)>[
                  (Icons.folder_copy_outlined, 'Folders', const FoldersScreen()),
                  (Icons.schedule_send_outlined, 'Scheduled messages', const ScheduledScreen()),
                  (Icons.shield_outlined, 'Privacy & security', const SecurityScreen()),
                  (Icons.storage_rounded, 'Storage', const StorageScreen()),
                ])
                  ListTile(
                    leading: Icon(icon, color: AppColors.text2),
                    title: Text(title),
                    subtitle: active ? null : Text('Switches to this account', style: context.text.bodySmall),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () {
                      final nav = Navigator.of(context);
                      if (!active) {
                        ctl.switchTo(accountId);
                        showSnack(context, 'Switched to ${account.label}', icon: Icons.swap_horiz_rounded);
                      }
                      nav.push(MaterialPageRoute<void>(builder: (_) => page));
                    },
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, 0),
                child: Text('ALERTS', style: context.text.labelSmall),
              ),
              card([
                SwitchListTile(
                  title: const Text('Notify me of mentions and replies'),
                  subtitle: Text(
                    settings.mentionAlerts
                        ? 'When someone mentions or replies to this account.'
                        : 'Mention alerts are off for every account (Settings → Telegram).',
                    style: context.text.bodySmall,
                  ),
                  value: settings.mentionAlerts && account.mentionAlerts,
                  onChanged: settings.mentionAlerts ? (v) => ctl.setMentionAlerts(accountId, v) : null,
                ),
              ]),
              const SizedBox(height: Space.xl),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign out of this account'),
                onPressed: () async {
                  final last = accounts.signedIn.length == 1;
                  if (!await confirmAction(
                    context,
                    title: 'Sign out of ${account.label}?',
                    message: last
                        ? 'This ends Triangle\'s Telegram session and removes your conversations from this device. '
                              'Nothing in your Telegram account is deleted.'
                        : 'This ends Triangle\'s session for this account and deletes its data from this phone. '
                              'Your other accounts stay signed in. Nothing in your Telegram account is deleted.',
                    action: 'Sign out',
                  )) {
                    return;
                  }
                  if (last) await ref.read(settingsProvider.notifier).setTelegramSkipped(true);
                  await ref.read(authControllerProvider.notifier).signOut(accountId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
