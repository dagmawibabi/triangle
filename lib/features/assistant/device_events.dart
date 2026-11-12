import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:http/http.dart' as http;

import '../device/device.dart';
import '../device/net.dart';
import '../finance/finance_store.dart' show financeStoreProvider;
import '../finance/parser_config.dart' show ParserConfig;
import '../settings/data/settings.dart' show settingsProvider;
import '../finance/sms_parser.dart' show parseBankSms;
import '../web/web_fetch.dart' show ReadablePage;
import '../youtube/youtube_api.dart';

/// Something on the phone a watch or routine can start on.
enum DeviceTriggerKind {
  batteryLow('Battery low', 'When the battery falls to a level, while not charging'),
  charging('Plugged in', 'When the phone starts charging'),
  unplugged('Unplugged', 'When the phone stops charging'),
  wifiConnected('Wi-Fi connects', 'When the phone joins Wi-Fi (any, or one network)'),
  wifiDisconnected('Wi-Fi disconnects', 'When the phone leaves Wi-Fi (any, or one network)'),
  arrive('Arrive somewhere', 'When you get to a place'),
  leave('Leave somewhere', 'When you leave a place'),
  missedCall('Missed call', 'When you miss a call (from anyone, or matching a name or number)'),
  newSms('New text message', 'When an SMS arrives (any, or matching a sender or words)'),
  appOpened('I open Triangle', 'When you open the app'),
  notification('New notification', 'When another app shows a notification (any app or one, any text or matching words)'),
  moneyIn('Money received', 'When a bank or wallet SMS says money came in (over an amount, from someone)'),
  moneyOut('Money spent', 'When a bank or wallet SMS says money went out (over an amount, to someone)'),
  pageChanged('Web page changes', 'When a web page changes, or when words appear on it ("in stock")'),
  offline('Internet lost', 'When the phone loses its internet connection'),
  online('Internet back', 'When the internet works again after being down'),
  mobileData('Mobile data used', "When today's mobile data passes an amount"),
  storageLow('Storage low', 'When free storage falls below an amount'),
  youtubeUpload('New YouTube video', 'When a YouTube channel uploads (needs the YouTube key)');

  const DeviceTriggerKind(this.label, this.explanation);
  final String label;
  final String explanation;

  bool get needsPlace => this == arrive || this == leave;
  bool get usesSsid => this == wifiConnected || this == wifiDisconnected;
  bool get usesQuery => this == missedCall || this == newSms || this == notification || this == moneyIn || this == moneyOut || this == pageChanged || this == youtubeUpload;
  bool get usesAmount => this == moneyIn || this == moneyOut || this == mobileData || this == storageLow;
  bool get usesUrl => this == pageChanged;
  bool get usesApp => this == notification;

  /// Checked on their own schedule (pages, YouTube), not every poll.
  bool get interval => this == pageChanged || this == youtubeUpload;
}

/// When a phone trigger fires: its kind and what it is about.
@immutable
class DeviceCondition {
  const DeviceCondition({
    required this.kind,
    this.threshold = 20,
    this.ssid = '',
    this.lat,
    this.lng,
    this.radius = 150,
    this.placeName = '',
    this.query = '',
    this.cooldownMinutes = 30,
    this.amount = 0,
    this.url = '',
    this.app = '',
  });

  /// Money for money in/out, megabytes for mobile data, gigabytes free for
  /// storage.
  final double amount;

  /// The page a page-change trigger watches.
  final String url;

  /// The app (name or package) a notification trigger listens to.
  final String app;

  final DeviceTriggerKind kind;

  /// Battery percentage for [DeviceTriggerKind.batteryLow].
  final int threshold;

  /// A Wi-Fi network's name; empty for any network.
  final String ssid;

  /// A place, for arrive and leave.
  final double? lat;
  final double? lng;
  final int radius;
  final String placeName;

  /// For calls and texts: a name, number or words to match; empty for any.
  final String query;

  /// For [DeviceTriggerKind.appOpened]: at most once in this many minutes.
  final int cooldownMinutes;

  bool get hasPlace => lat != null && lng != null;

