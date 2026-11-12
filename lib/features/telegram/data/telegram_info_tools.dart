part of 'telegram_tools.dart';

// Screen time, the image tools, and free lookups: packages and domains,
// xkcd, metal and fuel prices, earthquakes and disasters, recipes and food,
// air quality and the sun, dictionary and translation, Wikipedia. The chat
// controller runs these (features/info/info_tools.dart); the cards are in
// info_result_cards.dart.

const _imageFile = {'type': 'string', 'description': 'The picture: an attachment or generated file\'s name from this chat (list_attachments), or a path.'};
const _formatParam = {'type': 'string', 'enum': ['jpeg', 'png', 'webp'], 'description': 'Save as; default keeps the original\'s format.'};

final _infoTools = <TelegramTool>[
  // ---- screen time ------------------------------------------------------------------
  TelegramTool(
    name: 'screen_time',
    label: 'Checking screen time',
    category: ToolCategory.screenTime,
    cost: ToolCost.device,
    description:
        'How the phone was used, from Android\'s usage stats: view today (or one date) gives total screen time, unlocks, '
        'first use, the busiest hour, an hour-by-hour chart, top apps with opens and the last 7 days; view week gives the '
        'last 7 days against the 7 before (change %), average per day, busiest and quietest day, categories and top apps. '
        'The user sees a screen time card, so answer in a sentence or two.',
    parameters: _obj({
      'view': {'type': 'string', 'enum': ['today', 'day', 'week'], 'description': 'Default today.'},
      'date': {'type': 'string', 'description': 'For view day: YYYY-MM-DD (Android keeps about a month).'},
    }),
  ),
  TelegramTool(
    name: 'app_usage',
    label: 'Checking an app\'s screen time',
    category: ToolCategory.screenTime,
    cost: ToolCost.device,
    description:
        'One app\'s screen time day by day: total, average per day, days used, opens, its share of all screen time, '
        'the busiest day and the trend (later half against earlier half of the span).',
    parameters: _obj({
      'app': {'type': 'string', 'description': 'App name or package, like "YouTube" or "com.instagram.android".'},
      'days': {'type': 'integer', 'description': '7-30; default 14.'},
    }, ['app']),
  ),

  // ---- images -----------------------------------------------------------------------
  TelegramTool(
    name: 'image_info',
    label: 'Reading picture details',
    category: ToolCategory.imageTools,
    cost: ToolCost.device,
    description: 'A picture\'s size in pixels, file size, format, camera, when it was taken and whether it holds a GPS location.',
    parameters: _obj({'file': _imageFile}, ['file']),
  ),
  TelegramTool(
    name: 'image_resize',
    label: 'Resizing a picture',
    category: ToolCategory.imageTools,
    cost: ToolCost.device,
    description:
        'Resizes a picture on the phone into a new file (the original stays). Give width and/or height in pixels (one '
        'keeps the proportions), max_side, or percent. With both width and height, fit is contain (fits inside, default), '
        'cover (fills, trimming the overflow) or stretch. The user sees before and after; send the result with send_message.',
    parameters: _obj({
      'file': _imageFile,
      'width': {'type': 'integer', 'description': 'Target width in pixels.'},
      'height': {'type': 'integer', 'description': 'Target height in pixels.'},
      'max_side': {'type': 'integer', 'description': 'Longest side in pixels; never enlarges.'},
      'percent': {'type': 'number', 'description': 'Scale, like 50.'},
      'fit': {'type': 'string', 'enum': ['contain', 'cover', 'stretch'], 'description': 'With both width and height: contain fits inside, cover fills and trims, stretch distorts. Default contain.'},
      'format': _formatParam,
      'quality': {'type': 'integer', 'description': '1-100 for jpeg/webp; default 90.'},
    }, ['file']),
  ),
  TelegramTool(
    name: 'image_crop',
    label: 'Cropping a picture',
    category: ToolCategory.imageTools,
    cost: ToolCost.device,
    description:
        'Crops a picture into a new file: to an aspect ratio like "1:1", "4:5" or "16:9" (centred, or at gravity), or to a '
        'box given by x, y, width, height in pixels or as fractions 0-1 of the picture.',
    parameters: _obj({
      'file': _imageFile,
      'aspect': {'type': 'string', 'description': 'Like "1:1", "9:16".'},
      'gravity': {'type': 'string', 'enum': ['center', 'top', 'bottom', 'left', 'right'], 'description': 'Where an aspect crop sits; default center.'},
      'x': {'type': 'number', 'description': 'Left edge, in pixels or 0-1 of the width.'},
      'y': {'type': 'number', 'description': 'Top edge, in pixels or 0-1 of the height.'},
      'width': {'type': 'number', 'description': 'Box width, in pixels or 0-1 of the picture.'},
      'height': {'type': 'number', 'description': 'Box height, in pixels or 0-1 of the picture.'},
      'format': _formatParam,
    }, ['file']),
  ),
  TelegramTool(
    name: 'image_compress',
    label: 'Compressing a picture',
    category: ToolCategory.imageTools,
    cost: ToolCost.device,
    description:
        'Makes a picture\'s file smaller into a new file: a jpeg/webp quality, a target size in KB (lowers the quality, then '
        'the size, until it fits), and optionally a max_side. PNGs become JPEG (or WebP when transparent) unless format is set.',
    parameters: _obj({
      'file': _imageFile,
      'quality': {'type': 'integer', 'description': '1-100; default 75.'},
      'target_kb': {'type': 'integer', 'description': 'Aim for at most this many KB.'},
      'max_side': {'type': 'integer', 'description': 'Also shrink so the longest side is at most this many pixels.'},
      'format': _formatParam,
    }, ['file']),
  ),
  TelegramTool(
    name: 'image_convert',
    label: 'Converting a picture',
    category: ToolCategory.imageTools,
    cost: ToolCost.device,
    description: 'Converts a picture (including HEIC/HEIF and AVIF from the camera) to JPEG, PNG or WebP as a new file. Transparency becomes white in JPEG.',
    parameters: _obj({
      'file': _imageFile,
      'format': {'type': 'string', 'enum': ['jpeg', 'png', 'webp'], 'description': 'The format to save as.'},
      'quality': {'type': 'integer', 'description': '1-100 for jpeg/webp; default 90 (100 = lossless webp).'},
    }, ['file', 'format']),
  ),
  TelegramTool(
    name: 'image_remove_background',
    label: 'Removing the background',
    category: ToolCategory.imageTools,
    cost: ToolCost.device,
    description:
        'Cuts the main subject (people, pets, objects) out of a picture on the phone with ML Kit, as a transparent PNG or on '
        'a solid background colour. Nothing is uploaded. The first use may wait for Google Play services to fetch the model.',
    parameters: _obj({
      'file': _imageFile,
      'background': {'type': 'string', 'description': '"transparent" (default), "white", "black" or a hex colour like "#FFCC00".'},
    }, ['file']),
  ),

  // ---- packages, domains, xkcd ------------------------------------------------------
  TelegramTool(
    name: 'package_info',
    label: 'Looking up a package',
    category: ToolCategory.packages,
    cost: ToolCost.web,
    description:
        'A package from npm, PyPI or pub.dev: latest version and date, description, licence, links, downloads, recent '
        'versions, dependencies and the install command; pub.dev adds likes, pub points and platforms.',
    parameters: _obj({
      'registry': {'type': 'string', 'enum': ['npm', 'pypi', 'pub'], 'description': 'npm (JavaScript), pypi (Python) or pub (Dart/Flutter).'},
      'name': {'type': 'string', 'description': 'The exact package name, like "react", "requests" or "riverpod".'},
    }, ['registry', 'name']),
  ),
  TelegramTool(
    name: 'package_search',
    label: 'Searching packages',
    category: ToolCategory.packages,
    cost: ToolCost.web,
    description: 'Searches npm or pub.dev for packages matching words. PyPI has no search API: there it tries the words as package names.',
    parameters: _obj({
      'registry': {'type': 'string', 'enum': ['npm', 'pypi', 'pub'], 'description': 'npm, pypi or pub.'},
      'query': {'type': 'string', 'description': 'Words describing what the package does.'},
      'limit': {'type': 'integer', 'description': '1-20; default 10.'},
    }, ['registry', 'query']),
  ),
  TelegramTool(
    name: 'domain_lookup',
    label: 'Looking up a domain',
    category: ToolCategory.packages,
    cost: ToolCost.web,
    description:
        'Everything about a domain: registration (WHOIS via RDAP: registrar, created, expires and days left, nameservers, '
        'status, DNSSEC), DNS records (A, AAAA, CNAME, MX, NS, TXT, CAA) and the HTTPS certificate (issuer, expiry, days left, '
        'whether it is trusted). Pick checks to do fewer.',
    parameters: _obj({
      'domain': {'type': 'string', 'description': 'A domain or URL.'},
      'checks': {
        'type': 'array',
        'items': {'type': 'string', 'enum': ['whois', 'dns', 'ssl']},
        'description': 'Default all three.',
      },
    }, ['domain']),
  ),
  TelegramTool(
    name: 'xkcd',
    label: 'Fetching xkcd',
    category: ToolCategory.packages,
    cost: ToolCost.web,
    description: 'An xkcd comic: the latest, a number, or random. The user sees the comic with its alt text; don\'t repeat the alt text.',
    parameters: _obj({
      'number': {'type': 'integer', 'description': 'A comic number; leave out for the latest.'},
      'random': {'type': 'boolean', 'description': 'Pick a random comic.'},
    }),
  ),

  // ---- the world --------------------------------------------------------------------
  TelegramTool(
    name: 'metal_prices',
    label: 'Checking gold prices',
    category: ToolCategory.world,
    cost: ToolCost.web,
    description:
        'Live gold, silver, platinum, palladium and base-metal prices from metals.dev in any currency and unit, with gold per '
        'gram by karat (24k-14k). Needs the user\'s metals.dev key. Not investment advice.',
    parameters: _obj({
      'currency': {'type': 'string', 'description': 'ISO code like USD, ETB, EUR; default USD.'},
      'unit': {'type': 'string', 'enum': ['toz', 'g', 'kg', 'oz'], 'description': 'Default toz (troy ounce).'},
    }),
  ),
  TelegramTool(
    name: 'fuel_prices',
    label: 'Checking fuel prices',
    category: ToolCategory.world,
    cost: ToolCost.web,
    description:
        'A country\'s retail fuel prices per litre (and electricity per kWh) from GlobalPetrolPrices.com, updated weekly or '
        'monthly, in local currency, USD and EUR, with the world average.',
    parameters: _obj({
      'country': {'type': 'string', 'description': 'English name, like "Ethiopia".'},
      'fuels': {
        'type': 'array',
        'items': {'type': 'string', 'enum': ['gasoline', 'diesel', 'lpg', 'kerosene', 'electricity']},
        'description': 'Default gasoline and diesel.',
      },
    }, ['country']),
  ),
  TelegramTool(
    name: 'earthquakes',
    label: 'Checking earthquakes',
    category: ToolCategory.world,
    cost: ToolCost.web,
    description:
        'Recent earthquakes from USGS, worldwide or near a place (within radius_km, default 500 for a place), newest or '
        'strongest first, with magnitude, depth, distance, felt reports, PAGER alert and tsunami flag. Default worldwide M4.5+ '
        'in the last 7 days.',
    parameters: _obj({
      'place': {'type': 'string', 'description': 'A city or region to search around.'},
      'latitude': {'type': 'number', 'description': 'Centre latitude, instead of place.'},
      'longitude': {'type': 'number', 'description': 'Centre longitude, instead of place.'},
      'radius_km': {'type': 'number', 'description': 'Search radius around the place in km.'},
      'min_magnitude': {'type': 'number', 'description': 'Smallest magnitude; default 4.5 worldwide, 2.5 near a place.'},
      'days': {'type': 'integer', 'description': '1-365; default 7.'},
      'order': {'type': 'string', 'enum': ['time', 'magnitude'], 'description': 'Newest first (time, default) or strongest first.'},
      'limit': {'type': 'integer', 'description': '1-100; default 20.'},
    }),
  ),
  TelegramTool(
    name: 'disasters',
    label: 'Checking disaster alerts',
    category: ToolCategory.world,
    cost: ToolCost.web,
    description:
        'Current and recent disasters from GDACS (the UN/EU alert system): earthquakes, tropical cyclones, floods, '
        'volcanoes, droughts and wildfires with green, orange or red alert level, countries, dates and severity.',
    parameters: _obj({
      'types': {
        'type': 'array',
        'items': {'type': 'string', 'enum': ['EQ', 'TC', 'FL', 'VO', 'DR', 'WF']},
        'description': 'Default all.',
      },
      'min_alert': {'type': 'string', 'enum': ['green', 'orange', 'red'], 'description': 'Default green (everything).'},
      'country': {'type': 'string', 'description': 'Only events whose countries include this name.'},
      'days': {'type': 'integer', 'description': '1-365; default 30.'},
    }),
  ),
  TelegramTool(
    name: 'air_quality',
    label: 'Checking air quality',
    category: ToolCategory.world,
    cost: ToolCost.web,
    description:
        'Air quality (US and European AQI, PM2.5, PM10, ozone, NO₂, SO₂, CO, dust), UV index now and today\'s peak, pollen '
        '(Europe only), and sunrise, sunset and day length for a place, from Open-Meteo (the weather tool\'s provider). '
        'Without a place it uses the phone\'s location.',
    parameters: _obj({
      'place': {'type': 'string', 'description': 'A city or region; leave out to use where the phone is.'},
      'latitude': {'type': 'number', 'description': 'Latitude, instead of place.'},
      'longitude': {'type': 'number', 'description': 'Longitude, instead of place.'},
    }),
  ),

  // ---- food -------------------------------------------------------------------------
  TelegramTool(
    name: 'recipe_search',
    label: 'Finding recipes',
    category: ToolCategory.food,
    cost: ToolCost.web,
    description:
        'Finds recipes on TheMealDB by dish name, main ingredient, category (Beef, Chicken, Dessert, Seafood, Vegetarian, '
        'Vegan, Breakfast, Pasta…) or cuisine (Italian, Indian, Moroccan, Kenyan…), or random ones. The user sees tappable '
        'recipe cards; use recipe_details for one recipe.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'A dish name, like "lasagne".'},
      'ingredient': {'type': 'string', 'description': 'A main ingredient, like "chicken_breast".'},
      'category': {'type': 'string', 'description': 'A TheMealDB category, like "Dessert".'},
      'cuisine': {'type': 'string', 'description': 'A cuisine, like "Italian".'},
      'random': {'type': 'boolean', 'description': 'Random recipes instead of a search.'},
      'limit': {'type': 'integer', 'description': '1-30; default 12.'},
    }),
  ),
  TelegramTool(
    name: 'recipe_details',
    label: 'Opening a recipe',
    category: ToolCategory.food,
    cost: ToolCost.web,
    description: 'One recipe: ingredients with measures, numbered steps, category, cuisine, tags, video and source. The user sees the recipe; summarise rather than repeat it.',
    parameters: _obj({
      'recipe': {'type': 'string', 'description': 'A TheMealDB id from recipe_search, or a dish name.'},
    }, ['recipe']),
  ),
  TelegramTool(
    name: 'food_nutrition',
    label: 'Looking up nutrition',
    category: ToolCategory.food,
    cost: ToolCost.web,
    description:
        'Nutrition facts from Open Food Facts: by barcode number, by a photo of the barcode (file), by scanning it with the '
        'camera now (scan true: opens the scanner on screen), or by searching product names. Gives Nutri-Score, NOVA group, '
        'calories and nutrients per 100 g, ingredients, allergens and additives.',
    parameters: _obj({
      'barcode': {'type': 'string', 'description': 'A product barcode (EAN/UPC digits).'},
      'file': {'type': 'string', 'description': 'A photo of the barcode from this chat.'},
      'scan': {'type': 'boolean', 'description': 'Open the camera to scan a barcode.'},
      'query': {'type': 'string', 'description': 'Search product names instead.'},
    }),
  ),

  // ---- words and Wikipedia ----------------------------------------------------------
  TelegramTool(
    name: 'define_word',
    label: 'Looking up a word',
    category: ToolCategory.reference,
    cost: ToolCost.web,
    description: 'A word\'s pronunciation (with audio), meanings by part of speech, examples, synonyms and antonyms, from the Free Dictionary API (Wiktionary).',
    parameters: _obj({
      'word': {'type': 'string', 'description': 'The word to look up.'},
      'language': {'type': 'string', 'description': 'Default en.'},
    }, ['word']),
  ),
  TelegramTool(
    name: 'translate_text',
    label: 'Translating',
    category: ToolCategory.reference,
    cost: ToolCost.web,
    description:
        'Translates text (up to 500 characters with MyMemory; longer when the user set up LibreTranslate) into a language, '
        'detecting the source. For a Telegram message use translate_message instead.',
    parameters: _obj({
      'text': {'type': 'string', 'description': 'The text to translate.'},
      'to': {'type': 'string', 'description': 'ISO 639-1 code like fr, am, es, ar, zh.'},
      'from': {'type': 'string', 'description': 'Source code; default detected.'},
    }, ['text', 'to']),
  ),
  TelegramTool(
    name: 'wikipedia_search',
    label: 'Searching Wikipedia',
    category: ToolCategory.reference,
    cost: ToolCost.web,
    description: 'Searches Wikipedia articles, with a short description, the first sentences and a picture for each.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'What to search for.'},
      'language': {'type': 'string', 'description': 'Wikipedia language code; default en.'},
      'limit': {'type': 'integer', 'description': '1-20; default 8.'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'wikipedia_summary',
    label: 'Reading Wikipedia',
    category: ToolCategory.reference,
    cost: ToolCost.web,
    description: 'The summary of one Wikipedia article (the closest match when the title isn\'t exact), with its picture and link.',
    parameters: _obj({
      'title': {'type': 'string', 'description': 'The article title (or close to it).'},
      'language': {'type': 'string', 'description': 'Wikipedia language code; default en.'},
    }, ['title']),
  ),
  TelegramTool(
    name: 'wikipedia_on_this_day',
    label: 'Checking on this day',
    category: ToolCategory.reference,
    cost: ToolCost.web,
    description: 'What happened on a date in history from Wikipedia: selected events, or all events, births, deaths and holidays.',
    parameters: _obj({
      'date': {'type': 'string', 'description': 'MM-DD or YYYY-MM-DD; default today.'},
      'type': {'type': 'string', 'enum': ['selected', 'events', 'births', 'deaths', 'holidays', 'all'], 'description': 'Default selected.'},
      'language': {'type': 'string', 'description': 'Wikipedia language code; default en.'},
      'limit': {'type': 'integer', 'description': '1-40 per section; default 12.'},
    }),
  ),
  // ---- sports -----------------------------------------------------------------------
  TelegramTool(
    name: 'sports_scores',
    label: 'Checking scores',
    category: ToolCategory.sports,
    cost: ToolCost.web,
    description:
        'Live scores, results and fixtures for a league on a day (default today) from ESPN: soccer (Premier League, LaLiga, '
        'Serie A, Bundesliga, Ligue 1, Champions League and more), NBA, WNBA, NFL, MLB, NHL and college leagues. Each game '
        'has its status, score, scorers or top performers, venue and TV. The user sees a scoreboard and can tap a game for '
        'the full match; use sports_match for one game.',
    parameters: _obj({
      'league': {'type': 'string', 'enum': leagueIds, 'description': 'League id, like epl, laliga, ucl, nba, nfl.'},
      'date': {'type': 'string', 'description': 'YYYY-MM-DD; default today in the league schedule.'},
      'team': {'type': 'string', 'description': 'Only games of this team.'},
    }, ['league']),
  ),
  TelegramTool(
    name: 'sports_match',
    label: 'Opening a match',
    category: ToolCategory.sports,
    cost: ToolCost.web,
    description:
        'One game in full: score, status, goals, cards and substitutions with minutes, team stats side by side '
        '(possession, shots…), lineups with formations, or top performers for other sports, venue and attendance. '
        'Needs the event id from sports_scores or sports_team.',
    parameters: _obj({
      'league': {'type': 'string', 'enum': leagueIds, 'description': 'The league the game is in.'},
      'event_id': {'type': 'string', 'description': 'The game id from sports_scores.'},
    }, ['league', 'event_id']),
  ),
  TelegramTool(
    name: 'sports_standings',
    label: 'Checking the table',
    category: ToolCategory.sports,
    cost: ToolCost.web,
    description:
        'A league table or conference standings: position, played, won, drawn, lost, goal difference and points (soccer), '
        'or win %, games behind, streak and last ten (US sports), with qualification and relegation zones.',
    parameters: _obj({
      'league': {'type': 'string', 'enum': leagueIds, 'description': 'League id.'},
    }, ['league']),
  ),
  TelegramTool(
    name: 'sports_team',
    label: 'Looking up a team',
    category: ToolCategory.sports,
    cost: ToolCost.web,
    description: 'A team: position and record, form (last five), recent results and next games, with its crest and colours.',
    parameters: _obj({
      'league': {'type': 'string', 'enum': leagueIds, 'description': 'The league the team plays in.'},
      'team': {'type': 'string', 'description': 'Team name or abbreviation, like "Arsenal" or "LAL".'},
    }, ['league', 'team']),
  ),
  TelegramTool(
    name: 'sports_player',
    label: 'Looking up a player',
    category: ToolCategory.sports,
    cost: ToolCost.web,
    description:
        'A player or athlete in any sport from TheSportsDB: photo, team and national team, position, number, nationality, '
        'age and birthplace, height and weight, and a biography.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'The player name.'},
    }, ['name']),
  ),
  TelegramTool(
    name: 'sports_news',
    label: 'Reading sports news',
    category: ToolCategory.sports,
    cost: ToolCost.web,
    description: 'The latest ESPN headlines for a league, with pictures and links.',
    parameters: _obj({
      'league': {'type': 'string', 'enum': leagueIds, 'description': 'League id.'},
      'limit': {'type': 'integer', 'description': '1-25; default 10.'},
    }, ['league']),
  ),
  TelegramTool(
    name: 'sports_top_scorers',
    label: 'Checking top scorers',
    category: ToolCategory.sports,
    cost: ToolCost.web,
    description:
        'The goal scorers table of a football competition with goals, assists, penalties and games, from football-data.org. '
        'Needs the free football-data.org key the user adds in Settings.',
    parameters: _obj({
      'competition': {'type': 'string', 'enum': scorerCompetitions.keys.toList(), 'description': 'Competition id, like epl or ucl.'},
      'limit': {'type': 'integer', 'description': '1-30; default 15.'},
    }, ['competition']),
  ),
  TelegramTool(
    name: 'formula1',
    label: 'Checking Formula 1',
    category: ToolCategory.sports,
    cost: ToolCost.web,
    description:
        'Formula 1 from Jolpica (Ergast): next (the next Grand Prix with every session time and the championship leader), '
        'standings (drivers), constructors, last_race (full classification) or calendar (the season).',
    parameters: _obj({
      'view': {'type': 'string', 'enum': ['next', 'standings', 'constructors', 'last_race', 'calendar'], 'description': 'Default next.'},
      'season': {'type': 'string', 'description': 'A year like 2025; default the current season.'},
    }),
  ),

];

