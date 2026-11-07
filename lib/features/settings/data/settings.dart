import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/data/ai.dart' show canonicalModelId;

/// How much a reasoning model may think before answering.
enum Thinking {
  auto('Auto'),
  off('Off'),
  low('Low'),
  medium('Medium'),
  high('High');

  const Thinking(this.label);
  final String label;
}

/// Light or dark, or whatever the phone uses.
enum AppThemeMode {
  system('System'),
  light('Light'),
  dark('Dark');

  const AppThemeMode(this.label);
  final String label;
}

/// What voice mode's reacting shape is.
enum OrbShape {
  triangle('Triangle'),
  sphere('Sphere');

  const OrbShape(this.label);
  final String label;
}

/// The typeface answers and messages are set in.
enum ChatFont {
  system('Default', null),
  serif('Serif', 'serif'),
  mono('Mono', 'monospace');

  const ChatFont(this.label, this.family);
  final String label;

  /// The font family; null keeps the app's own.
  final String? family;
}

/// Who reads answers aloud.
enum VoiceEngine {
  device('Device'),
  ai('AI model'),
  addis('Addis AI'),
  elevenLabs('ElevenLabs');

  const VoiceEngine(this.label);
  final String label;
}

/// Who turns speech into text in the input box.
enum DictationEngine {
  device('Device'),
  ai('AI model'),
  elevenLabs('ElevenLabs');

  const DictationEngine(this.label);
  final String label;
}

enum AccentChoice {
  blue('Blue', 0xFF8AB4FF),
  violet('Violet', 0xFFB49CFF),
  mint('Mint', 0xFF69D9BA),
  coral('Coral', 0xFFFF9A8D),
  amber('Amber', 0xFFFFC86B),
  mono('Monochrome', 0xFFF4F4F5);

  const AccentChoice(this.label, this.value);
  final String label;
  final int value;
}

/// How much the assistant writes.
enum AnswerStyle {
  concise('Concise', 'Short and to the point'),
  balanced('Balanced', 'Clear, with the detail that matters'),
  detailed('Detailed', 'Thorough, with context and specifics');

  const AnswerStyle(this.label, this.explanation);
  final String label;
  final String explanation;
}

enum CodeThemeChoice {
  midnight('Midnight'),
  ocean('Ocean'),
  ember('Ember');

  const CodeThemeChoice(this.label);
  final String label;
}

/// When actions that change something (sending, reacting, muting…) need a tap.
enum ApprovalMode {
  ask('Always ask', 'Every action waits for you to approve it.'),
  watches(
    'Ask in chats only',
    'Watches and routines act on their own; the chat still asks.',
  ),
  never(
    'Never ask',
    'The assistant acts right away everywhere. Use with care.',
  );

  const ApprovalMode(this.label, this.explanation);
  final String label;
  final String explanation;
}

@immutable
class AppSettings {
  const AppSettings({
    this.vercelKey = '',
    this.openRouterKey = '',
    this.geminiKey = '',
    this.lmStudioUrl = '',
    this.addisKey = '',
    this.elevenKey = '',
    this.model = defaultModel,
    this.imageModel = defaultImageModel,
    this.thinking = Thinking.auto,
    this.voiceEngine = VoiceEngine.device,
    this.speechModel = defaultSpeechModel,
    this.aiVoice = '',
    this.deviceVoice = '',
    this.elevenVoiceId = '',
    this.elevenVoiceName = '',
    this.elevenModel = 'eleven_flash_v2_5',
    this.speechRate = 1.0,
    this.dictationEngine = DictationEngine.device,
    this.transcriptionModel = defaultTranscriptionModel,
    this.disabledTools = const {},
    this.enabledDangerTools = const {},
    this.readOnlyMode = false,
    this.accountFallback = false,
    this.autoPhotos = true,
    this.autoVoice = true,
    this.autoMusic = false,
    this.customInstructions = '',
    this.approvalMode = ApprovalMode.ask,
    this.proactive = true,
    this.watchResponseDelaySeconds = 12,
    this.notifications = true,
    this.keepAlive = true,
    this.mentionAlerts = true,
    this.aiReadOnReply = false,
    this.aiReadOnView = false,
    this.backgroundAlways = false,
    this.startOnBoot = false,
    this.drawerChats = true,
    this.drawerFolders = true,
    this.drawerTools = true,
    this.drawerChatsOpen = true,
    this.drawerFoldersOpen = true,
    this.drawerToolsOpen = true,
    this.rainbowLogo = false,
    this.haptics = true,
    this.appearOnline = true,
    this.showMessageUsage = true,
    this.showChatDateTime = true,
    this.briefNightOn = true,
    this.briefMorningOn = true,
    this.autoCompact = true,
    this.compactChat = false,
    this.showModelName = true,
    this.chatFont = ChatFont.system,
    this.themeMode = AppThemeMode.dark,
    this.orbShape = OrbShape.triangle,
    this.voiceEnabled = true,
    this.mediaEnabled = true,
    this.videoEnabled = false,
    this.videoModel = '',
    this.aiChatEnabled = true,
    this.showChatCopyButton = true,
    this.showChatSpeakButton = true,
    this.briefsScheduled = true,
    this.translateTo = '',
    this.showLinkPreviews = true,
    this.answerStyle = AnswerStyle.balanced,
    this.answerLanguage = '',
    this.maxSteps = 14,
    this.showThinking = true,
    this.showToolCalls = true,
    this.leadingIcons = true,
    this.openLastChat = false,
    this.use24h = true,
    this.groupAvatars = true,
    this.compactList = false,
    this.markReadOnOpen = false,
    this.quietHours = false,
    this.quietStart = '23:00',
    this.quietEnd = '07:00',
    this.briefMorning = '08:00',
    this.briefNight = '21:30',
    this.accent = AccentChoice.mono,
    this.chatFontSize = 15.5,
    this.codeTheme = CodeThemeChoice.midnight,
    this.exaKey = '',
    this.composioKey = '',
    this.composioUserId = '',
    this.cloudflareToken = '',
    this.cloudflareAccountId = '',
    this.r2AccessKeyId = '',
    this.r2SecretKey = '',
    this.r2Bucket = '',
    this.e2bKey = '',
    this.e2bTemplate = 'code-interpreter-v1',
    this.e2bTimeoutMinutes = 10,
    this.e2bInternet = true,
    this.e2bKeepAlive = true,
    this.telegramSkipped = false,
    this.loaded = false,
  });

  /// The user's own standing instructions, added to every conversation.
  final String customInstructions;
  final ApprovalMode approvalMode;

  /// Watches and routines may run. Off pauses all of them.
  final bool proactive;