  DeviceCondition copyWith({
    DeviceTriggerKind? kind,
    int? threshold,
    String? ssid,
    double? lat,
    double? lng,
    int? radius,
    String? placeName,
    String? query,
    int? cooldownMinutes,
    double? amount,
    String? url,
    String? app,
  }) => DeviceCondition(
    kind: kind ?? this.kind,
    threshold: threshold ?? this.threshold,
    ssid: ssid ?? this.ssid,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    radius: radius ?? this.radius,
    placeName: placeName ?? this.placeName,
    query: query ?? this.query,
    cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
    amount: amount ?? this.amount,
    url: url ?? this.url,
    app: app ?? this.app,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (kind == DeviceTriggerKind.batteryLow) 'threshold': threshold,
    if (ssid.isNotEmpty) 'ssid': ssid,
    'lat': ?lat,
    'lng': ?lng,
    if (kind.needsPlace) 'radius': radius,
    if (placeName.isNotEmpty) 'place': placeName,
    if (query.isNotEmpty) 'query': query,
    if (kind == DeviceTriggerKind.appOpened || kind.interval) 'cooldown_minutes': cooldownMinutes,
    if (kind.usesAmount && amount > 0) 'amount': amount,
    if (url.isNotEmpty) 'url': url,
    if (app.isNotEmpty) 'app': app,
  };

  static DeviceCondition? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = DeviceTriggerKind.values.asNameMap()['${j['kind']}'];
    if (kind == null) return null;
    return DeviceCondition(
      kind: kind,
      threshold: (j['threshold'] as num?)?.toInt().clamp(1, 99) ?? 20,
      ssid: '${j['ssid'] ?? ''}',
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      radius: (j['radius'] as num?)?.toInt().clamp(50, 50000) ?? 150,
      placeName: '${j['place'] ?? ''}',
      query: '${j['query'] ?? ''}',
      cooldownMinutes: (j['cooldown_minutes'] as num?)?.toInt().clamp(0, 24 * 60) ?? (kind.interval ? 60 : 30),
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      url: '${j['url'] ?? ''}',
      app: '${j['app'] ?? ''}',
    );
  }

  /// "Battery at 20% or less", "Arrive at Home".
  String describe() => switch (kind) {
    DeviceTriggerKind.batteryLow => 'Battery at $threshold% or less',
    DeviceTriggerKind.charging => 'Plugged in',
    DeviceTriggerKind.unplugged => 'Unplugged',
    DeviceTriggerKind.wifiConnected => ssid.isEmpty ? 'Joins any Wi-Fi' : 'Joins Wi-Fi "$ssid"',
    DeviceTriggerKind.wifiDisconnected => ssid.isEmpty ? 'Leaves Wi-Fi' : 'Leaves Wi-Fi "$ssid"',
    DeviceTriggerKind.arrive => 'Arrive at ${placeName.isEmpty ? 'a place' : placeName}',
    DeviceTriggerKind.leave => 'Leave ${placeName.isEmpty ? 'a place' : placeName}',
    DeviceTriggerKind.missedCall => query.isEmpty ? 'Missed call' : 'Missed call from "$query"',
    DeviceTriggerKind.newSms => query.isEmpty ? 'New text message' : 'Text matching "$query"',
    DeviceTriggerKind.appOpened => cooldownMinutes > 0 ? 'I open Triangle (at most every $cooldownMinutes min)' : 'I open Triangle',
    DeviceTriggerKind.notification => ['Notification', if (app.isNotEmpty) 'from $app', if (query.isNotEmpty) 'matching "$query"'].join(' '),
    DeviceTriggerKind.moneyIn => 'Money received${amount > 0 ? ' over ${amount.round()}' : ''}${query.isEmpty ? '' : ' from "$query"'}',
    DeviceTriggerKind.moneyOut => 'Money spent${amount > 0 ? ' over ${amount.round()}' : ''}${query.isEmpty ? '' : ' to "$query"'}',
    DeviceTriggerKind.pageChanged => query.isEmpty ? '${Uri.tryParse(url)?.host ?? 'A page'} changes' : '"$query" appears on ${Uri.tryParse(url)?.host ?? 'a page'}',
    DeviceTriggerKind.offline => 'Internet lost',
    DeviceTriggerKind.online => 'Internet back',
    DeviceTriggerKind.mobileData => 'Mobile data over ${amount.round()} MB today',
    DeviceTriggerKind.storageLow => 'Storage under ${amount.toStringAsFixed(amount < 10 ? 1 : 0)} GB free',
    DeviceTriggerKind.youtubeUpload => query.isEmpty ? 'New YouTube video' : 'New video from $query',
  };
}