final infoToolNames = {for (final t in _infoTools) t.name};

/// Screen time and the image tools run through Android.
bool infoToolReady(TelegramTool t) => !(t.category == ToolCategory.screenTime || t.category == ToolCategory.imageTools) || Device.supported;

/// The image tools only write new files; the rest read.
const _infoPolicies = <String, ToolPolicy>{
  'screen_time': ToolPolicy(ToolAccess.read),
  'app_usage': ToolPolicy(ToolAccess.read),
  'image_info': ToolPolicy(ToolAccess.read),
  'package_info': ToolPolicy(ToolAccess.read),
  'package_search': ToolPolicy(ToolAccess.read),
  'domain_lookup': ToolPolicy(ToolAccess.read),
  'xkcd': ToolPolicy(ToolAccess.read),
  'metal_prices': ToolPolicy(ToolAccess.read),
  'fuel_prices': ToolPolicy(ToolAccess.read),
  'earthquakes': ToolPolicy(ToolAccess.read),
  'disasters': ToolPolicy(ToolAccess.read),
  'air_quality': ToolPolicy(ToolAccess.read),
  'recipe_search': ToolPolicy(ToolAccess.read),
  'recipe_details': ToolPolicy(ToolAccess.read),
  'food_nutrition': ToolPolicy(ToolAccess.read),
  'define_word': ToolPolicy(ToolAccess.read),
  'translate_text': ToolPolicy(ToolAccess.read),
  'wikipedia_search': ToolPolicy(ToolAccess.read),
  'wikipedia_summary': ToolPolicy(ToolAccess.read),
  'wikipedia_on_this_day': ToolPolicy(ToolAccess.read),
  'image_resize': ToolPolicy(ToolAccess.modify),
  'image_crop': ToolPolicy(ToolAccess.modify),
  'image_compress': ToolPolicy(ToolAccess.modify),
  'image_convert': ToolPolicy(ToolAccess.modify),
  'image_remove_background': ToolPolicy(ToolAccess.modify),
  'sports_scores': ToolPolicy(ToolAccess.read),
  'sports_match': ToolPolicy(ToolAccess.read),
  'sports_standings': ToolPolicy(ToolAccess.read),
  'sports_team': ToolPolicy(ToolAccess.read),
  'sports_player': ToolPolicy(ToolAccess.read),
  'sports_news': ToolPolicy(ToolAccess.read),
  'sports_top_scorers': ToolPolicy(ToolAccess.read),
  'formula1': ToolPolicy(ToolAccess.read),
};