  /// How long a message-triggered watch waits after the newest message before
  /// it starts its AI run. Zero means respond as soon as Telegram delivers it.
  final int watchResponseDelaySeconds;
  final bool notifications;

  /// Keeps the app alive in the background (a quiet ongoing notification)
  /// while watches are on, so they still hear new messages.
  final bool keepAlive;

  /// A notification when someone mentions or replies to the account.
  final bool mentionAlerts;

  /// Marks a chat read when the assistant replies or sends in it.
  final bool aiReadOnReply;

  /// Marks a chat read when the assistant reads its messages.
  final bool aiReadOnView;

  /// Keeps the app running in the background from the moment it opens, watches or not.
  final bool backgroundAlways;

  /// Starts the app in the background when the phone restarts (read natively by BootReceiver).
  final bool startOnBoot;

  /// The drawer shows the Chats section.
  final bool drawerChats;

  /// The drawer shows the Folders section.
  final bool drawerFolders;

  /// The drawer shows Files, Brief, Canvas, Search and Browser.
  final bool drawerTools;

  /// Whether the drawer's Chats section is expanded.
  final bool drawerChatsOpen;

  /// Whether the drawer's Folders section is expanded.
  final bool drawerFoldersOpen;

  /// Whether the drawer's Tools section is expanded.
  final bool drawerToolsOpen;

  /// A fun one: the logo slowly cycles through colours.
  final bool rainbowLogo;

  /// A light tap of the phone when sending and approving.
  final bool haptics;

  /// Shows the account as online while the app is on screen, which is what
  /// lets Telegram send typing indicators and live status.
  final bool appearOnline;

  /// Shows tokens and cost under each answer.
  final bool showMessageUsage;
  final bool showChatDateTime;
  /// The night brief is written on its own (when briefs are scheduled).
  final bool briefNightOn;
  /// The morning brief is written on its own (when briefs are scheduled).
  final bool briefMorningOn;
  /// Summarise older messages when a chat nears the model's context limit.
  final bool autoCompact;
  /// Less space between messages in the assistant chat.
  final bool compactChat;
  /// The model's name under each answer.
  final bool showModelName;
  /// The typeface of chat text.
  final ChatFont chatFont;
  /// Light, dark or following the phone.
  final AppThemeMode themeMode;
  final OrbShape orbShape;
  /// Read aloud, dictation and the audio tools.
  final bool voiceEnabled;
  /// Image and video tools: making pictures and looking at them.
  final bool mediaEnabled;

  /// Making videos (generate_video), apart from pictures: videos cost far
  /// more, so they start off.
  final bool videoEnabled;

  /// The model generate_video uses; empty until one is picked.
  final String videoModel;
  /// The assistant chat answers; off keeps it from calling any model.
  final bool aiChatEnabled;
  final bool showChatCopyButton;
  final bool showChatSpeakButton;

  /// Language code translations go into; empty means the phone's.
  final String translateTo;

  /// Draws link previews under messages.
  final bool showLinkPreviews;

  /// How long and detailed answers are.
  final AnswerStyle answerStyle;

  /// Language answers are written in; empty matches the question.
  final String answerLanguage;

  /// Most model calls (tool rounds) one answer may take.
  final int maxSteps;

  /// Shows the model's reasoning above answers.
  final bool showThinking;

  /// Shows each tool call as a card (approvals always show).
  final bool showToolCalls;

  /// Icons at the start of list rows across the app.
  final bool leadingIcons;

  /// Opening the app shows the last chat instead of a new one.
  final bool openLastChat;

  /// Message times as 14:05 rather than 2:05 PM.
  final bool use24h;

  /// Avatars next to messages in groups.
  final bool groupAvatars;

  /// Tighter rows in chat lists.
  final bool compactList;

  /// Opening a chat marks it as read, like Telegram does.
  final bool markReadOnOpen;

  /// No notifications between quietStart and quietEnd (updates still arrive in the app).
  final bool quietHours;
  final String quietStart;
  final String quietEnd;

  /// Writes a brief each morning and night at these times (HH:mm).
  final bool briefsScheduled;
  final String briefMorning;
  final String briefNight;
  final AccentChoice accent;
  final double chatFontSize;
  final CodeThemeChoice codeTheme;
  final String exaKey;

  /// Composio project API key (ak_…): connects Gmail, Slack, Notion and more.
  final String composioKey;

  /// Names this person's Composio connections; made once, kept with the
  /// preferences.
  final String composioUserId;

  /// Cloudflare API token (dash.cloudflare.com → My Profile → API Tokens).
  final String cloudflareToken;

  /// The account Workers, Pages, KV and R2 use; found from the token when
  /// empty.
  final String cloudflareAccountId;

  /// R2's S3 access key pair, for reading and writing files in buckets.
  final String r2AccessKeyId;
  final String r2SecretKey;

  /// The bucket R2 file tools use when none is named.
  final String r2Bucket;

  /// E2B API key: cloud sandboxes that run code.
  final String e2bKey;

  /// The E2B template sandboxes start from.
  final String e2bTemplate;

  /// How long an idle sandbox lives before E2B stops it.
  final int e2bTimeoutMinutes;

  /// Sandboxes may reach the internet (pip install, downloads).
  final bool e2bInternet;

  /// One sandbox is kept between runs, so variables and files carry over.
  final bool e2bKeepAlive;

  /// Chose to use the app without Telegram for now; it can be connected
  /// later under Settings → Apps & web → Telegram.
  final bool telegramSkipped;

  /// omni_ai model ids (`provider:model`).
  static const defaultModel = 'gateway:anthropic/claude-sonnet-5.5';
  static const defaultImageModel = 'gateway:google/gemini-3.1-flash-lite-image';
  static const defaultSpeechModel = 'gateway:openai/gpt-4o-mini-tts';
  static const defaultTranscriptionModel = 'gateway:google/gemini-3-flash';

  final String vercelKey;
  final String openRouterKey;

  /// Google AI Studio Gemini API key.
  final String geminiKey;

  /// Address of an LM Studio server (`192.168.1.20:1234`), or empty.
  final String lmStudioUrl;

  /// Addis AI key, used for Addis Voices 2.
  final String addisKey;
  final String elevenKey;

  /// A gateway id like `openai/gpt-5`, or `or:` + an OpenRouter id.
  final String model;
  final String imageModel;
  final Thinking thinking;

  final VoiceEngine voiceEngine;
  final String speechModel;
  final String aiVoice;

  /// The device voice's name, or empty for the system default.
  final String deviceVoice;
  final String elevenVoiceId;
  final String elevenVoiceName;
  final String elevenModel;

  /// Reading speed, 1 = normal.
  final double speechRate;

  final DictationEngine dictationEngine;

