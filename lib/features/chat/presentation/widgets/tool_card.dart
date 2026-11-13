import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:image_picker/image_picker.dart';

import '../../../../app/theme.dart';
import '../../../../core/files/download_progress.dart';
import '../../../telegram/data/telegram_store.dart';
import '../../../telegram/presentation/message_tile.dart';
import '../../../telegram/data/telegram_tools.dart';
import '../../../integrations/app_toolkits.dart';
import '../../../device/device.dart';
import '../../../web/browser_screen.dart';
import '../../data/chat_controller.dart';
import '../../domain/chat_models.dart';
import 'json_tree.dart';
import 'rich_results.dart';
import 'tool_controls.dart';
import 'tool_result_view.dart';
import '../../../assistant/approval_rules.dart';
import '../../../assistant/untrusted.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../infrastructure/telegram/accounts.dart';
import '../../../account/account_switcher.dart';
import '../../../telegram/data/account_tools.dart';
import 'utility_result_cards.dart' show SpeedTestPanel;

IconData toolIcon(String name) => switch (name) {
  'jev_box' => Icons.crop_free_rounded,
  'jev_batch' => Icons.checklist_rounded,
  'create_widget' ||
  'update_widget' ||
  'list_widgets' ||
  'delete_widget' => Icons.widgets_outlined,
  'jev_models' => Icons.view_list_rounded,
  final n when n.startsWith('jev_') => Icons.balance_rounded,
  'mcp_search' => Icons.travel_explore_rounded,
  'mcp_install' || 'mcp_install_catalog' => Icons.add_link_rounded,
  'mcp_uninstall' => Icons.link_off_rounded,
  'mcp_call_tool' => Icons.play_circle_outline_rounded,
  final n when n.startsWith('mcp_') => Icons.hub_outlined,
  'search_skills' => Icons.manage_search_rounded,
  'install_skill' => Icons.download_rounded,
  'uninstall_skill' => Icons.delete_outline_rounded,
  'list_skills' ||
  'is_skill_installed' ||
  'preview_skill' ||
  'load_skill' ||
  'read_skill_file' => Icons.school_outlined,
  'get_account_overview' => Icons.person_outline_rounded,
  'list_chats' => Icons.forum_outlined,
  'get_chat_info' => Icons.info_outline_rounded,
  'read_messages' => Icons.article_outlined,
  'get_recent_activity' => Icons.bolt_rounded,
  'search_messages' => Icons.search_rounded,
  'get_message' => Icons.chat_bubble_outline_rounded,
  'send_message' => Icons.send_rounded,
  'finance_verify_payment' => Icons.verified_outlined,
  'retro_games_search' => Icons.sports_esports_rounded,
  'retro_game_details' => Icons.videogame_asset_rounded,
  'retro_game_download' => Icons.download_for_offline_outlined,
  'youtube_comments' => Icons.mode_comment_outlined,
  'youtube_trending' => Icons.trending_up_rounded,
  'youtube_live' => Icons.sensors_rounded,
  'youtube_channel_videos' => Icons.video_library_outlined,
  'youtube_compare_channels' => Icons.compare_arrows_rounded,
  'youtube_new_uploads' => Icons.fiber_new_outlined,
  'ethiopian_date' || 'ethiopian_calendar' => Icons.calendar_month_outlined,
  'ethiopian_holidays' => Icons.celebration_outlined,
  'qr_generate' => Icons.qr_code_2_rounded,
  'qr_read' || 'qr_scan' => Icons.qr_code_scanner_rounded,
  'sim_cards' => Icons.sim_card_outlined,
  'speed_test' => Icons.speed_rounded,
  'phone_data_usage' => Icons.data_usage_rounded,
  'phone_notifications' => Icons.notifications_none_rounded,
  'send_voice_message' => Icons.mic_none_rounded,
  'list_contacts' => Icons.contacts_outlined,
  'list_chat_folders' => Icons.folder_outlined,
  'get_unread_mentions' => Icons.alternate_email_rounded,
  'get_pinned_messages' => Icons.push_pin_outlined,
  'get_comments' => Icons.mode_comment_outlined,
  'list_shared_media' => Icons.perm_media_outlined,
  'get_chat_members' => Icons.groups_outlined,
  'search_public_chats' => Icons.travel_explore_rounded,
  'forward_message' => Icons.shortcut_rounded,
  'show_channel_post' => Icons.article_outlined,
  'generate_audio' => Icons.graphic_eq_rounded,
  'generate_sound_effect' => Icons.surround_sound_rounded,
  'generate_music' => Icons.music_note_rounded,
  'generate_image' => Icons.brush_outlined,
  'get_model_settings' => Icons.psychology_outlined,
  'generate_video' => Icons.movie_creation_outlined,
  'get_forum_topics' => Icons.topic_outlined,
  'get_user_profile' => Icons.badge_outlined,
  'send_chat_action' => Icons.more_time_rounded,
  'react_to_message' => Icons.add_reaction_outlined,
  'set_chat_notifications' => Icons.notifications_none_rounded,
  'mark_as_read' => Icons.mark_chat_read_outlined,
  'explore_forum' => Icons.forum_outlined,
  'get_message_reactions' => Icons.emoji_emotions_outlined,
  'comment_on_post' => Icons.add_comment_outlined,
  'edit_message' => Icons.edit_note_rounded,
  'reply_to_message' => Icons.reply_rounded,
  'pin_message' => Icons.push_pin_outlined,
  'archive_chat' => Icons.archive_outlined,
  'schedule_message' => Icons.schedule_send_outlined,
  'list_scheduled_messages' => Icons.event_note_outlined,
  'reschedule_message' => Icons.update_rounded,
  'remember' => Icons.bookmark_add_outlined,
  'update_memory' => Icons.bookmark_outlined,
  'forget_memory' => Icons.bookmark_remove_outlined,
  'list_memories' => Icons.bookmarks_outlined,
  'create_watch' => Icons.visibility_outlined,
  'list_watches' => Icons.remove_red_eye_outlined,
  'update_watch' => Icons.edit_notifications_outlined,
  'delete_watch' => Icons.visibility_off_outlined,
  'notify_me' => Icons.notifications_active_outlined,
  'list_attachments' => Icons.attach_file_rounded,
  'create_poll' => Icons.poll_outlined,
  'get_poll_results' => Icons.bar_chart_rounded,
  'vote_poll' => Icons.how_to_vote_outlined,
  'stop_poll' => Icons.block_outlined,
  'send_contact' => Icons.contact_page_outlined,
  'search_gifs' => Icons.gif_box_outlined,
  'list_saved_gifs' => Icons.gif_outlined,
  'send_gif' => Icons.gif_rounded,
  'list_calls' => Icons.call_outlined,
  'view_image' => Icons.image_search_rounded,
  'view_profile_photo' => Icons.account_circle_outlined,
  'get_replied_message' => Icons.reply_all_rounded,
  'message_read_status' => Icons.done_all_rounded,
  'music_search' || 'music_album' => Icons.library_music_outlined,
  'music_artist' => Icons.mic_external_on_outlined,
  'movie_search' || 'movie_details' => Icons.movie_outlined,
  'tv_search' || 'tv_show' => Icons.live_tv_rounded,
  'reddit_posts' || 'reddit_search' || 'reddit_post' || 'reddit_subreddit' => Icons.reddit_rounded,
  'hn_stories' || 'hn_search' || 'hn_item' || 'hn_user' => Icons.whatshot_outlined,
  'bible_passage' || 'bible_chapter' || 'bible_compare' || 'bible_versions' || 'bible_books' || 'bible_verse_of_the_day' || 'bible_search' => Icons.menu_book_rounded,
  'finance_sync_sms' => Icons.sync_rounded,
  'call_history_summary' => Icons.insights_rounded,
  'call_history_person' => Icons.person_search_rounded,
  'call_history_calls' => Icons.call_outlined,
  'finance_update_patterns' => Icons.cloud_download_outlined,
  'finance_parse_sms' => Icons.sms_outlined,
  'finance_overview' || 'finance_accounts' => Icons.account_balance_wallet_outlined,
  'finance_add_account' || 'finance_update_account' || 'finance_delete_account' || 'finance_banks' => Icons.account_balance_outlined,
  'finance_transactions' || 'finance_add_transaction' || 'finance_update_transaction' || 'finance_delete_transaction' => Icons.receipt_long_outlined,
  'finance_summary' => Icons.insights_rounded,
  'finance_insights' => Icons.health_and_safety_outlined,
  'finance_budgets' || 'finance_set_budget' => Icons.savings_outlined,
  'finance_categories' || 'finance_categorize' => Icons.sell_outlined,
  'ebook_search' || 'ebook_details' || 'ebook_download' || 'book_search' => Icons.auto_stories_rounded,
  'audiobook_search' || 'audiobook_chapters' || 'audio_download' => Icons.headphones_rounded,
  'radio_search' => Icons.radio_rounded,
  'podcast_search' || 'podcast_top' || 'podcast_episodes' => Icons.podcasts_rounded,
  'play_audio' => Icons.play_circle_outline_rounded,
  'country_info' || 'countries_list' => Icons.public_rounded,
  'nasa_apod' => Icons.auto_awesome_rounded,
  'pokemon_search' || 'pokemon_info' => Icons.catching_pokemon,
  'paper_search' || 'paper_search_everywhere' || 'paper_details' => Icons.article_outlined,
  'paper_recommendations' => Icons.auto_awesome_motion_outlined,
  'paper_author' => Icons.person_search_outlined,
  'paper_venue' => Icons.account_balance_outlined,
  'screen_time' || 'app_usage' => Icons.hourglass_bottom_rounded,
  'system_check' => Icons.health_and_safety_outlined,
  'list_api_keys' || 'set_api_key' || 'delete_api_key' => Icons.key_outlined,
  'get_app_settings' => Icons.settings_outlined,
  'set_appearance' => Icons.palette_outlined,
  'set_preferences' => Icons.tune_rounded,
  'screen_status' => Icons.touch_app_outlined,
  'screen_read' => Icons.view_quilt_outlined,
  'screen_screenshot' => Icons.screenshot_monitor_rounded,
  'screen_wait' => Icons.hourglass_top_rounded,
  'screen_tap' => Icons.touch_app_rounded,
  'screen_type' => Icons.keyboard_rounded,
  'screen_scroll' => Icons.swipe_vertical_rounded,
  'screen_swipe' => Icons.swipe_rounded,
  'screen_press' => Icons.radio_button_checked_rounded,
  'list_hidden' || 'block_mute_settings' => Icons.shield_outlined,
  'block_chat' => Icons.block_rounded,
  'unblock_chat' => Icons.check_circle_outline_rounded,
  'mute_words' => Icons.volume_off_outlined,
  'unmute_words' => Icons.volume_up_outlined,
  'image_info' => Icons.photo_outlined,
  'image_resize' => Icons.photo_size_select_large_rounded,
  'image_crop' => Icons.crop_rounded,
  'image_compress' => Icons.compress_rounded,
  'image_convert' => Icons.transform_rounded,
  'image_remove_background' => Icons.auto_fix_high_rounded,
  'package_info' || 'package_search' => Icons.inventory_2_outlined,
  'domain_lookup' => Icons.dns_outlined,
  'xkcd' => Icons.draw_outlined,
  'metal_prices' => Icons.diamond_outlined,
  'fuel_prices' => Icons.local_gas_station_outlined,
  'earthquakes' => Icons.ssid_chart_rounded,
  'disasters' => Icons.warning_amber_rounded,
  'air_quality' => Icons.air_rounded,
  'recipe_search' || 'recipe_details' => Icons.restaurant_menu_rounded,
  'food_nutrition' => Icons.qr_code_scanner_rounded,
  'define_word' => Icons.menu_book_outlined,
  'translate_text' => Icons.translate_rounded,
  'wikipedia_search' || 'wikipedia_summary' => Icons.public_rounded,
  'wikipedia_on_this_day' => Icons.history_edu_rounded,
  'sports_scores' || 'sports_match' => Icons.scoreboard_outlined,
  'sports_standings' => Icons.leaderboard_rounded,
  'sports_team' => Icons.shield_outlined,
  'sports_player' => Icons.sports_handball_rounded,
  'sports_news' => Icons.newspaper_rounded,
  'sports_top_scorers' => Icons.sports_soccer_rounded,
  'formula1' => Icons.sports_motorsports_rounded,
  'crypto_prices' || 'crypto_coin' || 'crypto_trending' => Icons.currency_bitcoin_rounded,
  'stock_quote' || 'stock_search' => Icons.candlestick_chart_outlined,
  'currency_convert' => Icons.currency_exchange_rounded,
  'weather' => Icons.cloud_outlined,
  'flight_status' => Icons.flight_rounded,
  'flight_search' => Icons.travel_explore_rounded,
  'public_holidays' => Icons.celebration_outlined,
  'online_alert' || 'list_online_alerts' => Icons.circle_notifications_outlined,
  'canvas_export' => Icons.ios_share_rounded,
  'export_channel_summary' => Icons.insert_chart_outlined,
  'list_my_bots' || 'get_bot_profile' => Icons.smart_toy_outlined,
  'edit_bot' || 'botfather' => Icons.precision_manufacturing_outlined,
  'create_bot' => Icons.add_reaction_outlined,
  'connect_bot' => Icons.link_rounded,
  'bot_api' => Icons.api_rounded,
  'stream_bot_message' => Icons.stream_rounded,
  'send_rich_message' || 'edit_rich_message' => Icons.table_chart_outlined,
  'read_rich_message' => Icons.article_outlined,
  'list_channel_dms' || 'read_channel_dm' => Icons.forum_outlined,
  'reply_channel_dm' => Icons.reply_rounded,
  'set_channel_dms' => Icons.mark_chat_read_outlined,
  'set_member_tag' => Icons.label_outline_rounded,
  'list_welcome_messages' ||
  'set_welcome_message' => Icons.waving_hand_outlined,
  'delete_welcome_message' => Icons.delete_outline_rounded,
  'set_private_note' || 'get_private_note' => Icons.sticky_note_2_outlined,
  'get_profile_music' || 'add_profile_music' => Icons.library_music_outlined,
  'remove_profile_music' => Icons.music_off_outlined,
  'send_ephemeral_command' => Icons.visibility_outlined,
  'get_bot_commands' => Icons.terminal_rounded,
  'stop_bot_reply' => Icons.stop_circle_outlined,
  'get_stories' => Icons.amp_stories_outlined,
  'add_contact' => Icons.person_add_alt_1_outlined,
  'set_draft' => Icons.edit_note_rounded,
  'start_bot' => Icons.play_circle_outline_rounded,
  'get_chat_stats' || 'get_post_stats' => Icons.query_stats_rounded,
  'list_members' || 'get_member' => Icons.groups_outlined,
  'get_chat_permissions' || 'set_chat_permissions' => Icons.tune_rounded,
  'promote_member' => Icons.admin_panel_settings_outlined,
  'restrict_member' => Icons.voice_over_off_outlined,
  'edit_chat_info' => Icons.edit_outlined,
  'list_invite_links' || 'create_invite_link' => Icons.link_rounded,
  'list_join_requests' || 'answer_join_request' => Icons.how_to_reg_outlined,
  'get_admin_log' => Icons.history_rounded,
  'add_members' => Icons.group_add_outlined,
  'create_chat' => Icons.add_box_outlined,
  'join_chat' => Icons.login_rounded,
  'list_blocked' => Icons.block_rounded,
  'list_briefs' || 'read_brief' || 'write_brief' => Icons.wb_twilight_rounded,
  'canvas_overview' => Icons.dashboard_outlined,
  'download_message_file' => Icons.download_rounded,
  'transcribe_message' => Icons.hearing_rounded,
  'view_stickers_and_gifs' => Icons.emoji_emotions_outlined,
  'canvas_create_folder' ||
  'canvas_update_folder' => Icons.create_new_folder_outlined,
  'canvas_delete_folder' || 'canvas_remove' => Icons.folder_delete_outlined,
  'canvas_add' || 'canvas_move' => Icons.dashboard_customize_outlined,
  'canvas_add_note' => Icons.sticky_note_2_outlined,
  'translate_message' => Icons.translate_rounded,
  'delete_messages' ||
  'clear_chat_history' ||
  'delete_all_from_member' => Icons.delete_outline_rounded,
  'leave_chat' => Icons.logout_rounded,
  'delete_chat' => Icons.delete_forever_outlined,
  'block_user' => Icons.block_rounded,
  'remove_contact' => Icons.person_remove_outlined,
  'ban_member' => Icons.gavel_rounded,
  'mark_as_unread' => Icons.mark_chat_unread_outlined,
  'pin_chat' => Icons.push_pin_outlined,
  'add_chat_to_folder' => Icons.create_new_folder_outlined,
  'list_my_chats' => Icons.admin_panel_settings_outlined,
  'recently_joined_chats' => Icons.new_releases_outlined,
  'contact_joins' => Icons.person_add_alt_outlined,
  'get_bot_buttons' || 'press_bot_button' => Icons.smart_button_outlined,
  'list_backgrounds' ||
  'get_chat_background' ||
  'set_chat_background' => Icons.wallpaper_rounded,
  'save_gif' => Icons.bookmark_add_outlined,
  'list_sticker_sets' => Icons.collections_outlined,
  'get_sticker_set' => Icons.emoji_emotions_outlined,
  'list_favorite_stickers' => Icons.star_outline_rounded,
  'favorite_sticker' => Icons.star_rounded,
  'create_reminder' || 'update_reminder' => Icons.alarm_add_rounded,
  'list_reminders' => Icons.alarm_rounded,
  'delete_reminder' => Icons.alarm_off_rounded,
  'zip_files' => Icons.folder_zip_outlined,
  'fetch_url' => Icons.language_rounded,
  'http_request' => Icons.http_rounded,
  'submit_form' => Icons.dynamic_form_outlined,
  'download_file' => Icons.download_rounded,
  'browser_open' || 'browser_read' || 'browser_back' => Icons.public_rounded,
  'browser_type' => Icons.keyboard_alt_outlined,
  'browser_click' || 'browser_submit' => Icons.ads_click_rounded,
  'browser_run_js' => Icons.code_rounded,
  'get_star_balance' ||
  'list_star_transactions' ||
  'get_star_revenue' => Icons.account_balance_wallet_outlined,
  'send_star_reaction' || 'get_star_reactors' => Icons.star_rounded,
  'list_star_subscriptions' ||
  'set_star_subscription' => Icons.card_membership_rounded,
  'web_screenshot' => Icons.screenshot_monitor_rounded,
  'web_inspect' || 'web_run_async_js' => Icons.developer_mode_rounded,
  'run_code' => Icons.terminal_rounded,
  'github_repo' ||
  'github_list' ||
  'github_read' ||
  'github_search' ||
  'github_issues' ||
  'github_commits' ||
  'github_releases' ||
  'github_download' => Icons.code_rounded,
  'list_stories' ||
  'view_story' ||
  'story_viewers' ||
  'post_story' ||
  'edit_story' ||
  'delete_story' ||
  'react_to_story' => Icons.amp_stories_outlined,
  'get_folder' ||
  'create_folder' ||
  'edit_folder' ||
  'delete_folder' ||
  'reorder_folders' ||
  'suggested_folders' ||
  'share_folder' => Icons.folder_copy_outlined,
  'set_chat_settings' ||
  'set_chat_reactions' ||
  'manage_topic' ||
  'delete_topic' => Icons.settings_suggest_outlined,
  'get_boosts' => Icons.rocket_launch_outlined,
  'invite_link_joins' => Icons.link_rounded,
  'list_sessions' ||
  'end_session' ||
  'set_session_options' => Icons.devices_rounded,
  'get_privacy' || 'set_privacy' => Icons.privacy_tip_outlined,
  'get_profile' || 'edit_profile' => Icons.account_circle_outlined,
  'account_health' => Icons.health_and_safety_outlined,
  'open_telegram_link' => Icons.link_rounded,
  'search_all_chats' => Icons.manage_search_rounded,
  'inline_bot_query' || 'send_inline_result' => Icons.alternate_email_rounded,
  'list_message_effects' => Icons.celebration_outlined,
  'reactions_to_me' || 'mark_reactions_seen' => Icons.favorite_border_rounded,
  'video_chat' || 'manage_video_chat' => Icons.video_call_outlined,
  'storage_report' || 'clean_storage' => Icons.storage_rounded,
  'data_usage' => Icons.data_usage_rounded,
  'search_books' ||
  'book_details' ||
  'find_free_copy' => Icons.menu_book_rounded,
  'download_book' => Icons.download_for_offline_outlined,
  'youtube_search' ||
  'youtube_video' ||
  'youtube_transcript' ||
  'youtube_channel' ||
  'youtube_playlist' => Icons.smart_display_outlined,
  'x_post' || 'x_profile' => Icons.alternate_email_rounded,
  _ => appToolIcon(name) ?? deviceToolIcon(name) ?? Icons.build_outlined,
};