const _infoReferences = <String, ToolReference>{
  'screen_time': ToolReference(['view', 'date', 'total', 'unlocks', 'first_use', 'busiest_hour', 'hourly_minutes', 'top_apps', 'categories', 'week', 'daily', 'change_percent']),
  'app_usage': ToolReference(['name', 'package', 'time', 'average_per_day', 'days_used', 'opens', 'share_of_screen_time', 'busiest_day', 'change_percent', 'series'], limits: ['days: 7-30.']),
  'image_info': ToolReference(['width', 'height', 'bytes', 'mime', 'camera', 'taken', 'has_location']),
  'image_resize': ToolReference(['image_path', 'width', 'height', 'bytes', 'original_width', 'original_height', 'original_bytes']),
  'image_crop': ToolReference(['image_path', 'width', 'height', 'bytes']),
  'image_compress': ToolReference(['image_path', 'bytes', 'original_bytes', 'saved_percent', 'quality']),
  'image_convert': ToolReference(['image_path', 'format', 'bytes']),
  'image_remove_background': ToolReference(['image_path', 'background', 'width', 'height']),
  'package_info': ToolReference(['name', 'version', 'description', 'license', 'published', 'downloads', 'recent_versions', 'dependencies', 'install', 'url']),
  'package_search': ToolReference(['count', 'packages'], limits: ['limit: 1-20.']),
  'domain_lookup': ToolReference(['domain', 'whois', 'dns', 'ssl']),
  'xkcd': ToolReference(['number', 'title', 'alt', 'image', 'date', 'url']),
  'metal_prices': ToolReference(['currency', 'unit', 'metals', 'gold_per_gram', 'updated']),
  'fuel_prices': ToolReference(['country', 'updated', 'prices']),
  'earthquakes': ToolReference(['count', 'strongest', 'earthquakes'], limits: ['days: 1-365; limit: 1-100.']),
  'disasters': ToolReference(['count', 'by_type', 'red', 'orange', 'events']),
  'air_quality': ToolReference(['place', 'aqi', 'pollutants', 'uv', 'pollen', 'sun', 'hourly']),
  'recipe_search': ToolReference(['count', 'recipes'], limits: ['limit: 1-30.']),
  'recipe_details': ToolReference(['id', 'name', 'ingredients', 'steps', 'category', 'cuisine', 'youtube']),
  'food_nutrition': ToolReference(['barcode', 'name', 'brand', 'nutriscore', 'nova', 'per_100g', 'allergens', 'ingredients']),
  'define_word': ToolReference(['word', 'phonetic', 'audio', 'meanings']),
  'translate_text': ToolReference(['translation', 'from', 'to', 'alternatives', 'engine'], limits: ['MyMemory: 500 characters.']),
  'wikipedia_search': ToolReference(['count', 'results']),
  'wikipedia_summary': ToolReference(['title', 'description', 'extract', 'image', 'url']),
  'wikipedia_on_this_day': ToolReference(['date', 'selected', 'events', 'births', 'deaths', 'holidays']),
  'sports_scores': ToolReference(['league', 'date', 'count', 'live', 'events: id, status, home, away, moments, leaders, venue']),
  'sports_match': ToolReference(['status', 'home', 'away', 'stats', 'events', 'lineups', 'leaders', 'venue', 'attendance']),
  'sports_standings': ToolReference(['league', 'season', 'groups: rows', 'zones']),
  'sports_team': ToolReference(['name', 'standing', 'record', 'form', 'recent', 'next']),
  'sports_player': ToolReference(['name', 'team', 'position', 'nationality', 'age', 'height', 'description', 'photo']),
  'sports_news': ToolReference(['articles']),
  'sports_top_scorers': ToolReference(['competition', 'season', 'scorers']),
  'formula1': ToolReference(['view', 'name', 'sessions', 'drivers', 'teams', 'results', 'races']),
};
