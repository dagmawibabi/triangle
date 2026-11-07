import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../account/storage_screen.dart';
import '../data/app_data.dart';
import '../../brief/widget_customizer_screen.dart';
import '../../chat/data/chat_controller.dart';
import '../../integrations/integrations_store.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/data/telegram_tools.dart';
import '../../usage/usage.dart';
import '../../usage/usage_screen.dart';
import '../data/settings.dart';
import 'capability_settings.dart';
import 'data_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart';

/// How a check came out.
enum CheckStatus {
  ok(Icons.check_circle_rounded),
  improve(Icons.tips_and_updates_outlined),
  warn(Icons.warning_amber_rounded),
  fail(Icons.error_rounded),
  info(Icons.info_outline_rounded);

  const CheckStatus(this.icon);
  final IconData icon;

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
  CheckGroup(this.title, this.icon);
  final String title;
  final IconData icon;
  final List<CheckResult> results = [];
  bool done = false;

  CheckStatus get worst {
    for (final s in const [CheckStatus.fail, CheckStatus.warn, CheckStatus.improve]) {
      if (results.any((r) => r.status == s)) return s;
    }
    return CheckStatus.ok;
  }
}

/// Settings → System check: goes through everything the app depends on —
/// AI keys and models, Telegram (TDLib), decisions, MCP servers, skills,
/// connected apps, watches and the check-in, widgets, voice, tools,
/// permissions and usage — and says what works, what's missing and what
/// could be better. It only reads; nothing is changed.
class SystemCheckScreen extends ConsumerStatefulWidget {
  const SystemCheckScreen({super.key});

  @override
  ConsumerState<SystemCheckScreen> createState() => _SystemCheckScreenState();
}

class _SystemCheckScreenState extends ConsumerState<SystemCheckScreen> {
  List<CheckGroup> _groups = const [];
  bool _running = false;
  DateTime? _at;

