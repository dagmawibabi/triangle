import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/widgets/code_highlight.dart' show codeTextStyle;
import '../../../domain/chat_models.dart';
import 'dev_card_kit.dart';

// MongoDB cards: the server and its databases, collections, a document
// browser that pages in place, counts, distinct values, schemas, indexes,
// storage stats, explain plans, server status, running operations, users,
// exports, write results; and a collection sheet to query, inspect the
// schema, indexes and stats.

List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
num _n(Object? v) => v is num ? v : (v is Map && v[r'$numberLong'] != null ? num.tryParse('${v[r'$numberLong']}') ?? 0 : num.tryParse('$v') ?? 0);
Color get _green => mongoGreen;

Widget? mongoResultFor(ToolPart part, Map<String, dynamic> j) {
  if (j['dev'] != 'mongodb') return null;
  final ns = '${j['database'] ?? ''}${j['collection'] == null ? '' : '.${j['collection']}'}';
  return switch (part.name) {
    'mongodb_overview' => _Overview(j: j),
    'mongodb_collections' => _Collections(database: '${j['database']}', collections: _l(j['collections'])),
    'mongodb_find' || 'mongodb_aggregate' => DocumentsCard(
      ns: ns,
      database: '${j['database']}',
      collection: '${j['collection']}',
      docs: _l(j['documents']),
      more: j['more'] == true,
      query: part.name == 'mongodb_find' ? part.args : null,
      filter: j['filter'] ?? j['pipeline'],
      aggregate: part.name == 'mongodb_aggregate',
    ),
    'mongodb_find_and_modify' when j['document'] is Map => DocumentsCard(ns: ns, database: '${j['database']}', collection: '${j['collection']}', docs: [_m(j['document'])], title: 'Updated document'),
    'mongodb_count' => _BigNumber(ns: ns, value: _n(j['count']), label: 'documents', filter: j['filter']),
    'mongodb_distinct' => _Distinct(ns: ns, field: '${j['field']}', values: j['values'] as List? ?? const [], count: _n(j['count'])),
    'mongodb_schema' => _Schema(ns: ns, sampled: _n(j['sampled']), fields: _l(j['fields'])),
    'mongodb_indexes' => _Indexes(ns: ns, indexes: _l(j['indexes'])),
    'mongodb_stats' => _Stats(ns: ns, stats: _m(j['stats'])),
    'mongodb_explain' => _Explain(ns: ns, j: j),
    'mongodb_server_status' => _ServerStatus(s: _m(j['status'])),
    'mongodb_current_ops' => _Ops(ops: _l(j['ops'])),
    'mongodb_users' => _Users(database: '${j['database']}', users: _l(j['users'])),
    'mongodb_export' => _Export(j: j),
    'mongodb_run_read_command' || 'mongodb_run_command' when j['result'] != null => _JsonCard(title: 'Command result · ${j['database']}', value: j['result']),
    'mongodb_insert' ||
    'mongodb_update' ||
    'mongodb_replace' ||
    'mongodb_import' ||
    'mongodb_create_collection' ||
    'mongodb_create_index' ||
    'mongodb_rename_collection' ||
    'mongodb_delete' ||
    'mongodb_aggregate_write' ||
    'mongodb_drop_index' ||
    'mongodb_drop_collection' ||
    'mongodb_drop_database' ||
    'mongodb_kill_op' => _WriteResult(tool: part.name, j: j, ns: ns),
    _ => null,
  };
}

// ---- server & databases ----------------------------------------------------------------

class _Overview extends StatelessWidget {
  const _Overview({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final s = _m(j['server']);
    final dbs = _l(j['databases'])..sort((a, b) => _n(b['size']).compareTo(_n(a['size'])));
    final top = dbs.isEmpty ? 1 : _n(dbs.first['size']).toDouble().clamp(1, double.infinity);
    return DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: 'MongoDB ${s['version'] ?? ''}', subtitle: '${s['host'] ?? ''}', value: j),
      children: [
        DevHead(brand: DevBrand.mongodb, title: 'MongoDB ${s['version'] ?? ''}', subtitle: '${s['topology'] ?? ''} · ${s['host'] ?? ''}'),
        StatTiles([
          ('databases', '${dbs.length}'),
          if (j['total_size'] != null) ('on disk', bytes(j['total_size'])),
          ('default', '${j['default_database']}'),
        ]),
        for (final d in dbs)
          InkWell(
            onTap: () => showMongoDatabase(context, '${d['name']}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storage_rounded, size: 16, color: d['name'] == j['default_database'] ? _green : AppColors.text3),
                      const SizedBox(width: Space.s),
                      Expanded(child: Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(bytes(d['size']), style: context.text.labelSmall),
                      Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ShareBar(value: _n(d['size']) / top, color: _green.withValues(alpha: 0.8)),
                ],
              ),
            ),
          ),
        if (j['note'] != null) pad(Text('${j['note']}', style: context.text.bodySmall)),
        const SizedBox(height: Space.xs),
      ],
    );
  }
}

