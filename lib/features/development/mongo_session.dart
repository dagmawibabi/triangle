import 'dart:async';
import 'dart:convert';

import 'package:mongo_dart/mongo_dart.dart' as mongo;
// The driver's generic command runner; it targets any database by name on
// one connection, which the public API does not expose.
// ignore: implementation_imports
import 'package:mongo_dart/src/database/commands/base/command_operation.dart' show CommandOperation;

/// A failed MongoDB call, with the server's message.
class MongoProblem implements Exception {
  const MongoProblem(this.message, {this.code});
  final String message;
  final Object? code;
  @override
  String toString() => message;
}

/// One connection per connection string, opened on first use and closed
/// after a few idle minutes. Every call names its database, so one
/// connection serves them all. Documents go in and come out as relaxed
/// Extended JSON ({"$oid": …}, {"$date": …}), which the model and the
/// cards can read and write.
class MongoSession {
  MongoSession._();
  static final instance = MongoSession._();

  mongo.Db? _db;
  String? _uri;
  Future<mongo.Db>? _opening;
  Timer? _idle;

  /// What the last successful connection reported, for Settings.
  Map<String, dynamic>? lastHello;

  static const idleTimeout = Duration(minutes: 4);

  /// The database named in [uri]'s path, or null.
  static String? databaseIn(String uri) {
    final m = RegExp(r'^mongodb(?:\+srv)?://[^/]+/([^?/]+)').firstMatch(uri.trim());
    final name = m == null ? null : Uri.decodeComponent(m[1]!);
    return name == null || name.isEmpty ? null : name;
  }

  /// [uri] with its password hidden, for showing.
  static String redact(String uri) => uri.replaceAllMapped(RegExp(r'(mongodb(?:\+srv)?://[^:/@]+):([^@]+)@'), (m) => '${m[1]}:••••@');

  /// The hosts of [uri], for showing.
  static String hostsOf(String uri) {
    final m = RegExp(r'^mongodb(?:\+srv)?://(?:[^@/]+@)?([^/?]+)').firstMatch(uri.trim());
    return m?[1] ?? '';
  }

  Future<mongo.Db> _connect(String uri) {
    _idle?.cancel();
    _idle = Timer(idleTimeout, close);
    if (_db != null && _uri == uri && _db!.isConnected) return Future.value(_db!);
    if (_opening != null && _uri == uri) return _opening!;
    final old = _db;
    _db = null;
    if (old != null) unawaited(old.close().catchError((_) {}));
    _uri = uri;
    final opening = () async {
      final db = await mongo.Db.create(uri);
      final srv = uri.startsWith('mongodb+srv://');
      final tlsOff = RegExp(r'[?&](tls|ssl)=false', caseSensitive: false).hasMatch(uri);
      await db.open(secure: srv && !tlsOff).timeout(const Duration(seconds: 25));
      _db = db;
      return db;
    }();
    _opening = opening;
    return opening.whenComplete(() => _opening = null).catchError((Object e) {
      _uri = null;
      throw _problem(e);
    });
  }

  /// Closes the connection; the next call opens a new one.
  Future<void> close() async {
    _idle?.cancel();
    final db = _db;
    _db = null;
    _uri = null;
    if (db != null) await db.close().catchError((_) {});
  }

  bool get connected => _db?.isConnected ?? false;

  /// Runs [command] against [database] and returns the reply as relaxed
  /// Extended JSON. [command] may hold Extended JSON values.
  Future<Map<String, dynamic>> command(String uri, String database, Map<String, dynamic> command, {Duration timeout = const Duration(seconds: 60)}) async {
    final db = await _connect(uri);
    try {
      final cmd = <String, Object>{for (final e in fromEjson(command).entries) e.key: e.value as Object};
      final reply = await CommandOperation(db, <String, Object>{mongo.keyDbName: database}, command: cmd).execute().timeout(timeout);
      final out = toEjson(reply);
      if (out['ok'] != null && out['ok'] != 1 && out['ok'] != 1.0 && out['ok'] != true) {
        throw MongoProblem('${out['errmsg'] ?? 'Command failed'}', code: out['code']);
      }
      if (out['writeErrors'] is List && (out['writeErrors'] as List).isNotEmpty) {
        final first = (out['writeErrors'] as List).first;
        throw MongoProblem('${first is Map ? first['errmsg'] : first}', code: first is Map ? first['code'] : null);
      }
      return out;
    } catch (e) {
      if (e is MongoProblem) rethrow;
      // A dropped connection: forget it so the next call reconnects.
      if (!db.isConnected) unawaited(close());
      throw _problem(e);
    }
  }

