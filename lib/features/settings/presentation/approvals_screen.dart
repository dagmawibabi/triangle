import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../telegram/data/telegram_tools.dart';
import '../../auth/data/auth_controller.dart';
import '../data/settings.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../account/account_switcher.dart';
import '../../account/accounts_settings.dart';
import '../../telegram/data/account_tools.dart';
import '../../assistant/approval_rules.dart';

/// When the assistant must wait for a tap before acting, and which of its
/// tools that covers.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final accounts = ref.watch(accountsProvider);
    // Telegram's tools only matter once it is connected.
    final telegram = ref.watch(telegramConnectedProvider);
    bool shown(TelegramTool t) => telegram || !t.needsTelegram;
    final asking = [for (final t in telegramTools) if (shown(t) && t.requiresApproval && !t.destructive && !t.alwaysAsk) t];
    final always = [for (final t in telegramTools) if (shown(t) && (t.destructive || t.alwaysAsk)) t];
    final byCategory = <ToolCategory, List<TelegramTool>>{};
    for (final t in asking) {
      (byCategory[t.category] ??= []).add(t);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Text(
            'Reading never asks. Anything that sends, changes or spends can wait for your tap first: Telegram messages, '
            'emails and Slack posts, calendar and Notion changes, Cloudflare changes, calls and texts from your phone. '
            'Pick how much the assistant may do on its own.',
            style: context.text.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: Space.l),
          for (final (mode, icon, example) in [
            (ApprovalMode.ask, Icons.front_hand_outlined, 'You approve every message, email, edit, reaction and change, in chats and in watches.'),
            (
              ApprovalMode.watches,
              Icons.visibility_outlined,
              'A watch or routine (answering DMs, filing emails, posting a daily update) acts straight away; asking in chat still shows an approval card.',
            ),
            (ApprovalMode.never, Icons.bolt_rounded, 'The assistant acts the moment it decides to. Good for power users.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: _ModeCard(
                mode: mode,
                icon: icon,
                example: example,
                selected: s.approvalMode == mode,
                onTap: () => ctl.setApprovalMode(mode),
              ),
            ),
          const SizedBox(height: Space.s),
          Container(
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
            child: SwitchListTile(
              secondary: lead(const Icon(Icons.lock_outline_rounded)),
              title: const Text('Read-only mode'),
              subtitle: Text(
                s.readOnlyMode ? 'Nothing can be sent or changed, whatever the mode above' : 'Turns off every tool that sends or changes something',
                style: context.text.bodySmall,
              ),
              value: s.readOnlyMode,
              onChanged: ctl.setReadOnlyMode,
            ),
          ),
          const SizedBox(height: Space.l),
          Text('ALWAYS ALLOWED', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          _RulesList(rules: ref.watch(approvalRulesProvider)),
          // Accounts with their own rules: these win for actions in them.
          if (accounts.hasSeveral) ...[
            const SizedBox(height: Space.l),
            Text('BY ACCOUNT', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            Container(
              margin: const EdgeInsets.only(bottom: Space.s),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
              child: SwitchListTile(
                secondary: lead(const Icon(Icons.alt_route_rounded)),
                title: const Text('Use another account when a tool is off'),
                subtitle: Text(
                  s.accountFallback
                      ? 'If a tool is off (or read-only) in the account you\'re working in, the assistant may do it through another account.'
                      : 'A tool you turned off in one account stays off: the assistant won\'t do it through another account unless you name that account.',
                  style: context.text.bodySmall,
                ),
                value: s.accountFallback,
                onChanged: ctl.setAccountFallback,
              ),
            ),
            Container(
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
              child: Column(
                children: [
                  for (final a in accounts.signedIn)
                    ListTile(
                      leading: AccountAvatar(account: a, size: 32),
                      title: Text(a.label),
                      subtitle: Text(
                        s.readOnlyMode || a.readOnly
                            ? 'Read-only'
                            : a.approvalMode == null
                            ? 'Same as above'
                            : '${approvalModeFor(s, a).label} · its own',
                        style: context.text.bodySmall,
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => AccountDetailScreen(accountId: a.id)),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.xl),
          _Section(
            title: 'ALWAYS ASK',
            subtitle: 'Deleting anything, leaving, blocking, spending Stars, texting from your phone, and running any app action wait for you in every mode.',
            color: AppColors.danger,
            tools: always,
          ),
          const SizedBox(height: Space.l),
          for (final e in byCategory.entries) ...[
            _Section(
              title: e.key.label.toUpperCase(),
              subtitle: switch (s.approvalMode) {
                ApprovalMode.ask => 'These ask first.',
                ApprovalMode.watches => 'These ask in chat; watches run them directly.',
                ApprovalMode.never => 'These run without asking.',
              },
              color: s.approvalMode == ApprovalMode.ask ? AppColors.accent : AppColors.warning,
              tools: e.value,
            ),
            const SizedBox(height: Space.m),
          ],
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.icon, required this.example, required this.selected, required this.onTap});
  final ApprovalMode mode;
  final IconData icon;
  final String example;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final warn = mode != ApprovalMode.ask;
    final color = selected ? (warn ? AppColors.warning : AppColors.accent) : AppColors.line;
    return Material(
      color: selected ? color.withValues(alpha: 0.08) : AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.l),
        side: BorderSide(color: color, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.l),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? color : AppColors.text2),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mode.label, style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(mode.explanation, style: context.text.bodySmall),
                    const SizedBox(height: Space.xs),
                    Text(example, style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? color : AppColors.text3,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.subtitle, required this.color, required this.tools});
  final String title;
  final String subtitle;
  final Color color;
  final List<TelegramTool> tools;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.m),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: Space.s),
            Expanded(child: Text(title, style: context.text.labelSmall)),
            Text('${tools.length}', style: context.text.labelSmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: context.text.bodySmall),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in tools)
              Tooltip(
                message: t.description,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(t.label, style: const TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// The standing approvals made from approval cards ("Always allow…").
class _RulesList extends ConsumerWidget {
  const _RulesList({required this.rules});
  final List<ApprovalRule> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
    child: rules.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(
              'No rules yet. On an approval card, tap "Always allow…" to let that action run without asking, '
              'in one chat or anywhere. Deleting, leaving, blocking and spending always ask.',
              style: context.text.bodySmall,
            ),
          )
        : Column(
            children: [
              for (final r in rules)
                ListTile(
                  leading: lead(Icon(r.anywhere ? Icons.public_rounded : Icons.chat_bubble_outline_rounded)),
                  title: Text(r.toolLabel),
                  subtitle: Text(
                    r.anywhere
                        ? 'Anywhere · still asks right after reading messages from others'
                        : 'Only in ${r.chatTitle?.trim().isNotEmpty == true ? r.chatTitle : 'chat ${r.chatId}'}',
                    style: context.text.bodySmall,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove rule',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => ref.read(approvalRulesProvider.notifier).remove(r.id),
                  ),
                ),
            ],
          ),
  );
}
