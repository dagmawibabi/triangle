import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../bible/bible_settings_screen.dart';
import '../../telegram/data/telegram_tools.dart';
import '../data/settings.dart';
import 'cloud_settings.dart' show KeyField;
import 'tools_screen.dart' show FeatureTools;
import '../../info/info_keys.dart';
import '../../screen_time/screen_time.dart';
import '../../youtube/youtube_api.dart';

/// Settings → More apps: the free services the assistant can use, one tab
/// each, with whatever key or setup they take and their tool switches.
class MoreAppsScreen extends StatelessWidget {
  const MoreAppsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  static const tabs = ['Markets & travel', 'Bible', 'News', 'Library', 'Explore', 'Phone tools', 'Lookups', 'YouTube', 'Papers', 'Sports'];

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: tabs.length,
    initialIndex: initialTab.clamp(0, tabs.length - 1),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('More apps'),
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in tabs) Tab(text: t)],
        ),
      ),
      body: const TabBarView(
        children: [_MarketsTab(), BibleSettingsView(), _NewsTab(), _LibraryTab(), _ExploreTab(), _PhoneToolsTab(), _LookupsTab(), _YoutubeTab(), _PapersTab(), _SportsTab()],
      ),
    ),
  );
}

/// Intro text, the setup widgets, then a switch for each of [categories]' tools.
class _AppTab extends ConsumerWidget {
  const _AppTab({required this.intro, required this.categories, this.setup = const [], this.sources});
  final String intro;
  final List<ToolCategory> categories;
  final List<Widget> setup;
  final String? sources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.x4),
      children: [
        Text(intro, style: context.text.bodySmall?.copyWith(height: 1.4)),
        ...setup,
        for (final cat in categories) ...[
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(child: Text(cat.label.toUpperCase(), style: context.text.labelSmall)),
              TextButton(
                onPressed: () {
                  final tools = [for (final t in telegramTools) if (t.category == cat) t];
                  final allOn = tools.every((t) => s.toolChosen(t.name, destructive: t.destructive));
                  for (final t in tools) {
                    ctl.setToolEnabled(t.name, !allOn);
                  }
                },
                child: const Text('All on / off'),
              ),
            ],
          ),
          // The same rows as the Tools page: tap one for everything about it.
          FeatureTools(category: cat),
        ],
        if (sources != null) ...[
          const SizedBox(height: Space.l),
          Text(sources!, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        ],
      ],
    );
  }
}

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: Space.xl, bottom: Space.s),
  child: Text(text, style: context.text.labelSmall),
);

class _MarketsTab extends ConsumerWidget {
  const _MarketsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return _AppTab(
      intro:
          'Crypto and stock prices, currency conversion, weather, flights and public holidays, from free public sources. '
          'They need no account; a free CoinGecko demo key just raises the crypto rate limit.',
      categories: const [ToolCategory.markets],
      setup: [
        _heading(context, 'COINGECKO'),
        KeyField(
          label: 'CoinGecko API key (optional)',
          hint: 'coingecko.com → Developer dashboard → demo key (CG-…)',
          value: s.coingeckoKey,
          secret: true,
          onSave: ref.read(settingsProvider.notifier).setCoingeckoKey,
          help: Uri.parse('https://www.coingecko.com/en/developers/dashboard'),
        ),
        const SizedBox(height: Space.xs),
        Text(
          s.hasCoingeckoKey ? 'Using your key.' : 'Without a key, CoinGecko allows roughly 5–30 requests a minute.',
          style: context.text.bodySmall?.copyWith(color: AppColors.text3),
        ),
      ],
      sources:
          'Sources: CoinGecko, Yahoo Finance (may be delayed), European Central Bank via Frankfurter, Open-Meteo, adsbdb and '
          'adsb.lol (ADS-B), Nager.Date. Flight fares open on Google Flights, Skyscanner or Kayak. Nothing here is investment advice.',
    );
  }
}