  /// A cursor command (find, aggregate, listCollections…) read to [limit]
  /// documents, following getMore. Returns the documents and whether more
  /// were left.
  Future<({List<Map<String, dynamic>> docs, bool more})> cursor(String uri, String database, Map<String, dynamic> cmd, {int limit = 50}) async {
    final first = await command(uri, database, cmd);
    final c = first['cursor'] as Map? ?? const {};
    final docs = <Map<String, dynamic>>[for (final d in (c['firstBatch'] as List? ?? const [])) if (d is Map) Map<String, dynamic>.from(d)];
    var id = c['id'];
    final ns = '${c['ns'] ?? ''}';
    final coll = ns.contains('.') ? ns.substring(ns.indexOf('.') + 1) : '${cmd.values.first}';
    while (_live(id) && docs.length < limit) {
      final next = await command(uri, database, {'getMore': _long(id), 'collection': coll, 'batchSize': (limit - docs.length).clamp(1, 1000)});
      final n = next['cursor'] as Map? ?? const {};
      docs.addAll([for (final d in (n['nextBatch'] as List? ?? const [])) if (d is Map) Map<String, dynamic>.from(d)]);
      id = n['id'];
    }
    if (_live(id)) {
      unawaited(command(uri, database, {'killCursors': coll, 'cursors': [_long(id)]}).catchError((_) => <String, dynamic>{}));
    }
    final more = docs.length > limit || _live(id);
    return (docs: docs.length > limit ? docs.sublist(0, limit) : docs, more: more);
  }

  static bool _live(Object? id) {
    if (id == null) return false;
    if (id is num) return id != 0;
    if (id is Map) return '${id[r'$numberLong'] ?? '0'}' != '0';
    return '$id' != '0';
  }

  static Object _long(Object? id) => id is Map ? {r'$numberLong': '${id[r'$numberLong']}'} : (id ?? 0);

  static MongoProblem _problem(Object e) {
    final text = '$e';
    if (e is mongo.MongoDartError) return MongoProblem(e.message, code: e.mongoCode);
    if (text.contains('Failed host lookup') || text.contains('SocketException')) {
      return MongoProblem('Couldn\'t reach the server: ${text.replaceFirst('SocketException: ', '')}');
    }
    if (text.contains('TimeoutException')) return const MongoProblem('The server didn\'t answer in time.');
    if (text.contains('Authentication failed') || text.contains('auth')) return MongoProblem('Sign-in failed: $text');
    return MongoProblem(text.replaceFirst('Exception: ', ''));
  }

  // ---- Extended JSON -------------------------------------------------------------

  /// Driver values (ObjectId, DateTime, Decimal128…) as relaxed Extended JSON.
  static Map<String, dynamic> toEjson(Map<String, dynamic> doc) {
    try {
      return mongo.EJsonCodec.deserialize(mongo.BsonCodec.serialize(doc), relaxed: true);
    } catch (_) {
      return _plain(doc) as Map<String, dynamic>;
    }
  }

  /// Extended JSON values ({"$oid"}, {"$date"}…) as driver values.
  static Map<String, dynamic> fromEjson(Map<String, dynamic> doc) {
    try {
      return mongo.EJsonCodec.eJson2Doc(_normalizeDates(doc) as Map<String, dynamic>);
    } catch (_) {
      return doc;
    }
  }

