import 'dart:convert';

import '../../ai/data/ai.dart';
import '../../ai/data/decision_settings.dart';
import '../../bible/bible.dart' show bibleSettingsProvider;
import '../../info/info_keys.dart';
import '../../settings/data/settings.dart';
import '../../settings/data/system_check.dart' show ProviderReader;
import 'telegram_tools.dart' show ToolOutput, apiKeyServiceIds;

// Runs the tools in telegram_system_tools.dart: the API keys of every
// service that takes one (AI, apps, cloud, web data), the app's look and
// everyday preferences. A key is never returned: only whether one is set,
// its last four characters and whether it works.

/// A service whose key the tools manage.
class ApiKeyService {
  const ApiKeyService(
    this.id,
    this.name,
    this.group,
    this.uses,
    this.url, {
    required this.get,
    required this.set,
    this.checkId,
    this.address = false,
    this.ready,
  });

  /// How the tools name it: `vercel`.
  final String id;
  final String name;

  /// ai, apps, cloud, web or money.
  final String group;

  /// What the app uses it for.
  final List<String> uses;

  /// Where to get a key.
  final String url;

  /// The key now ('' when none).
  final String Function(ProviderReader read) get;

  /// Saves a key ('' removes it).
  final Future<void> Function(ProviderReader read, String key) set;

  /// The omni_ai provider or toolkit that can test a key; null when it
  /// can't be tested here.
  final String? checkId;

  /// Holds an address or id, not a secret, so it is shown whole.
  final bool address;

  /// Waits until the key is loaded from storage.
  final Future<void> Function(ProviderReader read)? ready;
}

AppSettings _s(ProviderReader read) => read(settingsProvider);
SettingsController _c(ProviderReader read) => read(settingsProvider.notifier);
Future<void> _info(ProviderReader read) => InfoKeysNotifier.load();
InfoKeysNotifier _i(ProviderReader read) => read(infoKeysProvider.notifier);