class _Collections extends StatelessWidget {
  const _Collections({required this.database, required this.collections});
  final String database;
  final List<Map<String, dynamic>> collections;

  @override
  Widget build(BuildContext context) {
    final top = collections.fold<num>(1, (m, c) => _n(c['size']) > m ? _n(c['size']) : m);
    return DevPanel(
      onTap: () => showMongoDatabase(context, database),
      children: [
        DevHead(brand: DevBrand.mongodb, title: '$database · ${collections.length} collections'),
        for (final (i, c) in collections.take(80).indexed) ...[
          if (i > 0) const Divider(height: 1, indent: Space.m, endIndent: Space.m),
          InkWell(
            onTap: () => showMongoCollection(context, database, '${c['name']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(c['type'] == 'view' ? Icons.visibility_outlined : (c['type'] == 'timeseries' ? Icons.timeline_rounded : Icons.folder_outlined), size: 17, color: AppColors.text2),
                      const SizedBox(width: Space.s),
                      Expanded(child: Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (c['count'] != null) Text('${compact(c['count'])} docs', style: context.text.labelSmall),
                      if (c['size'] != null) Text('  ·  ${bytes(c['size'])}', style: context.text.labelSmall),
                      if (c['capped'] == true) Padding(padding: const EdgeInsets.only(left: 6), child: Pill('capped', color: AppColors.warning)),
                    ],
                  ),
                  if (c['size'] != null) Padding(padding: const EdgeInsets.only(top: 5, left: 25), child: ShareBar(value: _n(c['size']) / top, height: 4, color: _green.withValues(alpha: 0.7))),
                ],
              ),
            ),
          ),
        ],
        if (collections.isEmpty) pad(Text('No collections.', style: context.text.bodySmall), top: Space.s),
      ],
    );
  }
}

/// A database's collections in a sheet.
Future<void> showMongoDatabase(BuildContext context, String database) => showDevSheet(
  context,
  brand: DevBrand.mongodb,
  title: database,
  subtitle: 'Database',
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => Loaded<Map<String, dynamic>>(
      load: () => devRun(context, ref, 'mongodb_collections', {'database': database}),
      builder: (context, j, _) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(Space.l),
        children: [_Collections(database: database, collections: _l(j['collections']))],
      ),
    ),
  ),
);

// ---- documents -------------------------------------------------------------------------

/// Documents with each one opening into a tree; a find pages in place.
class DocumentsCard extends ConsumerStatefulWidget {
  const DocumentsCard({
    super.key,
    required this.ns,
    required this.database,
    required this.collection,
    required this.docs,
    this.more = false,
    this.query,
    this.filter,
    this.aggregate = false,
    this.title,
    this.openable = true,
  });

  /// Opens the collection sheet on tap; off when already inside it.
  final bool openable;
  final String ns;
  final String database;
  final String collection;
  final List<Map<String, dynamic>> docs;
  final bool more;

  /// The find's arguments, to fetch the next page.
  final Map<String, dynamic>? query;
  final Object? filter;
  final bool aggregate;
  final String? title;

  @override
  ConsumerState<DocumentsCard> createState() => _DocumentsCardState();
}

class _DocumentsCardState extends ConsumerState<DocumentsCard> {
  late final List<Map<String, dynamic>> _docs = [...widget.docs];
  late bool _more = widget.more;
  bool _busy = false;
  bool _chart = false;

