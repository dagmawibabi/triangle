part of 'telegram_tools.dart';

// The phone itself (Android, through DeviceChannel.kt): its specs, battery
// and network, installed apps, text messages, call log and contacts, and
// actions such as calling, texting, the flashlight, volume, alarms, timers,
// media keys and opening apps or settings. Listed under "Device" in
// Settings → Tools. Android permissions are asked for the first time a
// tool needs one.

final _deviceTools = <TelegramTool>[
  // ---- reading ---------------------------------------------------------------
  TelegramTool(
    name: 'device_info',
    label: 'Checking the phone',
    category: ToolCategory.device,
    cost: ToolCost.device,
    description: 'The phone\'s specs and state: maker and model, chip, Android version and security patch, CPU cores, RAM and storage (total and free), screen, uptime and battery.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'device_battery',
    label: 'Checking the battery',
    category: ToolCategory.device,
    cost: ToolCost.device,
    description: 'Battery level, charging and how (charger, USB, wireless), temperature, health and battery saver.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'network_info',
    label: 'Checking the network',
    category: ToolCategory.device,
    cost: ToolCost.device,
    description:
        'The phone\'s connection: Wi-Fi or mobile data, whether the internet works, VPN, metered, speeds, IP addresses, DNS, '
        'carrier and roaming; for Wi-Fi the signal, band, link speed and network name (the name needs location permission).',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'installed_apps',
    label: 'Listing installed apps',
    category: ToolCategory.device,
    cost: ToolCost.device,
    description: 'Apps installed on the phone with version and install/update dates. query filters by name; include_system adds system apps.',
    parameters: _obj({
      'query': {'type': 'string'},
      'include_system': {'type': 'boolean'},
      'limit': {'type': 'integer', 'description': 'Default 60.'},
    }),
  ),
  TelegramTool(
    name: 'read_sms',
    label: 'Reading text messages',
    category: ToolCategory.device,
    cost: ToolCost.device,
    description:
        'Reads the phone\'s SMS, newest first: inbox (default), sent or all. Filter by sender (from: number or part of it), text '
        '(query), since_hours or unread_only. Use for verification codes, bank or delivery texts, or messages from someone. Does not mark anything read.',
    parameters: _obj({
      'box': {'type': 'string', 'enum': ['inbox', 'sent', 'all']},
      'from': {'type': 'string', 'description': 'Phone number or sender name like "MPESA".'},
      'query': {'type': 'string'},
      'since_hours': {'type': 'number'},
      'unread_only': {'type': 'boolean'},
      'limit': {'type': 'integer', 'description': '1-200, default 30.'},
    }),
  ),
  TelegramTool(
    name: 'phone_contacts',
    label: 'Looking up phone contacts',
    category: ToolCategory.device,
    cost: ToolCost.device,
    description: 'Searches the phone\'s contacts (not Telegram\'s) by name or number, with their numbers. Use it to find who to call or text.',
    parameters: _obj({
      'query': {'type': 'string'},
      'limit': {'type': 'integer'},
    }),
  ),
  TelegramTool(
    name: 'read_clipboard',
    label: 'Reading the clipboard',
    category: ToolCategory.device,
    cost: ToolCost.device,
    description: 'The text currently copied on the phone.',
    parameters: _obj({}),
  ),

  // ---- actions (ask first) -------------------------------------------------------
  TelegramTool(
    name: 'make_call',
    label: 'Calling',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Places a phone call (a regular call, not Telegram). Find the number with phone_contacts when given a name. With dialer_only '
        'the dialer opens with the number instead. The user approves first.',
    parameters: _obj({
      'number': {'type': 'string'},
      'name': {'type': 'string', 'description': 'Who it is, for the approval card.'},
      'dialer_only': {'type': 'boolean'},
    }, ['number']),
  ),
  TelegramTool(
    name: 'send_sms',
    label: 'Sending a text message',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    alwaysAsk: true,
    description: 'Sends an SMS from the phone. The carrier may charge for it, so it always waits for the user\'s approval.',
    parameters: _obj({
      'to': {'type': 'string', 'description': 'Phone number.'},
      'name': {'type': 'string', 'description': 'Who it is, for the approval card.'},
      'text': {'type': 'string'},
    }, ['to', 'text']),
  ),
  TelegramTool(
    name: 'flashlight',
    label: 'Switching the flashlight',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Turns the flashlight (torch) on or off; toggles when on is left out.',
    parameters: _obj({
      'on': {'type': 'boolean'},
    }),
  ),
  TelegramTool(
    name: 'vibrate',
    label: 'Vibrating',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Vibrates the phone for a moment, e.g. to find it or as a signal.',
    parameters: _obj({
      'ms': {'type': 'integer', 'description': '10-5000, default 400.'},
    }),
  ),
  TelegramTool(
    name: 'device_volume',
    label: 'Volume',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Reads the volume of media, ring, alarm, notification and call sounds, and the ringer mode. With percent, mute or unmute it '
        'changes one stream (default media); only that asks first.',
    parameters: _obj({
      'stream': {'type': 'string', 'enum': ['media', 'ring', 'alarm', 'notification', 'call']},
      'percent': {'type': 'integer', 'description': '0-100.'},
      'mute': {'type': 'boolean'},
      'unmute': {'type': 'boolean'},
    }),
  ),
  TelegramTool(
    name: 'ringer_mode',
    label: 'Changing the ringer',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Sets the ringer to normal, vibrate or silent. Silent may need Do Not Disturb access, which Android asks for.',
    parameters: _obj({
      'mode': {'type': 'string', 'enum': ['normal', 'vibrate', 'silent']},
    }, ['mode']),
  ),
  TelegramTool(
    name: 'media_control',
    label: 'Controlling playback',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Presses a media key for whatever is playing on the phone (Spotify, YouTube Music, podcasts…): play, pause, toggle, next, previous or stop.',
    parameters: _obj({
      'action': {'type': 'string', 'enum': ['toggle', 'play', 'pause', 'next', 'previous', 'stop']},
    }, ['action']),
  ),
  TelegramTool(
    name: 'set_alarm',
    label: 'Setting an alarm',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Sets an alarm in the phone\'s Clock app (rings even on silent, unlike create_reminder). days repeats it: 1 Sunday … 7 Saturday.',
    parameters: _obj({
      'hour': {'type': 'integer', 'description': '0-23.'},
      'minute': {'type': 'integer'},
      'label': {'type': 'string'},
      'days': {'type': 'array', 'items': {'type': 'integer'}},
    }, ['hour', 'minute']),
  ),
  TelegramTool(
    name: 'set_timer',
    label: 'Starting a timer',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Starts a countdown timer in the phone\'s Clock app.',
    parameters: _obj({
      'seconds': {'type': 'integer'},
      'label': {'type': 'string'},
    }, ['seconds']),
  ),
  TelegramTool(
    name: 'open_app',
    label: 'Opening an app',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Opens an installed app by its package (from installed_apps), e.g. com.spotify.music.',
    parameters: _obj({
      'package': {'type': 'string'},
      'name': {'type': 'string', 'description': 'The app\'s name, for the approval card.'},
    }, ['package']),
  ),
  TelegramTool(
    name: 'open_device_settings',
    label: 'Opening settings',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Opens a page of Android\'s Settings so the user can change it: Wi-Fi, Bluetooth, mobile data, hotspot, airplane mode, location, battery, display, sound, Do Not Disturb, storage, apps, NFC.',
    parameters: _obj({
      'page': {
        'type': 'string',
        'enum': ['main', 'wifi', 'bluetooth', 'mobile_data', 'hotspot', 'airplane', 'location', 'battery', 'display', 'sound', 'dnd', 'storage', 'apps', 'nfc'],
      },
    }, ['page']),
  ),
  TelegramTool(
    name: 'write_clipboard',
    label: 'Copying to the clipboard',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Copies text to the phone\'s clipboard, replacing what is there.',
    parameters: _obj({
      'text': {'type': 'string'},
    }, ['text']),
  ),
  TelegramTool(
    name: 'keep_screen_on',
    label: 'Keeping the screen on',
    category: ToolCategory.device,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Keeps the screen from turning off while Triangle is open (e.g. while reading a recipe), or lets it sleep again.',
    parameters: _obj({
      'on': {'type': 'boolean'},
    }, ['on']),
  ),
];

