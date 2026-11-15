part of 'telegram_tools.dart';

// MongoDB, with the user's connection string (Settings → Development →
// MongoDB): databases and collections, finding, counting, aggregating,
// schemas, indexes, stats, explain plans, server status, exporting and
// importing; inserting, updating and indexing ask first; deleting and
// dropping are destructive. Documents are relaxed Extended JSON:
// {"$oid": "…"} for ids and {"$date": "…"} for dates.

const _mgDb = {'type': 'string', 'description': 'Database name. Default: the one in Settings or in the connection string.'};
const _mgColl = {'type': 'string', 'description': 'Collection name.'};
const _mgFilter = {
  'type': 'object',
  'description': 'Query filter in MongoDB syntax, e.g. {"status": "active", "age": {"\$gt": 30}}. Ids as {"\$oid": "…"}, dates as {"\$date": "2024-01-31T00:00:00Z"}.',
};
const _mgPipeline = {
  'type': 'array',
  'items': {'type': 'object', 'description': 'One stage, e.g. {"\$group": {"_id": "\$country", "n": {"\$sum": 1}}}.'},
  'description': 'Aggregation pipeline stages.',
};

TelegramTool _mg(String name, String label, String description, Map<String, dynamic> params, {List<String> required = const [], bool change = false, bool destructive = false}) =>
    TelegramTool(
      name: name,
      label: label,
      category: ToolCategory.mongodb,
      cost: ToolCost.cloud,
      requiresApproval: change || destructive,
      destructive: destructive,
      description: description,
      parameters: _obj(params, required),
    );