/// A few words on what a call is about: the chat, the query, the window.
String toolSubject(ToolPart part, TelegramStore store) {
  final a = part.args;
  final bits = <String>[];
  // Screen control says what the tap, typing or swipe is for.
  if (a['why'] case final String why when part.name.startsWith('screen_') && why.trim().isNotEmpty) {
    return a['text'] is String && part.name == 'screen_type' ? '${why.trim()}: "${a['text']}"' : why.trim();
  }
  for (final key in const ['chat_id', 'from_chat_id', 'to_chat_id']) {
    final id = a[key];
    if (id is num) bits.add(store.chat(id.toInt())?.title ?? 'chat $id');
  }
  if (a['to_chat_ids'] case final List ids when ids.isNotEmpty) {
    bits.add(
      ids.length == 1
          ? (store.chat((ids.first as num).toInt())?.title ?? 'a chat')
          : '${ids.length} chats',
    );
  }
  if (a['folder_id'] case final num f) {
    final name =
        store.folders.where((x) => x.id == f.toInt()).firstOrNull?.title ?? '';
    bits.add(name.isEmpty ? 'folder $f' : name);
  }
  if (a['query'] case final String q when q.isNotEmpty) bits.add('"$q"');
  if (a['url'] case final String u when u.isNotEmpty)
    bits.add(Uri.tryParse(u)?.host.isNotEmpty == true ? Uri.parse(u).host : u);
  if (a['prompt'] case final String p when p.isNotEmpty) bits.add(p);
  if (a['type'] case final String t when t != 'all') bits.add(t);
  if (a['since_hours'] case final num h)
    bits.add(h <= 24 ? 'last ${h.round()}h' : 'last ${(h / 24).round()}d');
  if (a['unread_only'] == true) bits.add('unread');
  return bits.join(' · ');
}

