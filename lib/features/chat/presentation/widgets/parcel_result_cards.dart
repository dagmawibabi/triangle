import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/code_highlight.dart' show codeTextStyle;
import '../../../parcels/parcel_api.dart' show parcelStages, parcelStatusLabel;
import '../../domain/chat_models.dart';
import 'dev/dev_card_kit.dart';

// Package cards: one parcel with where it is on its way (label → in transit
// → out for delivery → delivered), the latest scan and the estimate; the
// tracked list. Each opens a sheet with every scan, Check again, the
// carrier's page and Stop tracking.

List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Widget? parcelResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'track_package' when j['parcel'] is Map => _ParcelCard(p: _m(j['parcel']), links: _l(j['links']), live: j['live'] == true, note: j['note'] as String?),
  'tracked_packages' => _ParcelList(packages: _l(j['packages'])),
  _ => null,
};

Color parcelColor(Object? status) => switch ('$status') {
  'Delivered' => AppColors.success,
  'OutForDelivery' || 'AvailableForPickup' => adapt(const Color(0xFF60A5FA), const Color(0xFF2563EB)),
  'InTransit' || 'InfoReceived' => AppColors.warning,
  'DeliveryFailure' || 'Exception' || 'Expired' => AppColors.danger,
  _ => AppColors.text3,
};

IconData _statusIcon(Object? status) => switch ('$status') {
  'Delivered' => Icons.where_to_vote_rounded,
  'OutForDelivery' => Icons.delivery_dining_rounded,
  'AvailableForPickup' => Icons.storefront_rounded,
  'InTransit' => Icons.local_shipping_rounded,
  'InfoReceived' => Icons.receipt_long_rounded,
  'DeliveryFailure' || 'Exception' => Icons.report_gmailerrorred_rounded,
  'Expired' => Icons.history_toggle_off_rounded,
  _ => Icons.inventory_2_outlined,
};

String _when(Object? v) {
  final d = parseWhen(v);
  if (d == null) return '';
  return DateFormat(d.year == DateTime.now().year ? 'd MMM, HH:mm' : 'd MMM y, HH:mm').format(d);
}

/// Label → In transit → Out for delivery → Delivered.
class _Progress extends StatelessWidget {
  const _Progress({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final at = status == 'AvailableForPickup' ? 2 : parcelStages.indexOf(status);
    final bad = const {'DeliveryFailure', 'Exception', 'Expired'}.contains(status);
    return Row(
      children: [
        for (final (i, s) in parcelStages.indexed) ...[
          if (i > 0) Expanded(child: Container(height: 3, margin: const EdgeInsets.only(bottom: 18), decoration: BoxDecoration(color: i <= at ? parcelColor(status) : AppColors.line, borderRadius: BorderRadius.circular(2)))),
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: i <= at ? parcelColor(status).withValues(alpha: 0.18) : AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: i <= at ? parcelColor(status) : AppColors.line, width: 1.5),
                ),
                child: Icon(i == at && bad ? Icons.priority_high_rounded : _statusIcon(s), size: 14, color: i <= at ? parcelColor(status) : AppColors.text3),
              ),
              const SizedBox(height: 2),
              Text(switch (s) {
                'InfoReceived' => 'Label',
                'InTransit' => 'Transit',
                'OutForDelivery' => 'Out',
                _ => 'Delivered',
              }, style: context.text.labelSmall?.copyWith(fontSize: 10, color: i <= at ? parcelColor(status) : AppColors.text3)),
            ],
          ),
        ],
      ],
    );
  }
}