  Future<void> _next() async {
    final q = widget.query;
    if (q == null) return;
    setState(() => _busy = true);
    try {
      final limit = (q['limit'] as num?)?.toInt() ?? 20;
      final skip = ((q['skip'] as num?)?.toInt() ?? 0) + _docs.length;
      final r = await devRun(context, ref, 'mongodb_find', {...q, 'skip': skip, 'limit': limit});
      if (mounted) {
        setState(() {
          _docs.addAll(_l(r['documents']));
          _more = r['more'] == true;
        });
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Groups like [{_id: "x", n: 3}]: one label and one number each.
  List<(String, double)>? get _series {
    if (!widget.aggregate || _docs.length < 2 || _docs.length > 40) return null;
    final out = <(String, double)>[];
    for (final d in _docs) {
      final nums = [for (final e in d.entries) if (e.key != '_id' && (e.value is num || (e.value is Map && (e.value as Map).containsKey(r'$numberLong')))) _n(e.value).toDouble()];
      if (nums.isEmpty) return null;
      out.add((jsonInline(d['_id'], max: 24).replaceAll('"', ''), nums.first));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final series = _series;
    final peak = series?.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m) ?? 0;
    return DevPanel(
      onTap: widget.openable ? () => showMongoCollection(context, widget.database, widget.collection) : null,
      children: [
        DevHead(
          brand: DevBrand.mongodb,
          title: '${widget.title ?? widget.ns} · ${_docs.length}${_more ? '+' : ''} document${_docs.length == 1 ? '' : 's'}',
          subtitle: filter == null || (filter is Map && filter.isEmpty) ? null : jsonEncode(filter),
          trailing: series == null
              ? IconButton(
                  tooltip: 'Open collection',
                  icon: const Icon(Icons.open_in_full_rounded, size: 17),
                  onPressed: () => showMongoCollection(context, widget.database, widget.collection),
                )
              : IconButton(
                  tooltip: _chart ? 'Show documents' : 'Show chart',
                  icon: Icon(_chart ? Icons.data_object_rounded : Icons.bar_chart_rounded, size: 18),
                  onPressed: () => setState(() => _chart = !_chart),
                ),
        ),
        if (_chart && series != null)
          for (final (label, v) in series)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 2, Space.m, 4),
              child: Row(
                children: [
                  SizedBox(width: 96, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
                  Expanded(child: ShareBar(value: peak <= 0 ? 0 : v / peak, height: 10, color: _green.withValues(alpha: 0.8))),
                  SizedBox(width: 56, child: Text(compact(v), textAlign: TextAlign.end, style: context.text.labelSmall?.copyWith(fontFeatures: tabularFigures))),
                ],
              ),
            )
        else
          for (final (i, d) in _docs.indexed) _DocTile(doc: d, index: i, ns: widget.ns),
        if (_docs.isEmpty) pad(Text('No documents match.', style: context.text.bodySmall), top: Space.s),
        if (_more && widget.query != null) MoreRow(label: 'Load more', busy: _busy, onTap: _next) else const SizedBox(height: Space.xs),
      ],
    );
  }
}

class _DocTile extends StatefulWidget {
  const _DocTile({required this.doc, required this.index, required this.ns});
  final Map<String, dynamic> doc;
  final int index;
  final String ns;
  @override
  State<_DocTile> createState() => _DocTileState();
}

class _DocTileState extends State<_DocTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    final preview = [for (final e in d.entries.where((e) => e.key != '_id').take(3)) '${e.key}: ${jsonInline(e.value, max: 36)}'].join('  ·  ');
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xs + 2),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(Radii.s),
            onTap: () => setState(() => _open = !_open),
            onLongPress: () => _showDoc(context, d, widget.ns),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
              child: Row(
                children: [
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: AppColors.text3),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (d.containsKey('_id')) Text(jsonInline(d['_id'], max: 60), style: codeTextStyle.copyWith(fontSize: 11.5, color: jsonColor(d['_id']))),
                        if (preview.isNotEmpty) Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: codeTextStyle.copyWith(fontSize: 11.5, color: AppColors.text2)),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Full document',
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    onPressed: () => _showDoc(context, d, widget.ns),
                  ),
                ],
              ),
            ),
          ),
          if (_open) Padding(padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.s), child: JsonTree(value: d)),
        ],
      ),
    );
  }
}

void _showDoc(BuildContext context, Map<String, dynamic> d, String ns) => showDevSheet(
  context,
  brand: DevBrand.mongodb,
  title: jsonInline(d['_id'], max: 40),
  subtitle: ns,
  actions: [
    IconButton(
      tooltip: 'Copy JSON',
      icon: const Icon(Icons.copy_rounded, size: 18),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(d)));
        showSnack(context, 'Document copied');
      },
    ),
  ],
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.all(Space.l),
    children: [JsonTree(value: d, openDepth: 2)],
  ),
);

/// A collection in a sheet: query it, see its schema, indexes and stats.
Future<void> showMongoCollection(BuildContext context, String database, String collection) => showDevSheet(
  context,
  brand: DevBrand.mongodb,
  title: collection,
  subtitle: database,
  builder: (context, scroll) => _CollectionSheet(database: database, collection: collection, scroll: scroll),
);

