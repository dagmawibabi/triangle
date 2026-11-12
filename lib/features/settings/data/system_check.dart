import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:handy_tdlib/api.dart' as td;
import 'package:omni_ai/omni_ai.dart' show JevClient;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../ai/data/ai.dart';
import '../../ai/data/decision_settings.dart';
import '../../assistant/notifications.dart';
import '../../assistant/presentation/watches_screen.dart';
import '../../assistant/reminders.dart';
import '../../assistant/watch_engine.dart';
import '../../assistant/watches.dart';
import '../../brief/brief_settings_screen.dart';
import '../../brief/brief_store.dart';
import '../../brief/home_widgets.dart';
import '../../account/accounts_settings.dart';
import '../../account/storage_screen.dart';
import '../../calls/call_history.dart';
import '../../calls/call_history_screen.dart';
import '../../device/device.dart';
import '../../finance/finance_screen.dart';
import '../../finance/finance_store.dart';
import '../../lock/app_lock.dart';
import '../../lock/app_lock_settings.dart';
import '../../routines/routines.dart';
import '../../screen/screen_control.dart';
import '../../screen/screen_control_screen.dart';
import '../../routines/routines_screen.dart';
import '../../telegram/data/content_filters.dart';
import '../../telegram/presentation/block_mute_screen.dart';
import '../presentation/approvals_screen.dart';
import '../presentation/permissions_screen.dart';
import 'app_data.dart';
import '../../brief/widget_customizer_screen.dart';
import '../../chat/data/chat_controller.dart';
import '../../integrations/integrations_store.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/data/telegram_tools.dart';
import '../../usage/usage.dart';
import '../../usage/usage_screen.dart';
import 'settings.dart';
import '../presentation/capability_settings.dart';
import '../presentation/data_screen.dart';
import '../presentation/settings_screen.dart';
import '../presentation/tools_screen.dart';

/// How a check came out.
enum CheckStatus {
  ok(Icons.check_circle_rounded),
  improve(Icons.tips_and_updates_outlined),
  warn(Icons.warning_amber_rounded),
  fail(Icons.error_rounded),
  info(Icons.info_outline_rounded);

  const CheckStatus(this.icon);
  final IconData icon;

  /// Most serious first.
  int get rank => switch (this) {
    fail => 0,
    warn => 1,
    improve => 2,
    info => 3,
    ok => 4,
  };

  String get word => switch (this) {
    fail => 'broken',
    warn => 'warning',
    improve => 'suggestion',
    info => 'note',
    ok => 'passed',
  };

  Color get color => switch (this) {
    ok => AppColors.success,
    improve => AppColors.activeAccent,
    warn => AppColors.warning,
    fail => AppColors.danger,
    info => AppColors.text3,
  };
}

/// One finding, with the page that fixes it.
@immutable
class CheckResult {
  const CheckResult(this.status, this.title, [this.detail = '', this.fix]);
  final CheckStatus status;
  final String title;
  final String detail;

  /// Opens where it can be set up.
  final Widget Function()? fix;
}

/// A part of the app and what was found in it.
class CheckGroup {
  CheckGroup(this.id, this.title, this.icon);

  /// A short name for the system_check tool's areas: "ai", "telegram", ….
  final String id;
  final String title;
  final IconData icon;
  final List<CheckResult> results = [];
  bool done = false;

  /// How long its checks took.
  int ms = 0;

  int count(CheckStatus s) => results.where((r) => r.status == s).length;

  CheckStatus get worst {
    for (final s in const [CheckStatus.fail, CheckStatus.warn, CheckStatus.improve]) {
      if (results.any((r) => r.status == s)) return s;
    }
    return CheckStatus.ok;
  }
}

/// The areas a check goes through, in order: id → title and icon.
final systemCheckAreas = <String, (String, IconData)>{
  'ai': ('AI & models', Icons.auto_awesome_outlined),
  'telegram': ('Telegram accounts', Icons.send_rounded),
  'decisions': ('Decisions (Jev)', Icons.balance_rounded),
  'mcp': ('MCP servers', Icons.hub_outlined),
  'skills': ('Skills', Icons.auto_stories_outlined),
  'apps': ('Connected apps & services', Icons.apps_rounded),
  'connection': ('Phone & connection', Icons.network_check_rounded),
  'watches': ('Watches & check-in', Icons.visibility_outlined),
  'routines': ('Routines', Icons.event_repeat_rounded),
  'privacy': ('Privacy & safety', Icons.shield_outlined),
  'widgets': ('Home-screen widgets', Icons.widgets_outlined),
  'voice': ('Voice', Icons.graphic_eq_rounded),
  'tools': ('Tools, usage & data', Icons.build_outlined),
  'phone_data': ('Phone data: money & calls', Icons.account_balance_wallet_outlined),
  'upkeep': ('Memory, briefs, backup & storage', Icons.inventory_2_outlined),
};

/// Reads a provider: a WidgetRef's or a Ref's read.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Goes through everything the app depends on (AI keys and models,
/// Telegram, MCP servers, skills, connected apps, the phone and its
/// connection, watches, routines, privacy, widgets, voice, tools and
/// upkeep) and says what works, what's missing and what could be better.
/// It only reads; nothing is changed. Settings → System check shows it, and
/// the system_check tool runs it for the assistant.
class SystemChecker {
  SystemChecker(this.read);
  final ProviderReader read;