final _mongoTools = <TelegramTool>[
  // ---- read ----------------------------------------------------------------------
  _mg('mongodb_overview', 'Looking at the MongoDB server',
      'The server (version, topology, uptime) and every database with its size and collection count. Shown as an overview the user can open.', {}),
  _mg('mongodb_collections', 'Listing collections',
      'Collections and views in a database with document counts, sizes and index counts. Shown as a list the user can open.', {'database': _mgDb}),
  _mg('mongodb_find', 'Finding documents',
      'Documents matching a filter, with projection, sort, skip and limit. Shown as a document browser with paging.', {
        'collection': _mgColl,
        'database': _mgDb,
        'filter': _mgFilter,
        'projection': {'type': 'object', 'description': 'Fields to include (1) or exclude (0), e.g. {"name": 1, "_id": 0}.'},
        'sort': {'type': 'object', 'description': 'Sort order, e.g. {"created_at": -1}.'},
        'limit': {'type': 'integer', 'description': '1-200, default 20.'},
        'skip': {'type': 'integer', 'description': 'Documents to skip, for paging.'},
      }, required: ['collection']),
  _mg('mongodb_count', 'Counting documents', 'How many documents match a filter (all of them when no filter).', {
    'collection': _mgColl,
    'database': _mgDb,
    'filter': _mgFilter,
  }, required: ['collection']),
  _mg('mongodb_distinct', 'Listing distinct values', 'The distinct values of a field across matching documents, with how many there are.', {
    'collection': _mgColl,
    'database': _mgDb,
    'field': {'type': 'string', 'description': 'Field path, e.g. country or address.city.'},
    'filter': _mgFilter,
  }, required: ['collection', 'field']),
  _mg('mongodb_aggregate', 'Running an aggregation',
      'Runs an aggregation pipeline (\$match, \$group, \$lookup, \$facet, \$bucket…) and returns its results. Read-only: pipelines that write '
          '(\$out, \$merge) use mongodb_aggregate_write. Results with numbers per group are drawn as a chart.', {
        'collection': _mgColl,
        'database': _mgDb,
        'pipeline': _mgPipeline,
        'limit': {'type': 'integer', 'description': 'Results to return, 1-500, default 50.'},
      }, required: ['collection', 'pipeline']),
  _mg('mongodb_schema', 'Inferring a schema',
      'Samples documents and reports every field with its types and how often it is present. Use before writing queries on an unfamiliar collection.', {
        'collection': _mgColl,
        'database': _mgDb,
        'sample': {'type': 'integer', 'description': 'Documents to sample, 10-1000, default 200.'},
      }, required: ['collection']),
  _mg('mongodb_indexes', 'Listing indexes', 'A collection\'s indexes: keys, unique, TTL, partial filters, size and how often each is used.', {
    'collection': _mgColl,
    'database': _mgDb,
  }, required: ['collection']),
  _mg('mongodb_stats', 'Reading storage stats', 'Storage statistics of a database, or with collection, of that collection: documents, data, storage and index sizes.', {
    'database': _mgDb,
    'collection': {'type': 'string', 'description': 'One collection. Empty: the whole database.'},
  }),
  _mg('mongodb_explain', 'Explaining a query',
      'How MongoDB runs a find or aggregation: the plan (index scan or collection scan), keys and documents examined, time. Use to speed up slow queries.', {
        'collection': _mgColl,
        'database': _mgDb,
        'filter': _mgFilter,
        'sort': {'type': 'object', 'description': 'Sort of the find to explain.'},
        'pipeline': {'type': 'array', 'items': {'type': 'object', 'description': 'A stage.'}, 'description': 'Explain this pipeline instead of a find.'},
      }, required: ['collection']),
  _mg('mongodb_server_status', 'Reading server status',
      'Live server health: connections, operations per type, memory, network, uptime and replication role. Needs the clusterMonitor role on Atlas.', {}),
  _mg('mongodb_current_ops', 'Listing running operations', 'Operations running now (long queries, index builds) with how long they have run.', {
    'min_seconds': {'type': 'integer', 'description': 'Only operations running at least this long. Default 0.'},
  }),
  _mg('mongodb_users', 'Listing database users', 'Users defined on a database and their roles.', {'database': _mgDb}),
  _mg('mongodb_export', 'Exporting documents',
      'Saves matching documents to a JSON (Extended JSON array) or CSV file in this conversation, up to 20,000. The user can open or send it.', {
        'collection': _mgColl,
        'database': _mgDb,
        'filter': _mgFilter,
        'projection': {'type': 'object', 'description': 'Fields to include or exclude.'},
        'sort': {'type': 'object', 'description': 'Sort order.'},
        'format': {'type': 'string', 'enum': ['json', 'csv'], 'description': 'File format. Default json.'},
        'limit': {'type': 'integer', 'description': '1-20000, default 5000.'},
      }, required: ['collection']),
  _mg('mongodb_run_read_command', 'Running a read command',
      'Runs a database command that only reads (e.g. {"dbStats": 1}, {"collStats": "x"}, {"hostInfo": 1}, {"getParameter": "*"}, {"listCollections": 1}, '
          '{"validate": "x"} is not allowed). Commands that change anything use mongodb_run_command.', {
        'command': {'type': 'object', 'description': 'The command document, e.g. {"buildInfo": 1}.'},
        'database': _mgDb,
      }, required: ['command']),

  // ---- changes -------------------------------------------------------------------
  _mg('mongodb_insert', 'Inserting documents', 'Inserts one or more documents. They approve first.', {
    'collection': _mgColl,
    'database': _mgDb,
    'documents': {'type': 'array', 'items': {'type': 'object', 'description': 'A document.'}, 'description': 'Documents to insert (up to 1000).'},
  }, required: ['collection', 'documents'], change: true),
  _mg('mongodb_update', 'Updating documents',
      'Updates the first or every document matching a filter with update operators (\$set, \$inc, \$push, \$unset…) or a pipeline. They approve first.', {
        'collection': _mgColl,
        'database': _mgDb,
        'filter': _mgFilter,
        'update': {'type': 'object', 'description': 'Update operators, e.g. {"\$set": {"status": "done"}}.'},
        'pipeline': {'type': 'array', 'items': {'type': 'object', 'description': 'A stage.'}, 'description': 'An update pipeline instead of update.'},
        'many': {'type': 'boolean', 'description': 'Every matching document; default only the first.'},
        'upsert': {'type': 'boolean', 'description': 'Insert one when nothing matches.'},
        'array_filters': {'type': 'array', 'items': {'type': 'object', 'description': 'A filter for \$[identifier].'}, 'description': 'Filters for positional array updates.'},
      }, required: ['collection', 'filter'], change: true),
  _mg('mongodb_replace', 'Replacing a document', 'Replaces the first document matching a filter with a new one (keeping its _id). They approve first.', {
    'collection': _mgColl,
    'database': _mgDb,
    'filter': _mgFilter,
    'replacement': {'type': 'object', 'description': 'The whole new document, without update operators.'},
    'upsert': {'type': 'boolean', 'description': 'Insert it when nothing matches.'},
  }, required: ['collection', 'filter', 'replacement'], change: true),
  _mg('mongodb_find_and_modify', 'Updating and returning a document', 'Updates one document and returns it, before or after the change. They approve first.', {
    'collection': _mgColl,
    'database': _mgDb,
    'filter': _mgFilter,
    'update': {'type': 'object', 'description': 'Update operators.'},
    'sort': {'type': 'object', 'description': 'Which document first when several match.'},
    'return_new': {'type': 'boolean', 'description': 'Return the document after the change. Default true.'},
    'upsert': {'type': 'boolean', 'description': 'Insert when nothing matches.'},
  }, required: ['collection', 'filter', 'update'], change: true),
  _mg('mongodb_import', 'Importing documents',
      'Inserts the records of a file in this conversation: a JSON array, JSON lines (one document per line) or CSV with a header row. They approve first.', {
        'collection': _mgColl,
        'database': _mgDb,
        'file': {'type': 'string', 'description': 'A file of this conversation (.json, .jsonl, .ndjson or .csv).'},
      }, required: ['collection', 'file'], change: true),
  _mg('mongodb_create_collection', 'Creating a collection',
      'Creates a collection: plain, capped, time series, with a JSON Schema validator, or a view over a pipeline. They approve first.', {
        'collection': _mgColl,
        'database': _mgDb,
        'capped': {'type': 'boolean', 'description': 'A fixed-size collection.'},
        'size': {'type': 'integer', 'description': 'Capped: maximum bytes.'},
        'max': {'type': 'integer', 'description': 'Capped: maximum documents.'},
        'validator': {'type': 'object', 'description': 'Validation rules, e.g. {"\$jsonSchema": {…}}.'},
        'timeseries': {'type': 'object', 'description': 'Time series options, e.g. {"timeField": "ts", "metaField": "sensor", "granularity": "minutes"}.'},
        'expire_after_seconds': {'type': 'integer', 'description': 'Time series: delete documents older than this.'},
        'view_on': {'type': 'string', 'description': 'Make a view over this collection instead.'},
        'pipeline': {'type': 'array', 'items': {'type': 'object', 'description': 'A stage.'}, 'description': 'The view\'s pipeline.'},
      }, required: ['collection'], change: true),
  _mg('mongodb_create_index', 'Creating an index', 'Creates an index: single, compound, text, 2dsphere, hashed, unique, sparse, TTL or partial. They approve first.', {
    'collection': _mgColl,
    'database': _mgDb,
    'keys': {'type': 'object', 'description': 'Index keys, e.g. {"email": 1} or {"title": "text"}.'},
    'name': {'type': 'string', 'description': 'Index name. Default generated.'},
    'unique': {'type': 'boolean', 'description': 'Reject duplicate values.'},
    'sparse': {'type': 'boolean', 'description': 'Skip documents without the field.'},
    'expire_after_seconds': {'type': 'integer', 'description': 'TTL: delete documents this long after the date in the field.'},
    'partial_filter': {'type': 'object', 'description': 'Only index documents matching this.'},
  }, required: ['collection', 'keys'], change: true),
  _mg('mongodb_rename_collection', 'Renaming a collection', 'Renames a collection (apps using the old name stop finding it). They approve first.', {
    'collection': _mgColl,
    'database': _mgDb,
    'to': {'type': 'string', 'description': 'The new name.'},
  }, required: ['collection', 'to'], change: true),

  // ---- destructive ---------------------------------------------------------------
  _mg('mongodb_delete', 'Deleting documents', 'Deletes the first or every document matching a filter. An empty filter needs all: true. Can\'t be undone.', {
    'collection': _mgColl,
    'database': _mgDb,
    'filter': _mgFilter,
    'many': {'type': 'boolean', 'description': 'Every matching document; default only the first.'},
    'all': {'type': 'boolean', 'description': 'Confirms an empty filter: delete every document.'},
  }, required: ['collection', 'filter'], destructive: true),
  _mg('mongodb_aggregate_write', 'Writing an aggregation\'s output',
      'Runs a pipeline that ends in \$out (replaces the target collection) or \$merge (merges into it).', {
        'collection': _mgColl,
        'database': _mgDb,
        'pipeline': _mgPipeline,
      }, required: ['collection', 'pipeline'], destructive: true),
  _mg('mongodb_drop_index', 'Dropping an index', 'Drops an index by name (from mongodb_indexes). Queries using it get slower.', {
    'collection': _mgColl,
    'database': _mgDb,
    'name': {'type': 'string', 'description': 'Index name.'},
  }, required: ['collection', 'name'], destructive: true),
  _mg('mongodb_drop_collection', 'Dropping a collection', 'Drops a collection with all its documents and indexes. Can\'t be undone.', {
    'collection': _mgColl,
    'database': _mgDb,
  }, required: ['collection'], destructive: true),
  _mg('mongodb_drop_database', 'Dropping a database', 'Drops a whole database. Can\'t be undone.', {
    'database': {'type': 'string', 'description': 'The database to drop. Required: never the default by accident.'},
  }, required: ['database'], destructive: true),
  _mg('mongodb_kill_op', 'Stopping an operation', 'Stops a running operation (opid from mongodb_current_ops).', {
    'opid': {'type': 'string', 'description': 'Operation id.'},
  }, required: ['opid'], destructive: true),
  _mg('mongodb_run_command', 'Running a database command',
      'Runs any database command (bulk writes, collMod, compact, user and role management, admin commands…). Always asks first.', {
        'command': {'type': 'object', 'description': 'The command document, e.g. {"collMod": "users", "validator": {…}}.'},
        'database': _mgDb,
      }, required: ['command'], destructive: true),
];