class _CollectionSheet extends ConsumerStatefulWidget {
  const _CollectionSheet({required this.database, required this.collection, required this.scroll});
  final String database;
  final String collection;
  final ScrollController scroll;
  @override
  ConsumerState<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends ConsumerState<_CollectionSheet> {
  int _tab = 0;
  final _filter = TextEditingController(text: '{}');
  final _sort = TextEditingController(text: '{"_id": -1}');
  int _run = 0;

  @override
  void dispose() {
    _filter.dispose();
    _sort.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _base => {'database': widget.database, 'collection': widget.collection};

  Object? _json(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    try {
      return jsonDecode(t);
    } catch (_) {
      return t;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = '${widget.database}.${widget.collection}';
    final body = switch (_tab) {
      0 => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: TextField(
              controller: _filter,
              style: codeTextStyle.copyWith(fontSize: 13),
              decoration: const InputDecoration(isDense: true, labelText: 'Filter', hintText: '{"status": "active"}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sort,
                    style: codeTextStyle.copyWith(fontSize: 13),
                    decoration: const InputDecoration(isDense: true, labelText: 'Sort'),
                  ),
                ),
                const SizedBox(width: Space.s),
                FilledButton.icon(onPressed: () => setState(() => _run++), icon: const Icon(Icons.play_arrow_rounded, size: 18), label: const Text('Run')),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          Loaded<Map<String, dynamic>>(
            key: ValueKey('find$_run'),
            load: () {
              final q = {..._base, 'filter': _json(_filter), 'sort': _json(_sort), 'limit': 20};
              return devRun(context, ref, 'mongodb_find', q).then((r) => {...r, '_q': q});
            },
            builder: (context, r, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: DocumentsCard(
                ns: ns,
                database: widget.database,
                collection: widget.collection,
                docs: _l(r['documents']),
                more: r['more'] == true,
                query: _m(r['_q']),
                filter: r['filter'],
                openable: false,
              ),
            ),
          ),
        ],
      ),
      1 => Loaded<Map<String, dynamic>>(
        key: const ValueKey('schema'),
        load: () => devRun(context, ref, 'mongodb_schema', {..._base, 'sample': 300}),
        builder: (context, r, _) => Padding(padding: const EdgeInsets.all(Space.l), child: _Schema(ns: ns, sampled: _n(r['sampled']), fields: _l(r['fields']))),
      ),
      2 => Loaded<Map<String, dynamic>>(
        key: const ValueKey('indexes'),
        load: () => devRun(context, ref, 'mongodb_indexes', _base),
        builder: (context, r, _) => Padding(padding: const EdgeInsets.all(Space.l), child: _Indexes(ns: ns, indexes: _l(r['indexes']))),
      ),
      _ => Loaded<Map<String, dynamic>>(
        key: const ValueKey('stats'),
        load: () => devRun(context, ref, 'mongodb_stats', _base),
        builder: (context, r, _) => Padding(padding: const EdgeInsets.all(Space.l), child: _Stats(ns: ns, stats: _m(r['stats']))),
      ),
    };
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          // Two rows of two, so the labels never crowd on a phone.
          child: Column(
            children: [
              for (final row in const [
                [(0, Icons.data_object_rounded, 'Documents'), (1, Icons.schema_outlined, 'Schema')],
                [(2, Icons.bolt_rounded, 'Indexes'), (3, Icons.pie_chart_outline_rounded, 'Stats')],
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: Row(
                    children: [
                      for (final (i, (value, icon, label)) in row.indexed) ...[
                        if (i > 0) const SizedBox(width: Space.s),
                        Expanded(
                          child: _tab == value
                              ? FilledButton.icon(onPressed: () {}, icon: Icon(icon, size: 18), label: Text(label))
                              : OutlinedButton.icon(onPressed: () => setState(() => _tab = value), icon: Icon(icon, size: 18), label: Text(label)),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        body,
      ],
    );
  }
}

// ---- answers ---------------------------------------------------------------------------

class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.ns, required this.value, required this.label, this.filter});
  final String ns;
  final num value;
  final String label;
  final Object? filter;

  @override
  Widget build(BuildContext context) => DevPanel(
      onTap: ns.contains('.') ? () => showMongoCollection(context, ns.split('.').first, ns.substring(ns.indexOf('.') + 1)) : null,
    children: [
      DevHead(brand: DevBrand.mongodb, title: ns, subtitle: filter == null || (filter is Map && (filter as Map).isEmpty) ? 'all documents' : jsonEncode(filter)),
      pad(
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(compact(value), style: context.text.displaySmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
            const SizedBox(width: Space.s),
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(value >= 1000 ? '$value $label' : label, style: context.text.bodySmall)),
          ],
        ),
      ),
    ],
  );
}

class _Distinct extends StatelessWidget {
  const _Distinct({required this.ns, required this.field, required this.values, required this.count});
  final String ns;
  final String field;
  final List values;
  final num count;

  @override
  Widget build(BuildContext context) => DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: field, subtitle: '$ns · $count values', value: values),
    children: [
      DevHead(brand: DevBrand.mongodb, title: '$ns · $field', subtitle: '$count distinct values'),
      pad(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in values.take(120))
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(jsonInline(v, max: 40), style: codeTextStyle.copyWith(fontSize: 12, color: jsonColor(v))),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: v is String ? v : jsonEncode(v)));
                  showSnack(context, 'Copied');
                },
              ),
          ],
        ),
      ),
    ],
  );
}