class _ParcelCard extends StatelessWidget {
  const _ParcelCard({required this.p, required this.links, required this.live, this.note});
  final Map<String, dynamic> p;
  final List<Map<String, dynamic>> links;
  final bool live;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final status = '${p['status'] ?? ''}';
    final latest = _m(p['latest']);
    void open() => showParcel(context, '${p['number']}', initial: p, links: links);
    return DevPanel(
      glow: live ? parcelColor(status) : null,
      onTap: open,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: parcelColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(Radii.m)),
                child: Icon(_statusIcon(status), color: parcelColor(status), size: 26),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['label'] ?? p['status_label'] ?? 'Package'}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [if (p['label'] != null) '${p['status_label']}', if (p['carrier'] != null) '${p['carrier']}'].join(' · '),
                      style: context.text.bodySmall?.copyWith(color: parcelColor(status)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: '${p['number']}'));
            showSnack(context, 'Tracking number copied');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Row(
              children: [
                Icon(Icons.qr_code_2_rounded, size: 15, color: AppColors.text3),
                const SizedBox(width: 6),
                Expanded(child: Text('${p['number']}', style: codeTextStyle.copyWith(fontSize: 13, letterSpacing: 0.6))),
                Icon(Icons.copy_rounded, size: 13, color: AppColors.text3),
              ],
            ),
          ),
        ),
        if (live && status.isNotEmpty) pad(_Progress(status: status), top: Space.m),
        if (latest.isNotEmpty)
          pad(
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${latest['text'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text([if (latest['location'] != null) '${latest['location']}', _when(latest['at'])].where((x) => x.isNotEmpty).join(' · '), style: context.text.labelSmall),
                ],
              ),
            ),
          ),
        if (p['eta'] != null || p['days_in_transit'] != null)
          pad(
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (p['eta'] != null) Pill('Expected ${_when(p['eta']).split(',').first}', color: AppColors.accent, icon: Icons.event_available_rounded),
              if (p['days_in_transit'] != null) Pill('${p['days_in_transit']} days on the way', color: AppColors.text2, icon: Icons.timelapse_rounded),
              if (p['from'] != null && p['to'] != null) Pill('${p['from']} → ${p['to']}', color: AppColors.text2, icon: Icons.public_rounded),
            ]),
          ),
        if (!live)
          pad(
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final l in links.take(3)) ActionChip(avatar: const Icon(Icons.open_in_new_rounded, size: 14), label: Text('${l['carrier']}'), onPressed: () => openUrl('${l['url']}'))],
            ),
          ),
        if (note != null) pad(Text(note!, style: context.text.bodySmall)),
        pad(Row(children: [Text('${(p['events'] as List? ?? const []).length} scans', style: context.text.labelSmall), const Spacer(), TextButton(onPressed: open, child: const Text('Full timeline'))])),
      ],
    );
  }
}

class _ParcelList extends StatelessWidget {
  const _ParcelList({required this.packages});
  final List<Map<String, dynamic>> packages;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: packages.length == 1 ? () => showParcel(context, '${packages.first['number']}', initial: packages.first) : null,
    children: [
      DevHead(brand: DevBrand.parcels, title: 'Your packages · ${packages.length}', subtitle: '${packages.where((p) => p['status'] == 'Delivered').length} delivered'),
      for (final p in packages)
        ListTile(
          onTap: () => showParcel(context, '${p['number']}', initial: p),
          leading: lead(Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: parcelColor(p['status']).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(Radii.s)),
            child: Icon(_statusIcon(p['status']), color: parcelColor(p['status']), size: 20),
          )),
          title: Text('${p['label'] ?? p['number']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [if (p['carrier'] != null) '${p['carrier']}', '${_m(p['latest'])['text'] ?? 'not checked yet'}'].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Pill(parcelStatusLabel('${p['status'] ?? ''}'), color: parcelColor(p['status'])),
        ),
      if (packages.isEmpty) pad(Text('Nothing tracked yet.', style: context.text.bodySmall), top: Space.s),
    ],
  );
}

/// A package in a sheet: its progress, every scan, Check again, carrier
/// pages and Stop tracking.
Future<void> showParcel(BuildContext context, String number, {Map<String, dynamic>? initial, List<Map<String, dynamic>> links = const []}) => showDevSheet(
  context,
  brand: DevBrand.parcels,
  title: '${initial?['label'] ?? 'Package'}',
  subtitle: number,
  builder: (context, scroll) => _ParcelSheet(number: number, initial: initial ?? const {}, links: links, scroll: scroll),
);