/// One firing: what happened, in words the assistant reads.
@immutable
class DeviceFiring {
  const DeviceFiring(this.ownerId, this.event);
  final String ownerId;
  final String event;
}

/// What the phone looks like right now.
class _Snapshot {
  int? battery;
  bool? charging;
  bool? wifi;
  String? ssid;
  Position? position;
  bool? online;
  int? mobileToday;
  int? storageFree;
}

/// Watches the phone for the triggers of watches and routines. It polls (the
/// engine calls [poll] every 30 seconds) rather than registering receivers,
/// so it needs the app alive, which the background service already keeps.
///
/// A trigger fires on a change: the first look only notes how things are,
/// so a watch made while charging doesn't fire for "plugged in" at once.
class DeviceEventMonitor {
  /// Whether each owner's condition held at the last look.
  final Map<String, bool> _held = {};
  final Map<String, DateTime> _lastFired = {};

  DateTime? _lastPosition;
  Position? _position;
  int? _callsSince;
  int? _smsSince;

  /// Set by whoever runs the owners: called when the app is opened.
  void Function()? onAppOpened;

  /// The bank SMS patterns (Money), for money in and out.
  ParserConfig? Function()? parser;

  /// The YouTube Data API key, for new uploads.
  String Function()? youtubeKey;

  int? _notifSince;
  int? _moneySince;
  final Map<String, DateTime> _checked = {};
  final Map<String, String> _pageSeen = {};
  final Map<String, Set<String>> _videosSeen = {};
  final Map<String, String> _uploads = {};

  void appOpened() => onAppOpened?.call();

  /// Whether [ownerId] may fire an "app opened" trigger now, given its
  /// cooldown. Records the firing when it may.
  bool openedMayFire(String ownerId, DeviceCondition c) {
    final last = _lastFired[ownerId];
    if (last != null && DateTime.now().difference(last).inMinutes < c.cooldownMinutes) return false;
    _lastFired[ownerId] = DateTime.now();
    return true;
  }

  /// Forgets owners that are gone, so one made again starts fresh.
  void keepOnly(Set<String> owners) {
    _held.removeWhere((k, _) => !owners.contains(k));
  }