Map<String, dynamic>? _decode(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final v = jsonDecode(raw);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

String _summary(ToolPart part) {
  final j = _decode(part.result);
  if (j == null) return '';
  if (j['stopped'] == true) return 'Stopped';
  if (j['error'] != null) return 'Failed';
  if (j['sent'] == true) return j['forwarded'] != null ? 'Forwarded' : 'Sent';
  if (j['created'] == true) return 'Created';
  if (j['done'] == true) return 'Done';
  if (j['scheduled'] == true) return 'Scheduled';
  if (j['reminders'] is List)
    return '${(j['reminders'] as List).length} reminders';
  if (j['stars'] is num && j['transactions'] == null) return '${j['stars']} ⭐';
  if (j['status'] is num && j['url'] is String) return 'HTTP ${j['status']}';
  if (j['title'] is String && j['url'] is String)
    return '${j['title']}'.isEmpty ? 'Read' : '${j['title']}';
  if (j['scheduled'] is List)
    return '${(j['scheduled'] as List).length} scheduled';
  if (j['topics'] is List) return '${(j['topics'] as List).length} topics';
  if (j['count'] != null) return '${j['count']} messages';
  if (j['chats_read'] != null) return '${j['chats_read']} chats read';
  if (j['total_matching'] != null) return '${j['total_matching']} chats';
  if (j['total_chats'] != null) return '${j['total_chats']} chats';
  if (j['matching'] != null) return '${j['matching']} contacts';
  if (j['members'] is List) return '${(j['members'] as List).length} people';
  if (j['folders'] is List) return '${(j['folders'] as List).length} folders';
  if (j['chats'] is List) return '${(j['chats'] as List).length} chats';
  return '';
}

/// The store of the account [part] acts in, so a card names chats as that
/// account knows them.
TelegramStore _storeOfPart(WidgetRef ref, ToolPart part) {
  final accounts = ref.watch(accountsProvider);
  final id = accountOfCall(accounts, part.name, part.args);
  return id == null || accounts.byId(id)?.signedIn != true
      ? ref.watch(telegramStoreProvider)
      : ref.watch(accountStoreProvider(id));
}

class ToolCallCard extends ConsumerWidget {
  const ToolCallCard({super.key, required this.part});
  final ToolPart part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = _storeOfPart(ref, part);
    if (part.status == ToolStatus.awaitingApproval)
      return ApprovalCard(part: part);
    final tool = toolNamed(part.name);
    final subject = toolSubject(part, store);
    final summary = _summary(part);
    final (Widget status, Color tint) = switch (part.status) {
      ToolStatus.running => (
        const SizedBox.square(
          dimension: 13,
          child: CircularProgressIndicator(strokeWidth: 1.6),
        ),
        AppColors.text2,
      ),
      ToolStatus.done => (
        Icon(Icons.check_rounded, size: 15, color: AppColors.success),
        AppColors.text2,
      ),
      ToolStatus.error => (
        Icon(Icons.error_outline_rounded, size: 15, color: AppColors.danger),
        AppColors.danger,
      ),
      ToolStatus.denied => (
        Icon(Icons.block_rounded, size: 15, color: AppColors.text3),
        AppColors.text3,
      ),
      ToolStatus.awaitingApproval => (const SizedBox.shrink(), AppColors.text2),
    };
    // Generated images, screenshots and charts from code all show here.
    final decoded = part.result != null && part.result!.contains('"image_path"')
        ? _decode(part.result)
        : null;
    final image = decoded == null ? null : decoded['image_path'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.m),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.m),
              onTap: () => showToolDetails(context, part),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.m,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.m),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Icon(toolIcon(part.name), size: 16, color: AppColors.text2),
                    const SizedBox(width: Space.s + 2),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: part.status == ToolStatus.denied
                                  ? 'Declined: ${tool?.label ?? part.name}'
                                  : (tool?.label ?? part.name),
                              style: TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (subject.isNotEmpty)
                              TextSpan(
                                text: '  $subject',
                                style: TextStyle(color: AppColors.text3),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(width: Space.s),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: tint),
                        ),
                      ),
                    ],
                    if (part.name.startsWith('browser_'))
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => BrowserScreen.open(context),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Tooltip(
                            message: 'Watch the browser',
                            child: Icon(
                              Icons.open_in_new_rounded,
                              size: 15,
                              color: AppColors.text2,
                            ),
                          ),
                        ),
                      ),
                    if (part.autoApproved) ...[
                      const SizedBox(width: Space.s),
                      Tooltip(
                        message: 'Ran without asking (Settings → Approvals)',
                        child: Icon(
                          Icons.bolt_rounded,
                          size: 14,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                    const SizedBox(width: Space.s),
                    status,
                    if (part.status == ToolStatus.running &&
                        ref
                            .read(chatControllerProvider.notifier)
                            .canCancel(part))
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => ref
                            .read(chatControllerProvider.notifier)
                            .cancelTool(part),
                        child: Padding(
                          padding: EdgeInsets.only(left: Space.s),
                          child: Tooltip(
                            message: 'Stop',
                            child: Icon(
                              Icons.stop_circle_outlined,
                              size: 18,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // A download under way: what, how far, how fast.
          if (part.status == ToolStatus.running) DownloadPanel(callId: part.callId),
          if (part.status == ToolStatus.running && part.name == 'speed_test') SpeedTestPanel(id: part.callId),
          // Books, videos, posts, repos and pages get a card of their own;
          // other pictures (generated images, screenshots) show as they are.
          if (richResultFor(part) case final rich?)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: rich,
            )
          else if (image != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: GeneratedImage(path: image),
            ),
        ],
      ),
    );
  }
}

