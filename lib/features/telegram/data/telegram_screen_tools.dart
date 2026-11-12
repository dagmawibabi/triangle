part of 'telegram_tools.dart';

// Screen control: reading and using other apps on the phone through
// Triangle's accessibility service. The chat controller runs these
// (features/screen/screen_tools.dart); the cards are in
// screen_result_cards.dart. Open an app first with open_app.

const _screenElement = {
  'type': 'integer',
  'description': 'The element\'s id from the latest screen_read (ids change with every read).',
};
const _screenWhy = {
  'type': 'string',
  'description': 'What this does, in a few words, shown on the approval card: "Send the message", "Open Settings".',
};
const _screenFraction = 'A fraction of the screen, 0 (left/top) to 1 (right/bottom).';

final _screenTools = <TelegramTool>[
  TelegramTool(
    name: 'screen_status',
    label: 'Checking screen control',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    description:
        'Whether screen control is on (Triangle under Android Settings → Accessibility), and which app is on the '
        'screen now. If it is off, tell the user how to turn it on: Settings → Screen control in Triangle.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'screen_read',
    label: 'Reading the screen',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    description:
        'What is on the phone\'s screen now, in any app: the app, and its elements (id, role like button/field/text/'
        'switch/list, text, label, hint, whether it is clickable, editable, scrollable, checked, focused, disabled, and '
        'bounds in pixels). Use the ids with screen_tap, screen_type and screen_scroll. Read again after anything '
        'changes the screen: ids only last until the next read. Passwords are never shown. Give query to list only '
        'elements whose text, label or hint contains it. To use an app: open_app, screen_read, then act, reading again '
        'to check each step worked. Triangle\'s own screens, Android\'s permission screens and the apps the user put off '
        'limits can\'t be read.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'Only elements whose text, label or hint contains this (any case).'},
      'all': {'type': 'boolean', 'description': 'Also list layout elements with no text and no action; default false.'},
      'limit': {'type': 'integer', 'description': 'At most this many elements, 20-400; default 250.'},
    }),
  ),
  TelegramTool(
    name: 'screen_screenshot',
    label: 'Taking a screenshot',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    description:
        'Takes a screenshot of the phone\'s screen (Android 11 or newer) and saves it on the phone. To look at it, '
        'call view_image with the returned image_path. Prefer screen_read, which is exact and cheaper; use this for '
        'pictures, maps, games or apps whose elements read as empty. Some apps (banking, private tabs) block it.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'screen_wait',
    label: 'Waiting for the screen',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    description:
        'Waits until text appears on the screen, or (without text) until the screen changes: after opening an app, '
        'sending something or loading a page. Then read the screen.',
    parameters: _obj({
      'text': {'type': 'string', 'description': 'Wait until something on the screen says this.'},
      'seconds': {'type': 'number', 'description': 'Give up after this long, 1-20; default 5.'},
    }),
  ),
  TelegramTool(
    name: 'screen_tap',
    label: 'Tapping on the screen',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Taps an element in the app on screen: by id from screen_read (best), by its visible text, or at a point (x, '
        'y as fractions of the screen) when nothing else works. long_press for a long press. Returns which app is on '
        'screen after and whether it changed; read the screen again to see the result.',
    parameters: _obj({
      'element': _screenElement,
      'text': {'type': 'string', 'description': 'Tap the first visible element showing this text, when there is no id.'},
      'x': {'type': 'number', 'description': '$_screenFraction For a tap by position.'},
      'y': {'type': 'number', 'description': '$_screenFraction For a tap by position.'},
      'long_press': {'type': 'boolean', 'description': 'A long press instead of a tap.'},
      'why': _screenWhy,
    }, ['why']),
  ),
  TelegramTool(
    name: 'screen_type',
    label: 'Typing on the screen',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Types text into a text field of the app on screen: the field\'s id from screen_read, or the field that has '
        'focus. Replaces what is there unless append is true. submit presses the keyboard\'s action key (search, send, '
        'go) after, on Android 11 or newer. Never for passwords: those fields refuse, and the user types them.',
    parameters: _obj({
      'text': {'type': 'string', 'description': 'What to type.'},
      'element': _screenElement,
      'append': {'type': 'boolean', 'description': 'Add to what the field holds instead of replacing it.'},
      'submit': {'type': 'boolean', 'description': 'Press the keyboard\'s action key after typing.'},
      'why': _screenWhy,
    }, ['text', 'why']),
  ),
  TelegramTool(
    name: 'screen_scroll',
    label: 'Scrolling the screen',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    description:
        'Scrolls a list or page in the app on screen: down shows what is below, up what is above, left and right for '
        'carousels and tabs. Scrolls the given element, or the largest scrollable area. Read the screen after.',
    parameters: _obj({
      'direction': {'type': 'string', 'enum': ['down', 'up', 'left', 'right'], 'description': 'Which way the content moves into view; default down.'},
      'element': _screenElement,
    }),
  ),
  TelegramTool(
    name: 'screen_swipe',
    label: 'Swiping on the screen',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Swipes from one point to another (fractions of the screen): to dismiss, reveal swipe actions, move a slider or '
        'turn pages when screen_scroll doesn\'t. Swipes can delete or archive in some apps, so say what it does in why.',
    parameters: _obj({
      'from_x': {'type': 'number', 'description': 'Start. $_screenFraction'},
      'from_y': {'type': 'number', 'description': 'Start. $_screenFraction'},
      'to_x': {'type': 'number', 'description': 'End. $_screenFraction'},
      'to_y': {'type': 'number', 'description': 'End. $_screenFraction'},
      'milliseconds': {'type': 'integer', 'description': 'How long the swipe takes, 50-3000; default 350. Slower drags precisely.'},
      'why': _screenWhy,
    }, ['from_x', 'from_y', 'to_x', 'to_y', 'why']),
  ),
  TelegramTool(
    name: 'screen_press',
    label: 'Pressing a phone button',
    category: ToolCategory.screen,
    cost: ToolCost.device,
    description:
        'Presses a system button: back, home, recents (the app switcher), notifications (pulls down the shade), '
        'quick_settings, or lock (locks the screen).',
    parameters: _obj({
      'key': {'type': 'string', 'enum': ['back', 'home', 'recents', 'notifications', 'quick_settings', 'lock'], 'description': 'The button to press.'},
    }, ['key']),
  ),
];