final apiKeyServices = <ApiKeyService>[
  // ---- AI: chat, images & video, voice, decisions
  ApiKeyService('vercel', 'Vercel AI Gateway', 'ai', ['chat', 'images', 'video', 'speech', 'dictation'], 'https://vercel.com/ai-gateway',
      get: (r) => _s(r).vercelKey, set: (r, k) => _c(r).setVercelKey(k), checkId: 'gateway'),
  ApiKeyService('openrouter', 'OpenRouter', 'ai', ['chat', 'images', 'video', 'speech', 'dictation'], 'https://openrouter.ai/keys',
      get: (r) => _s(r).openRouterKey, set: (r, k) => _c(r).setOpenRouterKey(k), checkId: 'openrouter'),
  ApiKeyService('opencode', 'OpenCode Zen', 'ai', ['chat'], 'https://opencode.ai/console',
      get: (r) => _s(r).openCodeKey, set: (r, k) => _c(r).setOpenCodeKey(k), checkId: 'opencode'),
  ApiKeyService('gemini', 'Google AI Studio', 'ai', ['chat', 'images', 'video', 'speech', 'dictation'], 'https://aistudio.google.com/app/apikey',
      get: (r) => _s(r).geminiKey, set: (r, k) => _c(r).setGeminiKey(k), checkId: 'google'),
  ApiKeyService('lmstudio', 'LM Studio (server address)', 'ai', ['chat'], 'https://lmstudio.ai/docs/developer',
      get: (r) => _s(r).lmStudioUrl, set: (r, k) => _c(r).setLmStudioUrl(k), checkId: 'lmstudio', address: true),
  ApiKeyService('addis', 'Addis AI', 'ai', ['speech', 'dictation'], 'https://addisassistant.com/api-keys',
      get: (r) => _s(r).addisKey, set: (r, k) => _c(r).setAddisKey(k), checkId: 'addis'),
  ApiKeyService('elevenlabs', 'ElevenLabs', 'ai', ['speech', 'dictation', 'sound effects', 'music'], 'https://elevenlabs.io/app/settings/api-keys',
      get: (r) => _s(r).elevenKey, set: (r, k) => _c(r).setElevenKey(k), checkId: 'elevenlabs'),
  ApiKeyService('jev', 'TypeSafe Jev', 'ai', ['decisions'], 'https://console.typesafe.ai',
      get: (r) => r(decisionSettingsProvider).apiKey,
      set: (r, k) => r(decisionSettingsProvider.notifier).setApiKey(k),
      ready: (r) => r(decisionSettingsProvider.notifier).ready,
      checkId: 'jev'),
  // ---- Connected apps
  ApiKeyService('composio', 'Composio', 'apps', ['Gmail, Calendar, Drive, Slack, Notion, GitHub, Linear, Todoist and other connected apps'],
      'https://dashboard.composio.dev',
      get: (r) => _s(r).composioKey, set: (r, k) => _c(r).setComposioKey(k), checkId: 'composio'),
  // ---- Your cloud
  ApiKeyService('cloudflare', 'Cloudflare API token', 'cloud', ['Cloudflare browser, DNS, Workers, KV'], 'https://dash.cloudflare.com/profile/api-tokens',
      get: (r) => _s(r).cloudflareToken, set: (r, k) => _c(r).setCloudflareToken(k), checkId: 'cloudflare'),
  ApiKeyService('cloudflare_account', 'Cloudflare account ID', 'cloud', ['Cloudflare tools'], 'https://dash.cloudflare.com',
      get: (r) => _s(r).cloudflareAccountId, set: (r, k) => _c(r).setCloudflareAccountId(k), address: true),
  ApiKeyService('r2_access_key_id', 'Cloudflare R2 access key ID', 'cloud', ['R2 storage'],
      'https://dash.cloudflare.com/?to=/:account/r2/api-tokens',
      get: (r) => _s(r).r2AccessKeyId, set: (r, k) => _c(r).setR2Keys(accessKeyId: k)),
  ApiKeyService('r2_secret_key', 'Cloudflare R2 secret access key', 'cloud', ['R2 storage'],
      'https://dash.cloudflare.com/?to=/:account/r2/api-tokens',
      get: (r) => _s(r).r2SecretKey, set: (r, k) => _c(r).setR2Keys(secret: k)),
  ApiKeyService('e2b', 'E2B', 'cloud', ['cloud code sandbox'], 'https://e2b.dev/dashboard?tab=keys',
      get: (r) => _s(r).e2bKey, set: (r, k) => _c(r).setE2bKey(k), checkId: 'e2b'),
  // ---- The web
  ApiKeyService('exa', 'Exa', 'web', ['web search'], 'https://dashboard.exa.ai/api-keys',
      get: (r) => _s(r).exaKey, set: (r, k) => _c(r).setExaKey(k), checkId: 'exa'),
  ApiKeyService('youtube', 'YouTube Data API', 'web', ['YouTube search, videos, channels'],
      'https://console.cloud.google.com/apis/library/youtube.googleapis.com',
      get: (r) => _s(r).youtubeKey, set: (r, k) => _c(r).setYoutubeKey(k)),
  ApiKeyService('reddit', 'Reddit client ID', 'web', ['Reddit'], 'https://www.reddit.com/prefs/apps',
      get: (r) => _s(r).redditClientId, set: (r, k) => _c(r).setRedditClientId(k)),
  ApiKeyService('nasa', 'NASA', 'web', ['space pictures and data'], 'https://api.nasa.gov/',
      get: (r) => _s(r).nasaKey, set: (r, k) => _c(r).setNasaKey(k)),
  ApiKeyService('coingecko', 'CoinGecko', 'web', ['crypto prices'], 'https://www.coingecko.com/en/developers/dashboard',
      get: (r) => _s(r).coingeckoKey, set: (r, k) => _c(r).setCoingeckoKey(k)),
  ApiKeyService('scholarxiv', 'ScholarXIV', 'web', ['research papers'], 'https://scholarxiv.com/developers/dashboard/apikeys',
      get: (r) => _s(r).scholarxivKey, set: (r, k) => _c(r).setScholarxivKey(k)),
  ApiKeyService('metals', 'metals.dev', 'web', ['gold and metal prices'], 'https://metals.dev/',
      get: (r) => InfoKeysNotifier.current.metalsKey, set: (r, k) => _i(r).setMetalsKey(k), ready: _info),
  ApiKeyService('libretranslate_url', 'LibreTranslate server', 'web', ['translation'], 'https://libretranslate.com/',
      get: (r) => InfoKeysNotifier.current.libreUrl, set: (r, k) => _i(r).setLibreUrl(k), ready: _info, address: true),
  ApiKeyService('libretranslate', 'LibreTranslate API key', 'web', ['translation'], 'https://libretranslate.com/',
      get: (r) => InfoKeysNotifier.current.libreKey, set: (r, k) => _i(r).setLibreKey(k), ready: _info),
  ApiKeyService('football_data', 'football-data.org', 'web', ['football top scorers'], 'https://www.football-data.org/client/register',
      get: (r) => InfoKeysNotifier.current.footballDataKey, set: (r, k) => _i(r).setFootballDataKey(k), ready: _info),
  ApiKeyService('thesportsdb', 'TheSportsDB', 'web', ['sports scores and teams'], 'https://www.thesportsdb.com/free_sports_api',
      get: (r) => InfoKeysNotifier.current.sportsDbKey, set: (r, k) => _i(r).setSportsDbKey(k), ready: _info),
  ApiKeyService('youversion', 'YouVersion (Bible)', 'web', ['licensed Bible versions'], 'https://platform.youversion.com',
      get: (r) => r(bibleSettingsProvider).token,
      set: (r, k) => r(bibleSettingsProvider.notifier).setToken(k),
      ready: (r) => r(bibleSettingsProvider.notifier).ready),
  // ---- Money
  ApiKeyService('verify_et', 'Verify.ET', 'money', ['checking Ethiopian bank and Telebirr receipts'], 'https://verify.et/docs/get-started',
      get: (r) => _s(r).verifyEtKey, set: (r, k) => _c(r).setVerifyEtKey(k)),
];

