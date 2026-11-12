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
  static const _accountPrefs = ['watches.v1', 'reminders.v1', 'brief_prefs.v1', 'approval_rules.v1'];

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
  static Future<Map<String, dynamic>> export({bool keys = true, bool chats = false, bool vault = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final root = await _root();
    final files = <String, String>{};
    for (final name in _profileFiles) {
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
    return {
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
    for (final e in saved.entries) {
      final k = '${e.key}';
      if (_devicePref(k)) continue;
      var v = e.value;
      if (accountIds != null && v is String && _accountPrefs.contains(k)) v = remapAccounts(k, v, accountIds);
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
    final root = await _root();
    for (final e in ((profile['files'] as Map?) ?? const {}).entries) {
      final name = '${e.key}';
      // Only the files a profile writes, never a path outside the app.
      if (name.contains('..') || !(name.startsWith('conversations/') || _profileFiles.contains(name))) continue;
      final f = File('$root/$name');
      await f.parent.create(recursive: true);
      await f.writeAsString('${e.value}');
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
      ..invalidate(assistOpensProvider);
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
        } else if ((k == 'account' || k == 'folder_account') && x is String) {
          out[k] = ids[x] ?? x;
        } else {
          out[k] = walk(x);
        }
      }
      return out;
    }

    try {
      return jsonEncode(walk(jsonDecode(raw)));
    } catch (_) {
      return raw;
    }
  }

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
}