  static Future<T?> _try<T>(Future<T> work, {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await work.timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  static String _error(Object e) => '$e'.replaceFirst(RegExp(r'^\w*Exception:?\s*'), '');

  Future<void> Function(CheckGroup) _runner(String id) => switch (id) {
    'ai' => _ai,
    'telegram' => _telegram,
    'decisions' => _decisions,
    'mcp' => _mcp,
    'skills' => _skills,
    'apps' => _connectors,
    'connection' => _connection,
    'watches' => _automation,
    'routines' => _routines,
    'privacy' => _privacy,
    'widgets' => _widgets,
    'voice' => _voice,
    'tools' => _tools,
    'phone_data' => _phoneData,
    _ => _upkeep,
  };

  /// Runs the checks, [only] these areas when given. [onProgress] hears the
  /// groups each time one finishes (and once before the first starts).
  Future<List<CheckGroup>> run({Set<String>? only, void Function(List<CheckGroup> groups)? onProgress}) async {
    final groups = [
      for (final e in systemCheckAreas.entries)
        if ((only == null || only.isEmpty || only.contains(e.key)) && (e.key != 'phone_data' || Device.supported))
          CheckGroup(e.key, e.value.$1, e.value.$2),
    ];
    onProgress?.call(groups);
    for (final group in groups) {
      final clock = Stopwatch()..start();
      try {
        await _runner(group.id)(group);
      } catch (e) {
        group.results.add(CheckResult(CheckStatus.fail, 'The check itself failed', _error(e)));
      }
      group.ms = clock.elapsedMilliseconds;
      group.done = true;
      onProgress?.call(groups);
    }
    return groups;
  }

  /// Health out of 100: passed checks out of all that pass or fail; notes
  /// don't count, suggestions count half. Null with nothing scored.
  static int? score(List<CheckGroup> groups) {
    final all = [for (final g in groups) ...g.results];
    final scored = all.where((r) => r.status != CheckStatus.info).length;
    if (scored == 0) return null;
    final ok = all.where((r) => r.status == CheckStatus.ok).length;
    final better = all.where((r) => r.status == CheckStatus.improve).length;
    return ((ok + better * 0.5) / scored * 100).round();
  }

  /// What the system_check tool returns, and its card reads.
  static Map<String, dynamic> toJson(List<CheckGroup> groups, {DateTime? at}) {
    final all = [for (final g in groups) ...g.results];
    int count(CheckStatus s) => all.where((r) => r.status == s).length;
    return {
      'score': score(groups),
      'checked_at': (at ?? DateTime.now()).toIso8601String().substring(0, 16),
      'counts': {
        'broken': count(CheckStatus.fail),
        'warnings': count(CheckStatus.warn),
        'suggestions': count(CheckStatus.improve),
        'passed': count(CheckStatus.ok),
        'notes': count(CheckStatus.info),
      },
      'areas': [
        for (final g in groups)
          {
            'id': g.id,
            'title': g.title,
            'worst': g.worst.name,
            'ms': g.ms,
            'results': [
              for (final r in [...g.results]..sort((a, b) => a.status.rank.compareTo(b.status.rank)))
                {
                  'status': r.status.name,
                  'title': r.title,
                  if (r.detail.isNotEmpty) 'detail': r.detail,
                  if (r.fix != null) 'fixable_in_settings': true,
                },
            ],
          },
      ],
    };
  }

  // ---- the checks -------------------------------------------------------------

  Future<void> _ai(CheckGroup g) async {
    final s = read(settingsProvider);
    Widget aiPage() => const SettingsScreen(section: SettingsSection.ai);
    if (!s.hasAnyKey) {
      g.results.add(CheckResult(CheckStatus.fail, 'No AI key', 'The assistant can\'t answer, and watches can\'t run. Add one.', aiPage));
      return;
    }
    final keys = [
      if (s.hasVercelKey) 'Vercel AI Gateway',
      if (s.hasOpenRouterKey) 'OpenRouter',
      if (s.hasGeminiKey) 'Google Gemini',
      if (s.hasLmStudio) 'LM Studio',
    ];
    g.results.add(CheckResult(CheckStatus.ok, 'Keys for ${keys.join(', ')}'));
    await _try(read(modelCatalogProvider.notifier).ensureLoaded(), timeout: const Duration(seconds: 25));
    final catalog = read(modelCatalogProvider);
    if (catalog.models.isEmpty) {
      g.results.add(CheckResult(CheckStatus.warn, 'No models listed', catalog.error ?? 'The model list didn\'t load: check the keys and the connection.', aiPage));
    } else {
      g.results.add(CheckResult(CheckStatus.ok, '${catalog.models.length} models available'));
    }
    for (final e in catalog.providerErrors.entries) {
      g.results.add(CheckResult(CheckStatus.warn, '${e.key} didn\'t answer', e.value, aiPage));
    }
    final model = catalog.byId(s.model);
    if (catalog.models.isNotEmpty && model == null) {
      g.results.add(CheckResult(CheckStatus.warn, 'The chosen model isn\'t in the list', '${s.model}: pick one that is, or check its provider\'s key.', aiPage));
    } else if (model != null) {
      g.results.add(CheckResult(CheckStatus.ok, 'Chat model: ${model.name}'));
      if (model.contextWindow != null && model.contextWindow! < 32000) {
        g.results.add(CheckResult(CheckStatus.improve, 'Small context window', '${model.name} reads ${(model.contextWindow! / 1000).round()}k tokens: long chats compact often. A larger model helps.', aiPage));
      }
    }
    if (s.imageModel.isEmpty) {
      g.results.add(const CheckResult(CheckStatus.info, 'No image model chosen', 'Pictures use the default.'));
    }
    Widget media() => const SettingsScreen(section: SettingsSection.ai);
    final telegramReady = read(telegramClientProvider).authState is td.AuthorizationStateReady;
    for (final name in ['generate_image', if (s.videoEnabled) 'generate_video']) {
      final tool = telegramTools.where((t) => t.name == name).firstOrNull;
      if (tool == null) continue;
      final problems = toolPrerequisiteProblems(tool, s, telegram: telegramReady, connected: read(integrationsProvider).connected);
      g.results.add(problems.isEmpty
          ? CheckResult(CheckStatus.ok, name == 'generate_image' ? 'Images: ${s.imageModel}' : 'Video: ${s.videoModel}')
          : CheckResult(CheckStatus.warn, name == 'generate_image' ? "Pictures can't be made" : "Videos can't be made", problems.join(' '), media));
    }
    if (!s.videoEnabled) g.results.add(CheckResult(CheckStatus.info, 'Video is off', 'Turn it on and pick a model in Images & video.', media));
  }

  Future<void> _telegram(CheckGroup g) async {
    final s = read(settingsProvider);
    final accounts = read(accountsProvider);
    final signedIn = accounts.signedIn;
    if (signedIn.isEmpty) {
      g.results.add(CheckResult(
        s.telegramSkipped ? CheckStatus.info : CheckStatus.warn,
        s.telegramSkipped ? 'Telegram isn\'t connected' : 'Telegram isn\'t signed in',
        'Chats, channels, mention alerts and Telegram watches need it.',
        () => const AppsWebScreen(),
      ));
      return;
    }
    g.results.add(CheckResult(
      CheckStatus.ok,
      '${signedIn.length} account${signedIn.length == 1 ? '' : 's'} signed in',
      accounts.hasSeveral ? 'On screen: ${accounts.active.label}.' : '',
    ));
    // Accounts still listed but signed out (a session ended elsewhere, say).
    for (final a in accounts.accounts.where((a) => !a.signedIn && a.id != accounts.addingId && a.name.isNotEmpty)) {
      g.results.add(CheckResult(CheckStatus.warn, '${a.label} is signed out', 'Sign in again or remove it, so watches and tools don\'t miss it.', () => AccountDetailScreen(accountId: a.id)));
    }
    // The same Telegram user added twice.
    final users = <int, int>{};
    for (final a in signedIn) {
      users.update(a.userId!, (n) => n + 1, ifAbsent: () => 1);
    }
    if (users.values.any((n) => n > 1)) {
      g.results.add(const CheckResult(CheckStatus.warn, 'An account is added twice', 'Two entries sign in to the same Telegram user; remove one.'));
    }
    if (accounts.forAi.isEmpty) {
      g.results.add(CheckResult(CheckStatus.warn, 'The assistant can\'t reach any account', 'Every account has the assistant\'s access turned off, so Telegram tools find nothing.', () => AccountDetailScreen(accountId: accounts.activeId)));
    }
    for (final a in signedIn) {
      final client = read(telegramClientFamily(a.id));
      final name = accounts.hasSeveral ? a.label : 'This account';
      Widget page() => AccountDetailScreen(accountId: a.id);
      final clock = Stopwatch()..start();
      final version = await _try(client.send<td.TdObject>(const td.GetOption(name: 'version')), timeout: const Duration(seconds: 8));
      if (version == null) {
        g.results.add(CheckResult(CheckStatus.fail, '$name: TDLib isn\'t responding', 'Restart the app; if it stays, check Settings → About → TDLib controls.', page));
        continue;
      }
      final v = version is td.OptionValueString ? version.value : '';
      final store = read(telegramStoreFamily(a.id));
      g.results.add(CheckResult(
        CheckStatus.ok,
        '$name: ${store.chats.length} chats',
        'TDLib${v.isEmpty ? '' : ' $v'} answered in ${clock.elapsedMilliseconds} ms${a.username == null ? '' : ' · @${a.username}'}.',
      ));
      final password = await _try(client.send<td.PasswordState>(const td.GetPasswordState()), timeout: const Duration(seconds: 10));
      if (password != null && !password.hasPassword) {
        g.results.add(CheckResult(CheckStatus.warn, '$name: no two-step verification', 'Anyone with your SIM could sign in. Set a password in Telegram, or ask the assistant for an account_health check.', page));
      } else if (password != null && !password.hasRecoveryEmailAddress) {
        g.results.add(CheckResult(CheckStatus.improve, '$name: no recovery email', 'If you forget the two-step password, there\'s no way back in.', page));
      }
      final sessions = await _try(client.send<td.Sessions>(const td.GetActiveSessions()), timeout: const Duration(seconds: 10));
      if (sessions != null) {
        final others = sessions.sessions.where((x) => !x.isCurrent).toList();
        final unofficial = others.where((x) => !x.isOfficialApplication).length;
        if (unofficial > 0) {
          g.results.add(CheckResult(CheckStatus.warn, '$name: $unofficial unofficial app${unofficial == 1 ? '' : 's'} signed in', 'Check its devices (list_sessions) and end the ones you don\'t know.', page));
        } else if (others.length > 6) {
          g.results.add(CheckResult(CheckStatus.improve, '$name: ${others.length} other devices signed in', 'Old sessions are worth ending.', page));
        }
      }
      if (!a.aiAccess && accounts.hasSeveral) {
        g.results.add(CheckResult(CheckStatus.info, '$name: hidden from the assistant', 'Its chats aren\'t read or changed by tools.', page));
      }
      if (a.readOnly) g.results.add(CheckResult(CheckStatus.info, '$name: read-only', 'The assistant can read it but not send or change anything.', page));
      if (a.customTools) {
        g.results.add(CheckResult(CheckStatus.info, '$name: its own tool switches', '${a.disabledTools!.length} tools off for this account only.', page));
      }
      if (a.approvalMode != null && a.approvalMode != s.approvalMode.name) {
        g.results.add(CheckResult(CheckStatus.info, '$name: its own approvals', 'Approvals here: ${ApprovalMode.values.asNameMap()[a.approvalMode]?.label ?? a.approvalMode}.', page));
      }
    }
    if (s.mentionAlerts && !s.notifications) {
      g.results.add(CheckResult(CheckStatus.warn, 'Mention alerts are on, notifications off', 'You won\'t hear about mentions.', () => const SettingsScreen(section: SettingsSection.proactivity)));
    } else if (s.mentionAlerts && accounts.hasSeveral) {
      final muted = signedIn.where((a) => !a.mentionAlerts).map((a) => a.label).toList();
      if (muted.isNotEmpty) g.results.add(CheckResult(CheckStatus.info, 'No mention alerts for ${muted.join(', ')}', 'Turned off for that account.'));
    }
  }

  /// Money from bank SMS and the call log: whether Android lets the app
  /// read them, and how fresh what was read is.
  Future<void> _phoneData(CheckGroup g) async {
    final granted = await _try(Device.status([Device.sms.id, Device.callLog.id, Device.contacts.id])) ?? const <String, bool>{};
    Widget perms() => const PermissionsScreen();
    final fin = read(financeStoreProvider);
    if (granted[Device.sms.id] == false) {
      g.results.add(CheckResult(
        fin.accounts.isEmpty ? CheckStatus.info : CheckStatus.warn,
        'Can\'t read SMS',
        'Money can\'t pick up bank and wallet texts; only manual entries count.',
        perms,
      ));
    }
    if (fin.accounts.isEmpty) {
      g.results.add(CheckResult(CheckStatus.improve, 'Money isn\'t set up', 'Add accounts or sync bank SMS to track balances, spending and budgets.', () => const FinanceScreen()));
    } else {
      final days = fin.lastSync == null ? null : DateTime.now().difference(fin.lastSync!).inDays;
      g.results.add(CheckResult(
        days == null || days > 7 ? CheckStatus.improve : CheckStatus.ok,
        '${fin.accounts.length} money account${fin.accounts.length == 1 ? '' : 's'} · ${fin.transactions.length} transactions',
        days == null ? 'Never synced from SMS.' : (days == 0 ? 'Synced today.' : 'Last SMS sync $days day${days == 1 ? '' : 's'} ago.'),
        () => const FinanceScreen(),
      ));
      final uncategorized = fin.transactions.where((t) => t.category == null).length;
      if (uncategorized > 20) {
        g.results.add(CheckResult(CheckStatus.improve, '$uncategorized transactions without a category', 'Categorise them so spending and budgets add up.', () => const FinanceScreen(initialTab: 2)));
      }
      final parser = fin.parser;
      if (parser != null && (parser.fetchedAt == null || DateTime.now().difference(parser.fetchedAt!).inDays > 30)) {
        g.results.add(CheckResult(CheckStatus.improve, 'Bank SMS patterns are over a month old', 'Update them so new message wording is understood.', () => const FinanceScreen(initialTab: 4)));
      }
      if (fin.budgets.isNotEmpty) g.results.add(CheckResult(CheckStatus.info, '${fin.budgets.length} budget${fin.budgets.length == 1 ? '' : 's'} set'));
    }
    if (granted[Device.callLog.id] == false) {
      g.results.add(CheckResult(CheckStatus.info, 'Can\'t read the call log', 'Call history needs the call log permission.', perms));
    } else {
      final calls = await _try(CallHistory.instance.load(), timeout: const Duration(seconds: 20));
      if (calls != null) {
        g.results.add(CheckResult(
          calls.isEmpty ? CheckStatus.info : CheckStatus.ok,
          calls.isEmpty ? 'The call log is empty' : '${calls.length} calls in the log',
          '',
          () => const CallHistoryScreen(),
        ));
      }
    }
    if (granted[Device.contacts.id] == false) {
      g.results.add(CheckResult(CheckStatus.info, 'Can\'t read contacts', 'Calls and texts show numbers instead of names.', perms));
    }
  }

  /// The phone itself and the way out to the internet: storage, memory,
  /// battery and power saver, the network, and how quickly names resolve.
  Future<void> _connection(CheckGroup g) async {
    String gb(num bytes) => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (Device.supported) {
      final info = await _try(Device.call<Map>('deviceInfo'));
      if (info != null) {
        final free = (info['storage_free'] as num?) ?? 0;
        final total = (info['storage_total'] as num?) ?? 0;
        if (total > 0) {
          final low = free < 1024 * 1024 * 1024;
          g.results.add(CheckResult(
            low ? CheckStatus.fail : (free < 3 * 1024 * 1024 * 1024 ? CheckStatus.warn : CheckStatus.ok),
            '${gb(free)} free of ${gb(total)}',
            low
                ? 'The phone is almost full: downloads, voice notes and Telegram media may fail.'
                : (free < 3 * 1024 * 1024 * 1024 ? 'Space is getting low.' : ''),
            () => const StorageScreen(),
          ));
        }
        if (info['low_memory'] == true) {
          g.results.add(const CheckResult(CheckStatus.warn, 'The phone is low on memory', 'Android may close Triangle in the background. Close apps you aren\'t using.'));
        }
        final android = '${info['android'] ?? ''}';
        if (android.isNotEmpty) {
          g.results.add(CheckResult(CheckStatus.info, '${info['brand'] ?? ''} ${info['model'] ?? ''}'.trim(), 'Android $android'));
        }
      }
      final battery = await _try(Device.call<Map>('battery'));
      if (battery != null) {
        final level = (battery['level'] as num?)?.toInt() ?? -1;
        final charging = battery['charging'] == true;
        final heat = (battery['temperature_c'] as num?)?.toDouble() ?? 0;
        final health = '${battery['health'] ?? ''}';
        if (battery['power_saver'] == true) {
          g.results.add(CheckResult(CheckStatus.warn, 'Battery saver is on', 'Android delays background work: watches, routines and briefs may run late.', () => const PermissionsScreen()));
        }
        if (level >= 0) {
          g.results.add(CheckResult(
            level < 15 && !charging ? CheckStatus.warn : CheckStatus.ok,
            'Battery $level%${charging ? ', charging' : ''}',
            level < 15 && !charging ? 'Charge soon: Android pauses background work on a low battery.' : '',
          ));
        }
        if (heat >= 45) {
          g.results.add(CheckResult(CheckStatus.warn, 'The battery is hot (${heat.round()} °C)', 'Heavy work, like video or long sandboxes, may slow down.'));
        }
        if (health.isNotEmpty && health != 'good' && health != 'unknown') {
          g.results.add(CheckResult(CheckStatus.improve, 'Battery health: $health', 'It may not last as long between charges.'));
        }
      }
      final net = await _try(Device.call<Map>('network'));
      if (net != null) {
        final type = '${net['type'] ?? ''}';
        if (net['connected'] != true) {
          g.results.add(const CheckResult(CheckStatus.fail, 'Not connected to a network', 'The assistant, Telegram and connected apps need the internet.'));
        } else if (net['validated'] == false) {
          g.results.add(CheckResult(CheckStatus.warn, 'Connected to ${type.isEmpty ? 'a network' : type} without internet', 'A sign-in page or a blocked network may be in the way.'));
        } else {
          g.results.add(CheckResult(
            CheckStatus.ok,
            'Online${type.isEmpty ? '' : ' over $type'}${net['ssid'] is String && '${net['ssid']}'.isNotEmpty ? ' (${net['ssid']})' : ''}',
            [if (net['metered'] == true) 'Metered: large downloads use your data.', if (net['vpn'] == true) 'Through a VPN.'].join(' '),
          ));
        }
      }
    }
    // Name lookups, timed: the first thing every request does.
    final clock = Stopwatch()..start();
    final found = await _try(InternetAddress.lookup('api.telegram.org'), timeout: const Duration(seconds: 6));
    final ms = clock.elapsedMilliseconds;
    if (found == null || found.isEmpty) {
      g.results.add(const CheckResult(CheckStatus.fail, 'Can\'t look up addresses', 'DNS isn\'t answering, so nothing online can be reached.'));
    } else {
      g.results.add(CheckResult(ms > 800 ? CheckStatus.improve : CheckStatus.ok, 'Addresses resolve in $ms ms', ms > 800 ? 'Slow DNS makes every request start late. A private DNS like 1.1.1.1 may help.' : ''));
    }
  }

  /// Routines: whether each can run, and how their last runs went.
  Future<void> _routines(CheckGroup g) async {
    final s = read(settingsProvider);
    final routines = read(routineStoreProvider);
    Widget page() => const RoutinesScreen();
    if (routines.isEmpty) {
      g.results.add(CheckResult(CheckStatus.info, 'No routines yet', 'Describe a job and when to do it: "Every weekday at 9, catch me up."', page));
      return;
    }
    final on = routines.where((r) => r.enabled).toList();
    g.results.add(CheckResult(
      CheckStatus.ok,
      '${routines.length} routine${routines.length == 1 ? '' : 's'}',
      [
        '${on.length} on',
        if (routines.length > on.length) '${routines.length - on.length} paused',
        '${routines.fold<int>(0, (n, r) => n + r.runs)} runs in all',
      ].join(' · '),
      page,
    ));
    final scheduled = on.where((r) => r.trigger.kind != RoutineTriggerKind.manual).length;
    if (scheduled > 0 && !s.proactive) {
      g.results.add(CheckResult(CheckStatus.warn, '$scheduled scheduled routine${scheduled == 1 ? '' : 's'} won\'t run', 'Proactivity is off, so nothing starts on its own.', () => const SettingsScreen(section: SettingsSection.proactivity)));
    }
    for (final r in on) {
      if (r.steps.isEmpty) {
        g.results.add(CheckResult(CheckStatus.warn, '${r.name} has no steps', 'It runs but does nothing: add a step or remove it.', page));
        continue;
      }
      final last = r.history.firstOrNull;
      if (last != null && !last.ok) {
        final step = last.steps.where((x) => !x.ok && !x.skipped).firstOrNull;
        g.results.add(CheckResult(
          CheckStatus.warn,
          '${r.name}: the last run failed',
          last.error ?? (step == null ? 'See its history.' : '${step.label}: ${step.output}'.trim()),
          page,
        ));
      } else if (r.trigger.kind == RoutineTriggerKind.daily && r.lastRunAt != null && DateTime.now().difference(r.lastRunAt!).inHours > 50) {
        g.results.add(CheckResult(CheckStatus.warn, '${r.name} hasn\'t run in ${DateTime.now().difference(r.lastRunAt!).inDays} days', 'It should run daily: keep Triangle running in the background.', () => const SettingsScreen(section: SettingsSection.proactivity)));
      }
    }
    final failing = on.where((r) => r.history.length >= 3 && r.history.take(3).every((x) => !x.ok)).length;
    if (failing > 0) {
      g.results.add(CheckResult(CheckStatus.fail, '$failing routine${failing == 1 ? '' : 's'} failed three times in a row', 'Open it and check its steps and tools.', page));
    }
  }

  /// What protects the app and the accounts: the app lock, approvals, and
  /// what Telegram hides for you.
  Future<void> _privacy(CheckGroup g) async {
    final s = read(settingsProvider);
    final lock = read(appLockProvider);
    Widget lockPage() => const AppLockSettingsScreen();
    if (!lock.enabled) {
      g.results.add(CheckResult(CheckStatus.improve, 'App lock is off', 'Anyone holding your unlocked phone can open your chats, money and keys.', lockPage));
    } else {
      g.results.add(CheckResult(CheckStatus.ok, 'App lock is on', lock.biometrics ? 'Fingerprint or face unlocks it.' : '', lockPage));
      if (!lock.biometrics && lock.biometricsAvailable) {
        g.results.add(CheckResult(CheckStatus.info, 'Fingerprint unlock is available', 'Quicker than typing the PIN.', lockPage));
      }
    }
    if (Device.supported) {
      final screen = await _try(ScreenControl.status());
      if (screen?['enabled'] == true) {
        final offLimits = await ScreenOffLimits.load();
        g.results.add(CheckResult(
          s.approvalMode == ApprovalMode.ask ? CheckStatus.ok : CheckStatus.warn,
          'Screen control is on',
          s.approvalMode == ApprovalMode.ask
              ? 'The assistant can use other apps; each tap and typing asks first. ${offLimits.isEmpty ? 'No apps are off limits.' : '${offLimits.length} off limits.'}'
              : 'The assistant can tap and type in other apps without asking. Consider "Always ask" in Approvals.',
          () => const ScreenControlScreen(),
        ));
        if (offLimits.isEmpty) {
          g.results.add(CheckResult(CheckStatus.improve, 'No apps are off limits to screen control', 'Add your banking and password apps so the assistant never opens them.', () => const ScreenControlScreen()));
        }
      }
    }
    Widget approvals() => const ApprovalsScreen();
    g.results.add(switch (s.approvalMode) {
      ApprovalMode.ask => CheckResult(CheckStatus.ok, 'Every action asks first', '', approvals),
      ApprovalMode.watches => CheckResult(CheckStatus.info, 'Watches and routines act on their own', 'The chat still asks before it sends or changes anything.', approvals),
      ApprovalMode.never => CheckResult(CheckStatus.warn, 'Nothing asks first', 'The assistant sends, replies and changes things right away, everywhere.', approvals),
    });
    final filters = read(contentFiltersProvider);
    final blocked = read(blockedSendersProvider).length;
    final hidden = [
      if (blocked > 0) '$blocked blocked account${blocked == 1 ? '' : 's'}',
      if (filters.blockedChats.isNotEmpty) '${filters.blockedChats.length} blocked chat${filters.blockedChats.length == 1 ? '' : 's'}',
      if (filters.mutedWords.isNotEmpty) '${filters.mutedWords.length} muted word${filters.mutedWords.length == 1 ? '' : 's'}',
    ];
    if (read(accountsProvider).signedIn.isNotEmpty) {
      g.results.add(CheckResult(
        CheckStatus.info,
        hidden.isEmpty ? 'Nothing is hidden in Telegram' : 'Hidden in Telegram: ${hidden.join(', ')}',
        hidden.isEmpty ? 'Block channels and groups or mute words in Block & mute.' : (filters.inArchived ? 'Archived chats too.' : 'Not in archived chats.'),
        () => const BlockMuteScreen(),
      ));
    }
  }

  Future<void> _decisions(CheckGroup g) async {
    final d = read(decisionSettingsProvider);
    Widget page() => const SettingsScreen(section: SettingsSection.ai);
    if (d.apiKey.trim().isEmpty) {
      g.results.add(CheckResult(CheckStatus.improve, 'Not set up', 'With a TypeSafe key the assistant can classify, score and route with calibrated answers (and batches).', page));
      return;
    }
    if (!d.enabled) g.results.add(CheckResult(CheckStatus.info, 'Turned off', 'The key is saved; the Jev tools are hidden.', page));
    final problem = await _try(JevClient(apiKey: d.apiKey, baseUrl: d.baseUrl).verify());
    g.results.add(problem == null
        ? CheckResult(CheckStatus.ok, 'TypeSafe key works', 'Model ${d.model}.')
        : CheckResult(CheckStatus.fail, 'TypeSafe key didn\'t work', problem, page));
  }

  Future<void> _mcp(CheckGroup g) async {
    final mcp = read(aiProvider).mcp;
    await mcp.load();
    if (mcp.servers.isEmpty) {
      g.results.add(CheckResult(CheckStatus.info, 'No servers installed', 'MCP servers give the assistant tools from other services.', () => const McpSkillsSettingsScreen()));
      return;
    }
    for (final s in mcp.servers) {
      try {
        final client = await mcp.connect(s.id).timeout(const Duration(seconds: 15));
        final tools = await client.listTools().timeout(const Duration(seconds: 15));
        g.results.add(CheckResult(
          tools.isEmpty ? CheckStatus.warn : CheckStatus.ok,
          s.id,
          tools.isEmpty ? 'Connected, but it offers no tools.' : 'Connected · ${tools.length} tools',
        ));
      } catch (e) {
        g.results.add(CheckResult(CheckStatus.fail, '${s.id} didn\'t connect', _error(e), () => const McpSkillsSettingsScreen()));
      }
    }
  }

  Future<void> _skills(CheckGroup g) async {
    final skills = read(aiProvider).skills;
    await skills.load();
    if (skills.all.isEmpty) {
      g.results.add(CheckResult(CheckStatus.info, 'No skills installed', 'Skills teach the assistant how to do specific jobs.', () => const McpSkillsSettingsScreen(initialTab: 1)));
      return;
    }
    final empty = skills.all.where((s) => s.content.trim().isEmpty).toList();
    g.results.add(CheckResult(CheckStatus.ok, '${skills.all.length} installed', skills.all.map((s) => s.name).join(', ')));
    for (final s in empty) {
      g.results.add(CheckResult(CheckStatus.warn, '${s.name} has no instructions', 'Reinstall or remove it.', () => const McpSkillsSettingsScreen(initialTab: 1)));
    }
    final undescribed = skills.all.where((s) => s.description.trim().isEmpty).length;
    if (undescribed > 0) {
      g.results.add(CheckResult(CheckStatus.improve, '$undescribed without a description', 'The assistant picks skills by their description.'));
    }
  }

  Future<void> _connectors(CheckGroup g) async {
    final s = read(settingsProvider);
    Widget apps() => const AppsWebScreen();
    if (s.composioKey.trim().isEmpty) {
      g.results.add(CheckResult(CheckStatus.improve, 'Apps aren\'t set up', 'Connect Gmail, Calendar, Slack, Notion and more for the assistant and the check-in.', apps));
    } else {
      await _try(read(integrationsProvider.notifier).refresh(), timeout: const Duration(seconds: 20));
      final st = read(integrationsProvider);
      if (st.error != null) {
        g.results.add(CheckResult(CheckStatus.fail, 'Couldn\'t reach your apps', st.error!, apps));
      } else if (st.accounts.isEmpty) {
        g.results.add(CheckResult(CheckStatus.improve, 'No apps connected', 'The key works; connect an app to use it.', apps));
      } else {
        final active = st.accounts.where((a) => a.active).map((a) => a.toolkit).toSet();
        g.results.add(CheckResult(CheckStatus.ok, '${active.length} connected', active.join(', ')));
        for (final a in st.accounts.where((a) => !a.active)) {
          g.results.add(CheckResult(CheckStatus.warn, '${a.toolkit} needs reconnecting', 'Its connection expired or was revoked.', apps));
        }
      }
    }
    if (s.exaKey.trim().isEmpty) {
      g.results.add(CheckResult(CheckStatus.improve, 'Web search uses the free fallback', 'An Exa key gives better, fresher results.', apps));
    }
    if (s.e2bKey.trim().isEmpty) g.results.add(const CheckResult(CheckStatus.info, 'No code sandbox', 'An E2B key lets the assistant run code.'));
    if (s.cloudflareToken.trim().isNotEmpty && s.cloudflareAccountId.trim().isEmpty) {
      g.results.add(CheckResult(CheckStatus.warn, 'Cloudflare token without an account id', 'Add the account id too.', apps));
    }
    if (s.r2AccessKeyId.trim().isNotEmpty && (s.r2SecretKey.trim().isEmpty || s.r2Bucket.trim().isEmpty)) {
      g.results.add(CheckResult(CheckStatus.warn, 'R2 storage is half set up', 'It needs the secret and a bucket.', apps));
    }
  }

  Future<void> _automation(CheckGroup g) async {
    final s = read(settingsProvider);
    final watches = read(watchStoreProvider);
    final active = watches.where((w) => w.enabled).toList();
    final jobs = read(reminderStoreProvider).where((r) => r.enabled && r.isJob).length;
    Widget page() => const WatchesScreen();
    Widget proactivity() => const SettingsScreen(section: SettingsSection.proactivity);
    if (!s.proactive) {
      g.results.add(CheckResult(CheckStatus.warn, 'Proactivity is off', 'Every watch, routine and the check-in is paused.', proactivity));
    }
    final checkIn = watches.where((w) => w.id == checkInWatchId).firstOrNull;
    if (checkIn != null) {
      g.results.add(checkIn.enabled
          ? CheckResult(CheckStatus.ok, 'Check-in every ${(checkIn.everyMinutes ?? 360) ~/ 60} h${checkIn.quietAtNight ? ', quiet at night' : ''}')
          : CheckResult(CheckStatus.improve, 'Check-in is off', 'Turn it on for a nudge every few hours about what needs you.', page));
    }
    g.results.add(CheckResult(CheckStatus.info, '${active.where((w) => !w.builtIn).length} watches on · $jobs scheduled jobs'));
    final notifier = read(appNotifierProvider);
    final allowed = await _try(notifier.permitted());
    if (!s.notifications) {
      g.results.add(CheckResult(CheckStatus.warn, 'Notifications are off', 'Watches and the check-in run, but quietly.', proactivity));
    } else if (allowed == false) {
      g.results.add(CheckResult(CheckStatus.fail, 'Android blocks Triangle\'s notifications', 'Allow them in the phone\'s settings for Triangle.', proactivity));
    } else if (allowed == true) {
      g.results.add(const CheckResult(CheckStatus.ok, 'Notifications allowed'));
    }
    if (await _try(notifier.exactAlarms()) == false) {
      g.results.add(CheckResult(CheckStatus.warn, 'Exact alarms not allowed', 'Reminders may arrive late.', proactivity));
    }
    if ((active.isNotEmpty || jobs > 0) && s.proactive && !s.keepAlive && !s.backgroundAlways) {
      g.results.add(CheckResult(CheckStatus.warn, 'Watches stop when the app closes', 'Turn on "Keep running in the background" so they keep working.', proactivity));
    } else if ((active.isNotEmpty || jobs > 0) && s.proactive && s.backgroundNotice == BackgroundNotice.off) {
      g.results.add(CheckResult(CheckStatus.warn, 'The background notification is off', 'Without it Android may stop Triangle, pausing watches. "Minimised" hides it and keeps them running.', proactivity));
    } else if (notifier.alive) {
      g.results.add(CheckResult(CheckStatus.ok, 'Running in the background', s.backgroundNotice == BackgroundNotice.minimised ? 'With a minimised notification.' : ''));
    }
    if (Platform.isAndroid && (s.keepAlive || s.backgroundAlways) && await _try(FlutterForegroundTask.isIgnoringBatteryOptimizations) == false) {
      g.results.add(CheckResult(CheckStatus.improve, 'Battery optimisation is on for Triangle', 'Android may pause it in the background. Allow it to run unrestricted.', () => const PermissionsScreen()));
    }
    final store = read(telegramStoreProvider);
    final accounts = read(accountsProvider);
    final telegram = read(telegramClientProvider).authState is td.AuthorizationStateReady || accounts.signedIn.isNotEmpty;
    final connected = read(integrationsProvider).connected;
    for (final w in active) {
      // The accounts it covers, as stores; a folder watch has one.
      final covered = [
        for (final a in accounts.signedIn)
          if (w.covers(a.id)) read(telegramStoreFamily(a.id)),
      ];
      if (w.scope.needsTelegram && !telegram) {
        g.results.add(CheckResult(CheckStatus.warn, '${w.name} needs Telegram', 'It can\'t hear messages until Telegram is connected.', page));
      } else if (w.scope.needsTelegram && accounts.hasSeveral && covered.isEmpty) {
        g.results.add(CheckResult(CheckStatus.warn, '${w.name} covers no signed-in account', 'Edit it to pick the accounts it should hear.', page));
      } else if (w.scope == WatchScope.chats && telegram && store.chats.isNotEmpty) {
        // Missing only when no account it covers has the chat.
        final stores = covered.isEmpty ? [store] : covered;
        final missing = w.chatIds.where((id) => stores.every((s) => s.chat(id) == null)).length;
        if (missing > 0) g.results.add(CheckResult(CheckStatus.warn, '${w.name} watches $missing chat${missing == 1 ? '' : 's'} you left or that were deleted', 'Edit it to pick chats again.', page));
      } else if (w.scope == WatchScope.app && w.app != null && w.app != 'any' && !connected.contains(w.app)) {
        g.results.add(CheckResult(CheckStatus.warn, '${w.name}: ${w.app} isn\'t connected', 'It finds nothing until the app is connected.', () => const AppsWebScreen()));
      }
    }
    final error = read(watchEngineProvider).status.value.error;
    if (error != null) g.results.add(CheckResult(CheckStatus.warn, 'Last watch problem', error, page));
  }

  Future<void> _widgets(CheckGroup g) async {
    final store = read(homeWidgetsProvider.notifier);
    await store.ready;
    final defs = read(homeWidgetsProvider).where((d) => !d.isBrief).toList();
    final placed = await store.instances();
    g.results.add(CheckResult(
      placed.isEmpty ? CheckStatus.info : CheckStatus.ok,
      placed.isEmpty ? 'None on the home screen' : '${placed.length} on the home screen',
      placed.isEmpty ? 'Long-press the home screen → Widgets → Triangle.' : '',
      () => const WidgetCustomizerScreen(),
    ));
    final watches = read(watchStoreProvider.notifier);
    for (final d in defs) {
      if (d.byAssistant && (d.watchId == null || watches.byId(d.watchId!) == null)) {
        g.results.add(CheckResult(CheckStatus.warn, '${d.title} has no refresh', 'Its watch was deleted: edit and save it to refresh again.', () => WidgetCustomizerScreen(openWidget: d.id)));
      } else if (d.byAssistant && !(watches.byId(d.watchId!)?.enabled ?? true)) {
        g.results.add(CheckResult(CheckStatus.warn, '${d.title}\'s refresh is turned off', 'Turn its watch back on in Watches.', () => const WatchesScreen()));
      } else if (d.runs.isNotEmpty && !d.runs.first.ok) {
        g.results.add(CheckResult(CheckStatus.warn, '${d.title}\'s last refresh didn\'t update it', d.runs.first.note, () => WidgetCustomizerScreen(openWidget: d.id)));
      } else {
        g.results.add(CheckResult(CheckStatus.ok, d.title, d.items.isEmpty ? 'Empty so far' : '${d.items.length} rows'));
      }
    }
  }

  Future<void> _voice(CheckGroup g) async {
    final s = read(settingsProvider);
    Widget page() => const SettingsScreen(section: SettingsSection.voice);
    final needs = switch (s.voiceEngine) {
      VoiceEngine.elevenLabs => s.elevenKey.trim().isEmpty ? 'ElevenLabs' : null,
      VoiceEngine.addis => s.addisKey.trim().isEmpty ? 'Addis AI' : null,
      VoiceEngine.ai => s.hasAnyKey ? null : 'an AI',
      VoiceEngine.device => null,
    };
    g.results.add(needs == null
        ? CheckResult(CheckStatus.ok, 'Read aloud: ${s.voiceEngine.label}')
        : CheckResult(CheckStatus.fail, 'Read aloud needs $needs key', 'Add it, or switch to the device voice.', page));
  }

  Future<void> _tools(CheckGroup g) async {
    final s = read(settingsProvider);
    final telegram = read(telegramClientProvider).authState is td.AuthorizationStateReady;
    final connected = read(integrationsProvider).connected;
    final blocked = <String, int>{};
    var on = 0;
    for (final t in telegramTools.where((t) => t.isOn(s))) {
      on++;
      final problems = toolPrerequisiteProblems(t, s, telegram: telegram, connected: connected, decisionsReady: read(decisionsReadyProvider));
      for (final p in problems) {
        blocked.update(p, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    g.results.add(CheckResult(CheckStatus.ok, '$on tools turned on'));
    final top = blocked.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in top.take(6)) {
      g.results.add(CheckResult(CheckStatus.improve, '${e.value} tool${e.value == 1 ? '' : 's'} can\'t run yet', e.key, () => const ToolsScreen()));
    }
    if (s.readOnlyMode) g.results.add(CheckResult(CheckStatus.info, 'Read-only mode is on', 'Nothing can be sent or changed.', () => const ToolsScreen()));
    // Tools that change things for good without asking first.
    final unasked = telegramTools.where((t) => t.isOn(s) && t.destructive && !t.requiresApproval).length;
    if (unasked > 0) {
      g.results.add(CheckResult(CheckStatus.warn, '$unasked destructive tool${unasked == 1 ? '' : 's'} run without asking', 'Deleting and leaving can\'t be undone; consider asking first.', () => const ToolsScreen()));
    }
    // The same tool name twice would confuse the model.
    final names = <String>{};
    final twice = [for (final t in telegramTools) if (!names.add(t.name)) t.name];
    if (twice.isNotEmpty) g.results.add(CheckResult(CheckStatus.fail, 'Tools defined twice', twice.join(', ')));
    final accounts = read(accountsProvider);
    if (accounts.hasSeveral) {
      final telegramOn = telegramTools.where((t) => t.needsTelegram && t.isOn(s)).length;
      g.results.add(CheckResult(CheckStatus.info, '$telegramOn Telegram tools across ${accounts.forAi.length} account${accounts.forAi.length == 1 ? '' : 's'}', 'Each call says which account it acts in.'));
    }
    final usage = read(usageProvider).where((e) => DateTime.now().difference(e.at).inDays < 30).toList();
    final spent = usage.fold<double>(0, (n, e) => n + e.cost);
    g.results.add(CheckResult(CheckStatus.info, '${usd(spent)} spent in 30 days', '${usage.length} requests and tool calls.', () => const UsageScreen()));
    final calls = usage.where((e) => e.modality.isCapability).toList();
    final failed = calls.where((e) => !e.ok).length;
    if (calls.length >= 5 && failed / calls.length > 0.3) {
      g.results.add(CheckResult(CheckStatus.warn, '$failed of ${calls.length} MCP and skill calls failed', 'See which in Usage → MCP & Skills.', () => const UsageScreen()));
    }
    final chats = read(chatControllerProvider).history.length;
    g.results.add(CheckResult(CheckStatus.info, '$chats AI chats on this phone', 'Back them up in Data & backup.', () => const DataScreen()));
  }

  Future<void> _upkeep(CheckGroup g) async {
    final s = read(settingsProvider);
    final memories = await _try(read(aiProvider).memory.all());
    if (memories != null) {
      g.results.add(CheckResult(
        memories.isEmpty ? CheckStatus.improve : CheckStatus.ok,
        memories.isEmpty ? 'No memories yet' : '${memories.length} memories',
        memories.isEmpty ? 'Tell the assistant what to remember (your name, work, preferences) so it can tailor answers.' : '',
        () => const SettingsScreen(section: SettingsSection.assistant),
      ));
    }
    final briefs = read(briefStoreProvider).briefs;
    if (!s.briefsScheduled) {
      g.results.add(CheckResult(CheckStatus.improve, "Briefs aren't scheduled", 'A morning and evening brief of what happened and what needs you.', () => const BriefSettingsScreen()));
    } else {
      g.results.add(CheckResult(CheckStatus.ok, 'Briefs at ${s.briefMorning} and ${s.briefNight}'));
    }
    final last = briefs.firstOrNull;
    if (last?.error != null) {
      g.results.add(CheckResult(CheckStatus.warn, 'The last brief failed', last!.error!, () => const BriefSettingsScreen()));
    }
    final prefs = await SharedPreferences.getInstance();
    final backup = DateTime.tryParse(prefs.getString(AppData.lastBackupKey) ?? '');
    if (backup == null) {
      g.results.add(CheckResult(CheckStatus.improve, 'Never backed up', 'Export a profile so settings, watches, widgets, skills and memories survive a reinstall.', () => const DataScreen()));
    } else {
      final days = DateTime.now().difference(backup).inDays;
      g.results.add(CheckResult(
        days > 30 ? CheckStatus.improve : CheckStatus.ok,
        days == 0 ? 'Backed up today' : 'Backed up $days day${days == 1 ? '' : 's'} ago',
        days > 30 ? 'A fresh export keeps what changed since.' : '',
        () => const DataScreen(),
      ));
    }
    final size = await _try(_folderSize(), timeout: const Duration(seconds: 20));
    if (size != null) {
      final mb = size / (1024 * 1024);
      g.results.add(CheckResult(
        mb > 1500 ? CheckStatus.warn : CheckStatus.info,
        "Triangle's files: ${mb < 1 ? '<1' : mb.round()} MB",
        mb > 1500 ? "Downloads, generated files and voice notes add up: clear what you don't need." : "Chats, files the assistant made, downloads and caches (not Telegram's own data).",
        () => const StorageScreen(),
      ));
    }
    if (s.quietHours) g.results.add(CheckResult(CheckStatus.info, 'Quiet hours ${s.quietStart}–${s.quietEnd}', 'Notifications wait until they end.'));
  }

  static Future<int> _folderSize() async {
    final root = Directory((await getApplicationSupportDirectory()).path);
    var total = 0;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length().catchError((_) => 0);
    }
    return total;
  }
}