final _mongoToolNames = {for (final t in _mongoTools) t.name};

const _mongoPolicies = <String, ToolPolicy>{
  'mongodb_overview': ToolPolicy(ToolAccess.read),
  'mongodb_collections': ToolPolicy(ToolAccess.read),
  'mongodb_find': ToolPolicy(ToolAccess.read),
  'mongodb_count': ToolPolicy(ToolAccess.read),
  'mongodb_distinct': ToolPolicy(ToolAccess.read),
  'mongodb_aggregate': ToolPolicy(ToolAccess.read),
  'mongodb_schema': ToolPolicy(ToolAccess.read),
  'mongodb_indexes': ToolPolicy(ToolAccess.read),
  'mongodb_stats': ToolPolicy(ToolAccess.read),
  'mongodb_explain': ToolPolicy(ToolAccess.read),
  'mongodb_server_status': ToolPolicy(ToolAccess.read),
  'mongodb_current_ops': ToolPolicy(ToolAccess.read),
  'mongodb_users': ToolPolicy(ToolAccess.read),
  'mongodb_export': ToolPolicy(ToolAccess.read),
  'mongodb_run_read_command': ToolPolicy(ToolAccess.read),
  'mongodb_insert': ToolPolicy(ToolAccess.modify),
  'mongodb_update': ToolPolicy(ToolAccess.modify),
  'mongodb_replace': ToolPolicy(ToolAccess.modify),
  'mongodb_find_and_modify': ToolPolicy(ToolAccess.modify),
  'mongodb_import': ToolPolicy(ToolAccess.modify),
  'mongodb_create_collection': ToolPolicy(ToolAccess.modify),
  'mongodb_create_index': ToolPolicy(ToolAccess.modify),
  'mongodb_rename_collection': ToolPolicy(ToolAccess.modify),
  'mongodb_delete': ToolPolicy(ToolAccess.destructive),
  'mongodb_aggregate_write': ToolPolicy(ToolAccess.destructive),
  'mongodb_drop_index': ToolPolicy(ToolAccess.destructive),
  'mongodb_drop_collection': ToolPolicy(ToolAccess.destructive),
  'mongodb_drop_database': ToolPolicy(ToolAccess.destructive),
  'mongodb_kill_op': ToolPolicy(ToolAccess.destructive),
  'mongodb_run_command': ToolPolicy(ToolAccess.destructive),
};

const _mongoReferences = <String, ToolReference>{
  'mongodb_overview': ToolReference(['dev', 'server: version, host, topology, uptime', 'databases: name, size, empty, collections', 'default_database']),
  'mongodb_collections': ToolReference(['dev', 'database', 'collections: name, type, count, size, storage, indexes, capped']),
  'mongodb_find': ToolReference(['dev', 'database', 'collection', 'filter', 'documents', 'count', 'skip', 'more'], limits: ['Up to 200 documents; long strings are cut at 2,000 characters.']),
  'mongodb_count': ToolReference(['dev', 'database', 'collection', 'filter', 'count']),
  'mongodb_distinct': ToolReference(['dev', 'database', 'collection', 'field', 'values', 'count']),
  'mongodb_aggregate': ToolReference(['dev', 'database', 'collection', 'pipeline', 'documents', 'more']),
  'mongodb_schema': ToolReference(['dev', 'database', 'collection', 'sampled', 'fields: field, types, present, example']),
  'mongodb_indexes': ToolReference(['dev', 'database', 'collection', 'indexes: name, keys, unique, sparse, ttl, partial, size, uses']),
  'mongodb_stats': ToolReference(['dev', 'database', 'collection', 'stats']),
  'mongodb_explain': ToolReference(['dev', 'database', 'collection', 'plan', 'stages', 'keys_examined', 'docs_examined', 'returned', 'ms', 'index']),
  'mongodb_server_status': ToolReference(['dev', 'status']),
  'mongodb_current_ops': ToolReference(['dev', 'ops: opid, op, ns, secs, desc, client']),
  'mongodb_users': ToolReference(['dev', 'database', 'users: user, roles']),
  'mongodb_export': ToolReference(['dev', 'exported', 'format', 'created_files'], limits: ['Up to 20,000 documents.']),
  'mongodb_run_read_command': ToolReference(['dev', 'database', 'result']),
  'mongodb_insert': ToolReference(['dev', 'done', 'inserted', 'ids']),
  'mongodb_update': ToolReference(['dev', 'done', 'matched', 'modified', 'upserted']),
  'mongodb_replace': ToolReference(['dev', 'done', 'matched', 'modified', 'upserted']),
  'mongodb_find_and_modify': ToolReference(['dev', 'done', 'document']),
  'mongodb_import': ToolReference(['dev', 'done', 'inserted', 'skipped']),
  'mongodb_create_collection': ToolReference(['dev', 'done', 'created']),
  'mongodb_create_index': ToolReference(['dev', 'done', 'index']),
  'mongodb_rename_collection': ToolReference(['dev', 'done', 'renamed']),
  'mongodb_delete': ToolReference(['dev', 'deleted']),
  'mongodb_aggregate_write': ToolReference(['dev', 'done', 'target']),
  'mongodb_drop_index': ToolReference(['dev', 'deleted']),
  'mongodb_drop_collection': ToolReference(['dev', 'deleted']),
  'mongodb_drop_database': ToolReference(['dev', 'deleted']),
  'mongodb_kill_op': ToolReference(['dev', 'done']),
  'mongodb_run_command': ToolReference(['dev', 'database', 'result']),
};