Color _typeColor(String t) => switch (t) {
  'string' => jsonColor(''),
  'int' || 'double' || 'long' || 'decimal' => jsonColor(0),
  'bool' => jsonColor(true),
  'objectId' => jsonColor({r'$oid': ''}),
  'date' || 'timestamp' => jsonColor({r'$date': ''}),
  'array' => adapt(const Color(0xFF89DDFF), const Color(0xFF0E7490)),
  'object' => adapt(const Color(0xFFB2CCD6), const Color(0xFF475569)),
  _ => AppColors.text3,
};

class _Schema extends StatelessWidget {
  const _Schema({required this.ns, required this.sampled, required this.fields});
  final String ns;
  final num sampled;
  final List<Map<String, dynamic>> fields;

  @override
  Widget build(BuildContext context) => DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: 'Schema', subtitle: ns, value: fields),
    children: [
      DevHead(brand: DevBrand.mongodb, title: 'Schema · $ns', subtitle: '${fields.length} fields from $sampled sampled documents'),
      for (final f in fields.take(120))
        Padding(
          padding: EdgeInsets.fromLTRB(Space.m + 12.0 * '${f['field']}'.split('.').length - 12, 3, Space.m, 3),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text('${f['field']}'.split('.').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: codeTextStyle.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                flex: 5,
                child: Wrap(
                  spacing: 3,
                  children: [for (final t in (f['types'] as List? ?? const []).take(3)) Pill('$t', color: _typeColor('$t'))],
                ),
              ),
              SizedBox(width: 60, child: ShareBar(value: (f['present'] as num? ?? 0).toDouble(), color: _green.withValues(alpha: 0.75))),
              SizedBox(width: 38, child: Text('${((f['present'] as num? ?? 0) * 100).round()}%', textAlign: TextAlign.end, style: context.text.labelSmall)),
            ],
          ),
        ),
      const SizedBox(height: Space.s),
    ],
  );
}

class _Indexes extends StatelessWidget {
  const _Indexes({required this.ns, required this.indexes});
  final String ns;
  final List<Map<String, dynamic>> indexes;

  @override
  Widget build(BuildContext context) => DevPanel(
      onTap: () => showMongoIndexes(context, ns, indexes),
    children: [
      DevHead(brand: DevBrand.mongodb, title: 'Indexes · $ns', subtitle: '${indexes.length} indexes'),
      for (final (i, x) in indexes.indexed) ...[
        if (i > 0) const Divider(height: 1, indent: Space.m, endIndent: Space.m),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: _green),
                  const SizedBox(width: 4),
                  Expanded(child: Text('${x['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  if (x['size'] != null) Text(bytes(x['size']), style: context.text.labelSmall),
                ],
              ),
              const SizedBox(height: 3),
              Text(jsonEncode(x['keys']), style: codeTextStyle.copyWith(fontSize: 12, color: AppColors.text2)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (x['unique'] == true) Pill('unique', color: AppColors.accent),
                  if (x['sparse'] == true) Pill('sparse', color: AppColors.text2),
                  if (x['ttl'] != null) Pill('TTL ${x['ttl']}s', color: AppColors.warning),
                  if (x['partial'] != null) Pill('partial', color: AppColors.text2),
                  if (x['uses'] != null) Pill('${compact(x['uses'])} uses', color: _n(x['uses']) == 0 ? AppColors.danger : AppColors.success),
                ],
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class _Stats extends StatelessWidget {
  const _Stats({required this.ns, required this.stats});
  final String ns;
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    String b(String k) => bytes(stats[k]);
    return DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: 'Storage', subtitle: ns, value: stats),
      children: [
        DevHead(brand: DevBrand.mongodb, title: 'Storage · $ns'),
        StatTiles([
          if (stats['count'] ?? stats['objects'] case final n?) ('documents', compact(n)),
          if (stats['collections'] != null) ('collections', '${stats['collections']}'),
          if (stats['size'] ?? stats['dataSize'] case final _?) ('data', b(stats['size'] != null ? 'size' : 'dataSize')),
          if (stats['storageSize'] != null) ('on disk', b('storageSize')),
          if (stats['totalIndexSize'] ?? stats['indexSize'] case final _?) ('indexes', b(stats['totalIndexSize'] != null ? 'totalIndexSize' : 'indexSize')),
          if (stats['avgObjSize'] != null) ('avg doc', b('avgObjSize')),
          if (stats['nindexes'] ?? stats['indexes'] case final n?) ('index count', '$n'),
        ]),
        if (stats['indexSizes'] is Map)
          for (final e in (stats['indexSizes'] as Map).entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 4),
              child: Row(children: [Expanded(child: Text('${e.key}', style: codeTextStyle.copyWith(fontSize: 12))), Text(bytes(e.value), style: context.text.labelSmall)]),
            ),
        const SizedBox(height: Space.xs),
      ],
    );
  }
}