/// A message the assistant wants to send or forward, as an editable draft
/// waiting for the person's say-so.
class ApprovalCard extends ConsumerStatefulWidget {
  const ApprovalCard({super.key, required this.part});
  final ToolPart part;

  @override
  ConsumerState<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<ApprovalCard> {
  late final TextEditingController _text = TextEditingController(
    text: '${widget.part.args['text'] ?? ''}',
  );
  late final List<Attachment> _files = _initialFiles();
  late bool _asFiles = widget.part.args['send_as'] == 'file';
  bool _adding = false;
  List<td.Message>? _forwardPreview;

  bool get _forward => widget.part.name == 'forward_message';

  @override
  void initState() {
    super.initState();
    if (_forward) _loadForwardPreview();
  }

  Future<void> _loadForwardPreview() async {
    final from = widget.part.args['from_chat_id'];
    final ids = widget.part.args['message_ids'] as List? ?? const [];
    if (from is! num) return;
    final client = ref.read(telegramClientFamily(accountForCall(ref.read(accountsProvider), widget.part.args)));
    final messages = <td.Message>[];
    for (final id in ids) {
      if (id is! num) continue;
      try {
        messages.add(
          await client.send<td.Message>(
            td.GetMessage(chatId: from.toInt(), messageId: id.toInt()),
            limited: true,
          ),
        );
      } catch (_) {}
    }
    if (mounted) setState(() => _forwardPreview = messages);
  }

  /// A reaction, mute or mark-as-read: nothing to edit, just a yes or no.
  bool get _simple => !const {
    'forward_message',
    'send_message',
    'send_voice_message',
    'comment_on_post',
    'schedule_message',
    'reply_to_message',
  }.contains(widget.part.name);

  /// The files the assistant named, matched to what this conversation has.
  List<Attachment> _initialFiles() {
    final named = [
      for (final f in (widget.part.args['files'] as List? ?? const [])) '$f',
    ];
    if (named.isEmpty) return [];
    final available = ref.read(chatControllerProvider.notifier).sendableFiles();
    return [
      for (final n in named)
        ?available
            .where((a) => a.name == n || a.path == n || a.path.endsWith(n))
            .firstOrNull,
    ];
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add(Future<List<(String, String?)>> Function() pick) async {
    setState(() => _adding = true);
    try {
      for (final (path, name) in await pick()) {
        final a = await ChatController.attach(path, name: name);
        if (mounted) setState(() => _files.add(a));
      }
    } catch (e) {
      if (mounted)
        showSnack(
          context,
          'Couldn\'t attach: $e',
          icon: Icons.error_outline_rounded,
        );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Asks where the rule applies, saves it, then approves this call.
  Future<void> _alwaysAllow({
    required TelegramTool tool,
    required int? chatId,
    required String? chatTitle,
    required String? account,
    required VoidCallback approve,
  }) async {
    final where = chatTitle?.trim().isNotEmpty == true ? chatTitle! : 'chat $chatId';
    final anywhere = await showFormSheet<bool>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Always allow ${tool.label.toLowerCase()}?', style: context.text.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Matching calls will run without a card, in chats and in watches. Remove the rule any time under '
            'Settings → Approvals.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.l),
          if (chatId != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: Text('Only in $where'),
              subtitle: const Text('Also when a watch has just read messages from others'),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.public_rounded),
            title: const Text('Anywhere'),
            subtitle: const Text('Still asks after reading messages from others, since they could aim it elsewhere'),
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (anywhere == null || !mounted) return;
    await ref.read(approvalRulesProvider.notifier).add(
      tool: tool.name,
      toolLabel: tool.label,
      chatId: anywhere ? null : chatId,
      chatTitle: anywhere ? null : chatTitle,
      account: account,
    );
    if (!mounted) return;
    approve();
    showSnack(context, 'Rule saved: ${tool.label.toLowerCase()} ${anywhere ? 'anywhere' : 'in $where'}', icon: Icons.rule_rounded);
  }

  static Future<List<(String, String?)>> _pickMedia() async {
    final picked = await ImagePicker().pickMultipleMedia(imageQuality: 90);
    return [for (final x in picked) (x.path, x.name)];
  }

  static Future<List<(String, String?)>> _pickFiles() async {
    final files = await FilePicker.pickFiles();
    return [
      for (final f in files)
        if (f.path != null) (f.path!, f.name),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    final args = part.args;
    // The account the call acts in: what the card describes, and who it
    // comes from when several accounts are signed in.
    final accounts = ref.watch(accountsProvider);
    final accountId = accountForCall(accounts, args);
    final account = accounts.forAi.length > 1 ? accounts.byId(accountId) : null;
    final runner = ref.watch(toolRunnerFamily(accountId));
    final store = ref.watch(accountStoreProvider(accountId));
    final controller = ref.read(chatControllerProvider.notifier);
    final fromId = args['from_chat_id'];
    final ids = (args['message_ids'] as List? ?? const []);
    final canSend =
        _forward ||
        _simple ||
        _text.text.trim().isNotEmpty ||
        _files.isNotEmpty;

    final danger = toolNamed(widget.part.name)?.destructive ?? false;
    final tone = danger ? AppColors.danger : AppColors.warning;
    void approveNow() => _forward || _simple
        ? controller.approve(part.callId)
        : controller.approve(
            part.callId,
            text: _text.text.trim(),
            files: [..._files],
            asFiles: _asFiles,
          );
    // Deleting and spending always ask, so they get no standing rules.
    final tool = toolNamed(part.name);
    final ruleable = tool != null && !tool.destructive && !tool.alwaysAsk;
    final chats = chatsOfCall(args);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: danger
            ? AppColors.danger.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: tone.withValues(alpha: danger ? 0.8 : 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                danger ? Icons.warning_amber_rounded : Icons.shield_outlined,
                size: 16,
                color: tone,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  danger
                      ? 'Destructive action: approve?'
                      : _simple
                      ? 'Approve this?'
                      : (_forward ? 'Approve forwarding?' : 'Approve sending?'),
                  style: context.text.titleSmall,
                ),
              ),
              if (!_forward && !_simple)
                Text('You can edit this', style: context.text.labelSmall),
            ],
          ),
          if (controller.heldForSafety(part.callId)) ...[
            const SizedBox(height: Space.s),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.m),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.policy_outlined, size: 16, color: AppColors.warning),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      'This would normally run on its own, but the assistant has just read messages, emails or pages '
                      'written by other people, which can contain hidden instructions. Check that you want this.',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (controller.heldForVault(part.callId) case final shared when shared.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.m),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      'This shares ${shared.length == 1 ? 'something' : '${shared.length} things'} from your vault: '
                      '${shared.join(', ')}. Make sure you want ${shared.length == 1 ? 'it' : 'them'} to go out.',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.m),
          if (account != null) ...[
            Text('As', style: context.text.labelSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                AccountAvatar(account: account, size: 20),
                const SizedBox(width: Space.s),
                Expanded(child: Text(account.label, style: context.text.bodyMedium)),
              ],
            ),
            const SizedBox(height: Space.m),
          ],
          if (_simple)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.m),
              ),
              child: Text(
                runner.describeAction(part.name, args),
                style: context.text.bodyMedium,
              ),
            )
          else ...[
            Text('To', style: context.text.labelSmall),
            const SizedBox(height: 2),
            Text(
              runner.describeTarget(args, tool: part.name),
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: Space.m),
          ],
          if (_simple)
            const SizedBox.shrink()
          else if (_forward)
            _ForwardPostPreview(
              messages: _forwardPreview,
              count: ids.length,
              source: fromId is num ? store.chat(fromId.toInt()) : null,
              copied:
                  args['hide_sender'] == true || args['remove_caption'] == true,
              captionsRemoved: args['remove_caption'] == true,
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.m),
              ),
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_files.isNotEmpty || _adding)
                    SizedBox(
                      height: 72,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                        children: [
                          for (final a in _files)
                            _DraftFile(
                              attachment: a,
                              onRemove: () => setState(() => _files.remove(a)),
                            ),
                          if (_adding)
                            const Padding(
                              padding: EdgeInsets.all(Space.m),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 8,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.sentences,
                    style: context.text.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: _files.isEmpty
                          ? 'Message'
                          : 'Caption (optional)',
                      contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Add photos or videos',
                        icon: Icon(
                          Icons.photo_library_outlined,
                          size: 20,
                          color: AppColors.text2,
                        ),
                        onPressed: _adding ? null : () => _add(_pickMedia),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Add files',
                        icon: Icon(
                          Icons.attach_file_rounded,
                          size: 20,
                          color: AppColors.text2,
                        ),
                        onPressed: _adding ? null : () => _add(_pickFiles),
                      ),
                      const Spacer(),
                      if (_files.any((a) => a.isImage || a.isVideo))
                        Padding(
                          padding: const EdgeInsets.only(right: Space.s),
                          child: FilterChip(
                            visualDensity: VisualDensity.compact,
                            tooltip: _asFiles
                                ? 'Sent uncompressed, as files'
                                : 'Sent compressed, shown in the chat',
                            label: Text(
                              _asFiles ? 'As files' : 'Compressed',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _asFiles,
                            onSelected: (v) => setState(() => _asFiles = v),
                          ),
                        ),
                      if (_files.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: Space.s),
                          child: Text(
                            '${_files.length} attached',
                            style: context.text.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (args['reply_to_message_id'] != null) ...[
            const SizedBox(height: Space.s),
            Text(
              'As a reply to message ${args['reply_to_message_id']}',
              style: context.text.bodySmall,
            ),
          ],
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: AppColors.text,
                    side: BorderSide(color: AppColors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.m),
                    ),
                  ),
                  onPressed: () => controller.deny(part.callId),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: danger ? AppColors.danger : null,
                    foregroundColor: danger ? Colors.white : null,
                  ),
                  onPressed: !canSend || _adding ? null : approveNow,
                  child: Text(
                    _simple ? 'Approve' : (_forward ? 'Forward' : 'Send'),
                  ),
                ),
              ),
            ],
          ),
          if (ruleable)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text2),
                icon: const Icon(Icons.rule_rounded, size: 16),
                label: const Text('Always allow…'),
                onPressed: !canSend || _adding
                    ? null
                    : () => _alwaysAllow(
                        tool: tool,
                        chatId: chats.length == 1 ? chats.first : null,
                        chatTitle: chats.length == 1 ? store.chat(chats.first)?.title : null,
                        account: accounts.hasSeveral ? accountId : null,
                        approve: approveNow,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ForwardPostPreview extends StatelessWidget {
  const _ForwardPostPreview({
    required this.messages,
    required this.count,
    required this.source,
    required this.copied,
    required this.captionsRemoved,
  });
  final List<td.Message>? messages;
  final int count;
  final ChatInfo? source;
  final bool copied;
  final bool captionsRemoved;

  @override
  Widget build(BuildContext context) {
    final loaded = messages;
    if (loaded == null)
      return const Padding(
        padding: EdgeInsets.all(Space.m),
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    if (loaded.isEmpty)
      return Text(
        '$count message${count == 1 ? '' : 's'} from ${source?.title ?? 'a channel'}',
        style: context.text.bodyMedium,
      );
    final kind = source == null
        ? ChatKind.channel
        : (source!.type is td.ChatTypeSupergroup ||
                  source!.type is td.ChatTypeBasicGroup
              ? ChatKind.group
              : ChatKind.channel);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.s),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'POST${loaded.length == 1 ? '' : 'S'} FROM ${(source?.title ?? 'Channel').toUpperCase()}',
            style: context.text.labelSmall,
          ),
          const SizedBox(height: Space.s),
          for (final message in loaded)
            MessageTile(
              message: message,
              kind: kind,
              chatTitle: source?.title ?? 'Channel',
            ),
          if (copied || captionsRemoved)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(
                captionsRemoved ? 'Captions removed' : 'Forwarded as a copy',
                style: context.text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _DraftFile extends StatelessWidget {
  const _DraftFile({required this.attachment, required this.onRemove});
  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final video = a.mime.startsWith('video/');
    return Padding(
      padding: const EdgeInsets.only(right: Space.s),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.s),
            child: a.isImage && File(a.path).existsSync()
                ? Image.file(
                    File(a.path),
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: video ? 58 : 140,
                    height: 58,
                    color: AppColors.surface3,
                    padding: const EdgeInsets.symmetric(horizontal: Space.s),
                    child: video
                        ? Icon(
                            Icons.play_circle_outline_rounded,
                            color: AppColors.text2,
                          )
                        : Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 18,
                                color: AppColors.text2,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  a.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.text,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded, size: 13, color: AppColors.bg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pictures a tool handed back, large enough to see; tap for full screen.
class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final files = [
      for (final p in paths)
        if (File(p).existsSync()) p,
    ];
    if (files.isEmpty) {
      return Text(
        'The images are no longer on this phone.',
        style: context.text.bodySmall,
      );
    }
    Widget tile(String p, {double? height}) => GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              title: Text(p.split(RegExp(r'[\\/]')).last),
            ),
            body: Center(
              child: InteractiveViewer(maxScale: 6, child: Image.file(File(p))),
            ),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.m),
        child: Image.file(
          File(p),
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            height: height ?? 160,
            color: AppColors.surface2,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image_outlined, color: AppColors.text3),
          ),
        ),
      ),
    );
    if (files.length == 1) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Center(child: tile(files.single)),
      );
    }
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.s),
        itemBuilder: (_, i) =>
            SizedBox(width: 180, child: tile(files[i], height: 180)),
      ),
    );
  }
}