  /// A chat model that accepts audio, for AI dictation.
  final String transcriptionModel;

  /// Tools the assistant may not use.
  final Set<String> disabledTools;

  /// Destructive tools are off by default: these are the ones turned on.
  final Set<String> enabledDangerTools;

  /// Only tools that read are offered: nothing that sends, changes or
  /// deletes, whatever the per-tool switches say.
  final bool readOnlyMode;

  /// With several Telegram accounts: whether the assistant may do something
  /// in another account when the tool it needs is off (or the account is
  /// read-only) in the one it was working in. Off: a switch turned off in
  /// one account can't be worked around through another.
  final bool accountFallback;

  /// Inside the quiet hours right now.
  bool get isQuietNow {
    if (!quietHours) return false;
    int mins(String hm) {
      final p = hm.split(':');
      return (int.tryParse(p.first) ?? 0) * 60 + (int.tryParse(p.last) ?? 0);
    }

    final now = DateTime.now();
    final m = now.hour * 60 + now.minute,
        a = mins(quietStart),
        b = mins(quietEnd);
    return a <= b ? (m >= a && m < b) : (m >= a || m < b);
  }

  /// The user's switch for a tool.
  bool toolChosen(String name, {bool destructive = false}) => destructive
      ? enabledDangerTools.contains(name)
      : !disabledTools.contains(name);

  /// Whether the assistant gets the tool: its switch, unless read-only mode
  /// rules it out because it [writes].
  bool toolOn(String name, {bool destructive = false, bool writes = false}) =>
      toolChosen(name, destructive: destructive) &&
      !(readOnlyMode && (writes || destructive));

  /// Download these as soon as they show up; otherwise they wait for a tap.
  final bool autoPhotos;
  final bool autoVoice;
  final bool autoMusic;
  final bool loaded;

  bool get hasVercelKey => vercelKey.trim().isNotEmpty;
  bool get hasOpenRouterKey => openRouterKey.trim().isNotEmpty;
  bool get hasGeminiKey => geminiKey.trim().isNotEmpty;
  bool get hasLmStudio => lmStudioUrl.trim().isNotEmpty;
  bool get hasAddisKey => addisKey.trim().isNotEmpty;
  bool get hasElevenKey => elevenKey.trim().isNotEmpty;
  bool get hasExaKey => exaKey.trim().isNotEmpty;
  bool get hasComposioKey => composioKey.trim().isNotEmpty;
  bool get hasCloudflare => cloudflareToken.trim().isNotEmpty;
  bool get hasR2Keys => r2AccessKeyId.trim().isNotEmpty && r2SecretKey.trim().isNotEmpty;
  bool get hasE2bKey => e2bKey.trim().isNotEmpty;
  bool get hasAnyKey => hasVercelKey || hasOpenRouterKey || hasGeminiKey || hasLmStudio;