class _Explain extends StatelessWidget {
  const _Explain({required this.ns, required this.j});
  final String ns;
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final scan = j['plan'] == 'collection scan';
    final returned = _n(j['returned']);
    final examined = _n(j['docs_examined']);
    final ratio = examined <= 0 ? 1.0 : (returned / examined).clamp(0, 1).toDouble();
    final verdict = scan ? 'Collection scan' : (j['plan'] == 'index scan' ? 'Uses an index' : '${j['plan']}');
    return DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: 'Explain plan', subtitle: ns, value: j),
      glow: scan ? AppColors.warning : AppColors.success,
      children: [
        DevHead(
          brand: DevBrand.mongodb,
          title: 'Explain · $ns',
          trailing: Padding(padding: const EdgeInsets.only(right: Space.xs), child: Pill(verdict, color: scan ? AppColors.warning : AppColors.success, icon: scan ? Icons.warning_amber_rounded : Icons.bolt_rounded)),
        ),
        pad(
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final (i, s) in (j['stages'] as List? ?? const []).reversed.indexed) ...[
                if (i > 0) Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.text3),
                Pill('$s', color: '$s' == 'COLLSCAN' ? AppColors.warning : AppColors.text2),
              ],
            ],
          ),
          top: Space.xs,
        ),
        StatTiles([
          ('returned', compact(returned)),
          ('docs examined', compact(examined)),
          ('keys examined', compact(j['keys_examined'])),
          ('time', '${j['ms'] ?? '?'} ms'),
          if (j['index'] != null) ('index', '${j['index']}'),
        ]),
        pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Efficiency: ${(ratio * 100).round()}% of examined documents returned', style: context.text.labelSmall),
              const SizedBox(height: 4),
              ShareBar(value: ratio, color: ratio > 0.5 ? AppColors.success : (ratio > 0.1 ? AppColors.warning : AppColors.danger), height: 6),
              if (scan) Padding(padding: const EdgeInsets.only(top: Space.s), child: Text('An index on the filtered fields would avoid reading every document.', style: context.text.bodySmall)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServerStatus extends StatelessWidget {
  const _ServerStatus({required this.s});
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final conn = _m(s['connections']);
    final ops = _m(s['opcounters']);
    final mem = _m(s['memory_mb']);
    final net = _m(s['network_bytes']);
    final top = ops.values.fold<num>(1, (m, v) => _n(v) > m ? _n(v) : m);
    final up = Duration(seconds: _n(s['uptime_seconds']).toInt());
    return DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: 'Server status', subtitle: '${s['host'] ?? ''}', value: s),
      children: [
        DevHead(brand: DevBrand.mongodb, title: 'Server status · ${s['host'] ?? ''}', subtitle: 'MongoDB ${s['version'] ?? ''} · up ${up.inDays > 0 ? '${up.inDays} d' : span(up)}'),
        StatTiles([
          ('connections', '${conn['current'] ?? '?'}'),
          ('available', compact(conn['available'])),
          ('resident', '${mem['resident'] ?? '?'} MB'),
          ('in', bytes(net['in'])),
          ('out', bytes(net['out'])),
          ('requests', compact(net['requests'])),
        ]),
        for (final e in ops.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 5),
            child: Row(
              children: [
                SizedBox(width: 64, child: Text(e.key, style: context.text.labelSmall)),
                Expanded(child: ShareBar(value: _n(e.value) / top, height: 8, color: _green.withValues(alpha: 0.75))),
                SizedBox(width: 56, child: Text(compact(e.value), textAlign: TextAlign.end, style: context.text.labelSmall)),
              ],
            ),
          ),
        const SizedBox(height: Space.s),
      ],
    );
  }
}

