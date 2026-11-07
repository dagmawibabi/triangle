import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../device/device.dart';

/// The network card's full view: what the phone is connected to, every
/// detail Android reports, a latency test, and the radios' switches.
///
/// Since Android 10 apps can't flip Wi-Fi, mobile data, airplane mode or
/// NFC themselves. Each switch here shows the radio's real state and opens
/// the system's own control (a panel over the app where Android has one);
/// the sheet refreshes when you come back, so the switch follows.
Future<void> showNetworkSheet(BuildContext context, Map<String, dynamic> initial) => showAppSheet<void>(
  context,
  initialSize: 0.9,
  builder: (_, scroll) => _NetworkSheet(initial: initial, scroll: scroll),
);

class _NetworkSheet extends StatefulWidget {
  const _NetworkSheet({required this.initial, required this.scroll});
  final Map<String, dynamic> initial;
  final ScrollController scroll;

  @override
  State<_NetworkSheet> createState() => _NetworkSheetState();
}

class _NetworkSheetState extends State<_NetworkSheet> with WidgetsBindingObserver {
  late Map<String, dynamic> _net = widget.initial;
  DateTime _at = DateTime.now();
  bool _refreshing = false;
  Timer? _poll;

  /// Round trips to two public resolvers, in milliseconds; null while not
  /// tested, -1 for a failure.
  Map<String, List<int>>? _latency;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // While open, it follows changes (a network switch, a radio toggled
    // from the shade).
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from a system panel or settings page: the switch may have moved.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_refreshing || !Device.supported) return;
    if (!quiet) setState(() => _refreshing = true);
    try {
      final n = Device.map(await Device.call<Map>('network'));
      if (mounted) {
        setState(() {
          _net = {..._net, ...n};
          _at = DateTime.now();
        });
      }
    } catch (_) {
      // Keeps what it showed.
    } finally {
      _refreshing = false;
      if (mounted && !quiet) setState(() {});
    }
  }

  Future<void> _open(String page) async {
    try {
      await Device.call<Object>('openSettings', {'page': page});
    } on DeviceException catch (e) {
      if (mounted) showSnack(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  /// Times a TCP connection to each host, three times: a fair stand-in for
  /// ping, which apps can't send.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _latency = null;
    });
    final out = <String, List<int>>{};
    for (final (name, host, port) in const [('Cloudflare', '1.1.1.1', 443), ('Google', '8.8.8.8', 443)]) {
      final times = <int>[];
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        try {
          final s = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
          sw.stop();
          s.destroy();
          times.add(sw.elapsedMilliseconds);
        } catch (_) {
          times.add(-1);
        }
      }
      out[name] = times;
    }
    if (mounted) {
      setState(() {
        _latency = out;
        _testing = false;
      });
    }
  }

  void _copy(String what, String value) {
    Clipboard.setData(ClipboardData(text: value));
    showSnack(context, '$what copied', icon: Icons.copy_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final n = _net;
    final wifi = n['wifi'] is Map ? Map<String, dynamic>.from(n['wifi'] as Map) : null;
    final toggles = n['toggles'] is Map ? Map<String, dynamic>.from(n['toggles'] as Map) : const <String, dynamic>{};
    final type = '${n['type'] ?? 'none'}';
    final works = n['validated'] == true;
    final connected = n['connected'] == true;
    final name = type == 'wifi'
        ? (wifi?['ssid'] as String? ?? 'Wi-Fi')
        : type == 'cellular'
        ? '${n['carrier'] ?? 'Mobile data'}'
        : type == 'none'
        ? 'Offline'
        : type[0].toUpperCase() + type.substring(1);
    final status = n['captive_portal'] == true
        ? 'Sign-in page needed'
        : works
        ? 'Internet works'
        : connected
        ? 'Connected, no internet'
        : 'Not connected';
    final statusColor = works ? AppColors.success : (connected ? AppColors.warning : AppColors.danger);
    final bars = type == 'wifi'
        ? (wifi?['signal_bars'] as num?)?.toInt()
        : type == 'cellular'
        ? (n['cell_signal_level'] as num?)?.toInt()
        : null;
    double? mbps(Object? kbps) => kbps is num ? kbps / 1000 : null;
    final down = mbps(n['down_kbps']);
    final up = mbps(n['up_kbps']);
    String yes(Object? v) => v == true ? 'Yes' : (v == false ? 'No' : '');

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        // ---- what it's on ---------------------------------------------------
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(_typeIcon(type), color: statusColor, size: 26),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: context.text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 9, color: statusColor),
                      const SizedBox(width: 6),
                      Flexible(child: Text(status, style: context.text.bodySmall)),
                      if (bars != null) ...[const SizedBox(width: Space.s), _Bars(level: bars, of: type == 'wifi' ? 4 : 4)],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(
            [
              if (n['vpn'] == true) 'VPN on',
              if (n['metered'] == true) 'Metered',
              if (n['roaming'] == true) 'Roaming',
              if (n['airplane_mode'] == true) 'Airplane mode',
              'Updated ${TimeOfDay.fromDateTime(_at).format(context)}',
            ].join(' · '),
            style: context.text.labelSmall,
          ),
        ),
        if (n['captive_portal'] == true)
          _Note(
            icon: Icons.login_rounded,
            text: 'This network wants you to sign in on a web page first.',
            action: 'Open Wi-Fi',
            onTap: () => _open('wifi'),
          ),

        // ---- switches -------------------------------------------------------
        const _Title('Quick toggles'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Space.s,
          crossAxisSpacing: Space.s,
          childAspectRatio: 2.6,
          children: [
            _Toggle(icon: Icons.wifi_rounded, label: 'Wi-Fi', on: toggles['wifi'], onTap: () => _open('panel_wifi')),
            _Toggle(
              icon: Icons.swap_vert_rounded,
              label: 'Mobile data',
              on: toggles['mobile_data'],
              onTap: () => _open('panel_internet'),
            ),
            _Toggle(
              icon: Icons.airplanemode_active_rounded,
              label: 'Airplane mode',
              on: toggles['airplane'],
              onTap: () => _open('panel_internet'),
            ),
            _Toggle(icon: Icons.bluetooth_rounded, label: 'Bluetooth', on: toggles['bluetooth'], onTap: () => _open('bluetooth')),
            if (toggles.containsKey('nfc') && toggles['nfc'] != null)
              _Toggle(icon: Icons.nfc_rounded, label: 'NFC', on: toggles['nfc'], onTap: () => _open('panel_nfc')),
            _Toggle(icon: Icons.location_on_outlined, label: 'Location', on: toggles['location'], onTap: () => _open('location')),
            _Toggle(icon: Icons.wifi_tethering_rounded, label: 'Hotspot', on: null, onTap: () => _open('hotspot')),
            _Toggle(icon: Icons.vpn_lock_rounded, label: 'VPN', on: n['vpn'] == true, onTap: () => _open('vpn')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Text(
            'Android lets apps show these switches, not flip them: a tap opens the system\'s own control, '
            'and this sheet updates when you come back.',
            style: context.text.labelSmall,
          ),
        ),

        // ---- speed and latency ---------------------------------------------
        const _Title('Speed'),
        _Box(
          children: [
            Row(
              children: [
                Expanded(child: _Big(label: 'Download', value: down == null ? '–' : down.toStringAsFixed(down < 10 ? 1 : 0), unit: 'Mbps', icon: Icons.south_rounded)),
                Expanded(child: _Big(label: 'Upload', value: up == null ? '–' : up.toStringAsFixed(up < 10 ? 1 : 0), unit: 'Mbps', icon: Icons.north_rounded)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text('Android\'s estimate for this link, not a measured test.', style: context.text.labelSmall),
            ),
            const Divider(height: Space.xl),
            Row(
              children: [
                Expanded(
                  child: _latency == null
                      ? Text(_testing ? 'Testing…' : 'Latency to Cloudflare and Google', style: context.text.bodySmall)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final e in _latency!.entries) _LatencyRow(name: e.key, times: e.value),
                          ],
                        ),
                ),
                const SizedBox(width: Space.s),
                OutlinedButton.icon(
                  onPressed: _testing || !connected ? null : _test,
                  icon: _testing
                      ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed_rounded, size: 18),
                  label: Text(_latency == null ? 'Test' : 'Again'),
                ),
              ],
            ),
          ],
        ),

        // ---- Wi-Fi ----------------------------------------------------------
        if (wifi != null) ...[
          const _Title('Wi-Fi'),
          _Box(
            children: [
              _Row('Network', wifi['ssid'] as String? ?? (wifi['name_hidden'] == true ? 'Hidden (needs location permission)' : '')),
              _Row('Signal', wifi['signal_dbm'] == null ? '' : '${wifi['signal_dbm']} dBm · ${_quality(wifi['signal_dbm'] as num)}'),
              _Row('Band', [wifi['band'], if (wifi['channel'] != null) 'channel ${wifi['channel']}'].whereType<Object>().join(' · ')),
              _Row('Frequency', wifi['frequency_mhz'] == null ? '' : '${wifi['frequency_mhz']} MHz'),
              _Row('Standard', '${wifi['standard'] ?? ''}'),
              _Row('Link speed', wifi['link_mbps'] == null ? '' : '${wifi['link_mbps']} Mbps'),
              _Row(
                'Send / receive',
                wifi['tx_mbps'] == null && wifi['rx_mbps'] == null ? '' : '${wifi['tx_mbps'] ?? '–'} / ${wifi['rx_mbps'] ?? '–'} Mbps',
              ),
              _Row('Fastest possible', wifi['max_link_mbps'] == null ? '' : '${wifi['max_link_mbps']} Mbps'),
            ],
          ),
        ],

        // ---- mobile ---------------------------------------------------------
        if (n['carrier'] != null || type == 'cellular') ...[
          const _Title('Mobile'),
          _Box(
            children: [
              _Row('Carrier', '${n['carrier'] ?? ''}'),
              _Row('Signal', n['cell_signal_level'] == null ? '' : '${n['cell_signal_level']} of 4 bars'),
              _Row('Mobile data', yes(toggles['mobile_data'])),
              _Row('Roaming', yes(n['roaming'])),
              _Row('SIM country', '${n['sim_country'] ?? ''}'.toUpperCase()),
              _Row('Network country', '${n['operator_country'] ?? ''}'.toUpperCase()),
            ],
          ),
        ],

        // ---- addresses -----------------------------------------------------
        const _Title('Connection'),
        _Box(
          children: [
            _Row('Type', type == 'none' ? 'None' : type[0].toUpperCase() + type.substring(1)),
            _Row('IPv4', '${n['ipv4'] ?? ''}', onCopy: n['ipv4'] == null ? null : () => _copy('IP address', '${n['ipv4']}')),
            _Row('IPv6', '${n['ipv6'] ?? ''}', onCopy: n['ipv6'] == null ? null : () => _copy('IPv6 address', '${n['ipv6']}')),
            _Row('Gateway', '${n['gateway'] ?? ''}', onCopy: n['gateway'] == null ? null : () => _copy('Gateway', '${n['gateway']}')),
            _Row('DNS', (n['dns'] as List?)?.join('\n') ?? ''),
            _Row(
              'Private DNS',
              n['private_dns'] != null ? '${n['private_dns']}' : (n['private_dns_active'] == true ? 'Automatic (on)' : (n['private_dns_active'] == false ? 'Off' : '')),
            ),
            _Row('Interface', '${n['interface'] ?? ''}'),
            _Row('MTU', '${n['mtu'] ?? ''}'),
            _Row('Domains', '${n['domains'] ?? ''}'),
            _Row('Metered', yes(n['metered'])),
            _Row('VPN', yes(n['vpn'])),
          ],
        ),

        // ---- more ----------------------------------------------------------
        const _Title('More'),
        _Box(
          padding: EdgeInsets.zero,
          children: [
            for (final (icon, label, page) in const [
              (Icons.settings_ethernet_rounded, 'Network & internet settings', 'network'),
              (Icons.data_usage_rounded, 'Data usage', 'data_usage'),
              (Icons.sim_card_outlined, 'Mobile network', 'mobile_data'),
              (Icons.wifi_rounded, 'Wi-Fi settings', 'wifi'),
            ])
              ListTile(
                leading: Icon(icon, color: AppColors.text2),
                title: Text(label),
                trailing: Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.text3),
                onTap: () => _open(page),
              ),
          ],
        ),
      ],
    );
  }
}