/// Commands mongodb_run_read_command accepts: they only read.
const mongoReadCommands = {
  'find', 'aggregate', 'count', 'distinct', 'listcollections', 'listindexes', 'listdatabases', 'dbstats', 'collstats', 'datasize',
  'serverstatus', 'hostinfo', 'buildinfo', 'hello', 'ismaster', 'ping', 'connectionstatus', 'usersinfo', 'rolesinfo', 'getparameter',
  'currentop', 'top', 'explain', 'getlog', 'replsetgetstatus', 'replsetgetconfig', 'getcmdlineopts', 'features', 'listcommands',
  'getdefaultrwconcern', 'dbhash', 'connpoolstats', 'shardingstate', 'whatsmyuri', 'lockinfo', 'getmore',
};

/// Cuts long strings in [v] so a page of documents stays readable.
Object? _mgTrim(Object? v, {int max = 2000}) {
  if (v is String) return v.length > max ? '${v.substring(0, max)}…' : v;
  if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': _mgTrim(e.value, max: max)};
  if (v is List) return [for (final x in v.take(200)) _mgTrim(x, max: max)];
  return v;
}

Object? _mgNum(Object? v) => v is Map && v[r'$numberLong'] != null ? int.tryParse('${v[r'$numberLong']}') : (v is Map && v[r'$numberDouble'] != null ? double.tryParse('${v[r'$numberDouble']}') : v);

extension _MongoToolRuns on TelegramToolRunner {
  Future<ToolOutput>? _runMongo(String name, Map<String, dynamic> a) {
    if (!_mongoToolNames.contains(name)) return null;
    return _mongo(name, a);
  }

  String _ma(Map<String, dynamic> a, String k) => '${a[k] ?? ''}'.trim();

  String get _mgDefaultDb {
    if (_settings.mongoDatabase.isNotEmpty) return _settings.mongoDatabase;
    return MongoSession.databaseIn(_settings.mongoUri) ?? 'test';
  }

  Map<String, dynamic>? _mgMap(Map<String, dynamic> a, String k) {
    final v = MongoSession.parse(a[k], what: k);
    if (v == null) return null;
    if (v is! Map) throw MongoProblem('$k must be a JSON object.');
    return Map<String, dynamic>.from(v);
  }

  List<Map<String, dynamic>>? _mgArray(Map<String, dynamic> a, String k) {
    final v = MongoSession.parse(a[k], what: k);
    if (v == null) return null;
    final list = v is Map ? [v] : v;
    if (list is! List) throw MongoProblem('$k must be a JSON array.');
    return [for (final x in list) if (x is Map) Map<String, dynamic>.from(x) else throw MongoProblem('Every item of $k must be an object.')];
  }

