import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../infrastructure/telegram/accounts.dart';
import '../../ai/data/ai.dart';
import '../../ai/data/decision_settings.dart';
import '../../assistant/activity_log.dart';
import '../../assistant/approval_rules.dart';
import '../../assistant/default_assistant.dart';
import '../../assistant/memory.dart';
import '../../assistant/online_alerts.dart';
import '../../assistant/reminders.dart';
import '../../assistant/watches.dart';
import '../../finance/finance_store.dart';
import '../../library/library_favorites.dart';
import '../../routines/routines.dart';
import '../../telegram/data/content_filters.dart';
import '../../telegram/data/telegram_store.dart' show telegramStoreFamily;
import '../../usage/spend_limits.dart';
import '../../vault/vault.dart';
import '../../brief/brief_prefs.dart';
import '../../brief/brief_store.dart';
import '../../brief/brief_widget.dart';
import '../../brief/home_widgets.dart';
import '../../canvas/canvas_store.dart';
import '../../chat/data/chat_controller.dart';
import '../../integrations/integrations_store.dart';
import '../../usage/usage.dart';
import '../../bible/bible.dart' show bibleSettingsProvider;
import '../../calls/vapi.dart' show VapiStore;
import '../../components/components.dart' show componentPrefsProvider;
import '../../custom_folders/custom_folders.dart' show customFoldersProvider;
import '../../books/books.dart' show BooksStore, booksProvider, bookFeedProvider;
import '../../gallery/gallery.dart' show GalleryStore, galleryProvider, galleryFeedProvider;
import '../../marketplace/market.dart' show MarketStore, marketProvider, marketFeedProvider;
import '../../media/music_stats.dart' show MusicStatsStore, musicStatsProvider;
import '../../podcasts/podcast_store.dart' show podcastsProvider;
import '../../podcasts/radio_store.dart' show radioProvider;
import '../../gallery/gallery_search.dart' show galleryIndexProvider;
import '../../sections/activity_stats.dart' show activityStatsProvider;
import '../../movies/movies.dart' show MoviesStore, moviesProvider, videoFeedProvider;
import '../../opportunity/opportunity.dart' show opportunityProvider, oppFeedProvider;
import '../../playlists/playlists.dart' show playlistsProvider;
import '../../development/mongo_session.dart';
import '../../info/info_keys.dart';
import '../../integrations/mcp_permissions.dart' show mcpPermissionsProvider;
import 'settings.dart';

/// What the app keeps on this phone, besides Telegram's own database: one
/// place to back it up, bring it back and wipe it.
abstract final class AppData {
  static const format = 'triangle-profile';
  /// 2 added MCP servers without their headers, for exports without keys.
  /// 3 moved the vault out of the keys into its own part, and maps
  /// Telegram accounts onto the ones signed in where it is restored.
  static const version = 3;

  /// When a profile was last exported (Settings → System check).
  static const lastBackupKey = 'last_backup_at';

  /// Where omni_ai keeps installed MCP servers (secure storage, with their
  /// headers), and the plain copy a keyless profile restores into.
  static const _mcpKey = 'omni_ai.mcp.servers';

  /// Telegram's database keys (one per account) never leave the phone: with
  /// one, a copy of the session could be opened elsewhere. The app lock's
  /// passcode hash stays too: a short passcode's hash can be guessed from a
  /// file, and the lock belongs to this phone.
  static bool _neverExported(String key) => key.startsWith('tdlib_database_key') || key == _lockHashKey;

  static const _lockHashKey = 'app_lock.hash';

  /// Where the vault keeps its items (secure storage). Exported in its own
  /// part, with [export]'s `vault`, not with the keys.
  static const _vaultKey = 'vault.v1';

  /// Settings that belong to this phone and are never restored over it:
  /// the app lock (a profile would turn it off), and the Telegram account
  /// list (sign-ins stay as they are; their assistant settings are mapped
  /// onto the accounts signed in here instead).
  static bool _devicePref(String key) =>
      key.startsWith('app_lock_') || key == _accountsKey || key == _activeAccountKey;

  static const _accountsKey = 'tg_accounts';
  static const _activeAccountKey = 'tg_active_account';

  /// Settings that hold Telegram account ids, remapped on restore.
  static const _accountPrefs = ['watches.v1', 'reminders.v1', 'brief_prefs.v1', 'approval_rules.v1', _customFoldersKey, ..._sectionKeys];

