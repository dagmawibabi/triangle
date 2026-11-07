import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../device/device.dart';
import '../../domain/chat_models.dart';
import 'message_preview.dart';
import 'network_sheet.dart';

/// Cards for what the phone reports: its specs with RAM, storage and
/// battery gauges, the network, installed apps (tap to open), text messages,
/// calls and contacts (tap to call). Taps here are the user's own, so they
/// act directly.
Widget? deviceResultFor(ToolPart part, Map<String, dynamic> j) {
  if (j['device'] is! String) return null;
  List<Map<String, dynamic>> list(String k) => [
    for (final x in (j[k] as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'device_info' => _SpecsCard(info: j),
    'device_battery' => _Card(icon: Icons.battery_std_rounded, title: 'Battery', children: [_BatteryRow(b: j)]),
    'network_info' => _NetworkCard(net: j),
    'installed_apps' => _AppsCard(apps: list('apps'), total: j['total'] as int?),
    'read_sms' => _SmsCard(messages: list('messages')),
    'call_log' => _CallsCard(calls: list('calls')),
    'phone_contacts' => _ContactsCard(contacts: list('contacts')),
    'flashlight' when j['on'] is bool => _Chip(icon: j['on'] == true ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded, text: 'Flashlight ${j['on'] == true ? 'on' : 'off'}'),
    'device_volume' when j['levels'] is Map => _VolumeCard(v: j),
    _ => null,
  };
}

String _bytes(Object? n) {
  final v = n is num ? n.toDouble() : null;
  if (v == null) return '?';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var x = v;
  var i = 0;
  while (x >= 1024 && i < u.length - 1) {
    x /= 1024;
    i++;
  }
  return '${x < 10 ? x.toStringAsFixed(1) : x.round()} ${u[i]}';
}

String _when(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  if (d == null) return '';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return DateFormat.Hm().format(d);
  if (now.difference(d).inDays < 7) return DateFormat('EEE HH:mm').format(d);
  return DateFormat('d MMM').format(d);
}

Future<void> _device(BuildContext context, String method, Map<String, dynamic> args) async {
  try {
    await Device.call<Object>(method, args);
  } on DeviceException catch (e) {
    if (context.mounted) showSnack(context, e.message, icon: Icons.error_outline_rounded);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.children, this.onTap});
  final IconData icon;
  final String title;
  final List<Widget> children;

  /// Opens the full details, with a chevron in the header saying so.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.text2),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(title, style: context.text.labelMedium?.copyWith(color: AppColors.text2))),
                  if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.text3),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: AppColors.warning), const SizedBox(width: 6), Text(text)]),
    ),
  );
}

/// A labelled bar, e.g. RAM in use.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.label, required this.used, required this.total, required this.detail});
  final String label;
  final double used;
  final double total;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final f = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    final color = f > 0.9 ? AppColors.danger : (f > 0.75 ? AppColors.warning : AppColors.accent);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Text(detail, style: context.text.labelSmall),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: f, minHeight: 7, color: color, backgroundColor: AppColors.surface3),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts(this.facts);
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
    child: Wrap(
      spacing: Space.l,
      runSpacing: Space.s,
      children: [
        for (final (k, v) in facts)
          if (v.isNotEmpty && v != 'null')
            SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k.toUpperCase(), style: context.text.labelSmall?.copyWith(fontSize: 10)),
                  const SizedBox(height: 1),
                  Text(v, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
      ],
    ),
  );
}

class _BatteryRow extends StatelessWidget {
  const _BatteryRow({required this.b});
  final Map<String, dynamic> b;