  AppSettings copyWith({
    String? vercelKey,
    String? openRouterKey,
    String? geminiKey,
    String? lmStudioUrl,
    String? addisKey,
    String? elevenKey,
    String? model,
    String? imageModel,
    Thinking? thinking,
    VoiceEngine? voiceEngine,
    String? speechModel,
    String? aiVoice,
    String? deviceVoice,
    String? elevenVoiceId,
    String? elevenVoiceName,
    String? elevenModel,
    double? speechRate,
    DictationEngine? dictationEngine,
    String? transcriptionModel,
    Set<String>? disabledTools,
    Set<String>? enabledDangerTools,
    bool? readOnlyMode,
    bool? accountFallback,
    bool? autoPhotos,
    bool? autoVoice,
    bool? autoMusic,
    String? customInstructions,
    ApprovalMode? approvalMode,
    bool? proactive,
    int? watchResponseDelaySeconds,
    bool? notifications,
    bool? keepAlive,
    bool? mentionAlerts,
    bool? aiReadOnReply,
    bool? aiReadOnView,
    bool? backgroundAlways,
    bool? startOnBoot,
    bool? drawerChats,
    bool? drawerFolders,
    bool? drawerTools,
    bool? drawerChatsOpen,
    bool? drawerFoldersOpen,
    bool? drawerToolsOpen,
    bool? rainbowLogo,
    bool? haptics,
    bool? appearOnline,
    bool? showMessageUsage,
    bool? showChatDateTime,
    bool? briefNightOn,
    bool? briefMorningOn,
    bool? autoCompact,
    bool? compactChat,
    bool? showModelName,
    ChatFont? chatFont,
    AppThemeMode? themeMode,
    OrbShape? orbShape,
    bool? voiceEnabled,
    bool? mediaEnabled,
    bool? videoEnabled,
    String? videoModel,
    bool? aiChatEnabled,
    bool? showChatCopyButton,
    bool? showChatSpeakButton,
    bool? briefsScheduled,
    String? translateTo,
    bool? showLinkPreviews,
    AnswerStyle? answerStyle,
    String? answerLanguage,
    int? maxSteps,
    bool? showThinking,
    bool? showToolCalls,
    bool? leadingIcons,
    bool? openLastChat,
    bool? use24h,
    bool? groupAvatars,
    bool? compactList,
    bool? markReadOnOpen,
    bool? quietHours,
    String? quietStart,
    String? quietEnd,
    String? briefMorning,
    String? briefNight,
    AccentChoice? accent,
    double? chatFontSize,
    CodeThemeChoice? codeTheme,
    String? exaKey,
    String? composioKey,
    String? composioUserId,
    String? cloudflareToken,
    String? cloudflareAccountId,
    String? r2AccessKeyId,
    String? r2SecretKey,
    String? r2Bucket,
    String? e2bKey,
    String? e2bTemplate,
    int? e2bTimeoutMinutes,
    bool? e2bInternet,
    bool? e2bKeepAlive,
    bool? telegramSkipped,
    bool? loaded,
  }) => AppSettings(
    vercelKey: vercelKey ?? this.vercelKey,
    openRouterKey: openRouterKey ?? this.openRouterKey,
    geminiKey: geminiKey ?? this.geminiKey,
    lmStudioUrl: lmStudioUrl ?? this.lmStudioUrl,
    addisKey: addisKey ?? this.addisKey,
    elevenKey: elevenKey ?? this.elevenKey,
    model: model ?? this.model,
    imageModel: imageModel ?? this.imageModel,
    thinking: thinking ?? this.thinking,
    voiceEngine: voiceEngine ?? this.voiceEngine,
    speechModel: speechModel ?? this.speechModel,
    aiVoice: aiVoice ?? this.aiVoice,
    deviceVoice: deviceVoice ?? this.deviceVoice,
    elevenVoiceId: elevenVoiceId ?? this.elevenVoiceId,
    elevenVoiceName: elevenVoiceName ?? this.elevenVoiceName,
    elevenModel: elevenModel ?? this.elevenModel,
    speechRate: speechRate ?? this.speechRate,
    dictationEngine: dictationEngine ?? this.dictationEngine,
    transcriptionModel: transcriptionModel ?? this.transcriptionModel,
    disabledTools: disabledTools ?? this.disabledTools,
    enabledDangerTools: enabledDangerTools ?? this.enabledDangerTools,
    readOnlyMode: readOnlyMode ?? this.readOnlyMode,
    accountFallback: accountFallback ?? this.accountFallback,
    autoPhotos: autoPhotos ?? this.autoPhotos,
    autoVoice: autoVoice ?? this.autoVoice,
    autoMusic: autoMusic ?? this.autoMusic,
    customInstructions: customInstructions ?? this.customInstructions,
    approvalMode: approvalMode ?? this.approvalMode,
    proactive: proactive ?? this.proactive,
    watchResponseDelaySeconds:
        watchResponseDelaySeconds ?? this.watchResponseDelaySeconds,
    notifications: notifications ?? this.notifications,
    keepAlive: keepAlive ?? this.keepAlive,
    mentionAlerts: mentionAlerts ?? this.mentionAlerts,
    aiReadOnReply: aiReadOnReply ?? this.aiReadOnReply,
    aiReadOnView: aiReadOnView ?? this.aiReadOnView,
    backgroundAlways: backgroundAlways ?? this.backgroundAlways,
    startOnBoot: startOnBoot ?? this.startOnBoot,
    drawerChats: drawerChats ?? this.drawerChats,
    drawerFolders: drawerFolders ?? this.drawerFolders,
    drawerTools: drawerTools ?? this.drawerTools,
    drawerChatsOpen: drawerChatsOpen ?? this.drawerChatsOpen,
    drawerFoldersOpen: drawerFoldersOpen ?? this.drawerFoldersOpen,
    drawerToolsOpen: drawerToolsOpen ?? this.drawerToolsOpen,
    rainbowLogo: rainbowLogo ?? this.rainbowLogo,
    haptics: haptics ?? this.haptics,
    appearOnline: appearOnline ?? this.appearOnline,
    showMessageUsage: showMessageUsage ?? this.showMessageUsage,
    showChatDateTime: showChatDateTime ?? this.showChatDateTime,
    briefNightOn: briefNightOn ?? this.briefNightOn,
    briefMorningOn: briefMorningOn ?? this.briefMorningOn,
    autoCompact: autoCompact ?? this.autoCompact,
    compactChat: compactChat ?? this.compactChat,
    showModelName: showModelName ?? this.showModelName,
    chatFont: chatFont ?? this.chatFont,
    themeMode: themeMode ?? this.themeMode,
    orbShape: orbShape ?? this.orbShape,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    mediaEnabled: mediaEnabled ?? this.mediaEnabled,
    videoEnabled: videoEnabled ?? this.videoEnabled,
    videoModel: videoModel ?? this.videoModel,
    aiChatEnabled: aiChatEnabled ?? this.aiChatEnabled,
    showChatCopyButton: showChatCopyButton ?? this.showChatCopyButton,
    showChatSpeakButton: showChatSpeakButton ?? this.showChatSpeakButton,
    briefsScheduled: briefsScheduled ?? this.briefsScheduled,
    translateTo: translateTo ?? this.translateTo,
    showLinkPreviews: showLinkPreviews ?? this.showLinkPreviews,
    answerStyle: answerStyle ?? this.answerStyle,
    answerLanguage: answerLanguage ?? this.answerLanguage,
    maxSteps: maxSteps ?? this.maxSteps,
    showThinking: showThinking ?? this.showThinking,
    showToolCalls: showToolCalls ?? this.showToolCalls,
    leadingIcons: leadingIcons ?? this.leadingIcons,
    openLastChat: openLastChat ?? this.openLastChat,
    use24h: use24h ?? this.use24h,
    groupAvatars: groupAvatars ?? this.groupAvatars,
    compactList: compactList ?? this.compactList,
    markReadOnOpen: markReadOnOpen ?? this.markReadOnOpen,
    quietHours: quietHours ?? this.quietHours,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
    briefMorning: briefMorning ?? this.briefMorning,
    briefNight: briefNight ?? this.briefNight,
    accent: accent ?? this.accent,
    chatFontSize: chatFontSize ?? this.chatFontSize,
    codeTheme: codeTheme ?? this.codeTheme,
    exaKey: exaKey ?? this.exaKey,
    composioKey: composioKey ?? this.composioKey,
    composioUserId: composioUserId ?? this.composioUserId,
    cloudflareToken: cloudflareToken ?? this.cloudflareToken,
    cloudflareAccountId: cloudflareAccountId ?? this.cloudflareAccountId,
    r2AccessKeyId: r2AccessKeyId ?? this.r2AccessKeyId,
    r2SecretKey: r2SecretKey ?? this.r2SecretKey,
    r2Bucket: r2Bucket ?? this.r2Bucket,
    e2bKey: e2bKey ?? this.e2bKey,
    e2bTemplate: e2bTemplate ?? this.e2bTemplate,
    e2bTimeoutMinutes: e2bTimeoutMinutes ?? this.e2bTimeoutMinutes,
    e2bInternet: e2bInternet ?? this.e2bInternet,
    e2bKeepAlive: e2bKeepAlive ?? this.e2bKeepAlive,
    telegramSkipped: telegramSkipped ?? this.telegramSkipped,
    loaded: loaded ?? this.loaded,
  );
}