  Future<ToolOutput> _mongo(String name, Map<String, dynamic> a) async {
    if (!_settings.hasMongoUri) {
      return const ToolOutput({'error': 'No MongoDB connection string. The user can add one in Settings → Development → MongoDB.'});
    }
    final s = MongoSession.instance;
    final uri = _settings.mongoUri;
    final db = _ma(a, 'database').isEmpty ? _mgDefaultDb : _ma(a, 'database');
    final coll = _ma(a, 'collection');
    Future<Map<String, dynamic>> cmd(Map<String, dynamic> c, {String? on}) => s.command(uri, on ?? db, c);
    Map<String, dynamic> out(Map<String, dynamic> m) => {'dev': 'mongodb', ...m};
    int n(String k, int fallback, int max, {int min = 1}) => TelegramToolRunner._int(a, k, fallback: fallback, min: min, max: max);
    try {
      switch (name) {
        case 'mongodb_overview':
          final results = await Future.wait([
            cmd({'buildInfo': 1}, on: 'admin'),
            cmd({'hello': 1}, on: 'admin'),
            cmd({'listDatabases': 1, 'nameOnly': false, 'authorizedDatabases': true}, on: 'admin').catchError((Object e) => <String, dynamic>{'error': '$e'}),
          ]);
          final hello = results[1];
          s.lastHello = hello;
          final dbs = [
            for (final d in (results[2]['databases'] as List? ?? const []).whereType<Map>())
              {'name': d['name'], 'size': _mgNum(d['sizeOnDisk']), 'empty': d['empty']},
          ];
          return ToolOutput(out({
            'server': {
              'version': results[0]['version'],
              'host': MongoSession.hostsOf(uri),
              'topology': hello['setName'] != null ? 'replica set ${hello['setName']}' : (hello['msg'] == 'isdbgrid' ? 'sharded cluster' : 'standalone'),
              'primary': ?hello['primary'],
              'read_only': ?hello['readOnly'],
              'max_wire_version': ?hello['maxWireVersion'],
            },
            'databases': dbs,
            'total_size': ?_mgNum(results[2]['totalSize']),
            'default_database': _mgDefaultDb,
            if (results[2]['error'] != null) 'note': 'Listing databases needs more rights: ${results[2]['error']}',
          }));
        case 'mongodb_collections':
          final list = await s.cursor(uri, db, {'listCollections': 1, 'cursor': <String, dynamic>{}}, limit: 500);
          final rows = <Map<String, dynamic>>[];
          for (final c in list.docs) {
            final row = <String, dynamic>{'name': c['name'], 'type': c['type'], 'capped': ?((c['options'] as Map?)?['capped'])};
            if (c['type'] == 'collection' && rows.length < 60) {
              try {
                final st = await s.cursor(uri, db, {'aggregate': c['name'], 'pipeline': [{r'$collStats': {'storageStats': <String, dynamic>{}, 'count': <String, dynamic>{}}}], 'cursor': <String, dynamic>{}}, limit: 1);
                final ss = st.docs.isEmpty ? const {} : (st.docs.first['storageStats'] as Map? ?? const {});
                row['count'] = _mgNum(ss['count']);
                row['size'] = _mgNum(ss['size']);
                row['storage'] = _mgNum(ss['storageSize']);
                row['indexes'] = _mgNum(ss['nindexes']);
              } catch (_) {
                try {
                  row['count'] = _mgNum((await cmd({'count': c['name']}))['n']);
                } catch (_) {}
              }
            }
            rows.add(row);
          }
          rows.sort((x, y) => '${x['name']}'.compareTo('${y['name']}'));
          return ToolOutput(out({'database': db, 'collections': rows}));
        case 'mongodb_find':
          final filter = _mgMap(a, 'filter') ?? <String, dynamic>{};
          final limit = n('limit', 20, 200);
          final skip = n('skip', 0, 1 << 30, min: 0);
          final r = await s.cursor(uri, db, {
            'find': coll,
            'filter': filter,
            'projection': ?_mgMap(a, 'projection'),
            'sort': ?_mgMap(a, 'sort'),
            if (skip > 0) 'skip': skip,
            'limit': limit + 1,
            'batchSize': limit + 1,
          }, limit: limit + 1);
          final more = r.docs.length > limit;
          return ToolOutput(out({
            'database': db,
            'collection': coll,
            'filter': filter,
            'sort': ?_mgMap(a, 'sort'),
            'projection': ?_mgMap(a, 'projection'),
            'skip': skip,
            'documents': [for (final d in r.docs.take(limit)) _mgTrim(d)],
            'more': more,
          }));
        case 'mongodb_count':
          final filter = _mgMap(a, 'filter') ?? <String, dynamic>{};
          final r = await cmd({'count': coll, 'query': filter});
          return ToolOutput(out({'database': db, 'collection': coll, 'filter': filter, 'count': _mgNum(r['n'])}));
        case 'mongodb_distinct':
          final r = await cmd({'distinct': coll, 'key': _ma(a, 'field'), 'query': _mgMap(a, 'filter') ?? <String, dynamic>{}});
          final values = r['values'] as List? ?? const [];
          return ToolOutput(out({'database': db, 'collection': coll, 'field': _ma(a, 'field'), 'count': values.length, 'values': _mgTrim(values.take(500).toList(), max: 300)}));
        case 'mongodb_aggregate':
          final pipeline = _mgArray(a, 'pipeline') ?? const [];
          if (pipeline.any((st) => st.containsKey(r'$out') || st.containsKey(r'$merge'))) {
            return ToolOutput(out({'error': 'This pipeline writes (\$out/\$merge). Use mongodb_aggregate_write, which asks first.'}));
          }
          final limit = n('limit', 50, 500);
          final r = await s.cursor(uri, db, {'aggregate': coll, 'pipeline': pipeline, 'cursor': {'batchSize': limit}, 'allowDiskUse': true}, limit: limit);
          return ToolOutput(out({'database': db, 'collection': coll, 'pipeline': pipeline, 'documents': [for (final d in r.docs) _mgTrim(d)], 'more': r.more}));
        case 'mongodb_schema':
          final size = n('sample', 200, 1000, min: 10);
          final r = await s.cursor(uri, db, {'aggregate': coll, 'pipeline': [{r'$sample': {'size': size}}], 'cursor': <String, dynamic>{}}, limit: size);
          return ToolOutput(out({'database': db, 'collection': coll, 'sampled': r.docs.length, 'fields': inferSchema(r.docs)}));
        case 'mongodb_indexes':
          final r = await s.cursor(uri, db, {'listIndexes': coll, 'cursor': <String, dynamic>{}}, limit: 200);
          final uses = <String, Object?>{};
          try {
            final st = await s.cursor(uri, db, {'aggregate': coll, 'pipeline': [{r'$indexStats': <String, dynamic>{}}], 'cursor': <String, dynamic>{}}, limit: 200);
            for (final x in st.docs) {
              uses['${x['name']}'] = _mgNum((x['accesses'] as Map?)?['ops']);
            }
          } catch (_) {}
          Map sizes = const {};
          try {
            sizes = (await cmd({'collStats': coll}))['indexSizes'] as Map? ?? const {};
          } catch (_) {}
          return ToolOutput(out({
            'database': db,
            'collection': coll,
            'indexes': [
              for (final i in r.docs)
                {
                  'name': i['name'],
                  'keys': i['key'],
                  'unique': ?i['unique'],
                  'sparse': ?i['sparse'],
                  'ttl': ?_mgNum(i['expireAfterSeconds']),
                  'partial': ?i['partialFilterExpression'],
                  'size': ?_mgNum(sizes[i['name']]),
                  'uses': ?uses[i['name']],
                },
            ],
          }));
        case 'mongodb_stats':
          final r = coll.isEmpty ? await cmd({'dbStats': 1, 'scale': 1}) : await cmd({'collStats': coll, 'scale': 1});
          const keep = ['db', 'ns', 'collections', 'views', 'objects', 'count', 'avgObjSize', 'dataSize', 'size', 'storageSize', 'indexes', 'nindexes', 'indexSize', 'totalIndexSize', 'totalSize', 'fsUsedSize', 'fsTotalSize', 'capped', 'indexSizes'];
          return ToolOutput(out({'database': db, 'collection': ?(coll.isEmpty ? null : coll), 'stats': {for (final k in keep) if (r[k] != null) k: _mgNum(r[k])}}));
        case 'mongodb_explain':
          final pipeline = _mgArray(a, 'pipeline');
          final inner = pipeline != null && pipeline.isNotEmpty
              ? {'aggregate': coll, 'pipeline': pipeline, 'cursor': <String, dynamic>{}}
              : {'find': coll, 'filter': _mgMap(a, 'filter') ?? <String, dynamic>{}, 'sort': ?_mgMap(a, 'sort')};
          final r = await cmd({'explain': inner, 'verbosity': 'executionStats'});
          return ToolOutput(out({'database': db, 'collection': coll, ..._mgExplain(r)}));
        case 'mongodb_server_status':
          final r = await cmd({'serverStatus': 1}, on: 'admin');
          final conn = r['connections'] as Map? ?? const {};
          final mem = r['mem'] as Map? ?? const {};
          final net = r['network'] as Map? ?? const {};
          final repl = r['repl'] as Map? ?? const {};
          return ToolOutput(out({
            'status': {
              'host': r['host'],
              'version': r['version'],
              'uptime_seconds': _mgNum(r['uptime']),
              'connections': {'current': _mgNum(conn['current']), 'available': _mgNum(conn['available']), 'total_created': _mgNum(conn['totalCreated'])},
              'opcounters': {for (final e in ((r['opcounters'] as Map?) ?? const {}).entries) '${e.key}': _mgNum(e.value)},
              'memory_mb': {'resident': _mgNum(mem['resident']), 'virtual': _mgNum(mem['virtual'])},
              'network_bytes': {'in': _mgNum(net['bytesIn']), 'out': _mgNum(net['bytesOut']), 'requests': _mgNum(net['numRequests'])},
              if (repl.isNotEmpty) 'replication': {'set': repl['setName'], 'primary': repl['primary'], 'is_primary': repl['isWritablePrimary'] ?? repl['ismaster']},
            },
          }));
        case 'mongodb_current_ops':
          final min = n('min_seconds', 0, 86400, min: 0);
          final r = await cmd({'currentOp': 1, 'active': true, if (min > 0) 'secs_running': {r'$gte': min}}, on: 'admin');
          return ToolOutput(out({
            'ops': [
              for (final o in (r['inprog'] as List? ?? const []).whereType<Map>().take(100))
                {'opid': '${_mgNum(o['opid'])}', 'op': o['op'], 'ns': o['ns'], 'secs': _mgNum(o['secs_running']), 'desc': o['desc'], 'client': ?o['client']},
            ],
          }));
        case 'mongodb_users':
          final r = await cmd({'usersInfo': 1});
          return ToolOutput(out({
            'database': db,
            'users': [
              for (final u in (r['users'] as List? ?? const []).whereType<Map>())
                {'user': u['user'], 'roles': [for (final role in (u['roles'] as List? ?? const []).whereType<Map>()) '${role['role']}@${role['db']}']},
            ],
          }));
        case 'mongodb_export':
          final limit = n('limit', 5000, 20000);
          final r = await s.cursor(uri, db, {
            'find': coll,
            'filter': _mgMap(a, 'filter') ?? <String, dynamic>{},
            'projection': ?_mgMap(a, 'projection'),
            'sort': ?_mgMap(a, 'sort'),
            'limit': limit,
            'batchSize': 1000,
          }, limit: limit);
          final csv = _ma(a, 'format') == 'csv';
          final text = csv ? _mgCsv(r.docs) : const JsonEncoder.withIndent('  ').convert(r.docs);
          final file = await saveGeneratedBytes('$coll.${csv ? 'csv' : 'json'}', utf8.encode(text), folder: 'downloads');
          return ToolOutput(out({'database': db, 'collection': coll, 'exported': r.docs.length, 'format': csv ? 'csv' : 'json', 'created_files': [file.path], if (r.more) 'note': 'Stopped at $limit documents.'}));
        case 'mongodb_run_read_command':
          final c = _mgMap(a, 'command');
          if (c == null || c.isEmpty) return ToolOutput(out({'error': 'Give the command.'}));
          final verb = c.keys.first.toLowerCase();
          if (!mongoReadCommands.contains(verb)) {
            return ToolOutput(out({'error': '"${c.keys.first}" may change data. Use mongodb_run_command, which asks first.'}));
          }
          if (verb == 'aggregate' && '${c['pipeline']}'.contains(RegExp(r'\$out|\$merge'))) {
            return ToolOutput(out({'error': 'This pipeline writes. Use mongodb_aggregate_write.'}));
          }
          final r = await cmd(c);
          final text = jsonEncode(r);
          return ToolOutput(out({'database': db, 'result': text.length > 14000 ? '${text.substring(0, 14000)}…' : r}));

        // ---- changes ---------------------------------------------------------------
        case 'mongodb_insert':
          final docs = _mgArray(a, 'documents') ?? const [];
          if (docs.isEmpty) return ToolOutput(out({'error': 'Give documents to insert.'}));
          if (docs.length > 1000) return ToolOutput(out({'error': 'Up to 1000 documents per call.'}));
          // Ids made here, so the result can say what was inserted.
          final withIds = [for (final d in docs) d.containsKey('_id') ? d : {'_id': {r'$oid': _mgNewId()}, ...d}];
          final r = await cmd({'insert': coll, 'documents': withIds, 'ordered': true});
          return ToolOutput(out({'done': true, 'database': db, 'collection': coll, 'inserted': _mgNum(r['n']), 'ids': [for (final d in withIds.take(50)) d['_id']]}));
        case 'mongodb_update':
          final pipeline = _mgArray(a, 'pipeline');
          final update = pipeline ?? _mgMap(a, 'update');
          if (update == null) return ToolOutput(out({'error': 'Give update (operators) or pipeline.'}));
          if (update is Map && update.keys.any((k) => !k.startsWith(r'$'))) {
            return ToolOutput(out({'error': 'update needs operators like {"\$set": {…}}. To replace a whole document use mongodb_replace.'}));
          }
          final r = await cmd({
            'update': coll,
            'updates': [
              {
                'q': _mgMap(a, 'filter') ?? <String, dynamic>{},
                'u': update,
                'multi': a['many'] == true,
                'upsert': a['upsert'] == true,
                'arrayFilters': ?_mgArray(a, 'array_filters'),
              },
            ],
          });
          return ToolOutput(out(_mgWrite(r, db, coll)));
        case 'mongodb_replace':
          final doc = _mgMap(a, 'replacement');
          if (doc == null || doc.keys.any((k) => k.startsWith(r'$'))) return ToolOutput(out({'error': 'replacement must be a whole document without operators.'}));
          final r = await cmd({
            'update': coll,
            'updates': [
              {'q': _mgMap(a, 'filter') ?? <String, dynamic>{}, 'u': doc, 'multi': false, 'upsert': a['upsert'] == true},
            ],
          });
          return ToolOutput(out(_mgWrite(r, db, coll)));
        case 'mongodb_find_and_modify':
          final r = await cmd({
            'findAndModify': coll,
            'query': _mgMap(a, 'filter') ?? <String, dynamic>{},
            'update': _mgMap(a, 'update') ?? <String, dynamic>{},
            'sort': ?_mgMap(a, 'sort'),
            'new': a['return_new'] != false,
            'upsert': a['upsert'] == true,
          });
          return ToolOutput(out({'done': true, 'database': db, 'collection': coll, 'document': _mgTrim(r['value']), 'matched': (r['lastErrorObject'] as Map?)?['n']}));
        case 'mongodb_import':
          final file = File(_ma(a, 'file'));
          if (!file.existsSync()) return ToolOutput(out({'error': 'No file "${_ma(a, 'file')}" in this conversation.'}));
          final docs = _mgReadRecords(await file.readAsString(), file.path);
          if (docs.isEmpty) return ToolOutput(out({'error': 'No records found in the file.'}));
          var inserted = 0;
          for (var i = 0; i < docs.length; i += 1000) {
            final batch = docs.sublist(i, (i + 1000).clamp(0, docs.length));
            final r = await cmd({'insert': coll, 'documents': batch, 'ordered': false});
            inserted += (_mgNum(r['n']) as int?) ?? 0;
          }
          return ToolOutput(out({'done': true, 'database': db, 'collection': coll, 'inserted': inserted, 'skipped': docs.length - inserted}));
        case 'mongodb_create_collection':
          final viewOn = _ma(a, 'view_on');
          final r = await cmd({
            'create': coll,
            if (viewOn.isNotEmpty) ...{'viewOn': viewOn, 'pipeline': _mgArray(a, 'pipeline') ?? const []},
            if (a['capped'] == true) ...{'capped': true, 'size': n('size', 1 << 20, 1 << 40, min: 4096), if (a['max'] is num) 'max': (a['max'] as num).toInt()},
            'validator': ?_mgMap(a, 'validator'),
            'timeseries': ?_mgMap(a, 'timeseries'),
            if (a['expire_after_seconds'] is num) 'expireAfterSeconds': (a['expire_after_seconds'] as num).toInt(),
          });
          return ToolOutput(out({'done': r['ok'] != null, 'database': db, 'created': coll, 'view_on': ?(viewOn.isEmpty ? null : viewOn)}));
        case 'mongodb_create_index':
          final keys = _mgMap(a, 'keys');
          if (keys == null || keys.isEmpty) return ToolOutput(out({'error': 'Give keys, e.g. {"email": 1}.'}));
          final idxName = _ma(a, 'name').isNotEmpty ? _ma(a, 'name') : [for (final e in keys.entries) '${e.key}_${e.value}'].join('_');
          await cmd({
            'createIndexes': coll,
            'indexes': [
              {
                'key': keys,
                'name': idxName,
                if (a['unique'] == true) 'unique': true,
                if (a['sparse'] == true) 'sparse': true,
                if (a['expire_after_seconds'] is num) 'expireAfterSeconds': (a['expire_after_seconds'] as num).toInt(),
                'partialFilterExpression': ?_mgMap(a, 'partial_filter'),
              },
            ],
          });
          return ToolOutput(out({'done': true, 'database': db, 'collection': coll, 'index': idxName}));
        case 'mongodb_rename_collection':
          await cmd({'renameCollection': '$db.$coll', 'to': '$db.${_ma(a, 'to')}', 'dropTarget': false}, on: 'admin');
          return ToolOutput(out({'done': true, 'database': db, 'renamed': '$coll → ${_ma(a, 'to')}'}));

        // ---- destructive -----------------------------------------------------------
        case 'mongodb_delete':
          final filter = _mgMap(a, 'filter') ?? <String, dynamic>{};
          if (filter.isEmpty && a['all'] != true) return ToolOutput(out({'error': 'The filter is empty. Pass all: true to delete every document.'}));
          final r = await cmd({
            'delete': coll,
            'deletes': [
              {'q': filter, 'limit': a['many'] == true || a['all'] == true ? 0 : 1},
            ],
          });
          return ToolOutput(out({'database': db, 'collection': coll, 'deleted': _mgNum(r['n'])}));
        case 'mongodb_aggregate_write':
          final pipeline = _mgArray(a, 'pipeline') ?? const [];
          final last = pipeline.isEmpty ? const <String, dynamic>{} : pipeline.last;
          if (!last.containsKey(r'$out') && !last.containsKey(r'$merge')) {
            return ToolOutput(out({'error': 'The last stage must be \$out or \$merge; for reading use mongodb_aggregate.'}));
          }
          await cmd({'aggregate': coll, 'pipeline': pipeline, 'cursor': <String, dynamic>{}, 'allowDiskUse': true});
          return ToolOutput(out({'done': true, 'database': db, 'collection': coll, 'target': last[r'$out'] ?? last[r'$merge']}));
        case 'mongodb_drop_index':
          await cmd({'dropIndexes': coll, 'index': _ma(a, 'name')});
          return ToolOutput(out({'database': db, 'collection': coll, 'deleted': _ma(a, 'name')}));
        case 'mongodb_drop_collection':
          await cmd({'drop': coll});
          return ToolOutput(out({'database': db, 'deleted': coll}));
        case 'mongodb_drop_database':
          final target = _ma(a, 'database');
          if (target.isEmpty) return ToolOutput(out({'error': 'Name the database to drop.'}));
          await cmd({'dropDatabase': 1}, on: target);
          return ToolOutput(out({'deleted': target}));
        case 'mongodb_kill_op':
          final id = _ma(a, 'opid');
          await cmd({'killOp': 1, 'op': int.tryParse(id) ?? id}, on: 'admin');
          return ToolOutput(out({'done': true, 'opid': id}));
        case 'mongodb_run_command':
          final c = _mgMap(a, 'command');
          if (c == null || c.isEmpty) return ToolOutput(out({'error': 'Give the command.'}));
          final r = await cmd(c);
          final text = jsonEncode(r);
          return ToolOutput(out({'database': db, 'result': text.length > 12000 ? '${text.substring(0, 12000)}…' : r}));
      }
    } on MongoProblem catch (e) {
      return ToolOutput({'dev': 'mongodb', 'error': 'MongoDB: ${e.message}'});
    } on TimeoutException {
      return const ToolOutput({'dev': 'mongodb', 'error': 'MongoDB didn\'t answer in time.'});
    }
    return ToolOutput({'error': 'Unknown tool $name'});
  }