class _NewsTab extends ConsumerWidget {
  const _NewsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return _AppTab(
      intro: 'Reddit posts, threads and communities, and Hacker News stories, comments and users. Neither needs an account or key.',
      categories: const [ToolCategory.news],
      setup: [
        _heading(context, 'REDDIT'),
        Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      s.hasRedditClientId ? 'Public JSON, with your client id as backup' : 'Works without a key',
                      style: context.text.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s),
              Text(
                'Reddit is read through its public JSON pages, no key needed. Reddit sometimes refuses those on some '
                'networks; a free client id is then used as a backup. To get one (optional):\n'
                '1. Open reddit.com/prefs/apps while signed in, and tap "create another app".\n'
                '2. Pick "installed app", give it any name, and set the redirect uri to http://localhost.\n'
                '3. Copy the code under the app\'s name (its client id) and paste it here.',
                style: context.text.bodySmall?.copyWith(height: 1.45),
              ),
              const SizedBox(height: Space.s),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://www.reddit.com/prefs/apps'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open reddit.com/prefs/apps'),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        KeyField(
          label: 'Reddit client id',
          hint: 'Optional: the code under your installed app\'s name',
          value: s.redditClientId,
          secret: false,
          onSave: ref.read(settingsProvider.notifier).setRedditClientId,
          help: Uri.parse('https://www.reddit.com/prefs/apps'),
        ),
      ],
      sources: 'Sources: Reddit\'s public JSON pages (oauth.reddit.com with your client id only when those are refused), Hacker News (Firebase API) and Algolia\'s HN search.',
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context) => const _AppTab(
    intro:
        'Free ebooks to read in the app or download (Project Gutenberg), any book in Open Library\'s catalogue, free '
        'audiobooks (LibriVox, Internet Archive), live radio from around the world (Radio Browser) and podcasts (Apple\'s '
        'directory and the shows\' own feeds). None needs an account. Audio plays in the app\'s player and keeps going '
        'while you chat; downloads land in Files.',
    categories: [ToolCategory.library],
    sources: 'Try: "find free sherlock holmes books", "play jazz radio from France", "top podcasts in Ethiopia", "audiobook of Pride and Prejudice".',
  );
}

class _ExploreTab extends ConsumerWidget {
  const _ExploreTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return _AppTab(
      intro: 'Facts about every country (an open dataset, with World Bank population), NASA\'s Astronomy Picture of the Day with its explanation, and every Pokémon: Pokédex entries, stats, matchups and evolutions.',
      categories: const [ToolCategory.explore],
      setup: [
        _heading(context, 'NASA'),
        KeyField(
          label: 'NASA API key (optional)',
          hint: 'api.nasa.gov → Generate API key (free, instant)',
          value: s.nasaKey,
          secret: true,
          onSave: ref.read(settingsProvider.notifier).setNasaKey,
          help: Uri.parse('https://api.nasa.gov/'),
        ),
        const SizedBox(height: Space.xs),
        Text(
          s.hasNasaKey ? 'Using your key (1,000 requests an hour).' : 'Without a key, NASA\'s shared DEMO_KEY allows about 30 requests an hour.',
          style: context.text.bodySmall?.copyWith(color: AppColors.text3),
        ),
      ],
      sources: 'Sources: github.com/mledoze/countries, the World Bank, flagcdn.com, api.nasa.gov (APOD), pokeapi.co.',
    );
  }
}

class _PhoneToolsTab extends StatefulWidget {
  const _PhoneToolsTab();

  @override
  State<_PhoneToolsTab> createState() => _PhoneToolsTabState();
}

class _PhoneToolsTabState extends State<_PhoneToolsTab> with WidgetsBindingObserver {
  bool? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android's settings: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final a = await screenTimeAccess();
    if (mounted) setState(() => _access = a);
  }

  @override
  Widget build(BuildContext context) => _AppTab(
    intro:
        'Screen time from Android\'s usage stats (time per app, per day and per hour, opens, unlocks and weekly trends), and '
        'image tools that resize, crop, compress, convert and remove backgrounds. Everything runs on this phone; nothing is uploaded.',
    categories: const [ToolCategory.screenTime, ToolCategory.imageTools],
    setup: [
      _heading(context, 'USAGE ACCESS'),
      Row(
        children: [
          Icon(_access == true ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 18, color: _access == true ? AppColors.success : AppColors.warning),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              _access == null
                  ? 'Checking…'
                  : _access!
                  ? 'On. Screen time can read app usage.'
                  : 'Off. Screen time needs Android\'s "Usage access" for Triangle (the same switch as data usage).',
              style: context.text.bodySmall,
            ),
          ),
          if (_access == false) TextButton(onPressed: openScreenTimeAccess, child: const Text('Turn on')),
        ],
      ),
    ],
    sources: 'Background removal uses ML Kit on the phone; Google Play services fetches its model the first time.',
  );
}