Future<void> showToolDetails(BuildContext context, ToolPart part) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (context, scroll) => _ToolDetails(part: part, scroll: scroll),
    ),
  );
}

class _ToolDetails extends ConsumerStatefulWidget {
  const _ToolDetails({required this.part, required this.scroll});
  final ToolPart part;
  final ScrollController scroll;

  @override
  ConsumerState<_ToolDetails> createState() => _ToolDetailsState();
}

class _ToolDetailsState extends ConsumerState<_ToolDetails> {
  bool _raw = false;
  final _argsTree = JsonTreeController();
  final _resultTree = JsonTreeController();
  final _fullTree = JsonTreeController();

  @override
  void dispose() {
    _argsTree.dispose();
    _resultTree.dispose();
    _fullTree.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    final store = _storeOfPart(ref, part);
    // The part changes as the tool runs; the controller says when.
    ref.watch(chatControllerProvider.select((s) => s.revision));
    final controller = ref.read(chatControllerProvider.notifier);
    final tool = toolNamed(part.name);
    final result = _decode(part.result);
    final args = part.args;
    final (status, color) = switch (part.status) {
      ToolStatus.running => ('Running', AppColors.accent),
      ToolStatus.awaitingApproval => (
        'Waiting for approval',
        AppColors.warning,
      ),
      ToolStatus.denied => ('Declined by you', AppColors.text3),
      ToolStatus.done => ('Done', AppColors.success),
      ToolStatus.error => ('Failed', AppColors.danger),
    };

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Space.s),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.s),
              ),
              child: Icon(
                toolIcon(part.name),
                size: 18,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool?.label ?? part.name,
                    style: context.text.titleMedium,
                  ),
                  Text(
                    part.name,
                    style: context.text.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            _Pill(status, color: color),
            if (part.durationMs != null)
              _Pill('${(part.durationMs! / 1000).toStringAsFixed(2)} s'),
            if (tool != null) _Pill(tool.cost.label),
            if (part.autoApproved)
              _Pill('Ran without asking', color: AppColors.warning)
            else if (tool?.requiresApproval ?? false)
              const _Pill('Needs approval'),
            _Pill(TimeOfDay.fromDateTime(part.startedAt).format(context)),
          ],
        ),
        if (part.status == ToolStatus.running &&
            controller.canCancel(part)) ...[
          const SizedBox(height: Space.l),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => controller.cancelTool(part),
            icon: const Icon(Icons.stop_rounded),
            label: Text(switch (part.name) {
              'run_code' => 'Stop the code',
              final n
                  when n.startsWith('browser_') ||
                      n.startsWith('web_') ||
                      n == 'fetch_url' =>
                'Stop browsing',
              _ => 'Stop',
            }),
          ),
        ] else if (part.status == ToolStatus.awaitingApproval) ...[
          const SizedBox(height: Space.l),
          OutlinedButton.icon(
            onPressed: () {
              controller.deny(part.callId);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.block_rounded),
            label: const Text('Decline'),
          ),
        ],
        if (hasToolControls(part)) ToolControls(part: part, result: result),
        const SizedBox(height: Space.l),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Details'),
              icon: Icon(Icons.view_agenda_outlined, size: 16),
            ),
            ButtonSegment(
              value: true,
              label: Text('Raw JSON'),
              icon: Icon(Icons.data_object_rounded, size: 16),
            ),
          ],
          selected: {_raw},
          onSelectionChanged: (v) => setState(() => _raw = v.first),
        ),
        if (!_raw) ...[
          // Pictures the tool looked at (view_image, profile photos…).
          if (result case {'_images': final List images}
              when images.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Text('IMAGES', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            _ImageStrip(paths: [for (final p in images) '$p']),
          ],
          if (args.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Text('ASKED FOR', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final e in args.entries)
                  _ArgChip(name: e.key, value: e.value, store: store),
              ],
            ),
          ],
          const SizedBox(height: Space.xl),
          Text('RESULT', style: context.text.labelSmall),
          const SizedBox(height: Space.xs),
          if (result == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.m),
              child: Text(
                part.status == ToolStatus.running
                    ? 'Still running…'
                    : 'No result.',
                style: context.text.bodySmall,
              ),
            )
          else
            ToolResultView(name: part.name, json: result),
          if (part.full != null) ...[
            const SizedBox(height: Space.s),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: Text('FULL RESPONSE', style: context.text.labelSmall),
                subtitle: Text(
                  'Everything the app returned. The assistant got the shorter version above.',
                  style: context.text.bodySmall,
                ),
                children: [
                  _RawSection(
                    title: 'Full response',
                    raw: part.full!,
                    controller: _fullTree,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.xl),
          Text('ABOUT THIS CALL', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          if (tool != null) ...[
            Text(
              tool.description,
              style: context.text.bodySmall?.copyWith(height: 1.4),
            ),
            const SizedBox(height: Space.m),
          ],
          _InfoRow('Tool', part.name),
          if (tool != null) _InfoRow('Category', tool.category.label),
          if (tool != null)
            _InfoRow('Runs on', '${tool.cost.label}: ${tool.cost.explanation}'),
          _InfoRow(
            'Started',
            DateFormat('EEE d MMM y, HH:mm:ss').format(part.startedAt),
          ),
          if (part.durationMs != null) ...[
            _InfoRow(
              'Finished',
              DateFormat('HH:mm:ss.SSS').format(
                part.startedAt.add(Duration(milliseconds: part.durationMs!)),
              ),
            ),
            _InfoRow('Took', '${part.durationMs} ms'),
          ],
          _InfoRow(
            'Approval',
            part.autoApproved
                ? 'Ran without asking (approval setting)'
                : (tool?.requiresApproval ?? false)
                ? (part.status == ToolStatus.denied
                      ? 'You declined it'
                      : 'Asked you first')
                : (tool?.modifiesData ?? false)
                ? 'Not needed for this tool'
                : 'Not needed (read-only)',
          ),
          if (tool != null) _InfoRow('Access', tool.access.label),
          _InfoRow(
            'Arguments',
            '${args.length} · ${part.arguments.length} characters',
          ),
          if (part.result != null)
            _InfoRow(
              'Result size',
              '${part.result!.length} characters (≈${(part.result!.length / 4).round()} tokens sent back to the model)',
            ),
          if (part.full != null)
            _InfoRow(
              'Full response',
              '${part.full!.length} characters, kept on this phone only',
            ),
          if (result case {'error': final err?}) _InfoRow('Error', '$err'),
          _InfoRow('Call ID', part.callId),
        ] else ...[
          _RawSection(
            title: 'Arguments',
            raw: part.arguments.isEmpty ? '{}' : part.arguments,
            controller: _argsTree,
          ),
          if (part.full != null)
            _RawSection(
              title: 'Full response',
              raw: part.full!,
              controller: _fullTree,
            ),
          _RawSection(
            title: part.full != null ? 'Sent to the model' : 'Result',
            raw: part.result ?? 'null',
            controller: _resultTree,
          ),
        ],
      ],
    );
  }
}

