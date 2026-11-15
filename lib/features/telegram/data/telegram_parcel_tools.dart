part of 'telegram_tools.dart';

// Package tracking: any carrier's tracking number. With a free 17TRACK key
// (Settings → More apps → Packages) the latest status and every scan, kept
// on a list the user can come back to; without one, the likely carrier and
// its official tracking page.

final _parcelTools = <TelegramTool>[
  TelegramTool(
    name: 'track_package',
    label: 'Tracking a package',
    category: ToolCategory.parcels,
    cost: ToolCost.web,
    description:
        'Tracks a parcel by its tracking number, for any carrier (UPS, FedEx, DHL, USPS, postal services like Ethiopian Post, '
        'China Post/AliExpress, Amazon…): status, latest scan, every event with place and time, estimated delivery. Also '
        'keeps it on the user\'s tracked list. Without a 17TRACK key it names the likely carrier and gives tracking links. '
        'Shown as a card that opens the full timeline.',
    parameters: _obj({
      'number': {'type': 'string', 'description': 'The tracking number, e.g. 1Z999AA10123456784 or RR123456785ET.'},
      'label': {'type': 'string', 'description': 'A name for it on the list, e.g. "New phone".'},
      'carrier': {'type': 'integer', 'description': '17TRACK carrier code when auto-detection picks the wrong one.'},
    }, ['number']),
  ),
  TelegramTool(
    name: 'tracked_packages',
    label: 'Checking your packages',
    category: ToolCategory.parcels,
    cost: ToolCost.web,
    description: 'The packages the user is following with their last status; refresh checks each one again (uses 17TRACK).',
    parameters: _obj({
      'refresh': {'type': 'boolean', 'description': 'Check every package again now. Default false (last known status).'},
    }),
  ),
  TelegramTool(
    name: 'untrack_package',
    label: 'Stop tracking a package',
    category: ToolCategory.parcels,
    cost: ToolCost.web,
    requiresApproval: true,
    description: 'Removes a package from the tracked list and stops 17TRACK following it.',
    parameters: _obj({
      'number': {'type': 'string', 'description': 'The tracking number to stop following.'},
    }, ['number']),
  ),
];

final _parcelToolNames = {for (final t in _parcelTools) t.name};

const _parcelPolicies = <String, ToolPolicy>{
  'track_package': ToolPolicy(ToolAccess.read),
  'tracked_packages': ToolPolicy(ToolAccess.read),
  'untrack_package': ToolPolicy(ToolAccess.modify),
};

const _parcelReferences = <String, ToolReference>{
  'track_package': ToolReference(
    ['parcel: number, status, status_label, carrier, latest, events, eta, days_in_transit, from, to', 'links', 'live'],
    limits: ['17TRACK\'s free plan has a monthly quota; each new number uses one. New numbers can take a minute to show events.'],
  ),
  'tracked_packages': ToolReference(['packages: number, label, status, carrier, latest, eta, checked']),
  'untrack_package': ToolReference(['removed']),
};

extension _ParcelToolRuns on TelegramToolRunner {
  Future<ToolOutput>? _runParcels(String name, Map<String, dynamic> a) {
    if (!_parcelToolNames.contains(name)) return null;
    return _parcels(name, a);
  }

  Future<ToolOutput> _parcels(String name, Map<String, dynamic> a) async {
    // The saved key as it is now; load() only reads storage the first time.
    await InfoKeysNotifier.load();
    final keys = InfoKeysNotifier.current;
    final api = keys.hasTrackKey ? SeventeenTrack(keys.trackKey) : null;
    try {
      switch (name) {
        case 'track_package':
          final number = '${a['number'] ?? ''}'.replaceAll(RegExp(r'\s'), '').toUpperCase();
          if (number.length < 6) return const ToolOutput({'error': 'Give the full tracking number.'});
          final links = [for (final g in guessCarriers(number)) g.toJson()];
          if (api == null) {
            await ParcelStore.put(number, label: a['label'] as String?);
            return ToolOutput({
              'parcel': {'number': number, 'status': '', 'status_label': 'Not checked', 'carrier': links.first['carrier'], 'events': const []},
              'links': links,
              'live': false,
              'note': 'No 17TRACK key, so only the likely carrier and tracking pages. Add a free key in Settings → More apps → Packages for live status.',
            });
          }
          await api.register(number, carrier: a['carrier'] is num ? (a['carrier'] as num).toInt() : null);
          var info = await api.info(number);
          // A new number takes a moment to fetch.
          if (info == null) {
            await Future<void>.delayed(const Duration(seconds: 3));
            info = await api.info(number);
          }
          final summary = parcelSummary(number, info);
          final saved = await ParcelStore.put(number, summary: summary, label: a['label'] as String?);
          return ToolOutput({
            'parcel': {...summary, 'label': ?saved['label'], 'events': [for (final e in (summary['events'] as List).take(60)) e]},
            'links': links,
            'live': true,
          });
        case 'tracked_packages':
          var list = await ParcelStore.all();
          if (a['refresh'] == true && api != null) {
            for (final p in list.take(25)) {
              try {
                final s = parcelSummary('${p['number']}', await api.info('${p['number']}'));
                await ParcelStore.put('${p['number']}', summary: s);
              } catch (_) {}
            }
            list = await ParcelStore.all();
          }
          return ToolOutput({'packages': list, 'live': api != null, if (list.isEmpty) 'note': 'No packages yet. Track one with its number.'});
        case 'untrack_package':
          final number = '${a['number'] ?? ''}'.replaceAll(RegExp(r'\s'), '').toUpperCase();
          final removed = await ParcelStore.remove(number);
          if (api != null) {
            try {
              await api.stop(number);
            } catch (_) {}
          }
          return ToolOutput({'removed': removed ? number : null, if (!removed) 'note': '$number wasn\'t on the list.'});
      }
    } on ParcelException catch (e) {
      return ToolOutput({'error': e.message});
    } on TimeoutException {
      return const ToolOutput({'error': '17TRACK didn\'t answer in time.'});
    } on SocketException catch (e) {
      return ToolOutput({'error': 'Couldn\'t reach 17TRACK: ${e.message}'});
    } finally {
      api?.close();
    }
    return ToolOutput({'error': 'Unknown tool $name'});
  }

  String? _describeParcels(String name, Map<String, dynamic> a) => name == 'untrack_package' ? 'Stop tracking ${a['number']}' : null;
}