class _LookupsTab extends ConsumerWidget {
  const _LookupsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(infoKeysProvider);
    final ctl = ref.read(infoKeysProvider.notifier);
    return _AppTab(
      intro:
          'Package info (npm, PyPI, pub.dev), domain lookups (WHOIS, DNS, HTTPS expiry), xkcd, gold and fuel prices, '
          'earthquakes and disaster alerts, recipes and nutrition by barcode, air quality, UV, pollen and sunrise, the '
          'dictionary, translation and Wikipedia. Only gold prices need a key.',
      categories: const [ToolCategory.packages, ToolCategory.world, ToolCategory.food, ToolCategory.reference],
      setup: [
        _heading(context, 'METALS.DEV'),
        KeyField(
          label: 'metals.dev API key',
          hint: 'metals.dev → sign up → API key (free tier)',
          value: k.metalsKey,
          secret: true,
          onSave: ctl.setMetalsKey,
          help: Uri.parse('https://metals.dev/'),
        ),
        const SizedBox(height: Space.xs),
        Text(k.hasMetalsKey ? 'Gold and metal prices are on.' : 'Without a key, metal_prices can\'t run.', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        _heading(context, 'TRANSLATION'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: k.useLibre,
          onChanged: ctl.setUseLibre,
          title: const Text('Use LibreTranslate'),
          subtitle: const Text('Otherwise MyMemory (free, up to 500 characters at a time).'),
        ),
        if (k.useLibre) ...[
          KeyField(label: 'LibreTranslate server', hint: 'https://libretranslate.com or your own', value: k.libreUrl, onSave: ctl.setLibreUrl, help: Uri.parse('https://libretranslate.com/')),
          const SizedBox(height: Space.s),
          KeyField(label: 'LibreTranslate API key (if the server needs one)', value: k.libreKey, secret: true, onSave: ctl.setLibreKey),
        ],
      ],
      sources:
          'Sources: registry.npmjs.org, pypi.org, pypistats.org, pub.dev, rdap.org, dns.google, xkcd.com, metals.dev, GlobalPetrolPrices.com, '
          'USGS, GDACS, TheMealDB, Open Food Facts, Open-Meteo, dictionaryapi.dev, MyMemory, LibreTranslate, Wikipedia.',
    );
  }
}

class _YoutubeTab extends ConsumerStatefulWidget {
  const _YoutubeTab();

  @override
  ConsumerState<_YoutubeTab> createState() => _YoutubeTabState();
}

class _YoutubeTabState extends ConsumerState<_YoutubeTab> {
  @override
  void initState() {
    super.initState();
    YoutubeApi.loadUsed();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return _AppTab(
      intro:
          'Search YouTube with filters, exact views, likes and comment counts, comments with replies, what’s trending in a '
          'country, live streams and premieres, a channel’s uploads and most viewed videos, side-by-side channel comparisons, '
          'and new-upload checks for watches. Transcripts and, without a key, search, videos, channels and playlists work by '
          'reading YouTube’s pages.',
      categories: const [ToolCategory.youtube],
      setup: [
        _heading(context, 'YouTube Data API key'),
        KeyField(
          label: 'YouTube API key',
          hint: 'Google Cloud Console → APIs & Services → Credentials → API key (enable YouTube Data API v3)',
          value: s.youtubeKey,
          secret: true,
          onSave: ref.read(settingsProvider.notifier).setYoutubeKey,
          help: Uri.parse('https://console.cloud.google.com/apis/library/youtube.googleapis.com'),
        ),
        const SizedBox(height: Space.s),
        if (s.hasYoutubeKey)
          ValueListenableBuilder<int>(
            valueListenable: YoutubeApi.used,
            builder: (context, used, _) {
              final share = (used / YoutubeApi.dailyQuota).clamp(0.0, 1.0);
              return Container(
                padding: const EdgeInsets.all(Space.m),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Quota today', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                        Text('$used / ${YoutubeApi.dailyQuota} units', style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures)),
                      ],
                    ),
                    const SizedBox(height: Space.s),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: share, minHeight: 8, backgroundColor: AppColors.surface3, color: share > 0.9 ? AppColors.danger : AppColors.text),
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      'A search costs 100 units; videos, channels, comments, trending and playlists cost 1 each. It resets at midnight Pacific time.',
                      style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                    ),
                  ],
                ),
              );
            },
          )
        else
          Text('Without a key, comments, trending, live, channel videos, comparisons and new-upload checks are off.', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
      ],
      sources: 'Try: "what’s trending in Kenya in music", "top comments on this video", "compare MKBHD and Linus Tech Tips", "is anyone live streaming the match", "watch for new uploads from Veritasium every 3 hours".',
    );
  }
}

