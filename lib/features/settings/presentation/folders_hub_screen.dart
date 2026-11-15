import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../custom_folders/custom_folders.dart';
import '../../auth/data/auth_controller.dart';
import '../../custom_folders/custom_folders_ui.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/presentation/folders_screen.dart';
import '../data/settings.dart';
import 'settings_screen.dart' show DrawerSectionTile;

/// Everything about folders in one place: Telegram's own chat folders, the
/// app's folders of any chats, and what the side drawer lists.
class FoldersHubScreen extends ConsumerWidget {
  const FoldersHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telegram = ref.watch(telegramConnectedProvider);
    final tg = ref.watch(telegramStoreProvider).folders.length;
    final mine = ref.watch(customFoldersProvider).folders.length;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    Widget card(List<Widget> children) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: AppColors.line),
      ),
      child: Material(type: MaterialType.transparency, child: Column(children: children)),
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, Space.xs, Space.xs),
      child: Text(text.toUpperCase(), style: context.text.labelSmall),
    );
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    String count(int n) => n == 0 ? 'None yet' : '$n folder${n == 1 ? '' : 's'}';
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
            children: [
              label('Folders'),
              card([
                if (telegram) ...[
                  ListTile(
                    leading: lead(const Icon(Icons.folder_shared_outlined)),
                    title: const Text('Telegram folders'),
                    subtitle: Text('${count(tg)} · synced with Telegram on every device', style: context.text.bodySmall),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () => open(const FoldersScreen()),
                  ),
                  const Divider(indent: 68),
                ],
                ListTile(
                  leading: lead(const Icon(Icons.create_new_folder_outlined)),
                  title: const Text('My folders'),
                  subtitle: Text('${count(mine)} · any chats, from any account, on this phone', style: context.text.bodySmall),
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                  onTap: () => open(const CustomFoldersSettingsScreen()),
                ),
              ]),
              label('Side drawer'),
              card([
                DrawerSectionTile(
                  icon: Icons.forum_outlined,
                  title: 'Chats',
                  subtitle: 'DMs, groups, channels, bots, contacts and calls',
                  value: s.drawerChats,
                  onChanged: ctl.setDrawerChats,
                  items: DrawerItems.chats,
                  settings: s,
                  onItem: ctl.setDrawerItem,
                ),
                DrawerSectionTile(
                  icon: Icons.construction_rounded,
                  title: 'Tools',
                  subtitle: 'Files, Brief, Content Canvas, Search, Browser and PC screen',
                  value: s.drawerTools,
                  onChanged: ctl.setDrawerTools,
                  items: DrawerItems.tools,
                  settings: s,
                  onItem: ctl.setDrawerItem,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