/// Keys live in the platform keystore; the rest in shared preferences.
class SettingsController extends Notifier<AppSettings> {
  static const _secure = FlutterSecureStorage();
  static const _vercelKey = 'vercel_ai_gateway_key';
  static const _openRouterKey = 'openrouter_key';
  static const _geminiKey = 'gemini_key';
  static const _addisKey = 'addis_key';
  static const _elevenKey = 'elevenlabs_key';
  static const _exaKey = 'exa_key';
  static const _composioKey = 'composio_key';
  static const _cloudflareToken = 'cloudflare_token';
  static const _r2AccessKeyId = 'r2_access_key_id';
  static const _r2SecretKey = 'r2_secret_key';
  static const _e2bKey = 'e2b_key';

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<String> _secret(String key) async {
    try {
      return await _secure.read(key: key) ?? '';
    } catch (e) {
      debugPrint('[Settings] Could not read $key: $e');
      return '';
    }
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    const d = AppSettings();
    final loaded = AppSettings(
      vercelKey: await _secret(_vercelKey),
      openRouterKey: await _secret(_openRouterKey),
      geminiKey: await _secret(_geminiKey),
      lmStudioUrl: p.getString('lmstudio_url') ?? d.lmStudioUrl,
      addisKey: await _secret(_addisKey),
      elevenKey: await _secret(_elevenKey),
      exaKey: await _secret(_exaKey),
      composioKey: await _secret(_composioKey),
      composioUserId: p.getString('composio_user_id') ?? d.composioUserId,
      cloudflareToken: await _secret(_cloudflareToken),
      cloudflareAccountId: p.getString('cloudflare_account_id') ?? d.cloudflareAccountId,
      r2AccessKeyId: await _secret(_r2AccessKeyId),
      r2SecretKey: await _secret(_r2SecretKey),
      r2Bucket: p.getString('r2_bucket') ?? d.r2Bucket,
      e2bKey: await _secret(_e2bKey),
      e2bTemplate: p.getString('e2b_template') ?? d.e2bTemplate,
      e2bTimeoutMinutes: p.getInt('e2b_timeout_minutes') ?? d.e2bTimeoutMinutes,
      e2bInternet: p.getBool('e2b_internet') ?? d.e2bInternet,
      e2bKeepAlive: p.getBool('e2b_keep_alive') ?? d.e2bKeepAlive,
      telegramSkipped: p.getBool('telegram_skipped') ?? d.telegramSkipped,
      // Ids saved by earlier versions (`or:`, `g:`, bare) become omni_ai ids.
      model: canonicalModelId(p.getString('chat_model') ?? d.model),
      imageModel: canonicalModelId(p.getString('image_model') ?? d.imageModel),
      thinking:
          Thinking.values.asNameMap()[p.getString('thinking')] ?? d.thinking,
      voiceEngine:
          VoiceEngine.values.asNameMap()[p.getString('voice_engine')] ??
          d.voiceEngine,
      speechModel: canonicalModelId(p.getString('speech_model') ?? d.speechModel),
      aiVoice: p.getString('ai_voice') ?? d.aiVoice,
      deviceVoice: p.getString('device_voice') ?? d.deviceVoice,
      elevenVoiceId: p.getString('eleven_voice_id') ?? d.elevenVoiceId,
      elevenVoiceName: p.getString('eleven_voice_name') ?? d.elevenVoiceName,
      elevenModel: p.getString('eleven_model') ?? d.elevenModel,
      speechRate: p.getDouble('speech_rate') ?? d.speechRate,
      dictationEngine:
          DictationEngine.values.asNameMap()[p.getString('dictation_engine')] ??
          d.dictationEngine,
      transcriptionModel: canonicalModelId(p.getString('transcription_model') ?? d.transcriptionModel),
      disabledTools: (p.getStringList('disabled_tools') ?? const []).toSet(),
      enabledDangerTools: (p.getStringList('danger_tools') ?? const []).toSet(),
      readOnlyMode: p.getBool('read_only_mode') ?? d.readOnlyMode,
      accountFallback: p.getBool('account_fallback') ?? d.accountFallback,
      autoPhotos: p.getBool('auto_photos') ?? d.autoPhotos,
      autoVoice: p.getBool('auto_voice') ?? d.autoVoice,
      autoMusic: p.getBool('auto_music') ?? d.autoMusic,
      customInstructions:
          p.getString('custom_instructions') ?? d.customInstructions,
      approvalMode:
          ApprovalMode.values.asNameMap()[p.getString('approval_mode')] ??
          d.approvalMode,
      proactive: p.getBool('proactive') ?? d.proactive,
      watchResponseDelaySeconds:
          p.getInt('watch_response_delay_seconds') ??
          d.watchResponseDelaySeconds,
      notifications: p.getBool('notifications') ?? d.notifications,
      keepAlive: p.getBool('keep_alive') ?? d.keepAlive,
      mentionAlerts: p.getBool('mention_alerts') ?? d.mentionAlerts,
      aiReadOnReply: p.getBool('ai_read_on_reply') ?? d.aiReadOnReply,
      aiReadOnView: p.getBool('ai_read_on_view') ?? d.aiReadOnView,
      backgroundAlways: p.getBool('background_always') ?? d.backgroundAlways,
      startOnBoot: p.getBool('start_on_boot') ?? d.startOnBoot,
      drawerChats: p.getBool('drawer_chats') ?? d.drawerChats,
      drawerFolders: p.getBool('drawer_folders') ?? d.drawerFolders,
      drawerTools: p.getBool('drawer_tools') ?? d.drawerTools,
      drawerChatsOpen: p.getBool('drawer_chats_open') ?? d.drawerChatsOpen,
      drawerFoldersOpen:
          p.getBool('drawer_folders_open') ?? d.drawerFoldersOpen,
      drawerToolsOpen: p.getBool('drawer_tools_open') ?? d.drawerToolsOpen,
      rainbowLogo: p.getBool('rainbow_logo') ?? d.rainbowLogo,
      haptics: p.getBool('haptics') ?? d.haptics,
      appearOnline: p.getBool('appear_online') ?? d.appearOnline,
      showMessageUsage: p.getBool('show_message_usage') ?? d.showMessageUsage,
      showChatDateTime: p.getBool('show_chat_date_time') ?? d.showChatDateTime,
      briefNightOn: p.getBool('brief_night_on') ?? d.briefNightOn,
      briefMorningOn: p.getBool('brief_morning_on') ?? d.briefMorningOn,
      autoCompact: p.getBool('auto_compact') ?? d.autoCompact,
      compactChat: p.getBool('compact_chat') ?? d.compactChat,
      showModelName: p.getBool('show_model_name') ?? d.showModelName,
      chatFont: ChatFont.values.asNameMap()[p.getString('chat_font')] ?? d.chatFont,
      themeMode: AppThemeMode.values.asNameMap()[p.getString('theme_mode')] ?? d.themeMode,
      orbShape: OrbShape.values.asNameMap()[p.getString('orb_shape')] ?? d.orbShape,
      voiceEnabled: p.getBool('voice_enabled') ?? d.voiceEnabled,
      mediaEnabled: p.getBool('media_enabled') ?? d.mediaEnabled,
      videoEnabled: p.getBool('video_enabled') ?? d.videoEnabled,
      videoModel: p.getString('video_model') ?? d.videoModel,
      aiChatEnabled: p.getBool('ai_chat_enabled') ?? d.aiChatEnabled,
      showChatCopyButton: p.getBool('show_chat_copy_button') ?? d.showChatCopyButton,
      showChatSpeakButton: p.getBool('show_chat_speak_button') ?? d.showChatSpeakButton,
      briefsScheduled: p.getBool('briefs_scheduled') ?? d.briefsScheduled,
      translateTo: p.getString('translate_to') ?? d.translateTo,
      showLinkPreviews: p.getBool('link_previews') ?? d.showLinkPreviews,
      answerStyle:
          AnswerStyle.values.asNameMap()[p.getString('answer_style')] ??
          d.answerStyle,
      answerLanguage: p.getString('answer_language') ?? d.answerLanguage,
      maxSteps: p.getInt('max_steps') ?? d.maxSteps,
      showThinking: p.getBool('show_thinking') ?? d.showThinking,
      showToolCalls: p.getBool('show_tool_calls') ?? d.showToolCalls,
      leadingIcons: p.getBool('leading_icons') ?? d.leadingIcons,
      openLastChat: p.getBool('open_last_chat') ?? d.openLastChat,
      use24h: p.getBool('use_24h') ?? d.use24h,
      groupAvatars: p.getBool('group_avatars') ?? d.groupAvatars,
      compactList: p.getBool('compact_list') ?? d.compactList,
      markReadOnOpen: p.getBool('mark_read_on_open') ?? d.markReadOnOpen,
      quietHours: p.getBool('quiet_hours') ?? d.quietHours,
      quietStart: p.getString('quiet_start') ?? d.quietStart,
      quietEnd: p.getString('quiet_end') ?? d.quietEnd,
      briefMorning: p.getString('brief_morning') ?? d.briefMorning,
      briefNight: p.getString('brief_night') ?? d.briefNight,
      accent:
          AccentChoice.values.asNameMap()[p.getString('accent')] ?? d.accent,
      chatFontSize: p.getDouble('chat_font_size') ?? d.chatFontSize,
      codeTheme:
          CodeThemeChoice.values.asNameMap()[p.getString('code_theme')] ??
          d.codeTheme,
      loaded: true,
    );
    // Reading keys takes a while; the app may have moved on (a restore).
    if (ref.mounted) state = loaded;
  }

