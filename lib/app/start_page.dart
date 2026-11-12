import 'package:flutter/material.dart';

import '../features/brief/brief_screen.dart';
import '../features/chat/presentation/generated_files_screen.dart';
import '../features/search/everywhere_search_screen.dart';
import '../features/telegram/presentation/calls_screen.dart';
import '../features/telegram/presentation/chat_list_screen.dart';
import '../features/telegram/presentation/content_canvas_screen.dart';

/// The page the app opens on. The AI chat stays underneath, so going back
/// from any of the others lands there.
enum StartPage {
  assistant('AI chat', Icons.auto_awesome_outlined),
  dms('DMs', Icons.person_outline_rounded, section: BrowseSection.dms),
  channels('Channels', Icons.campaign_outlined, section: BrowseSection.channels),
  groups('Groups', Icons.groups_outlined, section: BrowseSection.groups),
  bots('Bots', Icons.smart_toy_outlined, section: BrowseSection.bots),
  contacts('Contacts', Icons.contacts_outlined, section: BrowseSection.contacts),
  archived('Archived', Icons.archive_outlined, section: BrowseSection.archived),
  calls('Calls', Icons.call_outlined, telegram: true),
  brief('Brief', Icons.wb_twilight_rounded),
  canvas('Content Canvas', Icons.dashboard_customize_outlined),
  files('Files', Icons.folder_copy_outlined),
  search('Search', Icons.manage_search_rounded);

  const StartPage(this.label, this.icon, {this.section, bool telegram = false}) : _telegram = telegram;
  final String label;
  final IconData icon;
  final BrowseSection? section;
  final bool _telegram;

  /// Needs a signed-in Telegram account to make sense.
  bool get needsTelegram => _telegram || section != null;

  static StartPage parse(String? name) => StartPage.values.where((p) => p.name == name).firstOrNull ?? assistant;

  /// The page itself; null for the AI chat, which is always there.
  Widget? build() => switch (this) {
    assistant => null,
    calls => const CallsScreen(),
    brief => const BriefScreen(),
    canvas => const ContentCanvasScreen(),
    files => const GeneratedFilesScreen(),
    search => const EverywhereSearchScreen(),
    _ => ChatListScreen(section: section!),
  };
}