  Future<List<DeviceFiring>> poll(List<(String, DeviceCondition)> owners) async {
    if (owners.isEmpty || !Platform.isAndroid) return const [];
    keepOnly({for (final (id, _) in owners) id});
    final kinds = {for (final (_, c) in owners) c.kind};
    final now = _Snapshot();
    if (kinds.any((k) => k == DeviceTriggerKind.batteryLow || k == DeviceTriggerKind.charging || k == DeviceTriggerKind.unplugged)) {
      try {
        final b = await Device.call<Map<Object?, Object?>>('battery');
        now.battery = (b?['level'] as num?)?.toInt();
        now.charging = b?['charging'] as bool?;
      } catch (e) {
        debugPrint('[DeviceEvents] battery: $e');
      }
    }
    if (kinds.any((k) => k.usesSsid)) {
      try {
        final n = await Device.call<Map<Object?, Object?>>('network');
        now.wifi = n?['type'] == 'wifi';
        final w = n?['wifi'];
        now.ssid = w is Map ? w['ssid'] as String? : null;
      } catch (e) {
        debugPrint('[DeviceEvents] network: $e');
      }
    }
    if (kinds.any((k) => k.needsPlace)) now.position = await _where();
    if (kinds.any((k) => k == DeviceTriggerKind.offline || k == DeviceTriggerKind.online)) {
      try {
        final n = await Device.call<Map<Object?, Object?>>('network');
        now.online = n?['validated'] == true;
      } catch (e) {
        debugPrint('[DeviceEvents] online: $e');
      }
    }
    if (kinds.contains(DeviceTriggerKind.mobileData)) {
      try {
        final d = await Net.dailyUsage(1);
        if (d.isNotEmpty) now.mobileToday = ((d.last['mobileRx'] as num?) ?? 0).toInt() + ((d.last['mobileTx'] as num?) ?? 0).toInt();
      } catch (_) {}
    }
    if (kinds.contains(DeviceTriggerKind.storageLow)) {
      try {
        final i = await Device.call<Map<Object?, Object?>>('deviceInfo');
        now.storageFree = (i?['storage_free'] as num?)?.toInt();
      } catch (_) {}
    }

    final out = <DeviceFiring>[];
    for (final (id, c) in owners) {
      final held = _holds(c, now);
      if (held == null) continue;
      final before = _held[id];
      _held[id] = held;
      if (before == null || before || !held) continue;
      // Flapping Wi-Fi or GPS: once every two minutes at most.
      final last = _lastFired[id];
      if (last != null && DateTime.now().difference(last) < const Duration(minutes: 2)) continue;
      _lastFired[id] = DateTime.now();
      out.add(DeviceFiring(id, _event(c, now)));
    }

    if (kinds.contains(DeviceTriggerKind.missedCall)) out.addAll(await _calls(owners));
    if (kinds.contains(DeviceTriggerKind.newSms)) out.addAll(await _texts(owners));
    if (kinds.contains(DeviceTriggerKind.notification)) out.addAll(await _notifications(owners));
    if (kinds.contains(DeviceTriggerKind.moneyIn) || kinds.contains(DeviceTriggerKind.moneyOut)) out.addAll(await _money(owners));
    for (final (id, c) in owners.where((o) => o.$2.kind.interval)) {
      // Pages and channels are checked every [cooldownMinutes], not every poll.
      final last = _checked[id];
      if (last != null && DateTime.now().difference(last).inMinutes < c.cooldownMinutes.clamp(5, 24 * 60)) continue;
      _checked[id] = DateTime.now();
      final f = c.kind == DeviceTriggerKind.pageChanged ? await _page(id, c) : await _youtube(id, c);
      if (f != null) out.add(f);
    }
    return out;
  }

  /// Whether [c] holds now; null when it can't be told (no reading).
  bool? _holds(DeviceCondition c, _Snapshot s) {
    switch (c.kind) {
      case DeviceTriggerKind.batteryLow:
        if (s.battery == null) return null;
        return s.battery! <= c.threshold && s.charging != true;
      case DeviceTriggerKind.charging:
        return s.charging;
      case DeviceTriggerKind.unplugged:
        return s.charging == null ? null : !s.charging!;
      case DeviceTriggerKind.wifiConnected:
      case DeviceTriggerKind.wifiDisconnected:
        if (s.wifi == null) return null;
        final on = s.wifi! && (c.ssid.isEmpty || (s.ssid ?? '').toLowerCase() == c.ssid.toLowerCase());
        // A named network whose name Android hides (no location
        // permission) can't be told apart.
        if (c.ssid.isNotEmpty && s.wifi! && s.ssid == null) return null;
        return c.kind == DeviceTriggerKind.wifiConnected ? on : !on;
      case DeviceTriggerKind.arrive:
      case DeviceTriggerKind.leave:
        final p = s.position;
        if (p == null || !c.hasPlace) return null;
        final d = Geolocator.distanceBetween(p.latitude, p.longitude, c.lat!, c.lng!);
        // A margin past the edge, so GPS wobble doesn't come and go.
        final inside = d <= c.radius + math.min(p.accuracy, 100);
        final outside = d > c.radius * 1.2 + 50;
        if (!inside && !outside) return null;
        return c.kind == DeviceTriggerKind.arrive ? inside : outside;
      case DeviceTriggerKind.offline:
        return s.online == null ? null : !s.online!;
      case DeviceTriggerKind.online:
        return s.online;
      case DeviceTriggerKind.mobileData:
        if (s.mobileToday == null || c.amount <= 0) return null;
        return s.mobileToday! >= c.amount * 1024 * 1024;
      case DeviceTriggerKind.storageLow:
        if (s.storageFree == null || c.amount <= 0) return null;
        return s.storageFree! < c.amount * 1024 * 1024 * 1024;
      case DeviceTriggerKind.missedCall:
      case DeviceTriggerKind.newSms:
      case DeviceTriggerKind.appOpened:
      case DeviceTriggerKind.notification:
      case DeviceTriggerKind.moneyIn:
      case DeviceTriggerKind.moneyOut:
      case DeviceTriggerKind.pageChanged:
      case DeviceTriggerKind.youtubeUpload:
        return null;
    }
  }