  Future<void> _write(String key, Object value) async {
    final p = await SharedPreferences.getInstance();
    switch (value) {
      case String v:
        await p.setString(key, v);
      case double v:
        await p.setDouble(key, v);
      case int v:
        await p.setInt(key, v);
      case List<String> v:
        await p.setStringList(key, v);
      case bool v:
        await p.setBool(key, v);
    }
  }

  Future<void> setVercelKey(String key) async {
    state = state.copyWith(vercelKey: key.trim());
    await _secure.write(key: _vercelKey, value: key.trim());
  }

  Future<void> setOpenRouterKey(String key) async {
    state = state.copyWith(openRouterKey: key.trim());
    await _secure.write(key: _openRouterKey, value: key.trim());
  }

  Future<void> setGeminiKey(String key) async {
    state = state.copyWith(geminiKey: key.trim());
    await _secure.write(key: _geminiKey, value: key.trim());
  }

  Future<void> setLmStudioUrl(String url) async {
    state = state.copyWith(lmStudioUrl: url.trim());
    await _write('lmstudio_url', url.trim());
  }

  Future<void> setAddisKey(String key) async {
    state = state.copyWith(addisKey: key.trim());
    await _secure.write(key: _addisKey, value: key.trim());
  }

  Future<void> setElevenKey(String key) async {
    state = state.copyWith(elevenKey: key.trim());
    await _secure.write(key: _elevenKey, value: key.trim());
  }

  Future<void> setExaKey(String key) async {
    state = state.copyWith(exaKey: key.trim());
    await _secure.write(key: _exaKey, value: key.trim());
  }

  Future<void> setComposioKey(String key) async {
    state = state.copyWith(composioKey: key.trim());
    await _secure.write(key: _composioKey, value: key.trim());
  }

  Future<void> setCloudflareToken(String v) async {
    state = state.copyWith(cloudflareToken: v.trim());
    await _secure.write(key: _cloudflareToken, value: v.trim());
  }

  Future<void> setR2Keys({String? accessKeyId, String? secret}) async {
    state = state.copyWith(r2AccessKeyId: accessKeyId?.trim(), r2SecretKey: secret?.trim());
    if (accessKeyId != null) await _secure.write(key: _r2AccessKeyId, value: accessKeyId.trim());
    if (secret != null) await _secure.write(key: _r2SecretKey, value: secret.trim());
  }

  Future<void> setCloudflareAccountId(String v) =>
      customize(state.copyWith(cloudflareAccountId: v.trim()), 'cloudflare_account_id', v.trim());
  Future<void> setR2Bucket(String v) => customize(state.copyWith(r2Bucket: v.trim()), 'r2_bucket', v.trim());

  Future<void> setE2bKey(String v) async {
    state = state.copyWith(e2bKey: v.trim());
    await _secure.write(key: _e2bKey, value: v.trim());
  }

  Future<void> setE2bTemplate(String v) => customize(
    state.copyWith(e2bTemplate: v.trim().isEmpty ? 'code-interpreter-v1' : v.trim()),
    'e2b_template',
    v.trim().isEmpty ? 'code-interpreter-v1' : v.trim(),
  );
  Future<void> setE2bTimeoutMinutes(int v) =>
      customize(state.copyWith(e2bTimeoutMinutes: v.clamp(1, 60)), 'e2b_timeout_minutes', v.clamp(1, 60));
  Future<void> setE2bInternet(bool v) => customize(state.copyWith(e2bInternet: v), 'e2b_internet', v);
  Future<void> setTelegramSkipped(bool v) =>
      customize(state.copyWith(telegramSkipped: v), 'telegram_skipped', v);
  Future<void> setE2bKeepAlive(bool v) => customize(state.copyWith(e2bKeepAlive: v), 'e2b_keep_alive', v);

  Future<void> setComposioUserId(String id) async {
    state = state.copyWith(composioUserId: id);
    await _write('composio_user_id', id);
  }

  Future<void> setAccent(AccentChoice value) async {
    state = state.copyWith(accent: value);
    await _write('accent', value.name);
  }

  Future<void> setChatFontSize(double value) async {
    state = state.copyWith(chatFontSize: value);
    await _write('chat_font_size', value);
  }

  Future<void> setCodeTheme(CodeThemeChoice value) async {
    state = state.copyWith(codeTheme: value);
    await _write('code_theme', value.name);
  }

  Future<void> setModel(String id) async {
    state = state.copyWith(model: id);
    await _write('chat_model', id);
  }

