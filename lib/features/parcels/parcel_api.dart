import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Package tracking. 17TRACK (api.17track.net, a free key with a monthly
// quota) gives live events for thousands of carriers and postal services.
// Without a key, the carrier is guessed from the number's shape and the
// official tracking pages are linked. The packages being followed are kept
// on the phone with their last status.

class ParcelException implements Exception {
  const ParcelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A carrier guessed from a tracking number, with its tracking page.
class CarrierGuess {
  const CarrierGuess(this.name, this.url);
  final String name;
  final String url;
  Map<String, dynamic> toJson() => {'carrier': name, 'url': url};
}

/// Carriers [number] could belong to, likeliest first, plus 17TRACK's and
/// Parcels' pages, which search every carrier.
List<CarrierGuess> guessCarriers(String number) {
  final n = number.replaceAll(RegExp(r'\s'), '').toUpperCase();
  final e = Uri.encodeComponent(n);
  final out = <CarrierGuess>[];
  if (RegExp(r'^1Z[0-9A-Z]{16}$').hasMatch(n)) out.add(CarrierGuess('UPS', 'https://www.ups.com/track?tracknum=$e'));
  if (RegExp(r'^(94|93|92|95|82)\d{18,20}$').hasMatch(n) || RegExp(r'^[A-Z]{2}\d{9}US$').hasMatch(n)) {
    out.add(CarrierGuess('USPS', 'https://tools.usps.com/go/TrackConfirmAction?tLabels=$e'));
  }
  if (RegExp(r'^(\d{12}|\d{15}|\d{20}|\d{22})$').hasMatch(n)) out.add(CarrierGuess('FedEx', 'https://www.fedex.com/fedextrack/?trknbr=$e'));
  if (RegExp(r'^\d{10,11}$').hasMatch(n) || RegExp(r'^(JJD|JVGL)\d+$').hasMatch(n)) {
    out.add(CarrierGuess('DHL', 'https://www.dhl.com/global-en/home/tracking/tracking-express.html?tracking-id=$e'));
  }
  if (RegExp(r'^TBA\d{12}$').hasMatch(n)) out.add(const CarrierGuess('Amazon Logistics', 'https://www.amazon.com/progress-tracker/package'));
  if (RegExp(r'^[A-Z]{2}\d{9}[A-Z]{2}$').hasMatch(n)) {
    final country = n.substring(11);
    out.add(CarrierGuess(_posts[country] ?? 'Postal service ($country)', 'https://www.17track.net/en/track?nums=$e'));
  }
  if (RegExp(r'^(LP|CN|YT|UB|LX|SF)\w{8,}$').hasMatch(n)) out.add(CarrierGuess('Cainiao / AliExpress', 'https://global.cainiao.com/newDetail.htm?mailNoList=$e'));
  out.add(CarrierGuess('17TRACK (any carrier)', 'https://t.17track.net/en#nums=$e'));
  out.add(CarrierGuess('Parcels (any carrier)', 'https://parcelsapp.com/en/tracking/$e'));
  return out;
}

const _posts = {
  'ET': 'Ethiopian Postal Service',
  'US': 'USPS',
  'CN': 'China Post',
  'GB': 'Royal Mail',
  'DE': 'Deutsche Post',
  'FR': 'La Poste',
  'KE': 'Posta Kenya',
  'IN': 'India Post',
  'JP': 'Japan Post',
  'CA': 'Canada Post',
  'AU': 'Australia Post',
  'NL': 'PostNL',
  'SG': 'Singapore Post',
  'HK': 'Hongkong Post',
  'AE': 'Emirates Post',
  'TR': 'PTT (Turkey)',
};

/// 17TRACK's main statuses, in delivery order, with a plain label.
const parcelStages = ['InfoReceived', 'InTransit', 'OutForDelivery', 'Delivered'];

String parcelStatusLabel(String s) => switch (s) {
  'NotFound' => 'Not found yet',
  'InfoReceived' => 'Label created',
  'InTransit' => 'In transit',
  'Expired' => 'Tracking expired',
  'AvailableForPickup' => 'Ready for pickup',
  'OutForDelivery' => 'Out for delivery',
  'DeliveryFailure' => 'Delivery failed',
  'Delivered' => 'Delivered',
  'Exception' => 'Problem',
  'Pending' => 'Fetching…',
  '' => 'Unknown',
  _ => s,
};

class SeventeenTrack {
  SeventeenTrack(this.key, {http.Client? client}) : _http = client ?? http.Client();
  final String key;
  final http.Client _http;
  static const base = 'https://api.17track.net/track/v2.4';

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final res = await _http
        .post(Uri.parse('$base/$path'), headers: {'17token': key, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic>? j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode == 401 || res.statusCode == 403) throw const ParcelException('17TRACK refused the key.');
    if (res.statusCode == 429) throw const ParcelException('17TRACK is rate limiting; try again in a moment.');
    if (res.statusCode >= 300 || j == null) throw ParcelException('17TRACK: HTTP ${res.statusCode}');
    if (j['code'] != 0) throw ParcelException('17TRACK: ${(j['data'] as Map?)?['errors'] ?? j['code']}');
    return j;
  }

  /// Starts following [number] (17TRACK counts this against the quota once).
  Future<void> register(String number, {int? carrier}) async {
    final j = await _post('register', [
      {'number': number, 'carrier': ?carrier},
    ]);
    final rejected = ((j['data'] as Map?)?['rejected'] as List?) ?? const [];
    for (final r in rejected.whereType<Map>()) {
      final err = r['error'] as Map? ?? const {};
      // Already registered is fine.
      if ('${err['code']}' == '-18019901') continue;
      throw ParcelException('${err['message'] ?? 'Not accepted'}');
    }
  }

  /// The latest tracking for [number], or null while 17TRACK is still fetching it.
  Future<Map<String, dynamic>?> info(String number) async {
    final j = await _post('gettrackinfo', [
      {'number': number},
    ]);
    final accepted = ((j['data'] as Map?)?['accepted'] as List?) ?? const [];
    if (accepted.isEmpty) {
      final rejected = ((j['data'] as Map?)?['rejected'] as List?) ?? const [];
      final err = rejected.whereType<Map>().firstOrNull?['error'] as Map?;
      if (err != null && '${err['code']}' != '-18019909') throw ParcelException('${err['message'] ?? 'Not tracked'}');
      return null;
    }
    return Map<String, dynamic>.from(accepted.first as Map);
  }

  Future<void> stop(String number) => _post('stoptrack', [
    {'number': number},
  ]);

  void close() => _http.close();
}

/// 17TRACK's answer for one number, shaped for the card and the model.
Map<String, dynamic> parcelSummary(String number, Map<String, dynamic>? accepted) {
  if (accepted == null) {
    return {'number': number, 'status': 'Pending', 'status_label': parcelStatusLabel('Pending'), 'events': const [], 'note': 'Just registered: 17TRACK is fetching it. Check again in a minute.'};
  }
  final t = accepted['track_info'] as Map? ?? const {};
  final latest = t['latest_status'] as Map? ?? const {};
  final ship = t['shipping_info'] as Map? ?? const {};
  final metrics = t['time_metrics'] as Map? ?? const {};
  final eta = metrics['estimated_delivery_date'] as Map?;
  final providers = ((t['tracking'] as Map?)?['providers'] as List? ?? const []).whereType<Map>().toList();
  final events = <Map<String, dynamic>>[
    for (final p in providers)
      for (final e in (p['events'] as List? ?? const []).whereType<Map>())
        {
          'at': e['time_iso'] ?? e['time_utc'],
          'text': e['description'],
          'location': ?(('${e['location'] ?? ''}').trim().isEmpty ? null : e['location']),
          'stage': ?e['stage'],
          'carrier': ((p['provider'] as Map?)?['name']),
        },
  ]..sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
  final provider = providers.isEmpty ? null : providers.first['provider'] as Map?;
  final status = '${latest['status'] ?? 'NotFound'}';
  return {
    'number': number,
    'status': status,
    'status_label': parcelStatusLabel(status),
    'sub_status': ?latest['sub_status'],
    'carrier': ?provider?['name'],
    'carrier_url': ?provider?['homepage'],
    'from': ?((ship['shipper_address'] as Map?)?['country']),
    'to': ?((ship['recipient_address'] as Map?)?['country']),
    'days_in_transit': ?metrics['days_of_transit'],
    'eta': ?(eta == null ? null : (eta['to'] ?? eta['from'])),
    'latest': events.isEmpty ? null : events.first,
    'events': events,
  };
}

/// The packages being followed, on this phone.
class ParcelStore {
  static const _key = 'tracked_packages';

  static Future<List<Map<String, dynamic>>> all() async {
    final p = await SharedPreferences.getInstance();
    try {
      return [for (final x in jsonDecode(p.getString(_key) ?? '[]') as List) if (x is Map) Map<String, dynamic>.from(x)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list));
  }

  /// Adds or updates [number] with its latest [summary] and [label].
  static Future<Map<String, dynamic>> put(String number, {Map<String, dynamic>? summary, String? label}) async {
    final list = await all();
    final i = list.indexWhere((x) => x['number'] == number);
    final old = i < 0 ? <String, dynamic>{'number': number, 'added': DateTime.now().toIso8601String()} : list[i];
    final next = {
      ...old,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      if (summary != null) ...{
        'status': summary['status'],
        'status_label': summary['status_label'],
        'carrier': summary['carrier'] ?? old['carrier'],
        'latest': summary['latest'],
        'eta': summary['eta'],
        'checked': DateTime.now().toIso8601String(),
      },
    };
    if (i < 0) {
      list.insert(0, next);
    } else {
      list[i] = next;
    }
    await _save(list);
    return next;
  }

  static Future<bool> remove(String number) async {
    final list = await all();
    final before = list.length;
    list.removeWhere((x) => x['number'] == number);
    await _save(list);
    return list.length < before;
  }
}