final screenToolNames = {for (final t in _screenTools) t.name};

const _screenPolicies = <String, ToolPolicy>{
  'screen_status': ToolPolicy(ToolAccess.read),
  'screen_read': ToolPolicy(ToolAccess.read),
  'screen_screenshot': ToolPolicy(ToolAccess.read),
  'screen_wait': ToolPolicy(ToolAccess.read),
  'screen_tap': ToolPolicy(ToolAccess.modify),
  'screen_type': ToolPolicy(ToolAccess.modify),
  'screen_scroll': ToolPolicy(ToolAccess.modify),
  'screen_swipe': ToolPolicy(ToolAccess.modify),
  'screen_press': ToolPolicy(ToolAccess.modify),
};

const _screenAfter = ['app_now', 'package_now', 'screen_changed'];

const _screenReferences = <String, ToolReference>{
  'screen_status': ToolReference(['enabled', 'running', 'package', 'app', 'screenshots']),
  'screen_read': ToolReference(
    ['package', 'app', 'screen', 'width', 'height', 'count', 'truncated', 'password_fields', 'elements: id, role, text, label, hint, view, clickable, editable, scrollable, checked, focused, disabled, password, bounds'],
    limits: ['limit: 20-400.'],
  ),
  'screen_screenshot': ToolReference(['image_path', 'width', 'height', 'app']),
  'screen_wait': ToolReference(['found', 'waited_ms', 'app'], limits: ['seconds: 1-20.']),
  'screen_tap': ToolReference(['tapped', 'long', 'by', ..._screenAfter]),
  'screen_type': ToolReference(['typed', 'into', 'replaced', 'submitted', ..._screenAfter]),
  'screen_scroll': ToolReference(['scrolled', 'by', ..._screenAfter]),
  'screen_swipe': ToolReference(['swiped', ..._screenAfter], limits: ['milliseconds: 50-3000.']),
  'screen_press': ToolReference(['pressed', ..._screenAfter]),
};
