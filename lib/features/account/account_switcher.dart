import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../auth/presentation/telegram_sign_in_screen.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/presentation/tg_avatar.dart';

/// An account's profile picture, from that account's own data.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.size = 32});
  final TelegramAccount account;
  final double size;

  @override
  Widget build(BuildContext context) => TgAvatar(
    accountId: account.id,
    userId: account.userId,
    title: account.label,
    size: size,
  );
}

/// Chats with unread messages (muted ones aside) in [account].
int _unreadChats(TelegramStore store) =>
    store.chats.values.where((c) => c.isListed && c.hasUnread && !c.isMuted).length;

/// The accounts sheet: switch to another account or add one. Opened by
/// long-pressing the profile at the bottom of the drawer.
Future<void> showAccountsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // The sheet's own context and ref are gone once it closes, so what
    // happens after closing uses the caller's ([context], [ref]).
    builder: (sheet) => Consumer(
      builder: (sheetContext, sheetRef, _) {
        final accounts = sheetRef.watch(accountsProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                child: Text('ACCOUNTS', style: context.text.labelSmall),
              ),
              for (final a in accounts.signedIn)
                _AccountTile(
                  account: a,
                  active: a.id == accounts.activeId,
                  onTap: () {
                    final accountsCtl = sheetRef.read(accountsProvider.notifier);
                    Navigator.pop(sheet);
                    accountsCtl.switchTo(a.id);
                  },
                ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                enabled: accounts.canAdd,
                leading: CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.surface3,
                  child: Icon(Icons.add_rounded, size: 20, color: AppColors.text2),
                ),
                title: const Text('Add account'),
                subtitle: accounts.canAdd
                    ? null
                    : Text('Up to $maxAccounts accounts', style: context.text.bodySmall),
                onTap: () {
                  final nav = Navigator.of(sheet);
                  nav.pop();
                  TelegramSignInScreen.addAccount(context, ref);
                },
              ),
              const SizedBox(height: Space.s),
            ],
          ),
        );
      },
    ),
  );
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account, required this.active, required this.onTap});
  final TelegramAccount account;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = _unreadChats(ref.watch(accountStoreProvider(account.id)));
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
      leading: AccountAvatar(account: account, size: 34),
      title: Text(account.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: account.username == null ? null : Text('@${account.username}', style: context.text.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unread > 0 && !active) _UnreadPill(count: unread),
          if (active) Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(10)),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: context.text.labelSmall?.copyWith(color: AppColors.accent),
    ),
  );
}

/// Which Telegram accounts a watch, job, check-in or brief covers: "All
/// accounts" (null, which includes accounts added later) or the ones ticked.
/// Shows nothing until a second account is signed in.
class AccountScopePicker extends ConsumerWidget {
  const AccountScopePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.title = 'ACCOUNTS',
    this.note,
  });

  final List<String>? value;
  final ValueChanged<List<String>?> onChanged;
  final String title;

  /// A line under the chips, e.g. what covering an account means here.
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    if (!accounts.hasSeveral) return const SizedBox.shrink();
    final signedIn = accounts.signedIn;
    final chosen = value == null ? {for (final a in signedIn) a.id} : value!.toSet();
    // Accounts signed out since: they no longer count.
    final covered = signedIn.where((a) => chosen.contains(a.id)).toList();
    void toggle(TelegramAccount a) {
      final next = {...chosen.where((id) => signedIn.any((s) => s.id == id))};
      if (!next.remove(a.id)) next.add(a.id);
      if (next.isEmpty) {
        showSnack(context, 'Keep at least one account');
        return;
      }
      // Every account ticked: "all", so accounts added later count too.
      onChanged(next.length == signedIn.length ? null : [for (final s in signedIn) if (next.contains(s.id)) s.id]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              showCheckmark: false,
              avatar: Icon(Icons.groups_outlined, size: 18, color: value == null ? AppColors.accent : AppColors.text2),
              label: const Text('All accounts'),
              selected: value == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final a in signedIn)
              FilterChip(
                showCheckmark: false,
                avatar: AccountAvatar(account: a, size: 20),
                label: Text(a.label),
                selected: chosen.contains(a.id),
                onSelected: (_) => toggle(a),
              ),
          ],
        ),
        if (value != null && covered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'The accounts it covered are signed out, so it covers none. Pick one.',
              style: context.text.bodySmall?.copyWith(color: AppColors.warning),
            ),
          )
        else if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(note!, style: context.text.bodySmall),
          ),
      ],
    );
  }
}

/// A bottom sheet with just an [AccountScopePicker], for things edited in
/// place (a scheduled job). Resolves to the choice, or null when dismissed;
/// the record's `all` is true for "All accounts".
Future<({List<String>? ids})?> pickAccountScope(
  BuildContext context, {
  required List<String>? initial,
  required String title,
  String? note,
}) {
  var value = initial;
  return showModalBottomSheet<({List<String>? ids})>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountScopePicker(value: value, title: title, note: note, onChanged: (v) => setState(() => value = v)),
              const SizedBox(height: Space.l),
              FilledButton(onPressed: () => Navigator.pop(sheet, (ids: value)), child: const Text('Save')),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A short description of which accounts [ids] covers, for list subtitles.
String accountScopeLabel(AccountsState s, List<String>? ids) {
  if (ids == null) return 'All accounts';
  final names = [for (final a in s.within(ids)) a.label];
  return names.isEmpty ? 'No account' : names.join(', ');
}

/// The active account's picture in an app bar, once more than one account
/// is signed in. Tapping it drops down the accounts to switch between.
class AccountSwitcherButton extends ConsumerWidget {
  const AccountSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    if (!accounts.hasSeveral) return const SizedBox.shrink();
    final active = accounts.active;
    final otherUnread = [
      for (final a in accounts.signedIn)
        if (a.id != active.id) _unreadChats(ref.watch(accountStoreProvider(a.id))),
    ].fold(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: PopupMenuButton<String>(
        tooltip: 'Switch account',
        position: PopupMenuPosition.under,
        onSelected: (id) {
          if (id == '+') {
            TelegramSignInScreen.addAccount(context, ref);
          } else {
            ref.read(accountsProvider.notifier).switchTo(id);
          }
        },
        itemBuilder: (_) => [
          for (final a in accounts.signedIn)
            PopupMenuItem(
              value: a.id,
              child: Consumer(
                builder: (context, ref, _) {
                  final unread = a.id == active.id ? 0 : _unreadChats(ref.watch(accountStoreProvider(a.id)));
                  return Row(
                    children: [
                      AccountAvatar(account: a, size: 28),
                      const SizedBox(width: Space.m),
                      Expanded(child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (unread > 0) ...[const SizedBox(width: Space.s), _UnreadPill(count: unread)],
                      if (a.id == active.id) ...[
                        const SizedBox(width: Space.s),
                        Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                      ],
                    ],
                  );
                },
              ),
            ),
          if (accounts.canAdd) ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: '+',
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 20, color: AppColors.text2),
                  const SizedBox(width: Space.m),
                  const Text('Add account'),
                ],
              ),
            ),
          ],
        ],
        child: Badge(
          isLabelVisible: otherUnread > 0,
          smallSize: 8,
          backgroundColor: AppColors.accent,
          child: AccountAvatar(account: active, size: 30),
        ),
      ),
    );
  }
}