ApiKeyService? apiKeyService(String id) => apiKeyServices.where((s) => s.id == id.trim().toLowerCase()).firstOrNull;

/// The last four characters of [key], for telling keys apart without
/// showing them. Empty when there is no key, all of it for an address.
String keyEnding(String key, {bool address = false}) {
  final k = key.trim();
  if (k.isEmpty) return '';
  if (address) return k;
  return k.length <= 8 ? '…' : '…${k.substring(k.length - 4)}';
}

/// [arguments] of a set_api_key call with the key hidden, so the saved
/// conversation (and what is sent back to the model) never holds it.
String redactKeyArguments(String arguments) {
  try {
    final a = Map<String, dynamic>.from(jsonDecode(arguments) as Map);
    final service = apiKeyService('${a['service'] ?? ''}');
    if (a['key'] is String && !(service?.address ?? false)) a['key'] = '[hidden ${keyEnding(a['key'] as String)}]';
    return jsonEncode(a);
  } catch (_) {
    return arguments;
  }
}

Future<String> _keyOf(ProviderReader read, ApiKeyService s) async {
  await s.ready?.call(read);
  return s.get(read);
}

Future<void> _save(ProviderReader read, ApiKeyService s, String key) async {
  await s.ready?.call(read);
  await s.set(read, key);
}

Map<String, dynamic> _appSettings(AppSettings s) => {
      'appearance': {
        'theme': s.themeMode.name,
        'accent': s.accent.name,
        'chat_font': s.chatFont.name,
        'chat_font_size': s.chatFontSize,
        'code_theme': s.codeTheme.name,
        'orb_shape': s.orbShape.name,
      },
      'preferences': {
        'answer_style': s.answerStyle.name,
        'speech_rate': s.speechRate,
        'haptics': s.haptics,
        'auto_download_photos': s.autoPhotos,
        'auto_download_voice': s.autoVoice,
        'auto_download_music': s.autoMusic,
      },
    };