  Map<String, dynamic> _mgWrite(Map<String, dynamic> r, String db, String coll) => {
    'done': true,
    'database': db,
    'collection': coll,
    'matched': _mgNum(r['n']),
    'modified': _mgNum(r['nModified']),
    if (r['upserted'] is List && (r['upserted'] as List).isNotEmpty) 'upserted': [for (final u in (r['upserted'] as List).whereType<Map>()) u['_id']],
  };

  /// The parts of an explain that say whether it was fast.
  Map<String, dynamic> _mgExplain(Map<String, dynamic> r) {
    Map? planner = r['queryPlanner'] as Map?;
    Map? exec = r['executionStats'] as Map?;
    if (planner == null && r['stages'] is List) {
      final first = (r['stages'] as List).whereType<Map>().firstOrNull?[r'$cursor'] as Map?;
      planner = first?['queryPlanner'] as Map?;
      exec = first?['executionStats'] as Map?;
    }
    final stages = <String>[];
    String? index;
    void walk(Object? p) {
      if (p is! Map) return;
      if (p['stage'] != null) stages.add('${p['stage']}');
      index ??= p['indexName'] as String?;
      walk(p['inputStage']);
      for (final s in (p['inputStages'] as List? ?? const [])) {
        walk(s);
      }
      walk(p['queryPlan']);
    }

    walk(planner?['winningPlan']);
    return {
      'plan': stages.contains('COLLSCAN') ? 'collection scan' : (index != null ? 'index scan' : (stages.isEmpty ? 'unknown' : stages.first)),
      'stages': stages,
      'index': ?index,
      'returned': _mgNum(exec?['nReturned']),
      'keys_examined': _mgNum(exec?['totalKeysExamined']),
      'docs_examined': _mgNum(exec?['totalDocsExamined']),
      'ms': _mgNum(exec?['executionTimeMillis']),
      'rejected_plans': (planner?['rejectedPlans'] as List?)?.length,
    };
  }