class _ParcelSheet extends ConsumerStatefulWidget {
  const _ParcelSheet({required this.number, required this.initial, required this.links, required this.scroll});
  final String number;
  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> links;
  final ScrollController scroll;
  @override
  ConsumerState<_ParcelSheet> createState() => _ParcelSheetState();
}

class _ParcelSheetState extends ConsumerState<_ParcelSheet> {
  late Map<String, dynamic> _p = widget.initial;
  late List<Map<String, dynamic>> _links = widget.links;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The list only keeps the latest scan: fetch the whole timeline.
    if ((_p['events'] as List?) == null) Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final r = await devRun(context, ref, 'track_package', {'number': widget.number});
      if (mounted) {
        setState(() {
          _p = {..._p, ..._m(r['parcel'])};
          _links = _l(r['links']);
        });
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${_p['status'] ?? ''}';
    final events = _l(_p['events']);
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: parcelColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.l)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(_statusIcon(status), color: parcelColor(status), size: 30),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(parcelStatusLabel(status), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: parcelColor(status))),
                          if (_p['carrier'] != null) Text('${_p['carrier']}', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    _busy
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(tooltip: 'Check again', icon: const Icon(Icons.refresh_rounded), onPressed: _refresh),
                  ],
                ),
                if (status.isNotEmpty && status != 'Pending' && status != 'NotFound') ...[const SizedBox(height: Space.m), _Progress(status: status)],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.number));
                  showSnack(context, 'Tracking number copied');
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy number'),
              ),
              for (final l in _links.take(2)) OutlinedButton.icon(onPressed: () => openUrl('${l['url']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text('${l['carrier']}')),
              ActionButton(
                label: 'Stop tracking',
                icon: Icons.remove_circle_outline_rounded,
                danger: true,
                done: 'No longer tracked',
                onRun: () async {
                  await devRun(context, ref, 'untrack_package', {'number': widget.number}, confirmTitle: 'Stop tracking ${widget.number}?', confirmLabel: 'Stop');
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
        const SheetLabel('Details'),
        SheetGroup(
          children: [
            CopyRow(label: 'Number', value: widget.number),
            if (_p['label'] != null) CopyRow(label: 'Name', value: '${_p['label']}', mono: false),
            if (_p['sub_status'] != null) CopyRow(label: 'Detail', value: '${_p['sub_status']}', mono: false),
            if (_p['from'] != null) CopyRow(label: 'From', value: '${_p['from']}', mono: false),
            if (_p['to'] != null) CopyRow(label: 'To', value: '${_p['to']}', mono: false),
            if (_p['eta'] != null) CopyRow(label: 'Expected', value: _when(_p['eta']), mono: false),
            if (_p['days_in_transit'] != null) CopyRow(label: 'On the way', value: '${_p['days_in_transit']} days', mono: false),
            if (_p['checked'] != null) CopyRow(label: 'Checked', value: _when(_p['checked']), mono: false),
          ],
        ),
        SheetLabel('Timeline · ${events.length} scans'),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Text(_busy ? 'Fetching…' : '${_p['note'] ?? 'No scans yet.'}', style: context.text.bodySmall),
          ),
        for (final (i, e) in events.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 22,
                    child: Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(color: i == 0 ? parcelColor(status) : AppColors.surface2, shape: BoxShape.circle, border: Border.all(color: i == 0 ? parcelColor(status) : AppColors.line, width: 2)),
                        ),
                        if (i < events.length - 1) Expanded(child: Container(width: 2, color: AppColors.line)),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Space.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e['text'] ?? ''}', style: TextStyle(fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500)),
                          Text(
                            [if (e['location'] != null) '${e['location']}', _when(e['at']), if (e['carrier'] != null && e['carrier'] != _p['carrier']) '${e['carrier']}'].where((x) => x.isNotEmpty).join(' · '),
                            style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
