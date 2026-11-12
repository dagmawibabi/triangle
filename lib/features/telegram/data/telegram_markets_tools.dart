part of 'telegram_tools.dart';

// Markets and travel, from free sources: CoinGecko for crypto (an optional
// demo key in Settings raises its rate limits), Yahoo Finance's public chart
// and search endpoints for stocks, ETFs and indices, Frankfurter (European
// Central Bank rates) for currencies, Open-Meteo for weather, adsbdb and
// adsb.lol for flight routes and live positions, and Nager.Date for public
// holidays. None needs an account.

final _marketsTools = <TelegramTool>[
  TelegramTool(
    name: 'crypto_prices',
    label: 'Checking crypto prices',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description:
        'Live crypto prices (CoinGecko): price, 1h/24h/7d change, market cap and rank, 24h volume, high/low, all-time '
        'high and a 7-day sparkline. coins: names, symbols or CoinGecko ids ("bitcoin", "ETH", "solana"); leave it out '
        'for the top coins by market cap. vs: quote currency (usd default; eur, gbp, btc…). The user sees a card.',
    parameters: _obj({
      'coins': {'description': 'Coins by name, symbol or CoinGecko id, like bitcoin, ETH or solana. Leave out for the top coins.', 
        'type': 'array',
        'items': {'type': 'string'},
      },
      'vs': {'description': 'Quote currency: usd (default), eur, gbp, jpy, btc, eth.', 'type': 'string'},
      'limit': {'type': 'integer', 'description': 'Top coins when no coins are given: 1-50, default 10.'},
    }),
  ),
  TelegramTool(
    name: 'crypto_coin',
    label: 'Looking up a coin',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description:
        'One cryptocurrency in full (CoinGecko): description, price and changes, market cap, supply (circulating, '
        'total, max), all-time high/low, categories, homepage and a price chart over days (1, 7, 30, 90, 365).',
    parameters: _obj({
      'coin': {'type': 'string', 'description': 'Name, symbol or CoinGecko id.'},
      'days': {'description': 'Chart length in days: 1, 7, 30 (default), 90 or 365.', 'type': 'integer'},
      'vs': {'description': 'Quote currency: usd (default), eur, gbp, btc.', 'type': 'string'},
    }, ['coin']),
  ),
  TelegramTool(
    name: 'crypto_trending',
    label: 'Finding trending coins',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description: 'The coins most searched on CoinGecko in the last 24 hours, with price and 24h change.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'stock_quote',
    label: 'Checking stock prices',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description:
        'Stock, ETF, index, futures or forex quotes (Yahoo Finance, may be delayed): price, change, day range, 52-week '
        'range, previous close, exchange, currency and a price chart. symbols: tickers like AAPL, MSFT, ^GSPC (S&P 500), '
        'BTC-USD, EURUSD=X, 7203.T; use stock_search to find one. range: 1d, 5d, 1mo (default), 6mo, 1y, 5y.',
    parameters: _obj({
      'symbols': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '1-8 tickers.',
      },
      'range': {'description': 'Chart range: 1d, 5d, 1mo (default), 6mo, 1y or 5y.', 
        'type': 'string',
        'enum': ['1d', '5d', '1mo', '6mo', '1y', '5y'],
      },
    }, ['symbols']),
  ),
  TelegramTool(
    name: 'stock_search',
    label: 'Finding a ticker',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description: 'Finds ticker symbols by company or fund name (Yahoo Finance): symbol, name, exchange and type.',
    parameters: _obj({
      'query': {'description': 'A company, fund or index name, like Tesla or S&P 500.', 'type': 'string'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'currency_convert',
    label: 'Converting currency',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description:
        'Converts money between currencies at European Central Bank reference rates (Frankfurter; updated on working '
        'days). amount (default 1), from (USD), to: one or more ISO codes. date: a past day (YYYY-MM-DD). days: also '
        'returns the rate history for the first "to" currency over that many days (up to 365), for a chart.',
    parameters: _obj({
      'amount': {'description': 'How much to convert; default 1.', 'type': 'number'},
      'from': {'description': 'ISO code of the currency to convert from; default USD.', 'type': 'string'},
      'to': {'description': 'ISO codes to convert into, like EUR and GBP.', 
        'type': 'array',
        'items': {'type': 'string'},
      },
      'date': {'description': 'A past day for historical rates, YYYY-MM-DD; default the latest.', 'type': 'string'},
      'days': {'description': 'Also return the rate history for the first to-currency over this many days (2-365).', 'type': 'integer'},
    }, ['to']),
  ),
  TelegramTool(
    name: 'weather',
    label: 'Checking the weather',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description:
        'Current weather and a forecast (Open-Meteo): temperature, feels-like, humidity, wind, conditions, the next 24 '
        'hours and up to 14 days (highs, lows, rain chance, sunrise, sunset). place: a city or town; or latitude and '
        'longitude. units: metric (default) or imperial.',
    parameters: _obj({
      'place': {'description': 'A city, town or place name, like Addis Ababa.', 'type': 'string'},
      'latitude': {'description': 'Latitude in degrees, instead of place.', 'type': 'number'},
      'longitude': {'description': 'Longitude in degrees, instead of place.', 'type': 'number'},
      'days': {'type': 'integer', 'description': '1-14, default 7.'},
      'units': {'description': 'metric (default: degrees C, km/h) or imperial (degrees F, mph).', 
        'type': 'string',
        'enum': ['metric', 'imperial'],
      },
    }),
  ),
  TelegramTool(
    name: 'flight_status',
    label: 'Tracking a flight',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description:
        'A flight\'s route and, if it is in the air now, its live position, altitude, speed, aircraft and registration '
        '(adsbdb and adsb.lol, from ADS-B receivers; schedules and delays aren\'t available). flight: the flight number '
        'as on the ticket (BA117, UA 901) or the ICAO callsign (BAW117).',
    parameters: _obj({
      'flight': {'description': 'Flight number as on the ticket (BA117, UA 901) or the ICAO callsign (BAW117).', 'type': 'string'},
    }, ['flight']),
  ),
  TelegramTool(
    name: 'flight_search',
    label: 'Finding flights',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description:
        'Builds ready-to-open searches on Google Flights, Skyscanner and Kayak for a trip (no free service gives fares, '
        'so prices show when the user opens one). from and to: airport or city IATA codes (LHR, NYC); date and '
        'return_date: YYYY-MM-DD; adults (default 1); cabin: economy, premium, business or first.',
    parameters: _obj({
      'from': {'description': 'Departure airport or city IATA code, like LHR or NYC.', 'type': 'string'},
      'to': {'description': 'Arrival airport or city IATA code, like ADD or JFK.', 'type': 'string'},
      'date': {'description': 'Departure day, YYYY-MM-DD.', 'type': 'string'},
      'return_date': {'description': 'Return day for a round trip, YYYY-MM-DD; leave out for one way.', 'type': 'string'},
      'adults': {'description': 'Number of adult passengers, 1-9; default 1.', 'type': 'integer'},
      'cabin': {'description': 'economy (default), premium, business or first.', 
        'type': 'string',
        'enum': ['economy', 'premium', 'business', 'first'],
      },
    }, ['from', 'to', 'date']),
  ),
  TelegramTool(
    name: 'public_holidays',
    label: 'Looking up holidays',
    category: ToolCategory.markets,
    cost: ToolCost.web,
    description:
        'Public holidays in a country for a year (Nager.Date): date, local and English name, and whether it is '
        'nationwide. country: two-letter code (US, GB, ET, DE). Upcoming ones are marked, and the next one has next: true. '
        'One call is enough: without a year, when few are left this year the result already includes the first ones of next year '
        '(includes_next_year). Call again only for a different country or a specific other year.',
    parameters: _obj({
      'country': {'description': 'Two-letter country code, like US, GB, ET or DE.', 'type': 'string'},
      'year': {'description': 'The year; default this year.', 'type': 'integer'},
    }, ['country']),
  ),
];

extension _MarketsTools on TelegramToolRunner {
  Future<ToolOutput>? _runMarkets(String name, Map<String, dynamic> args) => switch (name) {
    'crypto_prices' => _cryptoPrices(args),
    'crypto_coin' => _cryptoCoin(args),
    'crypto_trending' => _cryptoTrending(),
    'stock_quote' => _stockQuote(args),
    'stock_search' => _stockSearch(args),
    'currency_convert' => _currencyConvert(args),
    'weather' => _weather(args),
    'flight_status' => _flightStatus(args),
    'flight_search' => _flightSearch(args),
    'public_holidays' => _publicHolidays(args),
    _ => null,
  };

  // ---- shared ------------------------------------------------------------------

  static double? _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  /// At most [max] evenly spaced points of [values], last one kept, so charts
  /// stay small in the conversation.
  /// Indexes [_thin] keeps, so times can be thinned in step with prices.
  static List<int> _thinIdx(int n, [int max = 60]) {
    if (n <= max) return [for (var i = 0; i < n; i++) i];
    final step = (n - 1) / (max - 1);
    return [for (var i = 0; i < max; i++) (i * step).round()];
  }

  static List<double> _thin(List<double> values, [int max = 60]) {
    if (values.length <= max) return values;
    final step = (values.length - 1) / (max - 1);
    return [for (var i = 0; i < max; i++) values[(i * step).round()]];
  }

  static double _round(double v) {
    final a = v.abs();
    final digits = a >= 1000 ? 2 : (a >= 1 ? 4 : (a >= 0.01 ? 6 : 10));
    return double.parse(v.toStringAsFixed(digits));
  }

  static String _list(Object? v) => switch (v) {
    List l => l.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).join(','),
    String s => s,
    _ => '',
  };

  // ---- crypto (CoinGecko) ------------------------------------------------------

  Future<Object?> _gecko(String path, [Map<String, String> query = const {}]) {
    final key = _settings.coingeckoKey.trim();
    // Pro keys start with "CG-" too; the demo API accepts both headers.
    return _json(
      Uri.https('api.coingecko.com', '/api/v3$path', query),
      headers: {if (key.isNotEmpty) 'x-cg-demo-api-key': key},
    );
  }

  String _vs(Map<String, dynamic> args) {
    final v = '${args['vs'] ?? 'usd'}'.trim().toLowerCase();
    return RegExp(r'^[a-z]{2,5}$').hasMatch(v) ? v : 'usd';
  }

  /// CoinGecko ids for names or symbols ("eth" → "ethereum").
  Future<List<String>> _coinIds(List<String> names) async {
    final out = <String>[];
    for (final raw in names.take(25)) {
      final q = raw.trim().toLowerCase();
      if (q.isEmpty) continue;
      final j = await _gecko('/search', {'query': q}) as Map;
      final coins = (j['coins'] as List? ?? const []).whereType<Map>().toList();
      // An exact symbol or id beats the search's own order.
      final exact = coins.where((c) => '${c['symbol']}'.toLowerCase() == q || '${c['id']}' == q).firstOrNull;
      final pick = exact ?? coins.firstOrNull;
      if (pick != null) out.add('${pick['id']}');
    }
    return out;
  }

  Map<String, dynamic> _coinRow(Map c) => {
    'id': c['id'],
    'symbol': '${c['symbol'] ?? ''}'.toUpperCase(),
    'name': c['name'],
    'image': c['image'],
    'rank': c['market_cap_rank'],
    'price': _num(c['current_price']),
    'change_1h': _num(c['price_change_percentage_1h_in_currency']),
    'change_24h': _num(c['price_change_percentage_24h_in_currency'] ?? c['price_change_percentage_24h']),
    'change_7d': _num(c['price_change_percentage_7d_in_currency']),
    'market_cap': _num(c['market_cap']),
    'volume_24h': _num(c['total_volume']),
    'high_24h': _num(c['high_24h']),
    'low_24h': _num(c['low_24h']),
    'ath': _num(c['ath']),
    'ath_change': _num(c['ath_change_percentage']),
    'ath_date': '${c['ath_date'] ?? ''}'.split('T').first,
    'atl': _num(c['atl']),
    'atl_change': _num(c['atl_change_percentage']),
    'fdv': _num(c['fully_diluted_valuation']),
    'market_cap_change_24h': _num(c['market_cap_change_percentage_24h']),
    'price_change_24h': _num(c['price_change_24h']),
    'circulating_supply': _num(c['circulating_supply']),
    'total_supply': _num(c['total_supply']),
    'max_supply': _num(c['max_supply']),
    if ((c['sparkline_in_7d'] as Map?)?['price'] is List)
      'sparkline_7d': _thin([
        for (final p in (c['sparkline_in_7d'] as Map)['price'] as List)
          if (_num(p) != null) _round(_num(p)!),
      ], 42),
  };

  Future<ToolOutput> _cryptoPrices(Map<String, dynamic> args) async {
    final vs = _vs(args);
    final names = [for (final c in (args['coins'] as List? ?? const [])) '$c'];
    final ids = names.isEmpty ? <String>[] : await _coinIds(names);
    if (names.isNotEmpty && ids.isEmpty) throw ArgumentError('No coins found for ${names.join(', ')}.');
    final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 50);
    final rows = await _gecko('/coins/markets', {
      'vs_currency': vs,
      if (ids.isNotEmpty) 'ids': ids.join(','),
      'order': 'market_cap_desc',
      'per_page': '${ids.isNotEmpty ? ids.length : limit}',
      'page': '1',
      'sparkline': 'true',
      'price_change_percentage': '1h,24h,7d',
    }) as List;
    return ToolOutput({
      'vs': vs,
      'coins': [for (final c in rows.whereType<Map>()) _coinRow(c)],
      'source': 'CoinGecko',
    });
  }

  Future<ToolOutput> _cryptoCoin(Map<String, dynamic> args) async {
    final vs = _vs(args);
    final ids = await _coinIds(['${args['coin'] ?? ''}']);
    if (ids.isEmpty) throw ArgumentError('No coin called "${args['coin']}".');
    final id = ids.first;
    final days = const [1, 7, 30, 90, 365].firstWhere(
      (d) => d >= ((args['days'] as num?)?.toInt() ?? 30),
      orElse: () => 365,
    );
    final (info, chart) = await (
      _gecko('/coins/$id', {
        'localization': 'false',
        'tickers': 'false',
        'community_data': 'false',
        'developer_data': 'false',
      }),
      _gecko('/coins/$id/market_chart', {'vs_currency': vs, 'days': '$days'}),
    ).wait;
    final j = info as Map;
    final m = (j['market_data'] as Map?) ?? const {};
    double? at(String k) => _num((m[k] as Map?)?[vs]);
    final points = [
      for (final p in ((chart as Map)['prices'] as List? ?? const []))
        if (p is List && p.length > 1 && _num(p[0]) != null && _num(p[1]) != null) (_num(p[0])!.toInt(), _round(_num(p[1])!)),
    ];
    final keep = _thinIdx(points.length, 90);
    final prices = [for (final i in keep) points[i].$2];
    final times = [for (final i in keep) points[i].$1];
    final volumes = [
      for (final v in ((chart)['total_volumes'] as List? ?? const []))
        if (v is List && v.length > 1 && _num(v[1]) != null) _num(v[1])!,
    ];
    final links = (j['links'] as Map?) ?? const {};
    return ToolOutput({
      'id': id,
      'name': j['name'],
      'symbol': '${j['symbol'] ?? ''}'.toUpperCase(),
      'image': (j['image'] as Map?)?['large'],
      'rank': j['market_cap_rank'],
      'vs': vs,
      'price': at('current_price'),
      'change_24h': _num(m['price_change_percentage_24h']),
      'change_7d': _num(m['price_change_percentage_7d']),
      'change_30d': _num(m['price_change_percentage_30d']),
      'change_1y': _num(m['price_change_percentage_1y']),
      'market_cap': at('market_cap'),
      'volume_24h': at('total_volume'),
      'high_24h': at('high_24h'),
      'low_24h': at('low_24h'),
      'ath': at('ath'),
      'ath_date': '${(m['ath_date'] as Map?)?[vs] ?? ''}'.split('T').first,
      'atl': at('atl'),
      'circulating_supply': _num(m['circulating_supply']),
      'total_supply': _num(m['total_supply']),
      'max_supply': _num(m['max_supply']),
      'atl_date': '${(m['atl_date'] as Map?)?[vs] ?? ''}'.split('T').first,
      'ath_change': _num((m['ath_change_percentage'] as Map?)?[vs]),
      'fdv': at('fully_diluted_valuation'),
      'market_cap_change_24h': _num(m['market_cap_change_percentage_24h']),
      'change_1h': _num((m['price_change_percentage_1h_in_currency'] as Map?)?[vs]),
      'change_14d': _num(m['price_change_percentage_14d']),
      'change_60d': _num(m['price_change_percentage_60d']),
      'change_200d': _num(m['price_change_percentage_200d']),
      'sentiment_up_pct': _num(j['sentiment_votes_up_percentage']),
      'watchlist_users': _num(j['watchlist_portfolio_users']),
      'genesis_date': j['genesis_date'],
      'hashing_algorithm': j['hashing_algorithm'],
      'explorer': (links['blockchain_site'] as List?)?.whereType<String>().where((u) => u.isNotEmpty).firstOrNull,
      'github': ((links['repos_url'] as Map?)?['github'] as List?)?.whereType<String>().where((u) => u.isNotEmpty).firstOrNull,
      'reddit': '${links['subreddit_url'] ?? ''}'.isEmpty ? null : links['subreddit_url'],
      'twitter': '${links['twitter_screen_name'] ?? ''}'.isEmpty ? null : 'https://x.com/${links['twitter_screen_name']}',
      'categories': [for (final c in (j['categories'] as List? ?? const [])) if (c != null) '$c'].take(6).toList(),
      'description': _DiscoverTools._cut((j['description'] as Map?)?['en'], 900),
      'homepage': (links['homepage'] as List?)?.whereType<String>().where((u) => u.isNotEmpty).firstOrNull,
      'url': 'https://www.coingecko.com/en/coins/$id',
      'chart': {
        'days': days,
        'prices': prices,
        'times': times,
        if (volumes.isNotEmpty) 'volume_avg': volumes.reduce((a, b) => a + b) / volumes.length,
      },
      'source': 'CoinGecko',
    });
  }

  Future<ToolOutput> _cryptoTrending() async {
    final j = await _gecko('/search/trending') as Map;
    return ToolOutput({
      'coins': [
        for (final c in (j['coins'] as List? ?? const []).whereType<Map>())
          if (c['item'] is Map)
            {
              'id': (c['item'] as Map)['id'],
              'name': (c['item'] as Map)['name'],
              'symbol': '${(c['item'] as Map)['symbol'] ?? ''}'.toUpperCase(),
              'image': (c['item'] as Map)['large'] ?? (c['item'] as Map)['thumb'],
              'rank': (c['item'] as Map)['market_cap_rank'],
              'price': _num(((c['item'] as Map)['data'] as Map?)?['price']),
              'change_24h': _num((((c['item'] as Map)['data'] as Map?)?['price_change_percentage_24h'] as Map?)?['usd']),
            },
      ],
      'vs': 'usd',
      'source': 'CoinGecko',
    });
  }

  // ---- stocks (Yahoo Finance) --------------------------------------------------

  static const _yahooHeaders = {'user-agent': 'Mozilla/5.0 (Linux; Android 14) Triangle/1.0'};

  Future<Map<String, dynamic>> _quote(String symbol, String range) async {
    final interval = switch (range) {
      '1d' => '5m',
      '5d' => '30m',
      '5y' => '1wk',
      _ => '1d',
    };
    final j = await _json(
      Uri.https('query1.finance.yahoo.com', '/v8/finance/chart/${Uri.encodeComponent(symbol)}', {
        'range': range,
        'interval': interval,
        'includePrePost': 'false',
      }),
      headers: _yahooHeaders,
    ) as Map;
    final result = ((j['chart'] as Map?)?['result'] as List?)?.firstOrNull as Map?;
    if (result == null) {
      final why = ((j['chart'] as Map?)?['error'] as Map?)?['description'];
      throw ArgumentError('No quote for $symbol${why == null ? '' : ': $why'}. Try stock_search.');
    }
    final meta = (result['meta'] as Map?) ?? const {};
    final rawCloses = (((result['indicators'] as Map?)?['quote'] as List?)?.firstOrNull as Map?)?['close'] as List? ?? const [];
    final rawTimes = result['timestamp'] as List? ?? const [];
    final points = [
      for (var i = 0; i < rawCloses.length; i++)
        if (_num(rawCloses[i]) != null) (i < rawTimes.length && rawTimes[i] is num ? (rawTimes[i] as num).toInt() * 1000 : 0, _round(_num(rawCloses[i])!)),
    ];
    final keep = _thinIdx(points.length, 90);
    final closes = [for (final i in keep) points[i].$2];
    final times = [for (final i in keep) points[i].$1];
    final price = _num(meta['regularMarketPrice']);
    final prev = _num(meta['chartPreviousClose'] ?? meta['previousClose']);
    // Over a day, the change is against yesterday's close; over longer
    // ranges, against the range's start.
    final base = range == '1d' ? prev : (closes.isNotEmpty ? closes.first : prev);
    return {
      'symbol': meta['symbol'] ?? symbol,
      'name': meta['longName'] ?? meta['shortName'] ?? symbol,
      'exchange': meta['fullExchangeName'] ?? meta['exchangeName'],
      'currency': meta['currency'],
      'type': '${meta['instrumentType'] ?? ''}'.toLowerCase(),
      'price': price,
      'previous_close': prev,
      'change': price != null && base != null ? _round(price - base) : null,
      'change_pct': price != null && base != null && base != 0 ? double.parse(((price - base) / base * 100).toStringAsFixed(2)) : null,
      'day_high': _num(meta['regularMarketDayHigh']),
      'day_low': _num(meta['regularMarketDayLow']),
      'year_high': _num(meta['fiftyTwoWeekHigh']),
      'year_low': _num(meta['fiftyTwoWeekLow']),
      'volume': _num(meta['regularMarketVolume']),
      'market_time': meta['regularMarketTime'] is num
          ? DateTime.fromMillisecondsSinceEpoch((meta['regularMarketTime'] as num).toInt() * 1000).toIso8601String().substring(0, 16)
          : null,
      'range': range,
      'chart': closes,
      'chart_times': times,
      'url': 'https://finance.yahoo.com/quote/${Uri.encodeComponent('${meta['symbol'] ?? symbol}')}',
    };
  }

  Future<ToolOutput> _stockQuote(Map<String, dynamic> args) async {
    final symbols = [
      for (final s in (args['symbols'] as List? ?? [args['symbol'] ?? '']))
        if ('$s'.trim().isNotEmpty) '$s'.trim().toUpperCase(),
    ].take(8).toList();
    if (symbols.isEmpty) throw ArgumentError('Give at least one ticker symbol.');
    final range = const ['1d', '5d', '1mo', '6mo', '1y', '5y'].contains(args['range']) ? '${args['range']}' : '1mo';
    final quotes = <Map<String, dynamic>>[];
    final failed = <String>[];
    for (final s in symbols) {
      try {
        quotes.add(await _quote(s, range));
      } catch (e) {
        failed.add('$s (${e is ArgumentError ? e.message : e})');
      }
    }
    if (quotes.isEmpty) throw ArgumentError(failed.join('; '));
    return ToolOutput({
      'range': range,
      'quotes': quotes,
      if (failed.isNotEmpty) 'not_found': failed,
      'note': 'Prices may be delayed up to 20 minutes.',
      'source': 'Yahoo Finance',
    });
  }

  Future<ToolOutput> _stockSearch(Map<String, dynamic> args) async {
    final q = '${args['query'] ?? ''}'.trim();
    if (q.isEmpty) throw ArgumentError('What should I search for?');
    final j = await _json(
      Uri.https('query2.finance.yahoo.com', '/v1/finance/search', {'q': q, 'quotesCount': '10', 'newsCount': '0'}),
      headers: _yahooHeaders,
    ) as Map;
    return ToolOutput({
      'query': q,
      'results': [
        for (final r in (j['quotes'] as List? ?? const []).whereType<Map>())
          if (r['symbol'] != null)
            {
              'symbol': r['symbol'],
              'name': r['longname'] ?? r['shortname'],
              'exchange': r['exchDisp'] ?? r['exchange'],
              'type': r['typeDisp'] ?? r['quoteType'],
            },
      ],
      'source': 'Yahoo Finance',
    });
  }

  // ---- currency (Frankfurter) --------------------------------------------------

  Future<ToolOutput> _currencyConvert(Map<String, dynamic> args) async {
    final from = '${args['from'] ?? 'USD'}'.trim().toUpperCase();
    final to = _list(args['to']).toUpperCase().split(',').where((c) => c.length == 3 && c != from).toList();
    if (to.isEmpty) throw ArgumentError('Name at least one currency to convert to, like EUR.');
    final amount = _num(args['amount']) ?? 1;
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('${args['date'] ?? ''}') ? '${args['date']}' : 'latest';
    final j = await _json(Uri.https('api.frankfurter.dev', '/v1/$date', {'from': from, 'to': to.join(',')})) as Map;
    final rates = (j['rates'] as Map?) ?? const {};
    final days = ((args['days'] as num?)?.toInt() ?? 0).clamp(0, 365);
    Map<String, dynamic>? history;
    if (days > 1) {
      final end = DateTime.now();
      final start = end.subtract(Duration(days: days));
      String d(DateTime t) => t.toIso8601String().substring(0, 10);
      final h = await _json(Uri.https('api.frankfurter.dev', '/v1/${d(start)}..${d(end)}', {'from': from, 'to': to.first})) as Map;
      final series = (h['rates'] as Map?) ?? const {};
      final keys = series.keys.map((k) => '$k').toList()..sort();
      history = {
        'to': to.first,
        'from_date': keys.firstOrNull,
        'to_date': keys.lastOrNull,
        'rates': _thin([for (final k in keys) if (_num((series[k] as Map?)?[to.first]) != null) _num((series[k] as Map)[to.first])!], 80),
      };
    }
    return ToolOutput({
      'amount': amount,
      'from': from,
      'date': j['date'],
      'conversions': [
        for (final c in to)
          if (_num(rates[c]) != null) {'currency': c, 'rate': _num(rates[c]), 'value': _round(amount * _num(rates[c])!)},
      ],
      'history': ?history,
      if (to.where((c) => _num(rates[c]) == null).toList() case final missing when missing.isNotEmpty)
        'not_supported': '${missing.join(', ')}: the European Central Bank does not publish a rate for ${missing.length == 1 ? 'it' : 'them'}. Use web_search for an unofficial rate.',
      'source': 'European Central Bank via Frankfurter',
    });
  }

  // ---- weather (Open-Meteo) ----------------------------------------------------

  static String _sky(int? code) => switch (code) {
    0 => 'Clear',
    1 => 'Mostly clear',
    2 => 'Partly cloudy',
    3 => 'Overcast',
    45 || 48 => 'Fog',
    51 || 53 || 55 => 'Drizzle',
    56 || 57 => 'Freezing drizzle',
    61 || 63 => 'Rain',
    65 => 'Heavy rain',
    66 || 67 => 'Freezing rain',
    71 || 73 => 'Snow',
    75 => 'Heavy snow',
    77 => 'Snow grains',
    80 || 81 => 'Showers',
    82 => 'Heavy showers',
    85 || 86 => 'Snow showers',
    95 => 'Thunderstorm',
    96 || 99 => 'Thunderstorm with hail',
    _ => 'Unknown',
  };

  Future<ToolOutput> _weather(Map<String, dynamic> args) async {
    var lat = _num(args['latitude']), lon = _num(args['longitude']);
    String? place, country, admin;
    if (lat == null || lon == null) {
      final q = '${args['place'] ?? ''}'.trim();
      if (q.isEmpty) throw ArgumentError('Name a place, or give latitude and longitude.');
      final g = await _json(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': q, 'count': '1'})) as Map;
      final r = (g['results'] as List?)?.firstOrNull as Map?;
      if (r == null) throw ArgumentError('No place called "$q".');
      lat = _num(r['latitude']);
      lon = _num(r['longitude']);
      place = r['name'] as String?;
      country = r['country'] as String?;
      admin = r['admin1'] as String?;
    }
    final imperial = args['units'] == 'imperial';
    final days = ((args['days'] as num?)?.toInt() ?? 7).clamp(1, 14);
    final j = await _json(Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day,precipitation',
      'hourly': 'temperature_2m,precipitation_probability,weather_code',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
      'timezone': 'auto',
      'forecast_days': '$days',
      if (imperial) 'temperature_unit': 'fahrenheit',
      if (imperial) 'wind_speed_unit': 'mph',
    })) as Map;
    final cur = (j['current'] as Map?) ?? const {};
    final hourly = (j['hourly'] as Map?) ?? const {};
    final daily = (j['daily'] as Map?) ?? const {};
    List l(Map m, String k) => m[k] as List? ?? const [];
    // The next 24 hours from now, in the place's own time.
    final now = '${cur['time'] ?? ''}';
    final times = l(hourly, 'time').map((t) => '$t').toList();
    final from = times.indexWhere((t) => t.compareTo(now) >= 0).clamp(0, times.length);
    return ToolOutput({
      'place': ?place,
      'region': ?admin,
      'country': ?country,
      'latitude': lat,
      'longitude': lon,
      'timezone': j['timezone'],
      'units': imperial ? 'imperial' : 'metric',
      'temp_unit': imperial ? '°F' : '°C',
      'wind_unit': imperial ? 'mph' : 'km/h',
      'current': {
        'time': now,
        'temperature': _num(cur['temperature_2m']),
        'feels_like': _num(cur['apparent_temperature']),
        'humidity': _num(cur['relative_humidity_2m']),
        'wind': _num(cur['wind_speed_10m']),
        'precipitation': _num(cur['precipitation']),
        'code': cur['weather_code'],
        'conditions': _sky((cur['weather_code'] as num?)?.toInt()),
        'is_day': cur['is_day'] == 1,
      },
      'hourly': [
        for (var i = from; i < from + 24 && i < times.length; i++)
          {
            'time': times[i].length >= 16 ? times[i].substring(11, 16) : times[i],
            'temperature': _num(l(hourly, 'temperature_2m').elementAtOrNull(i)),
            'rain_chance': _num(l(hourly, 'precipitation_probability').elementAtOrNull(i)),
            'code': l(hourly, 'weather_code').elementAtOrNull(i),
          },
      ],
      'daily': [
        for (var i = 0; i < l(daily, 'time').length; i++)
          {
            'date': l(daily, 'time')[i],
            'high': _num(l(daily, 'temperature_2m_max').elementAtOrNull(i)),
            'low': _num(l(daily, 'temperature_2m_min').elementAtOrNull(i)),
            'rain_chance': _num(l(daily, 'precipitation_probability_max').elementAtOrNull(i)),
            'code': l(daily, 'weather_code').elementAtOrNull(i),
            'conditions': _sky((l(daily, 'weather_code').elementAtOrNull(i) as num?)?.toInt()),
            'sunrise': '${l(daily, 'sunrise').elementAtOrNull(i) ?? ''}'.split('T').last,
            'sunset': '${l(daily, 'sunset').elementAtOrNull(i) ?? ''}'.split('T').last,
          },
      ],
      'source': 'Open-Meteo',
    });
  }

  // ---- flights (adsbdb, adsb.lol) ----------------------------------------------

  static double _km(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lon2 - lon1) / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static Map<String, dynamic>? _airport(Object? a) => a is! Map
      ? null
      : {
          'name': a['name'],
          'iata': a['iata_code'],
          'icao': a['icao_code'],
          'city': a['municipality'],
          'country': a['country_name'],
          'latitude': _num(a['latitude']),
          'longitude': _num(a['longitude']),
        };

  Future<ToolOutput> _flightStatus(Map<String, dynamic> args) async {
    final flight = '${args['flight'] ?? ''}'.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (flight.isEmpty) throw ArgumentError('Which flight? Give its number, like BA117.');
    Map? route;
    try {
      final j = await _json(Uri.https('api.adsbdb.com', '/v0/callsign/$flight')) as Map;
      route = (j['response'] as Map?)?['flightroute'] as Map?;
    } catch (_) {
      // Unknown route: a live position may still be found by callsign.
    }
    final callsign = '${route?['callsign_icao'] ?? route?['callsign'] ?? flight}'.toUpperCase();
    Map? ac;
    try {
      final live = await _json(Uri.https('api.adsb.lol', '/v2/callsign/$callsign')) as Map;
      ac = (live['ac'] as List?)?.whereType<Map>().firstOrNull;
    } catch (_) {}
    if (route == null && ac == null) {
      throw ArgumentError('No route or live position for $flight. Check the number, or try the ICAO callsign (BAW117 for BA117).');
    }
    final origin = _airport(route?['origin']);
    final dest = _airport(route?['destination']);
    Map<String, dynamic>? position;
    double? progress;
    if (ac != null) {
      final lat = _num(ac['lat']), lon = _num(ac['lon']);
      final alt = ac['alt_baro'];
      position = {
        'latitude': lat,
        'longitude': lon,
        'on_ground': alt == 'ground',
        'altitude_ft': alt is num ? alt.toInt() : null,
        'speed_kt': _num(ac['gs'])?.round(),
        'heading': _num(ac['track'])?.round(),
        'vertical_rate_fpm': _num(ac['baro_rate'])?.round(),
        'registration': ac['r'],
        'aircraft': ac['desc'] ?? ac['t'],
        'hex': ac['hex'],
        'squawk': ac['squawk'],
        'seen_seconds_ago': _num(ac['seen'])?.round(),
      };
      final oLat = origin?['latitude'] as double?, oLon = origin?['longitude'] as double?;
      final dLat = dest?['latitude'] as double?, dLon = dest?['longitude'] as double?;
      if (lat != null && lon != null && oLat != null && oLon != null && dLat != null && dLon != null) {
        final total = _km(oLat, oLon, dLat, dLon);
        final left = _km(lat, lon, dLat, dLon);
        if (total > 0) progress = ((1 - left / total).clamp(0, 1) * 100).roundToDouble();
        position['km_to_go'] = left.round();
      }
    }
    final hex = position?['hex'];
    return ToolOutput({
      'flight': route?['callsign_iata'] ?? flight,
      'callsign': callsign,
      'airline': (route?['airline'] as Map?)?['name'],
      'airline_country': (route?['airline'] as Map?)?['country'],
      'origin': ?origin,
      'destination': ?dest,
      'airborne': position != null && position['on_ground'] != true,
      'live': ?position,
      'progress_pct': ?progress,
      'map_url': hex != null ? 'https://globe.adsb.lol/?icao=$hex' : 'https://globe.adsb.lol/?callsign=$callsign',
      'note': position == null
          ? 'Not transmitting now: it is on the ground or out of receiver range. Times and delays aren\'t available from this source.'
          : 'Live from ADS-B receivers; times and delays aren\'t available from this source.',
      'source': 'adsbdb, adsb.lol',
    });
  }

  Future<ToolOutput> _flightSearch(Map<String, dynamic> args) async {
    String code(Object? v) => '${v ?? ''}'.trim().toUpperCase();
    final from = code(args['from']), to = code(args['to']);
    final date = '${args['date'] ?? ''}'.trim();
    final back = '${args['return_date'] ?? ''}'.trim();
    final day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (from.isEmpty || to.isEmpty) throw ArgumentError('Give from and to as airport or city codes, like LHR and JFK.');
    if (!day.hasMatch(date)) throw ArgumentError('Give the date as YYYY-MM-DD.');
    final hasBack = day.hasMatch(back);
    final adults = ((args['adults'] as num?)?.toInt() ?? 1).clamp(1, 9);
    final cabin = '${args['cabin'] ?? 'economy'}';
    String yymmdd(String d) => d.substring(2).replaceAll('-', '');
    final google = Uri.https('www.google.com', '/travel/flights', {
      'q': 'Flights from $from to $to on $date${hasBack ? ' returning $back' : ''}'
          '${adults > 1 ? ' for $adults adults' : ''}${cabin == 'economy' ? '' : ' $cabin class'}',
    });
    final sky = Uri.https(
      'www.skyscanner.net',
      '/transport/flights/${from.toLowerCase()}/${to.toLowerCase()}/${yymmdd(date)}/${hasBack ? '${yymmdd(back)}/' : ''}',
      {
        'adultsv2': '$adults',
        'cabinclass': switch (cabin) {
          'premium' => 'premiumeconomy',
          'business' => 'business',
          'first' => 'first',
          _ => 'economy',
        },
      },
    );
    final kayak = Uri.https(
      'www.kayak.com',
      '/flights/$from-$to/$date${hasBack ? '/$back' : ''}${adults > 1 ? '/${adults}adults' : ''}'
          '${cabin == 'economy' ? '' : '/${cabin == 'premium' ? 'premium' : cabin}'}',
    );
    return ToolOutput({
      'from': from,
      'to': to,
      'date': date,
      'return_date': hasBack ? back : null,
      'adults': adults,
      'cabin': cabin,
      'links': [
        {'site': 'Google Flights', 'url': '$google'},
        {'site': 'Skyscanner', 'url': '$sky'},
        {'site': 'Kayak', 'url': '$kayak'},
      ],
      'note': 'Fares aren\'t available from a free service: the user sees them when they open a link.',
    });
  }

  // ---- holidays (Nager.Date) ---------------------------------------------------

  Future<ToolOutput> _publicHolidays(Map<String, dynamic> args) async {
    final cc = '${args['country'] ?? ''}'.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(cc)) throw ArgumentError('Give the country as a two-letter code, like US.');
    final asked = (args['year'] as num?)?.toInt();
    final year = asked ?? DateTime.now().year;
    Future<List<Map>> fetch(int y) async => [for (final h in (await _json(Uri.https('date.nager.at', '/api/v3/PublicHolidays/$y/$cc')) as List? ?? const []).whereType<Map>()) h];
    final today = DateTime.now().toIso8601String().substring(0, 10);
    var list = await fetch(year);
    // Late in the year few are left: add next year's first ones, so one
    // call answers "what's coming up" (the model otherwise calls again).
    var nextYear = 0;
    if (asked == null && list.where((h) => '${h['date']}'.compareTo(today) >= 0).length < 3) {
      try {
        final more = (await fetch(year + 1)).take(4).toList();
        nextYear = more.length;
        list = [...list, ...more];
      } catch (_) {}
    }
    var nextMarked = false;
    return ToolOutput({
      'country': cc,
      'year': year,
      'holidays': [
        for (final h in list)
          {
            'date': h['date'],
            'name': h['name'],
            'local_name': h['localName'],
            'nationwide': h['global'] == true,
            if (h['global'] != true && h['counties'] is List) 'regions': (h['counties'] as List).take(8).toList(),
            'upcoming': '${h['date']}'.compareTo(today) >= 0,
            if (!nextMarked && '${h['date']}'.compareTo(today) >= 0 && (nextMarked = true)) 'next': true,
          },
      ],
      if (nextYear > 0) 'includes_next_year': nextYear,
      'source': 'Nager.Date',
    });
  }
}