  /// {"$date": "2024-01-01"} without a time is accepted by people but not by
  /// the codec, which wants a full ISO date.
  static Object? _normalizeDates(Object? v) {
    if (v is Map) {
      if (v.length == 1 && v[r'$date'] is String) {
        final d = DateTime.tryParse(v[r'$date'] as String);
        if (d != null) return {r'$date': d.toUtc().toIso8601String()};
      }
      return <String, dynamic>{for (final e in v.entries) '${e.key}': _normalizeDates(e.value)};
    }
    if (v is List) return [for (final x in v) _normalizeDates(x)];
    return v;
  }

  static Object? _plain(Object? v) {
    if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': _plain(e.value)};
    if (v is List) return [for (final x in v) _plain(x)];
    if (v is mongo.ObjectId) return {r'$oid': v.oid};
    if (v is DateTime) return {r'$date': v.toUtc().toIso8601String()};
    if (v == null || v is num || v is String || v is bool) return v;
    return '$v';
  }

  /// Parses a JSON filter, document or pipeline the model or the person
  /// wrote. Accepts a map or list already decoded, or text.
  static Object? parse(Object? v, {String what = 'value'}) {
    if (v == null) return null;
    if (v is Map || v is List) return v;
    final text = '$v'.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      throw MongoProblem('$what is not valid JSON. Use double quotes, and {"\$oid": "…"} for ids.');
    }
  }
}

/// Field names and types seen across [docs]: how often each appears and as
/// what, for the schema card.
List<Map<String, dynamic>> inferSchema(List<Map<String, dynamic>> docs, {int maxFields = 120}) {
  final seen = <String, Map<String, int>>{};
  final examples = <String, Object?>{};
  void walk(String prefix, Object? v, int depth) {
    if (v is Map && !_isEjsonScalar(v) && depth < 4) {
      for (final e in v.entries) {
        final path = prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}';
        final t = _typeOf(e.value);
        (seen[path] ??= {})[t] = (seen[path]![t] ?? 0) + 1;
        examples.putIfAbsent(path, () => e.value is Map || e.value is List ? null : e.value);
        if (e.value is Map) walk(path, e.value, depth + 1);
        if (e.value is List) {
          for (final x in (e.value as List).take(5)) {
            if (x is Map) walk('$path[]', x, depth + 1);
          }
        }
      }
    }
  }

  for (final d in docs) {
    walk('', d, 0);
  }
  final n = docs.isEmpty ? 1 : docs.length;
  final fields = [
    for (final e in seen.entries)
      {
        'field': e.key,
        'types': [for (final t in (e.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) t.key],
        'present': (e.value.values.fold<int>(0, (a, b) => a + b) / n).clamp(0, 1).toDouble(),
        if (examples[e.key] != null) 'example': _clip(examples[e.key]),
      },
  ];
  return fields.take(maxFields).toList();
}

bool _isEjsonScalar(Map v) => v.length <= 2 && v.keys.every((k) => '$k'.startsWith(r'$'));

String _typeOf(Object? v) {
  if (v == null) return 'null';
  if (v is bool) return 'bool';
  if (v is int) return 'int';
  if (v is num) return 'double';
  if (v is String) return 'string';
  if (v is List) return 'array';
  if (v is Map) {
    if (v.containsKey(r'$oid')) return 'objectId';
    if (v.containsKey(r'$date')) return 'date';
    if (v.containsKey(r'$numberDecimal')) return 'decimal';
    if (v.containsKey(r'$numberLong')) return 'long';
    if (v.containsKey(r'$binary')) return 'binary';
    if (v.containsKey(r'$timestamp')) return 'timestamp';
    if (v.containsKey(r'$regularExpression')) return 'regex';
    return 'object';
  }
  return 'unknown';
}

Object? _clip(Object? v) {
  if (v is String && v.length > 60) return '${v.substring(0, 60)}…';
  if (v is Map) {
    final text = jsonEncode(v);
    return text.length > 60 ? '${text.substring(0, 60)}…' : v;
  }
  return v;
}