Future<ToolOutput> runSystemTool(ProviderReader read, String name, Map<String, dynamic> a) async {
  ApiKeyService service() {
    final id = '${a['service'] ?? ''}';
    return apiKeyService(id) ??
        (throw ArgumentError('Unknown service "$id". Use one of: ${apiKeyServiceIds.join(', ')}.'));
  }

  /// Null when [key] works, else what the service said. Services that
  /// can't be tested here count as working.
  Future<String?> check(ApiKeyService s, String key) async {
    final id = s.checkId;
    if (id == null) return null;
    try {
      return await read(aiProvider).verifyKey(id, key: key).timeout(const Duration(seconds: 30));
    } catch (e) {
      return aiErrorText(e);
    }
  }

  switch (name) {
    case 'list_api_keys':
      final test = a['check'] == true;
      final group = '${a['group'] ?? ''}'.trim();
      final keys = <Map<String, dynamic>>[];
      final checks = <Future<void>>[];
      for (final s in apiKeyServices) {
        if (group.isNotEmpty && s.group != group) continue;
        final key = (await _keyOf(read, s)).trim();
        final row = <String, dynamic>{
          'service': s.id,
          'name': s.name,
          'group': s.group,
          'uses': s.uses,
          'set': key.isNotEmpty,
          if (key.isNotEmpty) 'ends_with': keyEnding(key, address: s.address),
          'get_key_at': s.url,
        };
        if (test && key.isNotEmpty) {
          if (s.checkId == null) {
            row['works'] = 'not testable here';
          } else {
            checks.add(check(s, key).then((problem) {
              row['works'] = problem == null;
              if (problem != null) row['problem'] = problem;
            }));
          }
        }
        keys.add(row);
      }
      await Future.wait(checks);
      return ToolOutput({'keys': keys, 'set_count': keys.where((k) => k['set'] == true).length});

    case 'set_api_key':
      final s = service();
      final key = '${a['key'] ?? ''}'.trim();
      if (key.isEmpty) throw ArgumentError('Give the key to save.');
      if (key.contains(RegExp(r'\s'))) throw ArgumentError('A key has no spaces; check what the user gave.');
      final before = (await _keyOf(read, s)).trim();
      if (before == key) {
        return ToolOutput({'service': s.id, 'name': s.name, 'action': 'unchanged', 'ends_with': keyEnding(key, address: s.address), 'uses': s.uses});
      }
      final test = a['check'] != false && s.checkId != null;
      if (test) {
        final problem = await check(s, key);
        if (problem != null) {
          return ToolOutput({'error': '${s.name} refused this key, so it was not saved: $problem', 'service': s.id});
        }
      }
      await _save(read, s, key);
      return ToolOutput({
        'service': s.id,
        'name': s.name,
        'action': before.isEmpty ? 'added' : 'replaced',
        'ends_with': keyEnding(key, address: s.address),
        'checked': test,
        if (s.checkId == null) 'note': '${s.name} keys can\'t be tested here; it is checked the first time a tool uses it.',
        'uses': s.uses,
      });

    case 'delete_api_key':
      final s = service();
      final before = (await _keyOf(read, s)).trim();
      if (before.isEmpty) {
        return ToolOutput({'service': s.id, 'name': s.name, 'removed': false, 'note': '${s.name} had no key.'});
      }
      await _save(read, s, '');
      String note;
      if (s.group == 'ai') {
        final left = [
          for (final o in apiKeyServices)
            if (o.group == 'ai' && o.id != s.id && (await _keyOf(read, o)).trim().isNotEmpty) o.name,
        ];
        note = left.isEmpty
            ? 'No AI service has a key now; the assistant can\'t answer until one is added.'
            : 'Features that used ${s.name} switch to ${left.join(', ')} where they can.';
      } else {
        note = 'Tools that need ${s.name} (${s.uses.join(', ')}) stop working until a key is added again.';
      }
      return ToolOutput({
        'service': s.id,
        'name': s.name,
        'removed': true,
        'ends_with': keyEnding(before, address: s.address),
        'note': s.address ? note : '$note The key still works at ${s.name}; revoke it there if it should stop working.',
      });

    case 'get_app_settings':
      return ToolOutput(_appSettings(read(settingsProvider)));

    case 'set_appearance':
      final c = read(settingsProvider.notifier);
      final changed = <String>[];
      T? pick<T extends Enum>(String key, List<T> values) {
        final v = a[key];
        if (v == null) return null;
        return values.where((e) => e.name == '$v').firstOrNull ??
            (throw ArgumentError('$key must be one of: ${values.map((e) => e.name).join(', ')}.'));
      }

      final theme = pick('theme', AppThemeMode.values);
      final accent = pick('accent', AccentChoice.values);
      final font = pick('chat_font', ChatFont.values);
      final code = pick('code_theme', CodeThemeChoice.values);
      final orb = pick('orb_shape', OrbShape.values);
      final size = a['chat_font_size'] is num ? (a['chat_font_size'] as num).toDouble() : null;
      if (size != null && (size < 13 || size > 21)) throw ArgumentError('chat_font_size must be 13 to 21.');
      if (theme != null) {
        await c.setThemeMode(theme);
        changed.add('theme');
      }
      if (accent != null) {
        await c.setAccent(accent);
        changed.add('accent');
      }
      if (font != null) {
        await c.setChatFont(font);
        changed.add('chat_font');
      }
      if (size != null) {
        await c.setChatFontSize(size);
        changed.add('chat_font_size');
      }
      if (code != null) {
        await c.setCodeTheme(code);
        changed.add('code_theme');
      }
      if (orb != null) {
        await c.setOrbShape(orb);
        changed.add('orb_shape');
      }
      if (changed.isEmpty) throw ArgumentError('Give at least one of: theme, accent, chat_font, chat_font_size, code_theme, orb_shape.');
      return ToolOutput({'changed': changed, ..._appSettings(read(settingsProvider))});

    case 'set_preferences':
      final c = read(settingsProvider.notifier);
      final changed = <String>[];
      final style = a['answer_style'];
      if (style != null) {
        final v = AnswerStyle.values.where((e) => e.name == '$style').firstOrNull ??
            (throw ArgumentError('answer_style must be concise, balanced or detailed.'));
        await c.setAnswerStyle(v);
        changed.add('answer_style');
      }
      if (a['speech_rate'] is num) {
        final rate = (a['speech_rate'] as num).toDouble();
        if (rate < 0.5 || rate > 2.5) throw ArgumentError('speech_rate must be 0.5 to 2.5.');
        await c.setSpeechRate(rate);
        changed.add('speech_rate');
      }
      if (a['haptics'] is bool) {
        await c.setHaptics(a['haptics'] as bool);
        changed.add('haptics');
      }
      bool? flag(String k) => a[k] is bool ? a[k] as bool : null;
      final photos = flag('auto_download_photos');
      final voice = flag('auto_download_voice');
      final music = flag('auto_download_music');
      if (photos != null || voice != null || music != null) {
        await c.setAutoDownload(photos: photos, voice: voice, music: music);
        changed.addAll([
          if (photos != null) 'auto_download_photos',
          if (voice != null) 'auto_download_voice',
          if (music != null) 'auto_download_music',
        ]);
      }
      if (changed.isEmpty) {
        throw ArgumentError('Give at least one of: answer_style, speech_rate, haptics, auto_download_photos, '
            'auto_download_voice, auto_download_music.');
      }
      return ToolOutput({'changed': changed, ..._appSettings(read(settingsProvider))});
  }
  throw ArgumentError('No system tool named $name.');
}