  String _mgNewId() {
    final rnd = math.Random.secure();
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toRadixString(16).padLeft(8, '0');
    return ts + List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  List<Map<String, dynamic>> _mgReadRecords(String text, String path) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    if (path.toLowerCase().endsWith('.csv')) {
      final lines = const LineSplitter().convert(t);
      if (lines.length < 2) return const [];
      List<String> cells(String line) {
        final out = <String>[];
        final b = StringBuffer();
        var quoted = false;
        for (var i = 0; i < line.length; i++) {
          final c = line[i];
          if (c == '"') {
            if (quoted && i + 1 < line.length && line[i + 1] == '"') {
              b.write('"');
              i++;
            } else {
              quoted = !quoted;
            }
          } else if (c == ',' && !quoted) {
            out.add(b.toString());
            b.clear();
          } else {
            b.write(c);
          }
        }
        out.add(b.toString());
        return out;
      }

      final head = cells(lines.first);
      Object? typed(String v) => num.tryParse(v) ?? (v == 'true' ? true : (v == 'false' ? false : (v.isEmpty ? null : v)));
      return [
        for (final line in lines.skip(1))
          if (line.trim().isNotEmpty)
            {for (final (i, c) in cells(line).indexed) if (i < head.length) head[i]: typed(c)},
      ];
    }
    if (t.startsWith('[')) {
      final v = jsonDecode(t);
      return [for (final x in v as List) if (x is Map) Map<String, dynamic>.from(x)];
    }
    return [
      for (final line in const LineSplitter().convert(t))
        if (line.trim().startsWith('{')) Map<String, dynamic>.from(jsonDecode(line) as Map),
    ];
  }