  @override
  Widget build(BuildContext context) {
    final level = (b['level'] as num?)?.toInt() ?? 0;
    final charging = b['charging'] == true;
    final color = level <= 15 ? AppColors.danger : (level <= 30 ? AppColors.warning : AppColors.success);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: level / 100, strokeWidth: 5, color: color, backgroundColor: AppColors.surface3),
                Text('$level%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (charging) Icon(Icons.bolt_rounded, size: 16, color: AppColors.success),
                    Text(
                      b['full'] == true ? 'Full' : (charging ? 'Charging${b['plugged'] == null ? '' : ' · ${b['plugged']}'}' : 'On battery'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Text(
                  [
                    if (b['temperature_c'] != null) '${b['temperature_c']} °C',
                    if (b['health'] != null) 'health ${b['health']}',
                    if (b['power_saver'] == true) 'battery saver on',
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecsCard extends StatelessWidget {
  const _SpecsCard({required this.info});
  final Map<String, dynamic> info;

  @override
  Widget build(BuildContext context) {
    final ramTotal = (info['ram_total'] as num?)?.toDouble() ?? 0;
    final ramFree = (info['ram_available'] as num?)?.toDouble() ?? 0;
    final diskTotal = (info['storage_total'] as num?)?.toDouble() ?? 0;
    final diskFree = (info['storage_free'] as num?)?.toDouble() ?? 0;
    final up = Duration(milliseconds: (info['uptime_ms'] as num?)?.toInt() ?? 0);
    return _Card(
      icon: Icons.phone_android_rounded,
      title: '${info['manufacturer'] ?? ''} ${info['model'] ?? ''}'.trim(),
      children: [
        _Gauge(label: 'Memory', used: ramTotal - ramFree, total: ramTotal, detail: '${_bytes(ramTotal - ramFree)} of ${_bytes(ramTotal)} in use'),
        _Gauge(label: 'Storage', used: diskTotal - diskFree, total: diskTotal, detail: '${_bytes(diskFree)} free of ${_bytes(diskTotal)}'),
        if (info['battery'] is Map) _BatteryRow(b: Map<String, dynamic>.from(info['battery'] as Map)),
        _Facts([
          ('Android', '${info['android']} (API ${info['sdk']})'),
          ('Chip', '${info['soc'] ?? info['hardware'] ?? ''}'),
          ('CPU', '${info['cpu_cores']} cores · ${(info['abis'] as List?)?.firstOrNull ?? ''}'),
          ('Screen', '${info['screen_width_px']}×${info['screen_height_px']} · ${info['density_dpi']} dpi'),
          ('Security patch', '${info['security_patch'] ?? ''}'),
          ('Up for', up.inDays > 0 ? '${up.inDays} d ${up.inHours % 24} h' : '${up.inHours} h ${up.inMinutes % 60} min'),
        ]),
      ],
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.net});
  final Map<String, dynamic> net;

  @override
  Widget build(BuildContext context) {
    final wifi = net['wifi'] is Map ? Map<String, dynamic>.from(net['wifi'] as Map) : null;
    final type = '${net['type']}';
    final ok = net['validated'] == true;
    final bars = (wifi?['signal_bars'] as num?)?.toInt();
    return _Card(
      icon: switch (type) {
        'wifi' => Icons.wifi_rounded,
        'cellular' => Icons.signal_cellular_alt_rounded,
        'none' => Icons.signal_wifi_off_rounded,
        _ => Icons.lan_outlined,
      },
      title: 'Network',
      // The full details and the radios' switches.
      onTap: Device.supported ? () => showNetworkSheet(context, net) : null,
      children: [
        ListTile(
          title: Text(
            type == 'wifi'
                ? (wifi?['ssid'] as String? ?? 'Wi-Fi')
                : type == 'cellular'
                ? '${net['carrier'] ?? 'Mobile data'}'
                : (type == 'none' ? 'Offline' : type),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              ok ? 'internet works' : (net['connected'] == true ? 'no internet' : 'not connected'),
              if (net['vpn'] == true) 'VPN',
              if (net['metered'] == true) 'metered',
              if (net['roaming'] == true) 'roaming',
              if (net['airplane_mode'] == true) 'airplane mode',
            ].join(' · '),
          ),
          trailing: Icon(Icons.circle, size: 10, color: ok ? AppColors.success : AppColors.warning),
        ),
        if (bars != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 0),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 6,
                    height: 8.0 + i * 4,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: i < bars ? AppColors.accent : AppColors.surface3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                const SizedBox(width: Space.s),
                Text('${wifi?['signal_dbm']} dBm · ${wifi?['band'] ?? ''} · ${wifi?['link_mbps']} Mbps', style: context.text.bodySmall),
              ],
            ),
          ),
        _Facts([
          ('IP', '${net['ipv4'] ?? (net['ip_addresses'] as List?)?.firstOrNull ?? ''}'),
          ('DNS', (net['dns'] as List?)?.take(2).join(', ') ?? ''),
          ('Speed', net['down_kbps'] == null ? '' : '↓ ${((net['down_kbps'] as num) / 1000).toStringAsFixed(1)} · ↑ ${((net['up_kbps'] as num? ?? 0) / 1000).toStringAsFixed(1)} Mbps'),
          ('Private DNS', '${net['private_dns'] ?? ''}'),
          if (wifi?['name_hidden'] == true) ('Wi-Fi name', 'hidden without location permission'),
        ]),
      ],
    );
  }
}

class _AppsCard extends StatelessWidget {
  const _AppsCard({required this.apps, this.total});
  final List<Map<String, dynamic>> apps;
  final int? total;

  @override
  Widget build(BuildContext context) => _Card(
    icon: Icons.apps_rounded,
    title: 'Apps · ${total ?? apps.length}',
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.s, Space.m),
        child: Wrap(
          children: [
            for (final a in apps.take(40))
              SizedBox(
                width: 76,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.m),
                  onTap: a['can_open'] == true ? () => _device(context, 'openApp', {'package': a['package']}) : null,
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: '${a['package']}'));
                    showSnack(context, '${a['package']} copied');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.s),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: a['icon_path'] is String && File(a['icon_path'] as String).existsSync()
                              ? Image.file(File(a['icon_path'] as String), width: 44, height: 44)
                              : Container(width: 44, height: 44, color: AppColors.surface3, child: Icon(Icons.android_rounded, color: AppColors.text3)),
                        ),
                        const SizedBox(height: 4),
                        Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5)),
                        if (a['version'] != null)
                          Text('${a['version']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(fontSize: 9.5)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (apps.length > 40) Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: Text('${apps.length - 40} more', style: context.text.labelSmall)),
    ],
  );
}

