import '../../telegram/data/telegram_tools.dart';
import '../domain/chat_models.dart';

// Which tool groups a run starts with when tools load as needed (Settings →
// Assistant → Load tools as needed): the core groups, the ones the message
// mentions, and the ones the conversation already used or loaded. The model
// loads any other with load_tools. Generous on purpose: an extra group costs
// a few tokens, a missing one a round trip.

final _mentions = <ToolCategory, RegExp>{
  for (final e in {
    ToolCategory.account: r'session|privacy|password|two.?step|2fa|security|safe|hack|log ?out|devices?',
    ToolCategory.contacts: r'contacts?|profile|bio|username|phone number',
    ToolCategory.members: r'admins?|members?|ban|kick|promote|demote|restrict|permissions?|invite link|join request|moderat',
    ToolCategory.bots: r'bots?\b|botfather|inline',
    ToolCategory.calls: r'voice chat|video chat|live ?stream|group call',
    ToolCategory.analytics: r'stats|statistics|analytics|views|engagement|growth|subscribers',
    ToolCategory.media: r'stickers?|gifs?|emoji|wallpaper|background|theme|profile (photo|music)',
    ToolCategory.stories: r'stor(y|ies)',
    ToolCategory.folders: r'folders?',
    ToolCategory.stars: r'stars?\b|gifts?|subscription|revenue|donat',
    ToolCategory.canvas: r'canvas|organi[sz]e (the |my )?posts|saved posts',
    ToolCategory.code: r'\bcode\b|python|javascript|script|calculat|chart|plot|csv|excel',
    ToolCategory.routines: r'routines?',
    ToolCategory.developer: r'github|repo(sitory)?|commits?|pull request|release notes',
    ToolCategory.discover: r'music|songs?|albums?|artists?|movies?|films?|tv|series|episodes?|twitter|tweets?|x\.com|instagram|tiktok',
    ToolCategory.markets: r'weather|forecast|rain|crypto|bitcoin|btc|eth|stocks?|shares?|exchange rate|currency|convert .* to|usd|eur|etb|flights?|holidays?',
    ToolCategory.news: r'reddit|subreddit|hacker ?news|\bhn\b|news',
    ToolCategory.library: r'books?|audiobooks?|radio|podcasts?|ebook|novel',
    ToolCategory.explore: r'countr(y|ies)|nasa|space|planet|asteroid|pok[eé]mon',
    ToolCategory.utilities: r'ethiopian (calendar|date)|\bqr\b|barcode',
    ToolCategory.games: r'\bgames?\b|retro|play (a|some)',
    ToolCategory.youtube: r'youtube|yt\b|videos?',
    ToolCategory.papers: r'papers?|arxiv|research|study|studies|citations?|journal',
    ToolCategory.bible: r'bible|verse|scripture|psalm|gospel|genesis|john \d',
    ToolCategory.finance: r'money|spen[dt]|bank|balance|budgets?|birr|telebirr|cbe|transactions?|expenses?|income|salary|paid|payments?|receipts?|m-?pesa|savings?',
    ToolCategory.callHistory: r'call (history|log)|missed calls?|who called|called me|calls? (from|with|to)',
    ToolCategory.screenTime: r'screen ?time|app usage|how long .* (phone|app)',
    ToolCategory.imageTools: r'resize|crop|compress|convert (the |this )?(image|photo|picture)|remove (the )?background',
    ToolCategory.packages: r'\bnpm\b|pypi|pub\.dev|package|domain|whois|dns lookup|xkcd',
    ToolCategory.world: r'gold|silver|metal price|fuel|petrol|earthquakes?|quakes?|air quality|pollution',
    ToolCategory.food: r'recipes?|cook|nutrition|calories|ingredients?',
    ToolCategory.reference: r'defin(e|ition)|dictionary|meaning of|translat|wikipedia|synonyms?',
    ToolCategory.sports: r'football|soccer|premier league|la ?liga|nba|nfl|scores?|match(es)?|fixtures?|standings|goals?',
    ToolCategory.device: r'battery|wi-?fi|network|sms|text (message|him|her|them)|alarm|timer|flashlight|torch|volume|ringer|vibrat|installed apps|open (the )?app|clipboard|call (him|her|them|\+?\d)|phone',
    ToolCategory.screen: r'(tap|click|swipe|scroll) (on )?|on (my|the) screen|screenshot of (my|the) (phone|screen)',
    ToolCategory.gmail: r'e-?mails?|gmail|inbox|mail',
    ToolCategory.outlook: r'outlook|e-?mails?|inbox',
    ToolCategory.calendar: r'calendar|meetings?|events?|appointments?|schedule|agenda',
    ToolCategory.googleDocs: r'drive|docs?\b|documents?|sheets?|spreadsheets?',
    ToolCategory.slack: r'slack',
    ToolCategory.notion: r'notion',
    ToolCategory.githubAccount: r'my github|my repos?|pull requests?|\bprs?\b|issues? on github',
    ToolCategory.linear: r'linear|tickets?',
    ToolCategory.todoist: r'todoist|to-?do|tasks?',
    ToolCategory.apps: r'connect (my )?\w+|app integration|composio',
    ToolCategory.cloudflare: r'cloudflare|dns|workers?|kv\b|pages project',
    ToolCategory.r2: r'\br2\b|bucket|object storage',
    ToolCategory.decisions: r'\bjev\b|classify|categori[sz]e|triage|sentiment|moderate|grade|score (these|each)',
    ToolCategory.mcp: r'\bmcp\b',
    ToolCategory.skills: r'skills?',
    ToolCategory.e2b: r'e2b|sandbox|run (this|the) (script|code)',
  }.entries)
    e.key: RegExp(e.value, caseSensitive: false),
};

/// Groups [text] (a message, a watch's instructions) seems to need.
Set<ToolCategory> categoriesMentioned(String text) {
  if (text.trim().isEmpty) return const {};
  return {
    for (final e in _mentions.entries)
      if (e.value.hasMatch(text)) e.key,
  };
}

/// Groups of the tools [c] already called, so a follow-up has them.
Set<ToolCategory> categoriesUsed(Conversation c) {
  final names = <String>{
    for (final e in c.entries)
      if (e is AssistantEntry)
        for (final s in e.steps)
          for (final t in s.tools) t.name,
  };
  if (names.isEmpty) return const {};
  return {
    for (final t in telegramTools)
      if (names.contains(t.name)) t.category,
  };
}

/// The groups a run in [c] starts with, before the model loads more.
Set<ToolCategory> startingCategories({
  required Conversation c,
  required String message,
  Set<ToolCategory> loaded = const {},
  String watchInstructions = '',
}) => {
  ...coreToolCategories,
  ...loaded,
  ...categoriesUsed(c),
  ...categoriesMentioned(message),
  ...categoriesMentioned(watchInstructions),
};