class _ArgChip extends StatelessWidget {
  const _ArgChip({
    required this.name,
    required this.value,
    required this.store,
  });
  final String name;
  final Object? value;
  final TelegramStore store;

  @override
  Widget build(BuildContext context) {
    var shown = value is List ? (value as List).join(', ') : '$value';
    if (name.endsWith('chat_id') && value is num) {
      final title = store.chat((value as num).toInt())?.title;
      if (title != null) shown = title;
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.s),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${name.replaceAll('_', ' ')}  ',
              style: TextStyle(color: AppColors.text3),
            ),
            TextSpan(
              text: shown,
              style: TextStyle(color: AppColors.text),
            ),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {Color? color}) : _color = color;
  final String text;
  final Color? _color;
  Color get color => _color ?? AppColors.text2;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: color)),
  );
}

class _RawSection extends StatefulWidget {
  const _RawSection({
    required this.title,
    required this.raw,
    required this.controller,
    this.compact = false,
  });
  final String title;
  final String raw;
  final JsonTreeController controller;

  /// Inside another section: less space above.
  final bool compact;

  @override
  State<_RawSection> createState() => _RawSectionState();
}

class _RawSectionState extends State<_RawSection> {
  bool _tree = true;

  Object? get _parsed {
    try {
      return jsonDecode(widget.raw);
    } catch (_) {
      return null;
    }
  }