class _SmsCard extends StatelessWidget {
  const _SmsCard({required this.messages});
  final List<Map<String, dynamic>> messages;

  @override
  Widget build(BuildContext context) => _Card(
    icon: Icons.sms_outlined,
    title: 'Text messages · ${messages.length}',
    children: [
      if (messages.isEmpty) Padding(padding: const EdgeInsets.all(Space.m), child: Text('None found.', style: context.text.bodySmall)),
      for (final (i, m) in messages.take(30).indexed) ...[
        if (i > 0) const Divider(height: 1, indent: Space.m, endIndent: Space.m),
        InkWell(
          onTap: () => showMessagePreview(
            context,
            MessagePreview(
              from: '${m['name'] ?? m['address'] ?? 'Unknown'}${m['name'] != null && m['address'] != null ? ' · ${m['address']}' : ''}',
              text: '${m['body'] ?? ''}',
              date: DateTime.tryParse('${m['date'] ?? ''}'),
              source: 'SMS',
              icon: Icons.sms_outlined,
              sent: m['sent'] == true,
              replyUrl: m['address'] == null ? null : 'sms:${m['address']}',
            ),
          ),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: '${m['body']}'));
            showSnack(context, 'Message copied');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(m['sent'] == true ? Icons.north_east_rounded : Icons.south_west_rounded, size: 16, color: m['sent'] == true ? AppColors.accent : AppColors.success),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${m['name'] ?? m['address'] ?? 'Unknown'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: m['read'] == false ? FontWeight.w700 : FontWeight.w600),
                            ),
                          ),
                          Text(_when(m['date']), style: context.text.labelSmall),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${m['body'] ?? ''}', maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

class _CallsCard extends StatelessWidget {
  const _CallsCard({required this.calls});
  final List<Map<String, dynamic>> calls;

  @override
  Widget build(BuildContext context) => _Card(
    icon: Icons.history_rounded,
    title: 'Calls · ${calls.length}',
    children: [
      for (final c in calls.take(30))
        ListTile(
          dense: true,
          leading: lead(Icon(
            switch (c['type']) {
              'missed' => Icons.call_missed_rounded,
              'outgoing' => Icons.call_made_rounded,
              'rejected' || 'blocked' => Icons.call_end_rounded,
              _ => Icons.call_received_rounded,
            },
            color: c['type'] == 'missed' || c['type'] == 'rejected' ? AppColors.danger : AppColors.text2,
          )),
          title: Text('${c['name'] ?? c['number']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              if (c['name'] != null) '${c['number']}',
              _when(c['date']),
              if ((c['seconds'] as num? ?? 0) > 0) '${((c['seconds'] as num) / 60).floor()}:${'${(c['seconds'] as num).toInt() % 60}'.padLeft(2, '0')}',
            ].join(' · '),
          ),
          trailing: IconButton(
            tooltip: 'Call back',
            icon: Icon(Icons.call_rounded, color: AppColors.success),
            onPressed: () => _device(context, 'call', {'number': c['number'], 'direct': false}),
          ),
        ),
    ],
  );
}

class _ContactsCard extends StatelessWidget {
  const _ContactsCard({required this.contacts});
  final List<Map<String, dynamic>> contacts;

  @override
  Widget build(BuildContext context) => _Card(
    icon: Icons.contacts_outlined,
    title: 'Contacts · ${contacts.length}',
    children: [
      if (contacts.isEmpty) Padding(padding: const EdgeInsets.all(Space.m), child: Text('No match.', style: context.text.bodySmall)),
      for (final c in contacts.take(30))
        for (final n in [for (final x in (c['numbers'] as List? ?? const [])) if (x is Map) x].take(3))
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.surface3,
              child: Text('${c['name'] ?? '?'}'.characters.firstOrNull ?? '?', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            title: Text('${c['name']}${c['starred'] == true ? ' ★' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${n['number']}${'${n['label'] ?? ''}'.isEmpty ? '' : ' · ${n['label']}'}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Message',
                  icon: const Icon(Icons.sms_outlined, size: 20),
                  onPressed: () => _device(context, 'openSms', {'number': n['number']}),
                ),
                IconButton(
                  tooltip: 'Call',
                  icon: Icon(Icons.call_rounded, color: AppColors.success, size: 20),
                  onPressed: () => _device(context, 'call', {'number': n['number'], 'direct': false}),
                ),
              ],
            ),
          ),
    ],
  );
}

class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.v});
  final Map<String, dynamic> v;

  @override
  Widget build(BuildContext context) {
    final levels = Map<String, dynamic>.from(v['levels'] as Map);
    return _Card(
      icon: Icons.volume_up_rounded,
      title: 'Volume · ringer ${v['ringer']}',
      children: [
        for (final e in levels.entries) _Gauge(label: e.key, used: (e.value as num).toDouble(), total: 100, detail: '${e.value}%'),
        const SizedBox(height: Space.s),
      ],
    );
  }
}