  /// Playlists and the sections built from chats (Marketplace, Movies,
  /// Books, Gallery, Opportunities): their sources and tracks name their
  /// account as `a` (books as `ac`), and their items' keys start with it.
  static const _sectionKeys = ['playlists.v1', MarketStore.key, MarketStore.listingsKey, MoviesStore.key, BooksStore.key, BooksStore.notesKey, GalleryStore.key, _opportunityKey, _opportunityReadKey, MusicStatsStore.key];

  /// Explore's own files: podcast subscriptions and progress (Telegram shows
  /// as `tg:<account>:<chat>`), radio stations, and the gallery's search
  /// index (by item key). Backed up and restored, but not wiped by
  /// [clearAll], which is about the assistant's data.
  static const _exploreFiles = ['podcasts.json', 'radio.json', 'gallery_index.json'];

  /// Explore files that name Telegram accounts, remapped like [_sectionKeys].
  static const _accountFiles = ['podcasts.json', 'gallery_index.json'];

  /// Whether the setting or file [key] keeps Telegram account ids in its
  /// items (`a`, `ac`) and keys (`account:chat[:message]`).
  static bool _keepsAccounts(String key) => _sectionKeys.contains(key) || _accountFiles.contains(key) || key == _briefPrefsKey || _isStatsKey(key);

  /// Explore's time stats (`activity_stats.video` and the like): their
  /// items are keyed `account:chat:message`.
  static bool _isStatsKey(String key) => key.startsWith(_statsPrefix);
  static const _statsPrefix = 'activity_stats.';

  /// Brief settings: left-out folders are keyed `account:folder`.
  static const _briefPrefsKey = 'brief_prefs.v1';

  /// Opportunities' sources and saved posts, and what it has read of them.
  static const _opportunityKey = 'opportunity.v1';
  static const _opportunityReadKey = 'opportunity_read.v1';

  /// Pictures a profile carries (small ones): playlist covers and book
  /// covers, by their path under the app's folder.
  static const _mediaFolders = ['playlist_covers', 'books'];

  /// My folders: each chat in one names its account as `a`.
  static const _customFoldersKey = 'custom_folders.v1';

  /// Files under the app's folder that belong in a profile.
  static const _profileFiles = ['content_canvas.json', 'usage.json', 'finance.json'];

  /// Folders of things the assistant made, saved or downloaded.
  static const _dataFolders = [
    'conversations',
    'generated',
    'attachments',
    'viewed_images',
    'voice_notes',
    'screenshots',
    'downloads',
    'telegram',
    'exports',
    'mail',
    'sandbox',
    'briefs',
    'widgets',
  ];

  static Future<String> _root() async => (await getApplicationSupportDirectory()).path;