  String get _pretty {
    final p = _parsed;
    return p == null
        ? widget.raw
        : const JsonEncoder.withIndent('  ').convert(p);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return Padding(
      padding: EdgeInsets.only(top: widget.compact ? 0 : Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!widget.compact)
                Text(
                  widget.title.toUpperCase(),
                  style: context.text.labelSmall,
                ),
              const Spacer(),
              if (parsed is Map || parsed is List) ...[
                _Mini(
                  icon: Icons.unfold_more_rounded,
                  tip: 'Expand all',
                  onTap: () => setState(() {
                    _tree = true;
                    widget.controller.expandAll();
                  }),
                ),
                _Mini(
                  icon: Icons.unfold_less_rounded,
                  tip: 'Collapse all',
                  onTap: () => setState(() {
                    _tree = true;
                    widget.controller.collapseAll();
                  }),
                ),
                _Mini(
                  icon: _tree
                      ? Icons.notes_rounded
                      : Icons.account_tree_outlined,
                  tip: _tree ? 'Plain text' : 'Tree',
                  onTap: () => setState(() => _tree = !_tree),
                ),
              ],
              _Mini(
                icon: Icons.copy_rounded,
                tip: 'Copy',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _pretty));
                  showSnack(context, '${widget.title} copied');
                },
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(Radii.m),
              border: Border.all(color: AppColors.line),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: (parsed is Map || parsed is List) && _tree
                  ? JsonTree(data: parsed, controller: widget.controller)
                  : SelectableText(
                      _pretty.length > 30000
                          ? '${_pretty.substring(0, 30000)}\n…'
                          : _pretty,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.text2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.tip, required this.onTap});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 17, color: AppColors.text3),
    onPressed: onTap,
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: AppColors.text3),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(fontSize: 13, color: AppColors.text),
          ),
        ),
      ],
    ),
  );
}

