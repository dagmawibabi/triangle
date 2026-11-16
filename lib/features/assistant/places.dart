import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Places the person names once (Home, Work, Gym) and picks again for any
// location trigger, with address search and "where am I" from OpenStreetMap.

@immutable
class SavedPlace {
  const SavedPlace({required this.id, required this.name, required this.lat, required this.lng, this.radius = 150, this.emoji = '📍', this.address = ''});
  final String id;
  final String name;
  final double lat;
  final double lng;
  final int radius;
  final String emoji;
  final String address;

  SavedPlace copyWith({String? name, double? lat, double? lng, int? radius, String? emoji, String? address}) => SavedPlace(
    id: id,
    name: name ?? this.name,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    radius: radius ?? this.radius,
    emoji: emoji ?? this.emoji,
    address: address ?? this.address,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'lat': lat, 'lng': lng, 'radius': radius, 'emoji': emoji, if (address.isNotEmpty) 'address': address};

  factory SavedPlace.fromJson(Map j) => SavedPlace(
    id: '${j['id']}',
    name: '${j['name'] ?? 'Place'}',
    lat: (j['lat'] as num?)?.toDouble() ?? 0,
    lng: (j['lng'] as num?)?.toDouble() ?? 0,
    radius: (j['radius'] as num?)?.toInt() ?? 150,
    emoji: '${j['emoji'] ?? '📍'}',
    address: '${j['address'] ?? ''}',
  );

  Map<String, dynamic> describe() => {'place': name, 'latitude': lat, 'longitude': lng, 'radius_m': radius, if (address.isNotEmpty) 'address': address};
}

class SavedPlacesStore extends Notifier<List<SavedPlace>> {
  static const _key = 'saved_places.v1';
  late Future<void> ready;

  @override
  List<SavedPlace> build() {
    ready = _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      state = [for (final p in jsonDecode(raw) as List) if (p is Map) SavedPlace.fromJson(p)];
    } catch (e) {
      debugPrint('[Places] $e');
    }
  }

  Future<void> _save(List<SavedPlace> v) async {
    state = v;
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final p in v) p.toJson()]));
  }

  /// Adds [p], or replaces the place with the same name.
  Future<SavedPlace> put(SavedPlace p) async {
    await ready;
    final same = state.where((x) => x.id == p.id || x.name.toLowerCase() == p.name.toLowerCase()).firstOrNull;
    final kept = same == null ? p : SavedPlace(id: same.id, name: p.name, lat: p.lat, lng: p.lng, radius: p.radius, emoji: p.emoji, address: p.address);
    await _save(same == null ? [...state, kept] : [for (final x in state) x.id == same.id ? kept : x]);
    return kept;
  }

  Future<void> remove(String id) async {
    await ready;
    await _save([for (final x in state) if (x.id != id) x]);
  }

  SavedPlace? named(String name) {
    final q = name.trim().toLowerCase();
    if (q.isEmpty) return null;
    return state.where((p) => p.id == name.trim() || p.name.toLowerCase() == q).firstOrNull ?? state.where((p) => p.name.toLowerCase().contains(q)).firstOrNull;
  }

  static String newId() => const Uuid().v4().substring(0, 8);
}

final savedPlacesProvider = NotifierProvider<SavedPlacesStore, List<SavedPlace>>(SavedPlacesStore.new);

/// One address search result.
typedef GeoHit = ({String name, String address, double lat, double lng});

const _ua = {'User-Agent': 'Triangle/1.0 (Flutter; place picker)', 'Accept-Language': 'en'};

/// Addresses matching [query], from OpenStreetMap's Nominatim. Biased
/// towards [near] when given.
Future<List<GeoHit>> searchPlaces(String query, {({double lat, double lng})? near}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final params = {
    'q': q,
    'format': 'jsonv2',
    'limit': '8',
    'addressdetails': '0',
    if (near != null) 'viewbox': '${near.lng - 1},${near.lat + 1},${near.lng + 1},${near.lat - 1}',
  };
  final r = await http.get(Uri.https('nominatim.openstreetmap.org', '/search', params), headers: _ua).timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) throw Exception('The address search answered ${r.statusCode}.');
  final list = jsonDecode(r.body);
  if (list is! List) return const [];
  return [
    for (final m in list.whereType<Map>())
      if (double.tryParse('${m['lat']}') case final lat?)
        if (double.tryParse('${m['lon']}') case final lng?)
          (
            name: '${m['name'] ?? ''}'.trim().isEmpty ? '${m['display_name']}'.split(',').first.trim() : '${m['name']}'.trim(),
            address: '${m['display_name'] ?? ''}',
            lat: lat,
            lng: lng,
          ),
  ];
}

/// A short address for a point ("Bole Road, Addis Ababa"), or null.
Future<String?> addressAt(double lat, double lng) async {
  try {
    final r = await http
        .get(Uri.https('nominatim.openstreetmap.org', '/reverse', {'lat': '$lat', 'lon': '$lng', 'format': 'jsonv2', 'zoom': '17'}), headers: _ua)
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    if (j is! Map) return null;
    final parts = '${j['display_name'] ?? ''}'.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.take(3).join(', ');
  } catch (_) {
    return null;
  }
}

/// A point from pasted text: "9.0301, 38.7469", a Google Maps or OSM link,
/// or a geo: URI.
({double lat, double lng})? parseLatLng(String text) {
  final t = Uri.decodeFull(text.trim());
  final patterns = [
    RegExp(r'@(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'[?&](?:q|query|ll|center)=(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)'),
    RegExp(r'mlat=(-?\d{1,2}\.\d+)&mlon=(-?\d{1,3}\.\d+)'),
    RegExp(r'#map=\d+/(-?\d{1,2}\.\d+)/(-?\d{1,3}\.\d+)'),
    RegExp(r'geo:(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)'),
    RegExp(r'^\s*(-?\d{1,2}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)\s*$'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(t);
    if (m == null) continue;
    final lat = double.tryParse(m[1]!), lng = double.tryParse(m[2]!);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) continue;
    return (lat: lat, lng: lng);
  }
  return null;
}

/// Where the phone is now. Asks for permission when it hasn't been asked.
/// Throws a readable message when it can't.
Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) throw 'Location is turned off on this phone.';
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw 'Location permission is needed.';
  return Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)));
}

/// "350 m" or "4.2 km".
String distanceText(double metres) => metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(metres < 10000 ? 1 : 0)} km';

/// The slippy-map tile holding a point at [zoom], and where in it the point
/// falls (0..1).
({int x, int y, double fx, double fy}) tileFor(double lat, double lng, int zoom) {
  final n = math.pow(2, zoom).toDouble();
  final x = (lng + 180) / 360 * n;
  final r = lat * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
  return (x: x.floor(), y: y.floor(), fx: x - x.floor(), fy: y - y.floor());
}

/// Metres per screen pixel of a 256 px tile at [lat] and [zoom].
double metresPerPixel(double lat, int zoom) => 156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);