class _PapersTab extends ConsumerWidget {
  const _PapersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return _AppTab(
      intro:
          'Research papers from ScholarXIV: search millions of arXiv preprints by topic, title, author or category, or '
          'search eleven sources at once (arXiv, OpenAlex, Semantic Scholar, PubMed, Europe PMC, Crossref, bioRxiv, '
          'medRxiv, ChemRxiv, ChinaXiv, ClinicalTrials.gov) with citation counts and one-line TLDRs. Papers show as cards '
          'you can open for the abstract, PDF, authors’ profiles, similar papers and the journal.',
      categories: const [ToolCategory.papers],
      setup: [
        _heading(context, 'SCHOLARXIV API KEY'),
        KeyField(
          label: 'ScholarXIV API key',
          hint: 'scholarxiv.com → Developers → API keys → Create (sxv_…)',
          value: s.scholarxivKey,
          secret: true,
          onSave: ref.read(settingsProvider.notifier).setScholarxivKey,
          help: Uri.parse('https://scholarxiv.com/developers/dashboard/apikeys'),
        ),
        const SizedBox(height: Space.s),
        if (s.hasScholarxivKey && !s.scholarxivKey.startsWith('sxv_'))
          Text('ScholarXIV keys start with sxv_; this one may not work.', style: context.text.bodySmall?.copyWith(color: AppColors.warning))
        else
          Text(
            s.hasScholarxivKey ? 'Using your key.' : 'Without a key, the paper tools are off.',
            style: context.text.bodySmall?.copyWith(color: AppColors.text3),
          ),
        const SizedBox(height: Space.m),
        Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Plans', style: context.text.titleSmall),
              const SizedBox(height: Space.xs),
              Text(
                'Free: arXiv paper search (paper_search), 1,200 requests an hour.\n'
                'Go and above: everything else too: search across all eleven sources, paper details, related papers, '
                'author profiles and venues. The hourly limit is shared by all your keys.',
                style: context.text.bodySmall?.copyWith(height: 1.45),
              ),
              const SizedBox(height: Space.s),
              Wrap(
                spacing: Space.s,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse('https://scholarxiv.com/developers/dashboard/apikeys'), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: const Text('Get a key'),
                  ),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse('https://scholarxiv.com/developers/docs/papers-api'), mode: LaunchMode.externalApplication),
                    child: const Text('API docs'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      sources:
          'Try: "latest papers on retrieval augmented generation", "most cited papers on CRISPR since 2020", "who wrote '
          'Attention Is All You Need and what else have they published", "papers similar to arXiv 2005.11401".',
    );
  }
}

class _SportsTab extends ConsumerWidget {
  const _SportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(infoKeysProvider);
    final ctl = ref.read(infoKeysProvider.notifier);
    return _AppTab(
      intro:
          'Live scores, fixtures, match stats and lineups, league tables, teams and news for football (Premier League, LaLiga, '
          'Serie A, Bundesliga, Ligue 1, the Champions League and more), the NBA, NFL, MLB and NHL, plus Formula 1 and players '
          'in any sport. Scores, tables, F1 and players need no account; top scorers use a free football-data.org key.',
      categories: const [ToolCategory.sports],
      setup: [
        _heading(context, 'FOOTBALL-DATA.ORG'),
        KeyField(
          label: 'football-data.org API key (for top scorers)',
          hint: 'football-data.org → Register → the key arrives by email (free tier)',
          value: k.footballDataKey,
          secret: true,
          onSave: ctl.setFootballDataKey,
          help: Uri.parse('https://www.football-data.org/client/register'),
        ),
        const SizedBox(height: Space.xs),
        Text(
          k.hasFootballDataKey ? 'Top scorers are on (10 requests a minute on the free tier).' : 'Without a key, everything works except the top scorers table.',
          style: context.text.bodySmall?.copyWith(color: AppColors.text3),
        ),
        _heading(context, 'THESPORTSDB (OPTIONAL)'),
        KeyField(
          label: 'TheSportsDB key',
          hint: 'Leave empty to use the free shared key',
          value: k.sportsDbKey,
          secret: true,
          onSave: ctl.setSportsDbKey,
          help: Uri.parse('https://www.thesportsdb.com/free_sports_api'),
        ),
        const SizedBox(height: Space.xs),
        Text('Players come from TheSportsDB. A personal key only raises its limits.', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
      ],
      sources: 'Sources: ESPN (public scoreboard API), Jolpica (Ergast F1), TheSportsDB, football-data.org. Try: "Premier League scores", "NBA standings", "next F1 race", "Arsenal form", "who is Erling Haaland".',
    );
  }
}
