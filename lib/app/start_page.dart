import 'package:flutter/material.dart';

import '../features/books/books_screen.dart';
import '../features/brief/brief_screen.dart';
import '../features/gallery/gallery_screen.dart';
import '../features/marketplace/market_screen.dart';
import '../features/movies/movies_screen.dart';
import '../features/cinema/cinema_screen.dart';
import '../features/opportunity/opportunity_screen.dart';
import '../features/podcasts/podcasts_screen.dart';
import '../features/playlists/playlists_screen.dart';
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
  search('Search', Icons.manage_search_rounded),
  // The Explore pages, in the side drawer's order.
  playlists('Music & playlists', Icons.queue_music_rounded),
  movies('Video', Icons.movie_filter_rounded, telegram: true),
  cinema('Cinema', Icons.theaters_rounded, telegram: true),
  podcasts('Podcasts & radio', Icons.podcasts_rounded),
  books('Library', Icons.auto_stories_rounded),
  gallery('Gallery', Icons.photo_library_rounded, telegram: true),
  opportunity('Events & jobs', Icons.rocket_launch_rounded, telegram: true),
  marketplace('Marketplace', Icons.storefront_rounded, telegram: true);

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
    playlists => const PlaylistsScreen(),
    marketplace => const MarketplaceScreen(),
    movies => const MoviesScreen(),
    cinema => const CinemaScreen(),
    books => const BooksScreen(),
    gallery => const GalleryScreen(),
    opportunity => const OpportunityScreen(),
    podcasts => const PodcastsScreen(),
    _ => ChatListScreen(section: section!),
  };
}
