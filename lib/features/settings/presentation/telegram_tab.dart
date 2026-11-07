import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../account/security_screen.dart';
import '../../account/storage_screen.dart';
import '../../auth/data/auth_controller.dart';
import '../../auth/presentation/telegram_sign_in_screen.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/presentation/chat_actions.dart' show confirmAction;
import '../../telegram/presentation/folders_screen.dart';
import '../../telegram/presentation/scheduled_screen.dart';
import '../../telegram/presentation/tg_avatar.dart';
import '../data/settings.dart';
import 'tools_screen.dart';
import '../../account/accounts_settings.dart';
import '../../../infrastructure/telegram/accounts.dart';

/// Settings → Apps & web → Telegram: the account (connect it like any other
/// app, or sign out), and how Triangle behaves in it.
class TelegramTab extends ConsumerWidget {
  const TelegramTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).value;
    final ready = auth is td.AuthorizationStateReady;
    final store = ref.watch(telegramStoreProvider);
    final me = store.me;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final limiter = ref.watch(telegramClientProvider).limiter;
    final telegramTools = toolsIn(ToolGroup.telegram);
    final toolsOn = telegramTools.where((t) => t.isOn(s)).length;

    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
          child: Text(title.toUpperCase(), style: context.text.labelSmall),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        ),
      ],
    );

    Widget link(IconData icon, String title, String sub, Widget page) => ListTile(
      leading: lead(Icon(icon, color: AppColors.text2)),
      title: Text(title),
      subtitle: Text(sub, style: context.text.bodySmall),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
      onTap: () => open(page),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
          children: [
            Container(
              padding: const EdgeInsets.all(Space.l),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.l),
                border: Border.all(color: ready ? AppColors.success.withValues(alpha: 0.4) : AppColors.line),
              ),
              child: Row(
                children: [
                  if (ready && me != null)
                    TgAvatar(userId: me.id, title: '${me.firstName} ${me.lastName}', size: 48)
                  else
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(color: Color(0xFF2AABEE), shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ready && me != null ? '${me.firstName} ${me.lastName}'.trim() : 'Telegram',
                          style: context.text.titleMedium,
                        ),
                        Text(
                          ready
                              ? [
                                  if (me != null && store.username(me.usernames) != null) '@${store.username(me.usernames)}',
                                  if (me != null && me.phoneNumber.isNotEmpty) '+${me.phoneNumber}',
                                  'connected',
                                ].join(' · ')
                              : 'Not connected. Connect it to ask about your chats, reply, run channels, and get briefs and watches.',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.m),
            if (!ready)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48), backgroundColor: const Color(0xFF2AABEE), foregroundColor: Colors.white),
                onPressed: () => open(const TelegramSignInScreen()),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Connect Telegram'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => open(const ToolsScreen()),
                      icon: const Icon(Icons.handyman_outlined, size: 18),
                      label: Text('Tools · $toolsOn/${telegramTools.length}'),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () async {
                        final several = ref.read(accountsProvider).hasSeveral;
                        if (!await confirmAction(
                          context,
                          title: several ? 'Sign out of ${me?.firstName ?? 'this account'}?' : 'Sign out of Telegram?',
                          message: several
                              ? 'This ends Triangle\'s session for this account and deletes its data from this phone. '
                                    'Your other accounts stay signed in. Nothing in your Telegram account is deleted.'
                              : 'This ends Triangle\'s Telegram session and removes your conversations from this device. '
                                    'Nothing in your Telegram account is deleted. You can keep using Triangle without it.',
                          action: 'Sign out',
                        )) {
                          return;
                        }
                        if (!several) await ctl.setTelegramSkipped(true);
                        await ref.read(authControllerProvider.notifier).signOut();
                      },
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign out'),
                    ),
                  ),
                ],
              ),
            if (!ready)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Text(
                  'Sign in with your phone number or a QR code from another device. Triangle talks to Telegram directly from this '
                  'phone through the official TDLib library; nothing goes through Triangle servers.',
                  style: context.text.bodySmall,
                ),
              ),
            if (ready) const AccountsSection(),
            section('How Triangle behaves', [
              SwitchListTile(
                secondary: lead(Icon(Icons.circle, size: 14, color: AppColors.success)),
                title: const Text('Appear online while using the app'),
                subtitle: Text('Lets Telegram send typing indicators and live status', style: context.text.bodySmall),
                value: s.appearOnline,
                onChanged: ctl.setAppearOnline,
              ),
              SwitchListTile(
                secondary: lead(const Icon(Icons.done_all_rounded)),
                title: const Text('Mark chats read when I open them'),
                value: s.markReadOnOpen,
                onChanged: ctl.setMarkReadOnOpen,
              ),
              SwitchListTile(
                secondary: lead(const Icon(Icons.mark_chat_read_outlined)),
                title: const Text('Mark read when the assistant reads'),
                value: s.aiReadOnView,
                onChanged: ctl.setAiReadOnView,
              ),
              SwitchListTile(
                secondary: lead(const Icon(Icons.reply_rounded)),
                title: const Text('Mark read when the assistant replies'),
                value: s.aiReadOnReply,
                onChanged: ctl.setAiReadOnReply,
              ),
              SwitchListTile(
                secondary: lead(const Icon(Icons.alternate_email_rounded)),
                title: const Text('Notify me of mentions and replies'),
                value: s.mentionAlerts,
                onChanged: ctl.setMentionAlerts,
              ),
              SwitchListTile(
                secondary: lead(const Icon(Icons.link_rounded)),
                title: const Text('Link previews'),
                value: s.showLinkPreviews,
                onChanged: ctl.setShowLinkPreviews,
              ),
            ]),
            section('Downloads', [
              SwitchListTile(
                secondary: lead(const Icon(Icons.photo_outlined)),
                title: const Text('Photos'),
                subtitle: Text('Download as soon as they arrive', style: context.text.bodySmall),
                value: s.autoPhotos,
                onChanged: (v) => ctl.setAutoDownload(photos: v),
              ),
              SwitchListTile(
                secondary: lead(const Icon(Icons.mic_none_rounded)),
                title: const Text('Voice messages'),
                value: s.autoVoice,
                onChanged: (v) => ctl.setAutoDownload(voice: v),
              ),
              SwitchListTile(
                secondary: lead(const Icon(Icons.music_note_outlined)),
                title: const Text('Music'),
                value: s.autoMusic,
                onChanged: (v) => ctl.setAutoDownload(music: v),
              ),
            ]),
            if (ready)
              section('Account', [
                link(Icons.folder_copy_outlined, 'Folders', 'Make, edit and order chat folders', const FoldersScreen()),
                link(Icons.schedule_send_outlined, 'Scheduled messages', 'Everything waiting to go out', const ScheduledScreen()),
                link(Icons.shield_outlined, 'Privacy & security', 'Check-up, devices, who sees what', const SecurityScreen()),
                link(Icons.storage_rounded, 'Storage', 'What Telegram keeps on this phone', const StorageScreen()),
                ListTile(
                  leading: lead(Icon(Icons.speed_rounded, color: AppColors.text2)),
                  title: const Text('Request pacing'),
                  subtitle: Text(
                    'Requests are paced (bursts of ${limiter.capacity}, then about one a second) and stop when Telegram asks to wait.',
                    style: context.text.bodySmall,
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