  /// Switches the models that changed, e.g. to ones the person has a key
  /// for. A new voice model clears the voice picked for the old one.
  Future<void> useModels({
    required String chat,
    required String image,
    required String speech,
    required String transcription,
    VoiceEngine? voiceEngine,
    DictationEngine? dictationEngine,
  }) async {
    if (chat != state.model) await setModel(chat);
    if (image != state.imageModel) await setImageModel(image);
    if (voiceEngine != null && voiceEngine != state.voiceEngine) await setVoiceEngine(voiceEngine);
    if (speech != state.speechModel) {
      if (state.voiceEngine == VoiceEngine.addis) {
        // aiVoice holds the Addis voice then; keep it.
        state = state.copyWith(speechModel: speech);
        await _write('speech_model', speech);
      } else {
        await setSpeechModel(speech);
      }
    }
    if (transcription != state.transcriptionModel) await setTranscriptionModel(transcription);
    if (dictationEngine != null && dictationEngine != state.dictationEngine) await setDictationEngine(dictationEngine);
  }

  Future<void> setImageModel(String id) async {
    state = state.copyWith(imageModel: id);
    await _write('image_model', id);
  }

  Future<void> setThinking(Thinking v) async {
    state = state.copyWith(thinking: v);
    await _write('thinking', v.name);
  }

  Future<void> setVoiceEngine(VoiceEngine v) async {
    state = state.copyWith(voiceEngine: v);
    await _write('voice_engine', v.name);
  }

  Future<void> setSpeechModel(String id) async {
    state = state.copyWith(speechModel: id, aiVoice: '');
    await _write('speech_model', id);
    await _write('ai_voice', '');
  }

  Future<void> setAiVoice(String v) async {
    state = state.copyWith(aiVoice: v);
    await _write('ai_voice', v);
  }

  Future<void> setDeviceVoice(String v) async {
    state = state.copyWith(deviceVoice: v);
    await _write('device_voice', v);
  }

  Future<void> setElevenVoice(String id, String name) async {
    state = state.copyWith(elevenVoiceId: id, elevenVoiceName: name);
    await _write('eleven_voice_id', id);
    await _write('eleven_voice_name', name);
  }

  Future<void> setElevenModel(String id) async {
    state = state.copyWith(elevenModel: id);
    await _write('eleven_model', id);
  }

  Future<void> setSpeechRate(double v) async {
    state = state.copyWith(speechRate: v);
    await _write('speech_rate', v);
  }

  Future<void> setDictationEngine(DictationEngine v) async {
    state = state.copyWith(dictationEngine: v);
    await _write('dictation_engine', v.name);
  }

  Future<void> setTranscriptionModel(String id) async {
    state = state.copyWith(transcriptionModel: id);
    await _write('transcription_model', id);
  }

  Future<void> setAutoDownload({bool? photos, bool? voice, bool? music}) async {
    state = state.copyWith(
      autoPhotos: photos,
      autoVoice: voice,
      autoMusic: music,
    );
    if (photos != null) await _write('auto_photos', photos);
    if (voice != null) await _write('auto_voice', voice);
    if (music != null) await _write('auto_music', music);
  }

  Future<void> setCustomInstructions(String v) async {
    state = state.copyWith(customInstructions: v);
    await _write('custom_instructions', v);
  }

  Future<void> setApprovalMode(ApprovalMode v) async {
    state = state.copyWith(approvalMode: v);
    await _write('approval_mode', v.name);
  }

  Future<void> setProactive(bool v) async {
    state = state.copyWith(proactive: v);
    await _write('proactive', v);
  }

  Future<void> setWatchResponseDelay(Duration value) async {
    final seconds = value.inSeconds.clamp(0, 24 * 60 * 60).toInt();
    state = state.copyWith(watchResponseDelaySeconds: seconds);
    await _write('watch_response_delay_seconds', seconds);
  }

  Future<void> setNotifications(bool v) async {
    state = state.copyWith(notifications: v);
    await _write('notifications', v);
  }

  Future<void> setBriefs({
    bool? scheduled,
    String? morning,
    String? night,
  }) async {
    state = state.copyWith(
      briefsScheduled: scheduled,
      briefMorning: morning,
      briefNight: night,
    );
    if (scheduled != null) await _write('briefs_scheduled', scheduled);
    if (morning != null) await _write('brief_morning', morning);
    if (night != null) await _write('brief_night', night);
  }

  Future<void> setTranslateTo(String v) async {
    state = state.copyWith(translateTo: v);
    await _write('translate_to', v);
  }

  Future<void> setShowLinkPreviews(bool v) async {
    state = state.copyWith(showLinkPreviews: v);
    await _write('link_previews', v);
  }

  /// One switch or choice from the customization settings.
  Future<void> customize(AppSettings next, String key, Object value) async {
    state = next;
    await _write(key, value);
  }

  Future<void> setAnswerStyle(AnswerStyle v) =>
      customize(state.copyWith(answerStyle: v), 'answer_style', v.name);
  Future<void> setAnswerLanguage(String v) =>
      customize(state.copyWith(answerLanguage: v), 'answer_language', v);
  Future<void> setMaxSteps(int v) =>
      customize(state.copyWith(maxSteps: v), 'max_steps', v);
  Future<void> setShowThinking(bool v) =>
      customize(state.copyWith(showThinking: v), 'show_thinking', v);
  Future<void> setShowToolCalls(bool v) =>
      customize(state.copyWith(showToolCalls: v), 'show_tool_calls', v);
  Future<void> setLeadingIcons(bool v) =>
      customize(state.copyWith(leadingIcons: v), 'leading_icons', v);
  Future<void> setOpenLastChat(bool v) =>
      customize(state.copyWith(openLastChat: v), 'open_last_chat', v);
  Future<void> setUse24h(bool v) =>
      customize(state.copyWith(use24h: v), 'use_24h', v);
  Future<void> setGroupAvatars(bool v) =>
      customize(state.copyWith(groupAvatars: v), 'group_avatars', v);
  Future<void> setCompactList(bool v) =>
      customize(state.copyWith(compactList: v), 'compact_list', v);
  Future<void> setMarkReadOnOpen(bool v) =>
      customize(state.copyWith(markReadOnOpen: v), 'mark_read_on_open', v);
  Future<void> setQuietHours(bool v) =>
      customize(state.copyWith(quietHours: v), 'quiet_hours', v);
  Future<void> setQuietStart(String v) =>
      customize(state.copyWith(quietStart: v), 'quiet_start', v);
  Future<void> setQuietEnd(String v) =>
      customize(state.copyWith(quietEnd: v), 'quiet_end', v);