  String _event(DeviceCondition c, _Snapshot s) => switch (c.kind) {
    DeviceTriggerKind.batteryLow => 'The phone\'s battery is at ${s.battery}% and not charging.',
    DeviceTriggerKind.charging => 'The phone was plugged in to charge (battery ${s.battery ?? '?'}%).',
    DeviceTriggerKind.unplugged => 'The phone was unplugged (battery ${s.battery ?? '?'}%).',
    DeviceTriggerKind.wifiConnected => 'The phone joined Wi-Fi${s.ssid == null ? '' : ' "${s.ssid}"'}.',
    DeviceTriggerKind.wifiDisconnected => 'The phone left Wi-Fi${c.ssid.isEmpty ? '' : ' "${c.ssid}"'}.',
    DeviceTriggerKind.arrive => 'The user arrived at ${c.placeName.isEmpty ? 'the place' : c.placeName}.',
    DeviceTriggerKind.leave => 'The user left ${c.placeName.isEmpty ? 'the place' : c.placeName}.',
    DeviceTriggerKind.offline => 'The phone lost its internet connection.',
    DeviceTriggerKind.online => "The phone's internet works again.",
    DeviceTriggerKind.mobileData => 'Mobile data used today passed ${c.amount.round()} MB (now ${((s.mobileToday ?? 0) / 1048576).round()} MB).',
    DeviceTriggerKind.storageLow => 'Free storage is down to ${((s.storageFree ?? 0) / 1073741824).toStringAsFixed(1)} GB.',
    _ => c.describe(),
  };