  /// Everything needed to carry on after reinstalling: settings (appearance,
  /// decisions, home-screen widgets and their look), memories, instructions,
  /// watches and the check-in, routines, reminders, brief settings,
  /// approval rules, spend limits, Block & mute, installed skills, the
  /// Content Canvas, money (accounts, transactions, budgets), the activity
  /// log, usage, each Telegram account's assistant settings, MCP servers,
  /// and (when [keys]) API keys, bot tokens and MCP headers. [vault] adds
  /// the vault's items, [chats] the AI conversations. Widget pictures
  /// aren't copied: they're fetched again from their links.
  static Future<Map<String, dynamic>> export({bool keys = true, bool chats = false, bool vault = true, bool media = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final root = await _root();
    final files = <String, String>{};
    for (final name in [..._profileFiles, ..._exploreFiles]) {
      final f = File('$root/$name');
      if (await f.exists()) files[name] = await f.readAsString();
    }
    if (chats) {
      final dir = Directory('$root/conversations');
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is File && e.path.endsWith('.json')) {
            files['conversations/${e.uri.pathSegments.last}'] = await e.readAsString();
          }
        }
      }
    }
    final secrets = await const FlutterSecureStorage().readAll();
    final vaultRaw = secrets[_vaultKey];
    // Covers: playlist pictures, and each book's cover.jpg (not the books).
    final pictures = <String, String>{};
    if (media) {
      for (final folder in _mediaFolders) {
        final dir = Directory('$root/$folder');
        if (!await dir.exists()) continue;
        await for (final e in dir.list(recursive: true)) {
          if (e is! File) continue;
          final rel = e.path.substring(root.length + 1).replaceAll('\\', '/');
          final isCover = folder == 'playlist_covers' || rel.endsWith('/cover.jpg');
          if (!isCover || await e.length() > 2 << 20) continue;
          pictures[rel] = base64Encode(await e.readAsBytes());
        }
      }
    }
    return {
      'root': root,
      if (pictures.isNotEmpty) 'media': pictures,
      'format': format,
      'version': version,
      'exported_at': DateTime.now().toIso8601String(),
      // Without keys, MCP servers still come along, minus their headers.
      if (!keys) 'mcp_servers': _withoutHeaders(secrets),
      'prefs': {
        for (final k in prefs.getKeys())
          if (prefs.get(k) case final v?) k: v,
      },
      if (keys)
        'secrets': {
          for (final e in secrets.entries)
            if (!_neverExported(e.key) && e.key != _vaultKey) e.key: e.value,
        },
      if (vault && vaultRaw != null) 'vault': _decodeList(vaultRaw),
      'files': files,
    };
  }

  static List<Object?> _withoutHeaders(Map<String, String> secrets) {
    final raw = secrets.entries.where((e) => e.key.endsWith(_mcpKey)).firstOrNull?.value;
    if (raw == null) return const [];
    try {
      return [
        for (final s in jsonDecode(raw) as List)
          if (s is Map) {...s, 'headers': const {}, 'env': const {}},
      ];
    } catch (_) {
      return const [];
    }
  }

  static List<Object?> _decodeList(String? raw) {
    if (raw == null) return const [];
    try {
      return jsonDecode(raw) as List;
    } catch (_) {
      return const [];
    }
  }

  static int _count(Map prefs, String key) {
    try {
      return (jsonDecode('${prefs[key] ?? '[]'}') as List).length;
    } catch (_) {
      return 0;
    }
  }

  static int _folderCount(Map prefs) {
    try {
      return (((jsonDecode('${prefs[_customFoldersKey] ?? '{}'}') as Map)['folders'] as List?) ?? const []).length;
    } catch (_) {
      return 0;
    }
  }

  static int _innerFile(Map files, String name, String list) {
    try {
      final v = (jsonDecode('${files[name] ?? '{}'}') as Map)[list];
      return v is List ? v.length : (v is Map ? v.length : 0);
    } catch (_) {
      return 0;
    }
  }

  static int _inner(Map prefs, String key, String list) {
    try {
      return (((jsonDecode('${prefs[key] ?? '{}'}') as Map)[list] as List?) ?? const []).length;
    } catch (_) {
      return 0;
    }
  }

  /// Short counts of what [profile] holds, to show before restoring it.
  static Map<String, int> describe(Map<String, dynamic> profile) {
    final files = (profile['files'] as Map?) ?? const {};
    final prefs = (profile['prefs'] as Map?) ?? const {};
    final secrets = (profile['secrets'] as Map?) ?? const {};
    final mcp = secrets.entries.where((e) => '${e.key}'.endsWith(_mcpKey)).firstOrNull?.value;
    final vault = profile['vault'] is List ? profile['vault'] as List : _decodeList(secrets[_vaultKey] as String?);
    var transactions = 0;
    if (files['finance.json'] case final String finance) {
      try {
        transactions = (((jsonDecode(finance) as Map)['transactions'] as List?) ?? const []).length;
      } catch (_) {}
    }
    return {
      'settings': prefs.length,
      'keys': secrets.keys.where((k) => k != _vaultKey).length,
      'vault': vault.length,
      'routines': _count(prefs, 'routines.v1'),
      'rules': _count(prefs, 'approval_rules.v1'),
      'transactions': transactions,
      'chats': files.keys.where((k) => '$k'.startsWith('conversations/')).length,
      'watches': _count(prefs, 'watches.v1'),
      'widgets': _count(prefs, 'home_widgets.v1'),
      'skills': _count(prefs, 'omni_ai.skills'),
      'folders': _folderCount(prefs),
      'packages': _count(prefs, 'tracked_packages'),
      'playlists': _inner(prefs, 'playlists.v1', 'playlists'),
      'stores': _inner(prefs, MarketStore.key, 'sources'),
      'video_channels': _inner(prefs, MoviesStore.key, 'sources'),
      'books': _inner(prefs, BooksStore.key, 'books'),
      'gallery_sources': _inner(prefs, GalleryStore.key, 'sources'),
      'opportunity_sources': _inner(prefs, _opportunityKey, 'event_sources') + _inner(prefs, _opportunityKey, 'job_sources'),
      'podcasts': _innerFile(files, 'podcasts.json', 'subscriptions'),
      'radio': _innerFile(files, 'radio.json', 'stations'),
      'mcp': mcp != null ? _count({'m': mcp}, 'm') : ((profile['mcp_servers'] as List?) ?? const []).length,
    };
  }

  /// Writes [profile] back: its settings over the current ones, its keys
  /// and files. Then [ref]'s stores reload from it.
  static Future<void> restore(Ref ref, Map<String, dynamic> profile) async {
    if (profile['format'] != format) throw const FormatException('This is not a Triangle profile.');
    final prefs = await SharedPreferences.getInstance();
    final saved = (profile['prefs'] as Map?) ?? const {};
    // The profile's Telegram accounts, mapped onto the ones signed in here
    // by Telegram user id; their assistant settings come along.
    Map<String, String>? accountIds;
    if (saved[_accountsKey] case final String raw) {
      accountIds = ref.read(accountsProvider.notifier).applyRestored(_decodeList(raw));
    }
    final root = await _root();
    final oldRoot = '${profile['root'] ?? ''}';
    for (final e in saved.entries) {
      final k = '${e.key}';
      if (_devicePref(k)) continue;
      var v = e.value;
      if (accountIds != null && v is String && (_accountPrefs.contains(k) || _isStatsKey(k))) v = remapAccounts(k, v, accountIds);
      // Paths saved on another install point into this one's folder.
      if (v is String && oldRoot.isNotEmpty && oldRoot != root && (_sectionKeys.contains(k) || _isStatsKey(k))) {
        v = v.replaceAll(jsonEncode(oldRoot).replaceAll('"', ''), jsonEncode(root).replaceAll('"', ''));
      }
      switch (v) {
        case bool():
          await prefs.setBool(k, v);
        case int():
          await prefs.setInt(k, v);
        case double():
          await prefs.setDouble(k, v);
        case String():
          await prefs.setString(k, v);
        case List():
          await prefs.setStringList(k, [for (final x in v) '$x']);
      }
    }
    const secure = FlutterSecureStorage();
    final secrets = (profile['secrets'] as Map?) ?? const {};
    for (final e in secrets.entries) {
      if (!_neverExported('${e.key}')) await secure.write(key: '${e.key}', value: '${e.value}');
    }
    if (profile['vault'] case final List items) {
      await secure.write(key: _vaultKey, value: jsonEncode(items));
    }
    // A keyless profile's MCP servers: added without headers, unless this
    // phone already has servers (which keep theirs).
    final servers = profile['mcp_servers'];
    if (servers is List && servers.isNotEmpty && !secrets.keys.any((k) => '$k'.endsWith(_mcpKey))) {
      final here = (await secure.readAll()).entries.where((e) => e.key.endsWith(_mcpKey)).firstOrNull?.value;
      if (here == null || here == '[]') await prefs.setString(_mcpKey, jsonEncode(servers));
    }
    for (final e in ((profile['media'] as Map?) ?? const {}).entries) {
      final name = '${e.key}';
      if (name.contains('..') || !_mediaFolders.any((f) => name.startsWith('$f/'))) continue;
      try {
        final f = File('$root/$name');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(base64Decode('${e.value}'));
      } catch (_) {}
    }
    for (final e in ((profile['files'] as Map?) ?? const {}).entries) {
      final name = '${e.key}';
      // Only the files a profile writes, never a path outside the app.
      if (name.contains('..') || !(name.startsWith('conversations/') || _profileFiles.contains(name) || _exploreFiles.contains(name))) continue;
      var text = '${e.value}';
      if (accountIds != null && _accountFiles.contains(name)) text = remapAccounts(name, text, accountIds);
      // Saved paths (downloaded episodes) point into this install's folder.
      if (oldRoot.isNotEmpty && oldRoot != root && _exploreFiles.contains(name)) {
        text = text.replaceAll(jsonEncode(oldRoot).replaceAll('"', ''), jsonEncode(root).replaceAll('"', ''));
      }
      final f = File('$root/$name');
      await f.parent.create(recursive: true);
      await f.writeAsString(text);
    }
    _reload(ref);
    // The restored widgets' rows (and pictures) go back to the home screen.
    await ref.read(homeWidgetsProvider.notifier).publishAll();
    await BriefHomeWidget.publish(ref.read(briefStoreProvider).briefs);
  }

  /// Deletes the assistant's data on this phone: AI chats, memories, files
  /// it made or downloaded, briefs, the Content Canvas, watches, reminders,
  /// alerts and usage. With [settings], preferences and API keys go too.
  /// Telegram stays signed in.
  static Future<void> clearAll(Ref ref, {bool settings = false}) async {
    await ref.read(chatControllerProvider.notifier).deleteAll();
    await ref.read(aiProvider).memory.clear();
    await ref.read(canvasProvider.notifier).clear();
    await ref.read(briefStoreProvider.notifier).deleteAll();
    await ref.read(vaultProvider.notifier).clear();
    await ref.read(financeStoreProvider.notifier).clear();
    final root = await _root();
    for (final name in _dataFolders) {
      final d = Directory('$root/$name');
      if (await d.exists()) await d.delete(recursive: true);
    }
    for (final name in _profileFiles) {
      final f = File('$root/$name');
      if (await f.exists()) await f.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    for (final k in const [
      'watches.v1',
      'reminders.v1',
      'online_alerts.v1',
      'e2b_history.v1',
      'e2b_editor_draft',
      'routines.v1',
      'activity_log.v1',
      'library_favorites.v1',
      'tracked_packages',
      'home_widgets.v1',
      HomeWidgetStore.bindingsKey,
      HomeWidgetStore.defaultKey,
    ]) {
      await prefs.remove(k);
    }
    for (final k in prefs.getKeys().where((k) => k.startsWith('widget_payload.') && k != 'widget_payload.brief').toList()) {
      await prefs.remove(k);
    }
    if (settings) {
      // Keep whether Telegram was skipped (so the app opens where it was),
      // the signed-in accounts and the app lock: clearing data mustn't sign
      // anyone out or unlock the app.
      final kept = {
        for (final k in prefs.getKeys())
          if (k == 'telegram_skipped' || _devicePref(k)) k: prefs.get(k),
      };
      await prefs.clear();
      for (final e in kept.entries) {
        switch (e.value) {
          case final bool v:
            await prefs.setBool(e.key, v);
          case final int v:
            await prefs.setInt(e.key, v);
          case final double v:
            await prefs.setDouble(e.key, v);
          case final String v:
            await prefs.setString(e.key, v);
          case final List<String> v:
            await prefs.setStringList(e.key, v);
        }
      }
      const secure = FlutterSecureStorage();
      for (final k in (await secure.readAll()).keys) {
        if (!_neverExported(k)) await secure.delete(key: k);
      }
    }
    _reload(ref);
  }

  static void _reload(Ref ref) {
    // Keys cached outside providers, and a database connection made with
    // the old connection string, are read again on next use.
    VapiStore.forget();
    InfoKeysNotifier.forget();
    unawaited(MongoSession.instance.close());
    ref
      ..invalidate(settingsProvider)
      ..invalidate(decisionSettingsProvider)
      ..invalidate(aiProvider)
      ..invalidate(memoryProvider)
      ..invalidate(watchStoreProvider)
      ..invalidate(reminderStoreProvider)
      ..invalidate(onlineAlertStoreProvider)
      ..invalidate(briefPrefsProvider)
      ..invalidate(canvasProvider)
      ..invalidate(usageProvider)
      ..invalidate(homeWidgetsProvider)
      ..invalidate(widgetLookProvider)
      ..invalidate(integrationsProvider)
      ..invalidate(vaultProvider)
      ..invalidate(routineStoreProvider)
      ..invalidate(approvalRulesProvider)
      ..invalidate(activityLogProvider)
      ..invalidate(spendLimitsProvider)
      ..invalidate(contentFiltersProvider)
      ..invalidate(financeStoreProvider)
      ..invalidate(libraryFavoritesProvider)
      ..invalidate(assistOpensProvider)
      ..invalidate(customFoldersProvider)
      ..invalidate(playlistsProvider)
      ..invalidate(musicStatsProvider)
      ..invalidate(marketProvider)
      ..invalidate(marketFeedProvider)
      ..invalidate(moviesProvider)
      ..invalidate(videoFeedProvider)
      ..invalidate(booksProvider)
      ..invalidate(bookFeedProvider)
      ..invalidate(galleryProvider)
      ..invalidate(galleryFeedProvider)
      ..invalidate(opportunityProvider)
      ..invalidate(oppFeedProvider)
      ..invalidate(componentPrefsProvider)
      ..invalidate(mcpPermissionsProvider)
      ..invalidate(bibleSettingsProvider)
      ..invalidate(infoKeysProvider)
      ..invalidate(podcastsProvider)
      ..invalidate(radioProvider)
      ..invalidate(galleryIndexProvider)
      ..invalidate(activityStatsProvider);
  }

  /// Where a removed account's Explore things are kept: the sections'
  /// settings, playlists, music stats and My folders, plus [_accountFiles].
  static const _rehomeKeys = [..._sectionKeys, _customFoldersKey];

  /// After account [from] is removed: what Explore, playlists, podcasts and
  /// My folders kept under it moves to a signed-in account that is in the
  /// same chat (the one on screen first). Channels and supergroups read the
  /// same from any member, so sources keep working. A source or folder chat
  /// no remaining account is in is dropped (it couldn't be read); saved
  /// items (favorites, albums, cart, books, tracks) move to the account on
  /// screen and stay listed.
  static Future<void> rehomeAccount(Ref ref, String from) async {
    final accounts = ref.read(accountsProvider);
    final order = [
      for (final a in [accounts.active, ...accounts.signedIn])
        if (a.signedIn && a.id != from) a.id,
    ].toSet().toList();
    if (order.isEmpty) return;
    final known = <String, Set<int>>{};
    for (final id in order) {
      final store = ref.read(telegramStoreFamily(id));
      try {
        await store.ensureChatsLoaded().timeout(const Duration(seconds: 20));
      } catch (_) {}
      known[id] = store.chats.keys.toSet();
    }
    String? owner(int chat) => order.where((id) => known[id]!.contains(chat)).firstOrNull;
    final fallback = order.first;
    final pattern = _accountKey(from);
    String rekey(String s) {
      final m = pattern.firstMatch(s);
      if (m == null) return s;
      final chat = int.parse(m[2]!.substring(1).split(':').first);
      return '${m[1] ?? ''}${owner(chat) ?? fallback}${m[2]}';
    }

    const drop = Object();
    Object? walk(Object? v) {
      if (v is String) return rekey(v);
      if (v is List) {
        final out = <Object?>[];
        final seen = <String>{};
        for (final e in v) {
          final w = walk(e);
          if (identical(w, drop)) continue;
          // A source or folder chat now listed twice is kept once.
          if (w is Map && w['a'] is String && w['c'] is num && !w.containsKey('m') && !seen.add('${w['a']}:${w['c']}')) continue;
          out.add(w);
        }
        return out;
      }
      if (v is! Map) return v;
      final chat = v['c'] is num ? (v['c'] as num).toInt() : null;
      final mine = v['a'] == from || v['ac'] == from;
      final to = chat == null ? null : owner(chat);
      // A source (it has no message) no other account can read goes.
      if (mine && chat != null && to == null && !v.containsKey('m')) return drop;
      final out = <String, dynamic>{};
      for (final e in v.entries) {
        final k = '${e.key}';
        if ((k == 'a' || k == 'ac') && e.value == from) {
          out[k] = to ?? fallback;
          continue;
        }
        final w = walk(e.value);
        if (!identical(w, drop)) out[rekey(k)] = w;
      }
      return out;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final k in [..._rehomeKeys, ...prefs.getKeys().where(_isStatsKey)]) {
      final raw = prefs.getString(k);
      if (raw == null || !raw.contains(from)) continue;
      try {
        await prefs.setString(k, jsonEncode(walk(jsonDecode(raw))));
      } catch (e) {
        debugPrint('[AppData] re-homing $k: $e');
      }
    }
    final root = await _root();
    for (final name in _accountFiles) {
      final f = File('$root/$name');
      try {
        if (!await f.exists()) continue;
        final raw = await f.readAsString();
        if (raw.contains(from)) await f.writeAsString(jsonEncode(walk(jsonDecode(raw))));
      } catch (e) {
        debugPrint('[AppData] re-homing $name: $e');
      }
    }
    // The stores read it all again.
    ref
      ..invalidate(customFoldersProvider)
      ..invalidate(playlistsProvider)
      ..invalidate(musicStatsProvider)
      ..invalidate(marketProvider)
      ..invalidate(marketFeedProvider)
      ..invalidate(moviesProvider)
      ..invalidate(videoFeedProvider)
      ..invalidate(booksProvider)
      ..invalidate(bookFeedProvider)
      ..invalidate(galleryProvider)
      ..invalidate(galleryFeedProvider)
      ..invalidate(galleryIndexProvider)
      ..invalidate(opportunityProvider)
      ..invalidate(oppFeedProvider)
      ..invalidate(podcastsProvider)
      ..invalidate(activityStatsProvider);
  }

  /// [raw] (the setting [key] as JSON) with the Telegram account ids it
  /// names mapped through [ids]. An account limit naming no account signed
  /// in here goes back to every account; an approval rule for an account
  /// that isn't here is dropped rather than widened to all of them.
  @visibleForTesting
  static String remapAccounts(String key, String raw, Map<String, String> ids) {
    bool strayRule(Object? e) =>
        key == 'approval_rules.v1' && e is Map && e['account'] is String && !ids.containsKey(e['account']);

    Object? walk(Object? v) {
      if (v is List) return [for (final e in v) if (!strayRule(e)) walk(e)];
      if (v is! Map) return v;
      final out = <String, dynamic>{};
      for (final e in v.entries) {
        final k = '${e.key}';
        final x = e.value;
        if (k == 'accounts' && x is List) {
          final mapped = [for (final id in x) ?ids['$id']];
          if (mapped.isNotEmpty) out[k] = mapped;
        } else if ((k == 'account' || k == 'folder_account' || (k == 'a' && (key == _customFoldersKey || _keepsAccounts(key))) || (k == 'ac' && _keepsAccounts(key))) && x is String) {
          out[k] = ids[x] ?? x;
        } else if (_keepsAccounts(key) && x is String && x.contains(':')) {
          // Item keys ("account:chat:message") and the like.
          out[k] = _remapKey(x, ids);
        } else {
          out[k] = walk(x);
        }
      }
      return out;
    }

    Object? keys(Object? v) {
      if (!_keepsAccounts(key)) return v;
      if (v is List) return [for (final e in v) e is String ? _remapKey(e, ids) : keys(e)];
      if (v is Map) return {for (final e in v.entries) _remapKey('${e.key}', ids): keys(e.value)};
      return v;
    }

    try {
      return jsonEncode(keys(walk(jsonDecode(raw))));
    } catch (_) {
      return raw;
    }
  }

  /// "old:chat:message" → "new:chat:message" when it starts with a known
  /// account.
  static String _remapKey(String s, Map<String, String> ids) {
    for (final e in ids.entries) {
      final m = _accountKey(e.key).firstMatch(s);
      if (m != null) return '${m[1] ?? ''}${e.value}${m[2]}';
    }
    return s;
  }

  /// `account:chat`, `account:chat:message`, and the same after `tg:`
  /// (podcast shows, track keys), for [account].
  static RegExp _accountKey(String account) => RegExp('^(tg:)?${RegExp.escape(account)}(:-?\\d+(?::-?\\d+)?)\$');

  /// [profile] as a pretty JSON file's bytes.
  static List<int> encode(Map<String, dynamic> profile) =>
      utf8.encode(const JsonEncoder.withIndent('  ').convert(profile));
}

/// [AppData]'s actions with the app's providers at hand.
final appDataProvider = Provider<AppDataActions>(AppDataActions.new);

class AppDataActions {
  AppDataActions(this._ref);
  final Ref _ref;

  Future<void> restore(Map<String, dynamic> profile) => AppData.restore(_ref, profile);
  Future<void> clearAll({bool settings = false}) => AppData.clearAll(_ref, settings: settings);

  /// See [AppData.rehomeAccount].
  Future<void> rehomeAccount(String from) => AppData.rehomeAccount(_ref, from);
}