final _deviceToolNames = {for (final t in _deviceTools) t.name};

/// Device tools are offered on Android only.
bool deviceToolReady(TelegramTool t) => !_deviceToolNames.contains(t.name) || Device.supported;

/// Whether a device tool call needs approval: reading the volume doesn't.
bool deviceCallNeedsApproval(String name, Map<String, dynamic> args) =>
    name != 'device_volume' || args['percent'] != null || args['mute'] == true || args['unmute'] == true;

extension _DeviceToolRuns on TelegramToolRunner {
  Future<ToolOutput>? _runDevice(String name, Map<String, dynamic> args) {
    if (!_deviceToolNames.contains(name)) return null;
    return _device(name, args);
  }

  static int? _num(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  static String? _date(Object? ms) => ms is num && ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toIso8601String().substring(0, 16) : null;

  Future<ToolOutput> _device(String name, Map<String, dynamic> a) async {
    final out = <String, dynamic>{'device': name};
    try {
      switch (name) {
        case 'device_info':
          out.addAll(Device.map(await Device.call<Map>('deviceInfo')));
        case 'device_battery':
          out.addAll(Device.map(await Device.call<Map>('battery')));
        case 'network_info':
          out.addAll(Device.map(await Device.call<Map>('network')));
        case 'installed_apps':
          final apps = Device.list(await Device.call<List>('apps', {'system': a['include_system'] == true, 'query': a['query']}));
          final limit = TelegramToolRunner._int(a, 'limit', fallback: 60, max: 400);
          out['total'] = apps.length;
          out['apps'] = [
            for (final app in apps.take(limit))
              {...app, 'installed': _date(app['installed']), 'updated': _date(app['updated'])},
          ];
        case 'read_sms':
          final since = TelegramToolRunner._hours(a, 'since_hours');
          final msgs = Device.list(await Device.call<List>('sms', {
            'box': '${a['box'] ?? 'inbox'}',
            'address': a['from'],
            'query': a['query'],
            if (since != null) 'since': DateTime.now().subtract(Duration(minutes: (since * 60).round())).millisecondsSinceEpoch,
            'unread_only': a['unread_only'] == true,
            'limit': TelegramToolRunner._int(a, 'limit', fallback: 30, max: 200),
          }));
          out['messages'] = [
            for (final m in msgs) {...m, 'date': _date(m['date']), 'body': TelegramToolRunner._clip('${m['body'] ?? ''}', 2000)},
          ];
        case 'call_log':
          final calls = Device.list(await Device.call<List>('callLog', {
            if ('${a['type'] ?? 'all'}' != 'all') 'type': a['type'],
            'limit': TelegramToolRunner._int(a, 'limit', fallback: 30, max: 200),
          }));
          out['calls'] = [for (final c in calls) {...c, 'date': _date(c['date'])}];
        case 'phone_contacts':
          out['contacts'] = Device.list(await Device.call<List>('contacts', {
            'query': '${a['query'] ?? ''}',
            'limit': TelegramToolRunner._int(a, 'limit', fallback: 30, max: 300),
          }));
        case 'read_clipboard':
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          out['text'] = data?.text ?? '';
        case 'make_call':
          final number = '${a['number'] ?? ''}'.trim();
          if (number.isEmpty) return const ToolOutput({'error': 'number is required'});
          if (a['dialer_only'] != true && (await Device.status([Device.phone.id]))[Device.phone.id] != true) {
            await Device.request([Device.phone.id]);
          }
          out.addAll(Device.map(await Device.call<Map>('call', {'number': number, 'direct': a['dialer_only'] != true})));
          out['number'] = number;
          if (a['name'] != null) out['name'] = a['name'];
        case 'send_sms':
          out.addAll(Device.map(await Device.call<Map>('sendSms', {'to': '${a['to']}', 'text': '${a['text'] ?? ''}'})));
          out['to'] = a['to'];
        case 'flashlight':
          out.addAll(Device.map(await Device.call<Map>('flashlight', {if (a['on'] is bool) 'on': a['on']})));
        case 'vibrate':
          out.addAll(Device.map(await Device.call<Map>('vibrate', {'ms': _num(a['ms']) ?? 400})));
        case 'device_volume':
          out.addAll(Device.map(await Device.call<Map>('volume', {
            'stream': '${a['stream'] ?? 'media'}',
            if (_num(a['percent']) != null) 'percent': _num(a['percent']),
            if (a['mute'] == true) 'mute': true,
            if (a['unmute'] == true) 'unmute': true,
          })));
        case 'ringer_mode':
          out.addAll(Device.map(await Device.call<Map>('ringer', {'mode': '${a['mode']}'})));
        case 'media_control':
          out.addAll(Device.map(await Device.call<Map>('media', {'action': '${a['action'] ?? 'toggle'}'})));
        case 'set_alarm':
          await Device.call<Map>('alarm', {
            'hour': (_num(a['hour']) ?? 7).clamp(0, 23),
            'minute': (_num(a['minute']) ?? 0).clamp(0, 59),
            if (a['label'] != null) 'label': '${a['label']}',
            'days': [for (final d in (a['days'] as List? ?? const [])) ?_num(d)],
          });
          out['set'] = '${_num(a['hour'])}:${'${_num(a['minute']) ?? 0}'.padLeft(2, '0')}';
        case 'set_timer':
          await Device.call<Map>('timer', {'seconds': _num(a['seconds']) ?? 60, if (a['label'] != null) 'label': '${a['label']}'});
          out['seconds'] = _num(a['seconds']);
        case 'open_app':
          await Device.call<bool>('openApp', {'package': '${a['package']}'});
          out['opened'] = a['package'];
        case 'open_device_settings':
          await Device.call<bool>('openSettings', {'page': '${a['page']}'});
          out['opened'] = a['page'];
        case 'write_clipboard':
          await Clipboard.setData(ClipboardData(text: '${a['text'] ?? ''}'));
          out['copied'] = true;
        case 'keep_screen_on':
          out.addAll(Device.map(await Device.call<Map>('keepScreenOn', {'on': a['on'] != false})));
      }
      return ToolOutput(out);
    } on DeviceException catch (e) {
      return ToolOutput({'error': e.message});
    }
  }

  /// What a device action would do, for the approval card.
  String? _describeDevice(String name, Map<String, dynamic> a) {
    if (!_deviceToolNames.contains(name)) return null;
    String v(String k) => '${a[k] ?? ''}'.trim();
    String who(String k) => v('name').isEmpty ? v(k) : '${v('name')} (${v(k)})';
    return switch (name) {
      'make_call' => a['dialer_only'] == true ? 'Open the dialer with ${who('number')}' : 'Call ${who('number')}',
      'send_sms' => 'Text ${who('to')}\n“${v('text')}”',
      'flashlight' => a['on'] == null ? 'Toggle the flashlight' : 'Turn the flashlight ${a['on'] == true ? 'on' : 'off'}',
      'vibrate' => 'Vibrate for ${_num(a['ms']) ?? 400} ms',
      'device_volume' => a['percent'] != null
          ? 'Set ${v('stream').isEmpty ? 'media' : v('stream')} volume to ${a['percent']}%'
          : '${a['mute'] == true ? 'Mute' : 'Unmute'} ${v('stream').isEmpty ? 'media' : v('stream')}',
      'ringer_mode' => 'Set the ringer to ${v('mode')}',
      'media_control' => 'Media: ${v('action')}',
      'set_alarm' => 'Set an alarm for ${v('hour')}:${v('minute').padLeft(2, '0')}${v('label').isEmpty ? '' : ' “${v('label')}”'}',
      'set_timer' => 'Start a ${formatDuration(_num(a['seconds']) ?? 60)} timer${v('label').isEmpty ? '' : ' “${v('label')}”'}',
      'open_app' => 'Open ${v('name').isEmpty ? v('package') : v('name')}',
      'open_device_settings' => 'Open ${v('page')} settings',
      'write_clipboard' => 'Copy to the clipboard:\n“${TelegramToolRunner._clip(v('text'), 300)}”',
      'keep_screen_on' => a['on'] == false ? 'Let the screen sleep again' : 'Keep the screen on',
      _ => null,
    };
  }
}