  /// The phone's position, at most every two minutes; null without
  /// location permission (it isn't asked for from the background).
  Future<Position?> _where() async {
    if (_lastPosition != null && DateTime.now().difference(_lastPosition!) < const Duration(minutes: 2)) return _position;
    _lastPosition = DateTime.now();
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) return _position = null;
      if (!await Geolocator.isLocationServiceEnabled()) return _position = null;
      _position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
      );
    } catch (e) {
      debugPrint('[DeviceEvents] location: $e');
    }
    return _position;
  }

  static bool _matches(String query, Iterable<Object?> fields) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    for (final f in fields) {
      final s = '${f ?? ''}'.toLowerCase();
      if (s.contains(q)) return true;
      if (digits.length >= 4 && s.replaceAll(RegExp(r'\D'), '').contains(digits)) return true;
    }
    return false;
  }

  Future<bool> _granted(String permission) async => (await Device.status([permission]))[permission] == true;

  Future<List<DeviceFiring>> _calls(List<(String, DeviceCondition)> owners) async {
    if (!await _granted(Device.callLog.id)) return const [];
    try {
      final rows = await Device.call<List<Object?>>('callLog', {'type': 'missed', 'limit': 20}) ?? const [];
      final calls = [for (final r in rows) if (r is Map) r];
      final newest = calls.map((r) => (r['date'] as num?)?.toInt() ?? 0).fold<int>(0, math.max);
      final since = _callsSince;
      _callsSince = math.max(since ?? 0, newest == 0 ? DateTime.now().millisecondsSinceEpoch : newest);
      if (since == null) return const [];
      final fresh = calls.where((r) => ((r['date'] as num?)?.toInt() ?? 0) > since).toList();
      if (fresh.isEmpty) return const [];
      return [
        for (final (id, c) in owners.where((o) => o.$2.kind == DeviceTriggerKind.missedCall))
          if (fresh.where((r) => _matches(c.query, [r['name'], r['number']])).toList() case final hits when hits.isNotEmpty)
            DeviceFiring(
              id,
              'Missed call${hits.length == 1 ? '' : 's'}: ${hits.map((r) => '${r['name'] ?? 'Unknown'} (${r['number'] ?? 'hidden number'})').join(', ')}.',
            ),
      ];
    } catch (e) {
      debugPrint('[DeviceEvents] calls: $e');
      return const [];
    }
  }

  Future<List<DeviceFiring>> _texts(List<(String, DeviceCondition)> owners) async {
    if (!await _granted(Device.sms.id)) return const [];
    try {
      final rows = await Device.call<List<Object?>>('sms', {'box': 'inbox', 'limit': 20}) ?? const [];
      final texts = [for (final r in rows) if (r is Map) r];
      final newest = texts.map((r) => (r['date'] as num?)?.toInt() ?? 0).fold<int>(0, math.max);
      final since = _smsSince;
      _smsSince = math.max(since ?? 0, newest == 0 ? DateTime.now().millisecondsSinceEpoch : newest);
      if (since == null) return const [];
      final fresh = texts.where((r) => ((r['date'] as num?)?.toInt() ?? 0) > since).toList();
      if (fresh.isEmpty) return const [];
      return [
        for (final (id, c) in owners.where((o) => o.$2.kind == DeviceTriggerKind.newSms))
          if (fresh.where((r) => _matches(c.query, [r['name'], r['address'], r['body']])).toList() case final hits when hits.isNotEmpty)
            DeviceFiring(
              id,
              'New text message${hits.length == 1 ? '' : 's'}:\n${hits.map((r) => '- from ${r['name'] ?? r['address'] ?? 'unknown'}: ${r['body'] ?? ''}').join('\n')}',
            ),
      ];
    } catch (e) {
      debugPrint('[DeviceEvents] sms: $e');
      return const [];
    }
  }

  Future<List<DeviceFiring>> _notifications(List<(String, DeviceCondition)> owners) async {
    if (!await Net.notificationAccess()) return const [];
    try {
      final since = _notifSince;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (since == null) {
        _notifSince = now;
        return const [];
      }
      final items = await Net.notifications(since: DateTime.fromMillisecondsSinceEpoch(since + 1), limit: 200);
      _notifSince = items.map((x) => (x['time'] as num?)?.toInt() ?? 0).fold<int>(since, math.max);
      if (items.isEmpty) return const [];
      String text(Map<String, dynamic> x) {
        final msgs = [
          for (final m in (x['messages'] as List? ?? const []))
            if (m is Map) '${m['sender'] == null ? '' : '${m['sender']}: '}${m['text']}',
        ];
        return msgs.isNotEmpty ? msgs.join(' / ') : '${x['text'] ?? ''}';
      }

      return [
        for (final (id, c) in owners.where((o) => o.$2.kind == DeviceTriggerKind.notification))
          if (items.where((x) => (c.app.isEmpty || _matches(c.app, [x['app'], x['package']])) && _matches(c.query, [x['title'], x['text'], text(x)])).toList()
              case final hits when hits.isNotEmpty)
            DeviceFiring(
              id,
              'New notification${hits.length == 1 ? '' : 's'}:\n${hits.take(10).map((x) => '- ${x['app']}${x['title'] == null ? '' : ' · ${x['title']}'}: ${text(x)}').join('\n')}',
            ),
      ];
    } catch (e) {
      debugPrint('[DeviceEvents] notifications: $e');
      return const [];
    }
  }

  Future<List<DeviceFiring>> _money(List<(String, DeviceCondition)> owners) async {
    final config = parser?.call();
    if (config == null || !await _granted(Device.sms.id)) return const [];
    try {
      final rows = await Device.call<List<Object?>>('sms', {'box': 'inbox', 'limit': 30}) ?? const [];
      final texts = [for (final r in rows) if (r is Map) r];
      final newest = texts.map((r) => (r['date'] as num?)?.toInt() ?? 0).fold<int>(0, math.max);
      final since = _moneySince;
      _moneySince = math.max(since ?? 0, newest == 0 ? DateTime.now().millisecondsSinceEpoch : newest);
      if (since == null) return const [];
      final out = <DeviceFiring>[];
      for (final r in texts.where((r) => ((r['date'] as num?)?.toInt() ?? 0) > since)) {
        final p = parseBankSms('${r['body'] ?? ''}', r['address'] as String?, banks: config.banks, patterns: config.patterns);
        if (p == null) continue;
        final bank = config.banks.where((b) => b.id == p.bankId).firstOrNull?.shortName ?? 'Bank';
        final credit = p.type == 'CREDIT';
        for (final (id, c) in owners) {
          if (c.kind != (credit ? DeviceTriggerKind.moneyIn : DeviceTriggerKind.moneyOut)) continue;
          if (p.amount < c.amount || !_matches(c.query, [p.counterparty, bank])) continue;
          out.add(DeviceFiring(
            id,
            '${credit ? 'Money received' : 'Money spent'}: $bank ${p.amount.toStringAsFixed(2)}'
            '${p.counterparty.isEmpty ? '' : credit ? ' from ${p.counterparty}' : ' to ${p.counterparty}'}'
            '${p.balance == null ? '' : ', balance ${p.balance!.toStringAsFixed(2)}'}${p.reference == null ? '' : ' (ref ${p.reference})'}.',
          ));
        }
      }
      return out;
    } catch (e) {
      debugPrint('[DeviceEvents] money: $e');
      return const [];
    }
  }

  /// A page's readable text now; fires when it changed since the last look,
  /// or, with words to look for, when they first show up.
  Future<DeviceFiring?> _page(String id, DeviceCondition c) async {
    final uri = Uri.tryParse(c.url.contains('://') ? c.url : 'https://${c.url}');
    if (uri == null || uri.host.isEmpty) return null;
    try {
      final r = await http.get(uri, headers: const {'user-agent': 'Mozilla/5.0 (Linux; Android 14) Triangle'}).timeout(const Duration(seconds: 25));
      if (r.statusCode >= 400) return null;
      final text = ReadablePage.parse(r.body, uri).text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final q = c.query.trim().toLowerCase();
      final state = q.isEmpty ? '${text.length}:${text.hashCode}' : (text.toLowerCase().contains(q) ? 'yes' : 'no');
      final before = _pageSeen[id];
      _pageSeen[id] = state;
      if (before == null || before == state) return null;
      if (q.isNotEmpty && state != 'yes') return null;
      var snippet = '';
      if (q.isNotEmpty) {
        final at = text.toLowerCase().indexOf(q);
        snippet = ': …${text.substring(math.max(0, at - 120), math.min(text.length, at + q.length + 120))}…';
      }
      return DeviceFiring(id, q.isEmpty ? 'The page $uri changed.' : '"${c.query}" now appears on $uri$snippet');
    } catch (e) {
      debugPrint('[DeviceEvents] page: $e');
      return null;
    }
  }

  Future<DeviceFiring?> _youtube(String id, DeviceCondition c) async {
    final key = youtubeKey?.call().trim() ?? '';
    if (key.isEmpty || c.query.trim().isEmpty) return null;
    try {
      final yt = YoutubeApi(key);
      final uploads = _uploads[c.query] ??= '${(await yt.channel(c.query))['uploads_playlist'] ?? ''}';
      if (uploads.isEmpty) return null;
      final videos = await yt.playlistVideos(uploads, max: 5);
      final seen = _videosSeen[id];
      _videosSeen[id] = {for (final v in videos) '${v['video_id']}'};
      if (seen == null) return null;
      final fresh = videos.where((v) => !seen.contains('${v['video_id']}')).toList();
      if (fresh.isEmpty) return null;
      return DeviceFiring(
        id,
        'New YouTube video${fresh.length == 1 ? '' : 's'} from ${fresh.first['channel']}:\n${fresh.map((v) => '- ${v['title']} (${v['length'] ?? ''}) ${v['url']}').join('\n')}',
      );
    } catch (e) {
      debugPrint('[DeviceEvents] youtube: $e');
      return null;
    }
  }
}

