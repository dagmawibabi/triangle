import 'dart:io';

import '../device/device.dart';
import '../image_tools/image_ops.dart';
import '../qr/qr.dart';
import '../screen_time/screen_time.dart';
import '../sports/sports_api.dart';
import '../telegram/data/telegram_tools.dart' show ToolOutput;
import 'info_api.dart';
import 'info_keys.dart';

// Runs the tools in telegram_info_tools.dart. The chat controller resolves
// file names to paths before calling.

Future<ToolOutput> runInfoTool(String name, Map<String, dynamic> a) async {
  String str(String k) => '${a[k] ?? ''}'.trim();
  int? integer(String k) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(str(k));
  double? number(String k) => a[k] is num ? (a[k] as num).toDouble() : double.tryParse(str(k));
  List<String> strings(String k) => [for (final x in (a[k] as List? ?? const [])) '$x'.trim()].where((s) => s.isNotEmpty).toList();
  final api = InfoApi.instance;
  final sports = SportsApi.instance;
  await InfoKeysNotifier.load();
  try {
    switch (name) {
      // ---- screen time
      case 'screen_time':
        final view = str('view').isEmpty ? 'today' : str('view');
        DateTime? end;
        if (view == 'day') {
          end = DateTime.tryParse(str('date'));
          if (end == null) return const ToolOutput({'error': 'For view day give date as YYYY-MM-DD.'});
        }
        final raw = await loadScreenTime(days: view == 'week' ? 14 : 7, end: end);
        return ToolOutput(analyzeScreenTime(raw, view: view == 'week' ? 'week' : 'today'));
      case 'app_usage':
        final days = (integer('days') ?? 14).clamp(7, 30);
        final raw = await loadScreenTime(days: days);
        return ToolOutput(analyzeScreenTime(raw, view: 'app', app: str('app')));

      // ---- images
      case 'image_info':
        final f = str('file');
        final r = await runImageOp('info', f, const {});
        return ToolOutput({'file': f.split(RegExp(r'[\\/]')).last, ...r});
      case 'image_resize' || 'image_crop' || 'image_compress' || 'image_convert' || 'image_remove_background':
        final f = str('file');
        final op = name.substring(6);
        final args = <String, dynamic>{
          if (str('format').isNotEmpty) 'format': str('format') == 'jpg' ? 'jpeg' : str('format'),
          'quality': ?integer('quality'),
          'max_side': ?integer('max_side'),
          if (op == 'resize') ...{
            'width': ?integer('width'),
            'height': ?integer('height'),
            'percent': ?number('percent'),
            if (str('fit').isNotEmpty) 'fit': str('fit'),
          },
          if (op == 'crop') ...{
            if (str('aspect').isNotEmpty) 'aspect': str('aspect'),
            if (str('gravity').isNotEmpty) 'gravity': str('gravity'),
            'x': ?number('x'),
            'y': ?number('y'),
            'width': ?number('width'),
            'height': ?number('height'),
          },
          if (op == 'compress') 'target_kb': ?integer('target_kb'),
          if (op == 'remove_background') 'background': str('background').isEmpty ? 'transparent' : str('background'),
        };
        if (op == 'convert' && str('format').isEmpty) return const ToolOutput({'error': 'format is jpeg, png or webp.'});
        final suffix = switch (op) {
          'resize' => 'resized',
          'crop' => 'cropped',
          'compress' => 'compressed',
          'convert' => 'converted',
          _ => 'cutout',
        };
        final r = await runImageOp(op == 'remove_background' ? 'remove_background' : op, f, args, suffix: suffix);
        final path = '${r['path']}';
        final before = (r['original_bytes'] as num?) ?? 0;
        final after = (r['bytes'] as num?) ?? 0;
        return ToolOutput({
          'done': op,
          'image_path': path,
          'created_files': [path],
          'name': path.split(RegExp(r'[\\/]')).last,
          'source_path': f,
          'source': f.split(RegExp(r'[\\/]')).last,
          ...{for (final e in r.entries) if (e.key != 'path') e.key: e.value},
          'size_kb': (after / 1024).ceil(),
          'original_kb': (before / 1024).ceil(),
          if (before > 0) 'saved_percent': ((before - after) / before * 100).round(),
          'note': 'The user sees before and after. Send it with send_message by passing its name in files.',
        });

      // ---- packages, domains, xkcd
      case 'package_info':
        return ToolOutput(await api.package(str('registry'), str('name')));
      case 'package_search':
        final list = await api.packageSearch(str('registry'), str('query'), limit: (integer('limit') ?? 10).clamp(1, 20));
        return ToolOutput({'registry': str('registry'), 'query': str('query'), 'count': list.length, 'packages': list});
      case 'domain_lookup':
        final checks = strings('checks').toSet();
        return ToolOutput(await api.domain(str('domain'), checks: checks.isEmpty ? const {'whois', 'dns', 'ssl'} : checks));
      case 'xkcd':
        return ToolOutput(await api.xkcd(number: integer('number'), random: a['random'] == true));

      // ---- the world
      case 'metal_prices':
        return ToolOutput(await api.metals(currency: str('currency').isEmpty ? 'USD' : str('currency'), unit: str('unit').isEmpty ? 'toz' : str('unit')));
      case 'fuel_prices':
        final fuels = strings('fuels');
        return ToolOutput(await api.fuel(str('country'), types: fuels.isEmpty ? const ['gasoline', 'diesel'] : fuels));
      case 'earthquakes':
        return ToolOutput(await api.earthquakes(
          place: str('place'),
          latitude: number('latitude'),
          longitude: number('longitude'),
          radiusKm: number('radius_km'),
          minMagnitude: number('min_magnitude'),
          days: integer('days') ?? 7,
          order: str('order'),
          limit: integer('limit') ?? 20,
        ));
      case 'disasters':
        return ToolOutput(await api.disasters(
          types: strings('types'),
          minAlert: str('min_alert').isEmpty ? 'green' : str('min_alert'),
          country: str('country'),
          days: integer('days') ?? 30,
        ));
      case 'air_quality':
        return ToolOutput(await api.air(place: str('place'), latitude: number('latitude'), longitude: number('longitude')));

      // ---- food
      case 'recipe_search':
        return ToolOutput(await api.recipes(
          query: str('query'),
          ingredient: str('ingredient'),
          category: str('category'),
          cuisine: str('cuisine'),
          random: a['random'] == true,
          limit: integer('limit') ?? 12,
        ));
      case 'recipe_details':
        return ToolOutput(await api.recipe(str('recipe')));
      case 'food_nutrition':
        var code = str('barcode');
        var how = 'barcode';
        if (code.isEmpty && str('file').isNotEmpty) {
          final f = str('file');
          if (!File(f).existsSync()) return ToolOutput({'error': 'No picture "$f" in this chat.'});
          final codes = await Qr.read(f);
          code = codes.map((c) => '${c['value']}').firstWhere((v) => RegExp(r'^\d{8,14}$').hasMatch(v), orElse: () => '');
          if (code.isEmpty) return const ToolOutput({'error': 'No product barcode found in that picture. Try a sharper, closer photo.'});
          how = 'photo';
        }
        if (code.isEmpty && a['scan'] == true) {
          final r = await Qr.scan(prompt: 'Point at the product\'s barcode');
          if (r == null) return const ToolOutput({'error': 'Scanning was closed without a barcode (or the app isn\'t on screen).'});
          code = '${r['value'] ?? ''}';
          how = 'scan';
        }
        if (code.isNotEmpty) return ToolOutput({...await api.foodByBarcode(code), 'found_by': how});
        if (str('query').isNotEmpty) return ToolOutput(await api.foodSearch(str('query')));
        return const ToolOutput({'error': 'Give a barcode, a photo of one, scan true, or a product name in query.'});

      // ---- words and Wikipedia
      case 'define_word':
        return ToolOutput(await api.define(str('word'), language: str('language').isEmpty ? 'en' : str('language')));
      case 'translate_text':
        return ToolOutput(await api.translate(str('text'), to: str('to'), from: str('from')));
      case 'wikipedia_search':
        return ToolOutput(await api.wikiSearch(str('query'), language: str('language'), limit: integer('limit') ?? 8));
      case 'wikipedia_summary':
        return ToolOutput(await api.wikiSummary(str('title'), language: str('language')));
      case 'wikipedia_on_this_day':
        DateTime? date;
        final d = str('date');
        if (d.isNotEmpty) {
          date = DateTime.tryParse(d.length == 5 ? '${DateTime.now().year}-$d' : d);
          if (date == null) return const ToolOutput({'error': 'date is MM-DD or YYYY-MM-DD.'});
        }
        return ToolOutput(await api.onThisDay(date: date, type: str('type').isEmpty ? 'selected' : str('type'), language: str('language'), limit: integer('limit') ?? 12));

      // ---- sports
      case 'sports_scores':
        return ToolOutput(await sports.scores(str('league'), date: str('date'), team: str('team')));
      case 'sports_match':
        return ToolOutput(await sports.match(str('league'), str('event_id')));
      case 'sports_standings':
        return ToolOutput(await sports.standings(str('league')));
      case 'sports_team':
        return ToolOutput(await sports.team(str('league'), str('team')));
      case 'sports_player':
        return ToolOutput(await sports.player(str('name')));
      case 'sports_news':
        return ToolOutput(await sports.news(str('league'), limit: integer('limit') ?? 10));
      case 'sports_top_scorers':
        return ToolOutput(await sports.topScorers(str('competition'), limit: integer('limit') ?? 15));
      case 'formula1':
        return ToolOutput(await sports.f1(str('view').isEmpty ? 'next' : str('view'), season: str('season')));
    }
    return ToolOutput({'error': 'Unknown tool $name'});
  } on SportsException catch (e) {
    return ToolOutput({'error': e.message});
  } on InfoException catch (e) {
    return ToolOutput({'error': e.message});
  } on ScreenTimeAccessException catch (e) {
    return ToolOutput({'error': '$e', 'needs': 'usage_access'});
  } on DeviceException catch (e) {
    return ToolOutput({'error': e.message});
  }
}