  String _mgCsv(List<Map<String, dynamic>> docs) {
    final cols = <String>{for (final d in docs) ...d.keys}.toList();
    String cell(Object? v) {
      final s = v == null ? '' : (v is Map || v is List ? jsonEncode(v) : '$v');
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    return [cols.map(cell).join(','), for (final d in docs) cols.map((c) => cell(d[c] is Map && (d[c] as Map).containsKey(r'$oid') ? (d[c] as Map)[r'$oid'] : d[c])).join(',')].join('\n');
  }

  /// What a MongoDB change would do, for the approval card.
  String? _describeMongo(String name, Map<String, dynamic> a) {
    if (!_mongoToolNames.contains(name)) return null;
    String v(String k) => '${a[k] ?? ''}'.trim();
    String j(String k) => a[k] == null ? '' : TelegramToolRunner._clip(a[k] is String ? '${a[k]}' : jsonEncode(a[k]), 500);
    final db = v('database').isEmpty ? _mgDefaultDb : v('database');
    final ns = '$db.${v('collection')}';
    return switch (name) {
      'mongodb_insert' => 'Insert ${(a['documents'] is List ? (a['documents'] as List).length : 1)} document(s) into $ns\n${j('documents')}',
      'mongodb_update' => 'Update ${a['many'] == true ? 'every' : 'the first'} document in $ns matching\n${j('filter')}\nwith ${a['pipeline'] != null ? j('pipeline') : j('update')}${a['upsert'] == true ? '\n(insert if none match)' : ''}',
      'mongodb_replace' => 'Replace the first document in $ns matching\n${j('filter')}\nwith ${j('replacement')}',
      'mongodb_find_and_modify' => 'Update one document in $ns matching\n${j('filter')}\nwith ${j('update')}',
      'mongodb_import' => 'Import ${v('file').split(RegExp(r'[\\/]')).last} into $ns',
      'mongodb_create_collection' => 'Create ${v('view_on').isEmpty ? 'collection' : 'view on ${v('view_on')}'} $ns${a['capped'] == true ? ' (capped)' : ''}${a['validator'] != null ? '\nvalidator ${j('validator')}' : ''}',
      'mongodb_create_index' => 'Create ${a['unique'] == true ? 'a unique ' : 'an '}index on $ns\n${j('keys')}',
      'mongodb_rename_collection' => 'Rename $ns to ${v('to')}',
      'mongodb_delete' => 'Delete ${a['many'] == true || a['all'] == true ? 'every' : 'the first'} document in $ns matching\n${j('filter').isEmpty || j('filter') == '{}' ? 'EVERYTHING' : j('filter')}',
      'mongodb_aggregate_write' => 'Run a pipeline on $ns that writes its output\n${j('pipeline')}',
      'mongodb_drop_index' => 'Drop index ${v('name')} on $ns',
      'mongodb_drop_collection' => 'Drop $ns with all its documents',
      'mongodb_drop_database' => 'Drop the whole database ${v('database')}',
      'mongodb_kill_op' => 'Stop operation ${v('opid')}',
      'mongodb_run_command' => 'Run on $db:\n${j('command')}',
      _ => null,
    };
  }
}