final deviceEventsProvider = Provider<DeviceEventMonitor>(
  (ref) => DeviceEventMonitor()
    ..parser = (() => ref.read(financeStoreProvider).parser)
    ..youtubeKey = (() => ref.read(settingsProvider).youtubeKey),
);

/// A phone trigger from a tool call's arguments (`phone_event`,
/// `battery_below`, `wifi_name`, `place_*`, `match`).
({DeviceCondition? condition, String? error}) phoneConditionFrom(Map<String, dynamic> a) {
  final event = '${a['phone_event'] ?? ''}'.trim();
  final kind = switch (event) {
    'battery_low' => DeviceTriggerKind.batteryLow,
    'charging' => DeviceTriggerKind.charging,
    'unplugged' => DeviceTriggerKind.unplugged,
    'wifi_connected' => DeviceTriggerKind.wifiConnected,
    'wifi_disconnected' => DeviceTriggerKind.wifiDisconnected,
    'arrive' => DeviceTriggerKind.arrive,
    'leave' => DeviceTriggerKind.leave,
    'missed_call' => DeviceTriggerKind.missedCall,
    'new_sms' => DeviceTriggerKind.newSms,
    'app_opened' => DeviceTriggerKind.appOpened,
    'notification' => DeviceTriggerKind.notification,
    'money_in' => DeviceTriggerKind.moneyIn,
    'money_out' => DeviceTriggerKind.moneyOut,
    'page_changed' => DeviceTriggerKind.pageChanged,
    'offline' => DeviceTriggerKind.offline,
    'online' => DeviceTriggerKind.online,
    'mobile_data' => DeviceTriggerKind.mobileData,
    'storage_low' => DeviceTriggerKind.storageLow,
    'youtube_upload' => DeviceTriggerKind.youtubeUpload,
    _ => null,
  };
  if (kind == null) return (condition: null, error: 'Give phone_event for a phone trigger.');
  final lat = (a['place_latitude'] as num?)?.toDouble();
  final lng = (a['place_longitude'] as num?)?.toDouble();
  if (kind.needsPlace && (lat == null || lng == null)) {
    return (condition: null, error: 'arrive and leave need place_latitude and place_longitude.');
  }
  final url = '${a['url'] ?? ''}'.trim();
  if (kind == DeviceTriggerKind.pageChanged && url.isEmpty) return (condition: null, error: 'page_changed needs url.');
  final amount = (a['amount'] as num?)?.toDouble() ?? 0;
  if ((kind == DeviceTriggerKind.mobileData || kind == DeviceTriggerKind.storageLow) && amount <= 0) {
    return (condition: null, error: 'mobile_data needs amount (MB) and storage_low needs amount (GB free).');
  }
  if (kind == DeviceTriggerKind.youtubeUpload && '${a['match'] ?? ''}'.trim().isEmpty) {
    return (condition: null, error: 'youtube_upload needs match: the channel (@handle, link or name).');
  }
  return (
    condition: DeviceCondition(
      kind: kind,
      threshold: ((a['battery_below'] as num?)?.toInt() ?? 20).clamp(1, 99),
      ssid: '${a['wifi_name'] ?? ''}'.trim(),
      lat: lat,
      lng: lng,
      radius: ((a['place_radius_m'] as num?)?.toInt() ?? 150).clamp(50, 50000),
      placeName: '${a['place_name'] ?? ''}'.trim(),
      query: '${a['match'] ?? ''}'.trim(),
      amount: amount,
      url: url,
      app: '${a['app'] ?? ''}'.trim(),
      cooldownMinutes: ((a['check_every_minutes'] as num?)?.toInt() ?? (kind.interval ? 60 : 30)).clamp(kind.interval ? 5 : 0, 24 * 60),
    ),
    error: null,
  );
}