class _Ops extends ConsumerWidget {
  const _Ops({required this.ops});
  final List<Map<String, dynamic>> ops;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: 'Running operations', value: ops),
    children: [
      DevHead(brand: DevBrand.mongodb, title: 'Running operations · ${ops.length}'),
      for (final o in ops.take(40))
        ListTile(
          dense: true,
          leading: lead(Icon(Icons.sync_rounded, color: _n(o['secs']) > 10 ? AppColors.warning : AppColors.text2)),
          title: Text('${o['op']} ${o['ns'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${o['secs'] ?? 0}s · ${o['desc'] ?? ''}${o['client'] == null ? '' : ' · ${o['client']}'}'),
          trailing: IconButton(
            tooltip: 'Stop',
            icon: Icon(Icons.stop_circle_outlined, color: AppColors.danger, size: 20),
            onPressed: () async {
              try {
                await devRun(context, ref, 'mongodb_kill_op', {'opid': o['opid']}, confirmTitle: 'Stop operation ${o['opid']}?', confirmLabel: 'Stop');
                if (context.mounted) showSnack(context, 'Stopped');
              } catch (e) {
                if (context.mounted && !cancelled(e)) showSnack(context, '$e', icon: Icons.error_outline_rounded);
              }
            },
          ),
        ),
      if (ops.isEmpty) pad(Text('Nothing running.', style: context.text.bodySmall), top: Space.s),
    ],
  );
}

class _Users extends StatelessWidget {
  const _Users({required this.database, required this.users});
  final String database;
  final List<Map<String, dynamic>> users;

  @override
  Widget build(BuildContext context) => DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: 'Users', subtitle: database, value: users),
    children: [
      DevHead(brand: DevBrand.mongodb, title: 'Users · $database · ${users.length}'),
      for (final u in users)
        ListTile(
          dense: true,
          leading: lead(const Icon(Icons.person_outline_rounded)),
          title: Text('${u['user']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Wrap(spacing: 4, runSpacing: 4, children: [for (final r in (u['roles'] as List? ?? const [])) Pill('$r', color: AppColors.text2)]),
        ),
      if (users.isEmpty) pad(Text('No users defined on this database.', style: context.text.bodySmall), top: Space.s),
    ],
  );
}

class _Export extends StatelessWidget {
  const _Export({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final path = (j['created_files'] as List?)?.firstOrNull as String?;
    return DevPanel(
      onTap: path == null ? null : () => OpenFilex.open(path),
      children: [
        DevHead(brand: DevBrand.mongodb, title: 'Export · ${j['database']}.${j['collection']}'),
        ListTile(
          leading: Icon(j['format'] == 'csv' ? Icons.table_chart_outlined : Icons.data_object_rounded, color: _green),
          title: Text('${j['exported']} documents · ${'${j['format']}'.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(path?.split(RegExp(r'[\\/]')).last ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: path == null ? null : FilledButton.tonal(onPressed: () => OpenFilex.open(path), child: const Text('Open')),
        ),
        if (j['note'] != null) pad(Text('${j['note']}', style: context.text.bodySmall)),
      ],
    );
  }
}

class _JsonCard extends StatelessWidget {
  const _JsonCard({required this.title, required this.value});
  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) => DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.mongodb, title: title, value: value),
    children: [
      DevHead(
        brand: DevBrand.mongodb,
        title: title,
        trailing: IconButton(
          icon: const Icon(Icons.copy_rounded, size: 16),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value is String ? value as String : const JsonEncoder.withIndent('  ').convert(value)));
            showSnack(context, 'Copied');
          },
        ),
      ),
      pad(value is Map || value is List ? JsonTree(value: value, openDepth: 1) : SelectableText('$value', style: codeTextStyle.copyWith(fontSize: 12))),
    ],
  );
}

class _WriteResult extends StatelessWidget {
  const _WriteResult({required this.tool, required this.j, required this.ns});
  final String tool;
  final Map<String, dynamic> j;
  final String ns;