IconData _typeIcon(String type) => switch (type) {
  'wifi' => Icons.wifi_rounded,
  'cellular' => Icons.signal_cellular_alt_rounded,
  'ethernet' => Icons.settings_ethernet_rounded,
  'bluetooth' => Icons.bluetooth_rounded,
  'none' => Icons.signal_wifi_off_rounded,
  _ => Icons.lan_outlined,
};

/// How good a Wi-Fi signal of [dbm] is, in words.
String _quality(num dbm) => dbm >= -55
    ? 'excellent'
    : dbm >= -67
    ? 'good'
    : dbm >= -75
    ? 'fair'
    : 'weak';

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
    child: Text(text.toUpperCase(), style: context.text.labelSmall),
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.children, this.padding = const EdgeInsets.all(Space.m)});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(Radii.l),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

/// One fact; left out when Android didn't report it.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.onCopy});
  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value == 'null' || value == '[]') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: context.text.bodySmall)),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13.5))),
          if (onCopy != null)
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.copy_rounded, size: 16, color: AppColors.text3),
              ),
            ),
        ],
      ),
    );
  }
}

/// A radio's switch: its real state, tapping opens the system control.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;

  /// Null when Android doesn't say (the switch then just opens its page).
  final Object? on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = on == true;
    final known = on is bool;
    return Material(
      color: active ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surface2,
      borderRadius: BorderRadius.circular(Radii.l),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.l),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Row(
            children: [
              Icon(icon, size: 22, color: active ? AppColors.accent : AppColors.text2),
              const SizedBox(width: Space.s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    Text(
                      known ? (active ? 'On' : 'Off') : 'Settings',
                      style: context.text.labelSmall?.copyWith(color: active ? AppColors.accent : null),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.level, required this.of});
  final int level;
  final int of;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (var i = 0; i < of; i++)
        Container(
          width: 4,
          height: 5.0 + i * 3,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: i < level ? AppColors.accent : AppColors.surface3,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
    ],
  );
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value, required this.unit, required this.icon});
  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [Icon(icon, size: 14, color: AppColors.text3), const SizedBox(width: 4), Text(label, style: context.text.labelSmall)]),
      const SizedBox(height: 2),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            TextSpan(text: ' $unit', style: context.text.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _LatencyRow extends StatelessWidget {
  const _LatencyRow({required this.name, required this.times});
  final String name;
  final List<int> times;

  @override
  Widget build(BuildContext context) {
    final ok = times.where((t) => t >= 0).toList();
    final avg = ok.isEmpty ? null : (ok.reduce((a, b) => a + b) / ok.length).round();
    final color = avg == null
        ? AppColors.danger
        : avg < 60
        ? AppColors.success
        : avg < 150
        ? AppColors.warning
        : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text('$name ', style: context.text.bodySmall),
          Text(
            avg == null ? 'unreachable' : '$avg ms${ok.length < times.length ? ' · ${times.length - ok.length} lost' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.action, required this.onTap});
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: Space.m),
    padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.xs, Space.xs),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Radii.m),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.warning),
        const SizedBox(width: Space.s),
        Expanded(child: Text(text, style: context.text.bodySmall)),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    ),
  );
}