/// A download's live progress under its tool card: the file, a bar, how
/// much of how much, the speed and the time left. Nothing when the call
/// isn't downloading.
class DownloadPanel extends StatelessWidget {
  const DownloadPanel({super.key, required this.callId});
  final String callId;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, DownloadState>>(
    valueListenable: DownloadProgress.all,
    builder: (context, all, _) {
      final d = all[callId];
      if (d == null) return const SizedBox.shrink();
      final f = d.fraction;
      final left = d.secondsLeft;
      final ext = d.files > 1 ? '${d.files}' : (d.name.contains('.') ? d.name.split('.').last.toUpperCase() : 'FILE');
      final control = DownloadProgress.of(callId);
      final status = d.cancelled
          ? 'Cancelled at ${formatBytes(d.received)}'
          : d.error != null
          ? 'Failed: ${d.error}'
          : d.done
          ? '${d.upload ? 'Sent' : 'Saved'} · ${formatBytes(d.received)} in ${formatSeconds(d.elapsed.inSeconds.clamp(1, 1 << 30))}'
          : [
              if (d.paused) 'Paused',
              d.total == null ? '${formatBytes(d.received)} so far' : '${formatBytes(d.received)} of ${formatBytes(d.total!)}',
              if (!d.paused && d.bytesPerSecond > 0) '${formatBytes(d.bytesPerSecond)}/s',
              if (left != null) '${formatSeconds(left)} left',
            ].join(' · ');
      Widget button(IconData icon, String tip, VoidCallback onTap, {bool filled = false}) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: filled ? AppColors.text : AppColors.surface2,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Tooltip(
              message: tip,
              child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 18, color: filled ? AppColors.bg : AppColors.text)),
            ),
          ),
        ),
      );
      return Container(
        margin: const EdgeInsets.only(top: Space.s),
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
                  child: d.upload && d.files > 1
                      ? Icon(Icons.upload_rounded, size: 20, color: AppColors.text2)
                      : Text(ext.length > 4 ? ext.substring(0, 4) : ext, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.text2, letterSpacing: 0.4)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.upload && d.active ? 'Sending ${d.name}' : d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(color: d.error != null ? AppColors.danger : AppColors.text2, fontFeatures: tabularFigures),
                      ),
                    ],
                  ),
                ),
                if (f != null && d.active) Text('${(f * 100).round()}%', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                if (d.active && control != null && d.canPause)
                  d.paused
                      ? button(Icons.play_arrow_rounded, 'Resume', control.resume, filled: true)
                      : button(Icons.pause_rounded, 'Pause', control.pause),
                if (d.active && control != null && d.canCancel) button(Icons.close_rounded, d.upload ? 'Cancel sending' : 'Cancel download', control.cancel),
                if (d.done) Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                if (d.cancelled) Icon(Icons.cancel_outlined, color: AppColors.text3, size: 20),
              ],
            ),
            const SizedBox(height: Space.s + 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                // Unknown size: an indeterminate bar.
                // Paused or stopped: hold still where it got to.
                value: d.done ? 1 : (f ?? (d.paused || !d.active ? 0 : null)),
                minHeight: 6,
                color: d.error != null ? AppColors.danger : (d.done ? AppColors.success : (d.paused || d.cancelled ? AppColors.text3 : AppColors.text)),
                backgroundColor: AppColors.surface3,
              ),
            ),
            if (d.url != null) ...[
              const SizedBox(height: 6),
              Text(Uri.tryParse(d.url!)?.host ?? d.url!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ],
          ],
        ),
      );
    },
  );
}