  @override
  Widget build(BuildContext context) {
    final deleted = j['deleted'] != null;
    final (icon, text) = switch (tool) {
      'mongodb_insert' => (Icons.add_circle_outline_rounded, 'Inserted ${j['inserted']} document${j['inserted'] == 1 ? '' : 's'}'),
      'mongodb_import' => (Icons.upload_file_rounded, 'Imported ${j['inserted']} documents${_n(j['skipped']) > 0 ? ' · ${j['skipped']} skipped' : ''}'),
      'mongodb_update' || 'mongodb_replace' => (
        Icons.edit_note_rounded,
        'Matched ${j['matched'] ?? 0} · changed ${j['modified'] ?? 0}${j['upserted'] == null ? '' : ' · inserted ${(j['upserted'] as List).length}'}',
      ),
      'mongodb_delete' => (Icons.delete_outline_rounded, 'Deleted ${j['deleted']} document${j['deleted'] == 1 ? '' : 's'}'),
      'mongodb_create_collection' => (Icons.create_new_folder_outlined, 'Created ${j['created']}'),
      'mongodb_create_index' => (Icons.bolt_rounded, 'Index ${j['index']} created'),
      'mongodb_rename_collection' => (Icons.drive_file_rename_outline_rounded, 'Renamed ${j['renamed']}'),
      'mongodb_aggregate_write' => (Icons.output_rounded, 'Wrote the output to ${jsonInline(j['target'], max: 40)}'),
      'mongodb_drop_index' || 'mongodb_drop_collection' || 'mongodb_drop_database' => (Icons.delete_forever_rounded, 'Dropped ${j['deleted']}'),
      'mongodb_kill_op' => (Icons.stop_circle_outlined, 'Stopped operation ${j['opid']}'),
      _ => (Icons.check_circle_outline_rounded, 'Done'),
    };
    final color = deleted || tool.contains('drop') ? AppColors.danger : AppColors.success;
    final ids = j['ids'] as List?;
    return DevPanel(
      onTap: j['collection'] == null || tool.contains('drop') ? () => showJsonSheet(context, brand: DevBrand.mongodb, title: 'Result', subtitle: ns, value: j) : () => showMongoCollection(context, '${j['database']}', '${j['collection']}'),
      children: [
        ListTile(
          leading: DevMark(DevBrand.mongodb, size: 28),
          title: Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: Space.s), Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)))]),
          subtitle: Text(ns),
          trailing: j['collection'] == null || tool.contains('drop')
              ? null
              : IconButton(
                  tooltip: 'Open collection',
                  icon: const Icon(Icons.open_in_full_rounded, size: 17),
                  onPressed: () => showMongoCollection(context, '${j['database']}', '${j['collection']}'),
                ),
        ),
        if (ids != null && ids.isNotEmpty)
          pad(Wrap(spacing: 4, runSpacing: 4, children: [for (final id in ids.take(12)) Pill(jsonInline(id, max: 34), color: AppColors.text2)])),
      ],
    );
  }
}


/// A collection's indexes in a sheet: each with its keys and options, a
/// copy button and Drop (a destructive tool, which asks first).
void showMongoIndexes(BuildContext context, String ns, List<Map<String, dynamic>> indexes) {
  final db = ns.contains('.') ? ns.split('.').first : ns;
  final coll = ns.contains('.') ? ns.substring(ns.indexOf('.') + 1) : '';
  showDevSheet(
    context,
    brand: DevBrand.mongodb,
    title: 'Indexes',
    subtitle: ns,
    builder: (context, scroll) => Consumer(
      builder: (context, ref, _) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          for (final x in indexes) ...[
            SheetLabel('${x['name']}'),
            SheetGroup(
              children: [
                CopyRow(label: 'Keys', value: jsonEncode(x['keys'])),
                if (x['unique'] == true) const CopyRow(label: 'Unique', value: 'yes', mono: false),
                if (x['ttl'] != null) CopyRow(label: 'TTL', value: '${x['ttl']} seconds', mono: false),
                if (x['partial'] != null) CopyRow(label: 'Partial', value: jsonEncode(x['partial'])),
                if (x['size'] != null) CopyRow(label: 'Size', value: bytes(x['size']), mono: false),
                if (x['uses'] != null) CopyRow(label: 'Used', value: '${x['uses']} times since restart', mono: false),
                if (x['name'] != '_id_' && coll.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Space.m),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ActionButton(
                        label: 'Drop index',
                        icon: Icons.delete_outline_rounded,
                        danger: true,
                        done: 'Index dropped',
                        onRun: () => devRun(context, ref, 'mongodb_drop_index', {'database': db, 'collection': coll, 'name': x['name']},
                            confirmTitle: 'Drop ${x['name']}?', confirmMessage: 'Queries that use it get slower.', confirmLabel: 'Drop'),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

// ---- for the MongoDB manager page ------------------------------------------------------

/// Server metrics: connections, memory, network and operations.
class MongoServerStatusView extends StatelessWidget {
  const MongoServerStatusView(this.status, {super.key});
  final Map<String, dynamic> status;
  @override
  Widget build(BuildContext context) => _ServerStatus(s: status);
}