  static Future<T?> _try<T>(Future<T> work, {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await work.timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  static String _error(Object e) => '$e'.replaceFirst(RegExp(r'^\w*Exception:?\s*'), '');

  Future<void> _scan() async {
    final steps = <(CheckGroup, Future<void> Function(CheckGroup))>[
      (CheckGroup('AI & models', Icons.auto_awesome_outlined), _ai),
      (CheckGroup('Telegram (TDLib)', Icons.send_rounded), _telegram),
      (CheckGroup('Decisions (Jev)', Icons.balance_rounded), _decisions),
      (CheckGroup('MCP servers', Icons.hub_outlined), _mcp),
      (CheckGroup('Skills', Icons.auto_stories_outlined), _skills),
      (CheckGroup('Connected apps & services', Icons.apps_rounded), _connectors),
      (CheckGroup('Watches, routines & check-in', Icons.visibility_outlined), _automation),
      (CheckGroup('Home-screen widgets', Icons.widgets_outlined), _widgets),
      (CheckGroup('Voice', Icons.graphic_eq_rounded), _voice),
      (CheckGroup('Tools, usage & data', Icons.build_outlined), _tools),
      (CheckGroup('Memory, briefs, backup & storage', Icons.inventory_2_outlined), _upkeep),
    ];
    setState(() {
      _running = true;
      _groups = [for (final (g, _) in steps) g];
    });
    for (final (group, run) in steps) {
      try {
        await run(group);
      } catch (e) {
        group.results.add(CheckResult(CheckStatus.fail, 'The check itself failed', _error(e)));
      }
      group.done = true;
      if (!mounted) return;
      setState(() {});
    }
    if (mounted) {
      setState(() {
        _running = false;
        _at = DateTime.now();
      });
    }
  }

  // ---- the checks -------------------------------------------------------------

  Future<void> _ai(CheckGroup g) async {
    final s = ref.read(settingsProvider);
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
    await _try(ref.read(modelCatalogProvider.notifier).ensureLoaded(), timeout: const Duration(seconds: 25));
    final catalog = ref.read(modelCatalogProvider);
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
    final telegramReady = ref.read(telegramClientProvider).authState is td.AuthorizationStateReady;
    for (final name in ['generate_image', if (s.videoEnabled) 'generate_video']) {
      final tool = telegramTools.where((t) => t.name == name).firstOrNull;
      if (tool == null) continue;
      final problems = toolPrerequisiteProblems(tool, s, telegram: telegramReady, connected: ref.read(integrationsProvider).connected);
      g.results.add(problems.isEmpty
          ? CheckResult(CheckStatus.ok, name == 'generate_image' ? 'Images: ${s.imageModel}' : 'Video: ${s.videoModel}')
          : CheckResult(CheckStatus.warn, name == 'generate_image' ? "Pictures can't be made" : "Videos can't be made", problems.join(' '), media));
    }
    if (!s.videoEnabled) g.results.add(CheckResult(CheckStatus.info, 'Video is off', 'Turn it on and pick a model in Images & video.', media));
  }

  Future<void> _telegram(CheckGroup g) async {
    final s = ref.read(settingsProvider);
    final client = ref.read(telegramClientProvider);
    if (client.authState is! td.AuthorizationStateReady) {
      g.results.add(CheckResult(
        s.telegramSkipped ? CheckStatus.info : CheckStatus.warn,
        s.telegramSkipped ? 'Telegram isn\'t connected' : 'Telegram isn\'t signed in',
        'Chats, channels, mention alerts and Telegram watches need it.',
        () => const AppsWebScreen(),
      ));
      return;
    }
    final clock = Stopwatch()..start();
    final version = await _try(client.send<td.TdObject>(const td.GetOption(name: 'version')), timeout: const Duration(seconds: 8));
    if (version == null) {
      g.results.add(const CheckResult(CheckStatus.fail, 'TDLib isn\'t responding', 'Restart the app; if it stays, check Settings → About → TDLib controls.'));
      return;
    }
    final v = version is td.OptionValueString ? version.value : '';
    g.results.add(CheckResult(CheckStatus.ok, 'TDLib responding${v.isEmpty ? '' : ' (version $v)'}', 'Answered in ${clock.elapsedMilliseconds} ms.'));
    final store = ref.read(telegramStoreProvider);
    g.results.add(CheckResult(CheckStatus.ok, 'Signed in', '${store.chats.length} chats loaded.'));
    if (s.mentionAlerts && !s.notifications) {
      g.results.add(CheckResult(CheckStatus.warn, 'Mention alerts are on, notifications off', 'You won\'t hear about mentions.', () => const SettingsScreen(section: SettingsSection.proactivity)));
    }
  }

  Future<void> _decisions(CheckGroup g) async {
    final d = ref.read(decisionSettingsProvider);
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
    final mcp = ref.read(aiProvider).mcp;
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
    final skills = ref.read(aiProvider).skills;
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
    final s = ref.read(settingsProvider);
    Widget apps() => const AppsWebScreen();
    if (s.composioKey.trim().isEmpty) {
      g.results.add(CheckResult(CheckStatus.improve, 'Apps aren\'t set up', 'Connect Gmail, Calendar, Slack, Notion and more for the assistant and the check-in.', apps));
    } else {
      await _try(ref.read(integrationsProvider.notifier).refresh(), timeout: const Duration(seconds: 20));
      final st = ref.read(integrationsProvider);
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
    final s = ref.read(settingsProvider);
    final watches = ref.read(watchStoreProvider);
    final active = watches.where((w) => w.enabled).toList();
    final jobs = ref.read(reminderStoreProvider).where((r) => r.enabled && r.isJob).length;
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
    final notifier = ref.read(appNotifierProvider);
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
    } else if (notifier.alive) {
      g.results.add(const CheckResult(CheckStatus.ok, 'Running in the background'));
    }
    final store = ref.read(telegramStoreProvider);
    final accounts = ref.read(accountsProvider);
    final telegram = ref.read(telegramClientProvider).authState is td.AuthorizationStateReady || accounts.signedIn.isNotEmpty;
    final connected = ref.read(integrationsProvider).connected;
    for (final w in active) {
      // The accounts it covers, as stores; a folder watch has one.
      final covered = [
        for (final a in accounts.signedIn)
          if (w.covers(a.id)) ref.read(telegramStoreFamily(a.id)),
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
    final error = ref.read(watchEngineProvider).status.value.error;
    if (error != null) g.results.add(CheckResult(CheckStatus.warn, 'Last watch problem', error, page));
  }

  Future<void> _widgets(CheckGroup g) async {
    final store = ref.read(homeWidgetsProvider.notifier);
    await store.ready;
    final defs = ref.read(homeWidgetsProvider).where((d) => !d.isBrief).toList();
    final placed = await store.instances();
    g.results.add(CheckResult(
      placed.isEmpty ? CheckStatus.info : CheckStatus.ok,
      placed.isEmpty ? 'None on the home screen' : '${placed.length} on the home screen',
      placed.isEmpty ? 'Long-press the home screen → Widgets → Triangle.' : '',
      () => const WidgetCustomizerScreen(),
    ));
    final watches = ref.read(watchStoreProvider.notifier);
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
    final s = ref.read(settingsProvider);
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
    final s = ref.read(settingsProvider);
    final telegram = ref.read(telegramClientProvider).authState is td.AuthorizationStateReady;
    final connected = ref.read(integrationsProvider).connected;
    final blocked = <String, int>{};
    var on = 0;
    for (final t in telegramTools.where((t) => t.isOn(s))) {
      on++;
      final problems = toolPrerequisiteProblems(t, s, telegram: telegram, connected: connected, decisionsReady: ref.read(decisionsReadyProvider));
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
    final usage = ref.read(usageProvider).where((e) => DateTime.now().difference(e.at).inDays < 30).toList();
    final spent = usage.fold<double>(0, (n, e) => n + e.cost);
    g.results.add(CheckResult(CheckStatus.info, '${usd(spent)} spent in 30 days', '${usage.length} requests and tool calls.', () => const UsageScreen()));
    final calls = usage.where((e) => e.modality.isCapability).toList();
    final failed = calls.where((e) => !e.ok).length;
    if (calls.length >= 5 && failed / calls.length > 0.3) {
      g.results.add(CheckResult(CheckStatus.warn, '$failed of ${calls.length} MCP and skill calls failed', 'See which in Usage → MCP & Skills.', () => const UsageScreen()));
    }
    final chats = ref.read(chatControllerProvider).history.length;
    g.results.add(CheckResult(CheckStatus.info, '$chats AI chats on this phone', 'Back them up in Data & backup.', () => const DataScreen()));
  }

  Future<void> _upkeep(CheckGroup g) async {
    final s = ref.read(settingsProvider);
    final memories = await _try(ref.read(aiProvider).memory.all());
    if (memories != null) {
      g.results.add(CheckResult(
        memories.isEmpty ? CheckStatus.improve : CheckStatus.ok,
        memories.isEmpty ? 'No memories yet' : '${memories.length} memories',
        memories.isEmpty ? 'Tell the assistant what to remember (your name, work, preferences) so it can tailor answers.' : '',
        () => const SettingsScreen(section: SettingsSection.assistant),
      ));
    }
    final briefs = ref.read(briefStoreProvider).briefs;
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

  // ---- the page --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final all = [for (final g in _groups) ...g.results];
    int count(CheckStatus s) => all.where((r) => r.status == s).length;
    return Scaffold(
      appBar: AppBar(title: const Text('System check')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
            children: [
              Container(
                padding: const EdgeInsets.all(Space.xl),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.xl),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _groups.isEmpty
                          ? 'Check everything'
                          : _running
                          ? 'Checking ${_groups.where((g) => g.done).length + 1} of ${_groups.length}…'
                          : count(CheckStatus.fail) + count(CheckStatus.warn) == 0
                          ? 'All good'
                          : '${count(CheckStatus.fail) + count(CheckStatus.warn)} things need attention',
                      style: context.text.titleLarge,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      _groups.isEmpty
                          ? 'Goes through AI keys and models, Telegram, decisions, MCP servers, skills, connected apps, '
                                'watches and the check-in, widgets, voice, tools, permissions and usage. It only looks; '
                                'nothing is changed.'
                          : [
                              if (count(CheckStatus.fail) > 0) '${count(CheckStatus.fail)} broken',
                              if (count(CheckStatus.warn) > 0) '${count(CheckStatus.warn)} warnings',
                              if (count(CheckStatus.improve) > 0) '${count(CheckStatus.improve)} could be better',
                              '${count(CheckStatus.ok)} fine',
                              if (_at != null) 'checked ${TimeOfDay.fromDateTime(_at!).format(context)}',
                            ].join(' · '),
                      style: context.text.bodySmall,
                    ),
                    if (_running) ...[
                      const SizedBox(height: Space.m),
                      LinearProgressIndicator(value: _groups.where((g) => g.done).length / _groups.length),
                    ],
                    const SizedBox(height: Space.l),
                    FilledButton.icon(
                      onPressed: _running ? null : _scan,
                      icon: const Icon(Icons.radar_rounded),
                      label: Text(_groups.isEmpty ? 'Scan' : 'Scan again'),
                    ),
                  ],
                ),
              ),
              for (final g in _groups) _GroupCard(group: g),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final CheckGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final shown = [...g.results]..sort((a, b) => a.status.index == b.status.index ? 0 : _rank(a.status).compareTo(_rank(b.status)));
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: g.done && g.worst != CheckStatus.ok,
              key: ValueKey('${g.title}-${g.done}'),
              leading: lead(Icon(g.icon)),
              title: Text(g.title),
              subtitle: Text(
                !g.done ? 'Checking…' : '${g.results.length} check${g.results.length == 1 ? '' : 's'}',
                style: context.text.bodySmall,
              ),
              trailing: !g.done
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(g.worst.icon, color: g.worst.color),
              children: [
                for (final r in shown)
                  ListTile(
                    dense: true,
                    leading: Icon(r.status.icon, color: r.status.color, size: 20),
                    title: Text(r.title),
                    subtitle: r.detail.isEmpty ? null : Text(r.detail, style: context.text.bodySmall),
                    trailing: r.fix == null ? null : Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: r.fix == null ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => r.fix!())),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _rank(CheckStatus s) => switch (s) {
    CheckStatus.fail => 0,
    CheckStatus.warn => 1,
    CheckStatus.improve => 2,
    CheckStatus.info => 3,
    CheckStatus.ok => 4,
  };
}