  /// Every preference back to its default; keys are kept.
  Future<void> resetPreferences() async {
    final p = await SharedPreferences.getInstance();
    // Keys live in secure storage and aren't touched; the models and the
    // standing instructions are kept too.
    const keep = {'chat_model', 'image_model', 'custom_instructions', 'composio_user_id'};
    for (final k in p.getKeys().toList()) {
      if (!keep.contains(k)) await p.remove(k);
    }
    state = const AppSettings().copyWith(
      vercelKey: state.vercelKey,
      openRouterKey: state.openRouterKey,
      geminiKey: state.geminiKey,
      addisKey: state.addisKey,
      elevenKey: state.elevenKey,
      exaKey: state.exaKey,
      composioKey: state.composioKey,
      composioUserId: state.composioUserId,
      cloudflareToken: state.cloudflareToken,
      r2AccessKeyId: state.r2AccessKeyId,
      r2SecretKey: state.r2SecretKey,
      e2bKey: state.e2bKey,
      model: state.model,
      imageModel: state.imageModel,
      customInstructions: state.customInstructions,
      loaded: true,
    );
  }

  Future<void> setShowChatDateTime(bool v) => customize(state.copyWith(showChatDateTime: v), 'show_chat_date_time', v);
  Future<void> setBriefNightOn(bool v) => customize(state.copyWith(briefNightOn: v), 'brief_night_on', v);
  Future<void> setBriefMorningOn(bool v) => customize(state.copyWith(briefMorningOn: v), 'brief_morning_on', v);
  Future<void> setAutoCompact(bool v) => customize(state.copyWith(autoCompact: v), 'auto_compact', v);
  Future<void> setCompactChat(bool v) => customize(state.copyWith(compactChat: v), 'compact_chat', v);
  Future<void> setShowModelName(bool v) => customize(state.copyWith(showModelName: v), 'show_model_name', v);
  Future<void> setChatFont(ChatFont v) => customize(state.copyWith(chatFont: v), 'chat_font', v.name);
  Future<void> setThemeMode(AppThemeMode v) => customize(state.copyWith(themeMode: v), 'theme_mode', v.name);
  Future<void> setOrbShape(OrbShape v) => customize(state.copyWith(orbShape: v), 'orb_shape', v.name);
  Future<void> setVoiceEnabled(bool v) => customize(state.copyWith(voiceEnabled: v), 'voice_enabled', v);
  Future<void> setMediaEnabled(bool v) => customize(state.copyWith(mediaEnabled: v), 'media_enabled', v);
  Future<void> setVideoEnabled(bool v) => customize(state.copyWith(videoEnabled: v), 'video_enabled', v);
  Future<void> setVideoModel(String id) => customize(state.copyWith(videoModel: id), 'video_model', id);
  Future<void> setAiChatEnabled(bool v) => customize(state.copyWith(aiChatEnabled: v), 'ai_chat_enabled', v);
  Future<void> setShowChatCopyButton(bool v) => customize(state.copyWith(showChatCopyButton: v), 'show_chat_copy_button', v);
  Future<void> setShowChatSpeakButton(bool v) => customize(state.copyWith(showChatSpeakButton: v), 'show_chat_speak_button', v);

  Future<void> setShowMessageUsage(bool v) async {
    state = state.copyWith(showMessageUsage: v);
    await _write('show_message_usage', v);
  }

  Future<void> setAppearOnline(bool v) async {
    state = state.copyWith(appearOnline: v);
    await _write('appear_online', v);
  }

  Future<void> setKeepAlive(bool v) async {
    state = state.copyWith(keepAlive: v);
    await _write('keep_alive', v);
  }

  Future<void> setBackgroundAlways(bool v) async {
    state = state.copyWith(backgroundAlways: v);
    await _write('background_always', v);
  }

  Future<void> setStartOnBoot(bool v) async {
    state = state.copyWith(startOnBoot: v);
    await _write('start_on_boot', v);
  }

  Future<void> setDrawerChats(bool v) async {
    state = state.copyWith(drawerChats: v);
    await _write('drawer_chats', v);
  }

  Future<void> setDrawerFolders(bool v) async {
    state = state.copyWith(drawerFolders: v);
    await _write('drawer_folders', v);
  }

  Future<void> setDrawerTools(bool v) async {
    state = state.copyWith(drawerTools: v);
    await _write('drawer_tools', v);
  }

  Future<void> setDrawerChatsOpen(bool v) async {
    state = state.copyWith(drawerChatsOpen: v);
    await _write('drawer_chats_open', v);
  }

  Future<void> setDrawerFoldersOpen(bool v) async {
    state = state.copyWith(drawerFoldersOpen: v);
    await _write('drawer_folders_open', v);
  }

  Future<void> setDrawerToolsOpen(bool v) async {
    state = state.copyWith(drawerToolsOpen: v);
    await _write('drawer_tools_open', v);
  }

  Future<void> setRainbowLogo(bool v) async {
    state = state.copyWith(rainbowLogo: v);
    await _write('rainbow_logo', v);
  }

  Future<void> setHaptics(bool v) async {
    state = state.copyWith(haptics: v);
    await _write('haptics', v);
  }

  Future<void> setAiReadOnReply(bool v) async {
    state = state.copyWith(aiReadOnReply: v);
    await _write('ai_read_on_reply', v);
  }

  Future<void> setAiReadOnView(bool v) async {
    state = state.copyWith(aiReadOnView: v);
    await _write('ai_read_on_view', v);
  }

  Future<void> setMentionAlerts(bool v) async {
    state = state.copyWith(mentionAlerts: v);
    await _write('mention_alerts', v);
  }

  Future<void> setReadOnlyMode(bool v) async {
    state = state.copyWith(readOnlyMode: v);
    await _write('read_only_mode', v);
  }

  Future<void> setAccountFallback(bool v) async {
    state = state.copyWith(accountFallback: v);
    await _write('account_fallback', v);
  }

  /// Turns a set of tools on or off at once.
  Future<void> setToolsEnabled(
    Iterable<String> names,
    bool enabled, {
    bool destructive = false,
  }) async {
    if (destructive) {
      final next = {...state.enabledDangerTools};
      enabled ? next.addAll(names) : next.removeAll(names);
      state = state.copyWith(enabledDangerTools: next);
      await _write('danger_tools', next.toList());
    } else {
      final next = {...state.disabledTools};
      enabled ? next.removeAll(names) : next.addAll(names);
      state = state.copyWith(disabledTools: next);
      await _write('disabled_tools', next.toList());
    }
  }

  Future<void> setToolEnabled(
    String name,
    bool enabled, {
    bool destructive = false,
  }) async {
    if (destructive) {
      final next = {...state.enabledDangerTools};
      enabled ? next.add(name) : next.remove(name);
      state = state.copyWith(enabledDangerTools: next);
      await _write('danger_tools', next.toList());
      return;
    }
    final next = {...state.disabledTools};
    enabled ? next.remove(name) : next.add(name);
    state = state.copyWith(disabledTools: next);
    await _write('disabled_tools', next.toList());
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
