import '../telegram/data/telegram_tools.dart' show ToolOutput;
import 'screen_control.dart';

// Runs the tools in telegram_screen_tools.dart through the accessibility
// service. Errors come back as a sentence the assistant can pass on.

Future<ToolOutput> runScreenTool(String name, Map<String, dynamic> a) async {
  String str(String k) => '${a[k] ?? ''}'.trim();
  int? integer(String k) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(str(k));
  double? fraction(String k) {
    final v = a[k] is num ? (a[k] as num).toDouble() : double.tryParse(str(k));
    return v?.clamp(0.0, 1.0).toDouble();
  }

  bool flag(String k) => a[k] == true;

  try {
    switch (name) {
      case 'screen_status':
        final s = await ScreenControl.status();
        return ToolOutput({
          ...s,
          if (s['enabled'] != true)
            'how_to_turn_on': 'In Triangle: Settings → Screen control → Turn on, then switch on Triangle screen control in Android\'s Accessibility settings.',
        });
      case 'screen_read':
        final r = await ScreenControl.call('read', {
          'query': ?(str('query').isEmpty ? null : str('query')),
          'all': flag('all'),
          'limit': (integer('limit') ?? 250).clamp(20, 400),
        });
        return ToolOutput(r);
      case 'screen_screenshot':
        return ToolOutput(await ScreenControl.call('screenshot'));
      case 'screen_wait':
        final seconds = (a['seconds'] is num ? (a['seconds'] as num).toDouble() : 5.0).clamp(1.0, 20.0);
        return ToolOutput(await ScreenControl.call('wait', {
          'text': ?(str('text').isEmpty ? null : str('text')),
          'ms': (seconds * 1000).round(),
        }));
      case 'screen_tap':
        final x = fraction('x');
        final y = fraction('y');
        if (integer('element') == null && str('text').isEmpty && (x == null || y == null)) {
          return const ToolOutput({'error': 'Give element (from screen_read), text, or both x and y.'});
        }
        return ToolOutput(await ScreenControl.call('tap', {
          'id': ?integer('element'),
          'text': ?(str('text').isEmpty ? null : str('text')),
          'x': ?x,
          'y': ?y,
          'long': flag('long_press'),
        }));
      case 'screen_type':
        if (a['text'] == null) return const ToolOutput({'error': 'Give the text to type.'});
        return ToolOutput(await ScreenControl.call('type', {
          'id': ?integer('element'),
          'text': '${a['text']}',
          'replace': !flag('append'),
          'submit': flag('submit'),
        }));
      case 'screen_scroll':
        final direction = str('direction').isEmpty ? 'down' : str('direction');
        if (!const {'down', 'up', 'left', 'right'}.contains(direction)) {
          return const ToolOutput({'error': 'direction is down, up, left or right.'});
        }
        return ToolOutput(await ScreenControl.call('scroll', {'id': ?integer('element'), 'direction': direction}));
      case 'screen_swipe':
        final points = [fraction('from_x'), fraction('from_y'), fraction('to_x'), fraction('to_y')];
        if (points.contains(null)) return const ToolOutput({'error': 'Give from_x, from_y, to_x and to_y, each 0-1.'});
        return ToolOutput(await ScreenControl.call('swipe', {
          'x1': points[0],
          'y1': points[1],
          'x2': points[2],
          'y2': points[3],
          'ms': (integer('milliseconds') ?? 350).clamp(50, 3000),
        }));
      case 'screen_press':
        return ToolOutput(await ScreenControl.call('press', {'key': str('key')}));
    }
    return ToolOutput({'error': 'Unknown tool $name.'});
  } on ScreenControlError catch (e) {
    return ToolOutput({'error': e.message});
  }
}