/// Every markets tool only reads public data on the web.
const _marketsPolicies = <String, ToolPolicy>{
  'crypto_prices': ToolPolicy(ToolAccess.read),
  'crypto_coin': ToolPolicy(ToolAccess.read),
  'crypto_trending': ToolPolicy(ToolAccess.read),
  'stock_quote': ToolPolicy(ToolAccess.read),
  'stock_search': ToolPolicy(ToolAccess.read),
  'currency_convert': ToolPolicy(ToolAccess.read),
  'weather': ToolPolicy(ToolAccess.read),
  'flight_status': ToolPolicy(ToolAccess.read),
  'flight_search': ToolPolicy(ToolAccess.read),
  'public_holidays': ToolPolicy(ToolAccess.read),
};

const _marketsReferences = <String, ToolReference>{
  'crypto_prices': ToolReference(
    ['vs', 'coins', 'source'],
    limits: ['limit: default 10; minimum 1, maximum 50.', 'Without a CoinGecko key, about 30 calls a minute.'],
  ),
  'crypto_coin': ToolReference([
    'id',
    'name',
    'symbol',
    'price',
    'change_24h',
    'change_7d',
    'change_30d',
    'change_1y',
    'market_cap',
    'circulating_supply',
    'max_supply',
    'ath',
    'atl',
    'categories',
    'description',
    'homepage',
    'chart',
    'url',
  ], limits: ['days: 1, 7, 30, 90 or 365.']),
  'crypto_trending': ToolReference(['coins', 'vs', 'source']),
  'stock_quote': ToolReference(
    ['range', 'quotes', 'not_found', 'note', 'source'],
    limits: ['1-8 symbols; quotes may be delayed.'],
  ),
  'stock_search': ToolReference(['query', 'results', 'source']),
  'currency_convert': ToolReference(
    ['amount', 'from', 'date', 'conversions', 'history', 'source'],
    limits: ['days: up to 365. ECB reference rates, working days only.'],
  ),
  'weather': ToolReference(
    ['place', 'country', 'timezone', 'units', 'current', 'hourly', 'daily', 'source'],
    limits: ['days: default 7; minimum 1, maximum 14.'],
  ),
  'flight_status': ToolReference([
    'flight',
    'callsign',
    'airline',
    'origin',
    'destination',
    'airborne',
    'live',
    'progress_pct',
    'map_url',
    'note',
  ], limits: ['Live data only while the aircraft transmits ADS-B; no schedules or delays.']),
  'flight_search': ToolReference(['from', 'to', 'date', 'return_date', 'adults', 'cabin', 'links', 'note']),
  'public_holidays': ToolReference(['country', 'year', 'holidays', 'includes_next_year', 'source']),
};
