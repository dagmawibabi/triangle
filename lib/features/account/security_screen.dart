import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/data/telegram_tools.dart';
import 'widgets.dart';

/// The account's security in one place: a check-up with what to fix, the
/// devices logged in (log out the ones you don't know), and who may see
/// and do what.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key, this.tab = 0});
  final int tab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: tab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & security'),
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.health_and_safety_outlined, size: 20), text: 'Check-up'),
            Tab(icon: Icon(Icons.devices_rounded, size: 20), text: 'Devices'),
            Tab(icon: Icon(Icons.visibility_outlined, size: 20), text: 'Privacy'),
          ],
        ),
      ),
      body: const TabBarView(children: [_Health(), _Devices(), _Privacy()]),
    ),
  );
}

Color _scoreColor(int score) => score >= 85 ? AppColors.success : (score >= 60 ? AppColors.warning : AppColors.danger);

// ---- check-up ---------------------------------------------------------------

class _Health extends ConsumerStatefulWidget {
  const _Health();

  @override
  ConsumerState<_Health> createState() => _HealthState();
}

class _HealthState extends ConsumerState<_Health> with AutomaticKeepAliveClientMixin {
  late Future<Map<String, dynamic>> _report = ref.read(toolRunnerProvider).accountHealth();

  @override
  bool get wantKeepAlive => true;

  void _reload() => setState(() => _report = ref.read(toolRunnerProvider).accountHealth());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _report,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState('${snap.error}', onRetry: _reload);
        final r = snap.data;
        if (r == null) return const LoadingState('Checking your account…');
        final score = r['score'] as int;
        final color = _scoreColor(score);
        final fix = (r['fix'] as List).cast<String>();
        final fine = (r['fine'] as List).cast<String>();
        final twoStep = r['two_step_verification'] == true;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
            children: [
              Group(
                padded: true,
                children: [
                  Row(
                    children: [
                      Ring(
                        size: 112,
                        stroke: 11,
                        max: 100,
                        parts: [(score.toDouble(), color)],
                        child: Text('$score', style: context.text.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: Space.l),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              switch (r['verdict']) {
                                'good' => 'Well protected',
                                'could be better' => 'Could be safer',
                                _ => 'Needs attention',
                              },
                              style: context.text.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              fix.isEmpty ? 'Nothing to fix right now.' : '${fix.length} thing${fix.length == 1 ? '' : 's'} to look at',
                              style: context.text.bodySmall,
                            ),
                            const SizedBox(height: Space.s),
                            Text('Score out of 100', style: context.text.labelSmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.l),
                  StatStrip(
                    stats: [
                      (twoStep ? 'On' : 'Off', 'two-step'),
                      ('${r['devices']}', 'devices'),
                      ('${fine.length}/${fine.length + fix.length}', 'checks passed'),
                    ],
                  ),
                ],
              ),
              if (fix.isNotEmpty)
                Group(
                  label: 'To fix',
                  children: [
                    for (final f in fix)
                      Tile(
                        leading: IconBadge(Icons.priority_high_rounded, color: AppColors.warning),
                        title: f,
                        onTap: f.contains('device') || f.contains('login')
                            ? () => DefaultTabController.of(context).animateTo(1)
                            : (f.contains('see your') || f.contains('groups') ? () => DefaultTabController.of(context).animateTo(2) : null),
                        trailing: f.contains('device') || f.contains('login') || f.contains('see your') || f.contains('groups')
                            ? Icon(Icons.chevron_right_rounded, color: AppColors.text3)
                            : null,
                      ),
                  ],
                ),
              Group(
                label: 'At a glance',
                children: [
                  _Fact(
                    icon: Icons.password_rounded,
                    label: 'Two-step verification',
                    value: twoStep ? 'On' : 'Off',
                    good: twoStep,
                  ),
                  if (r['recovery_email'] != null)
                    _Fact(icon: Icons.alternate_email_rounded, label: 'Recovery email', value: r['recovery_email'] == true ? 'Set' : 'Not set', good: r['recovery_email'] == true),
                  _Fact(icon: Icons.devices_rounded, label: 'Devices logged in', value: '${r['devices']}'),
                  if (r['phone_number_visible_to'] != null)
                    _Fact(
                      icon: Icons.phone_outlined,
                      label: 'Phone number visible to',
                      value: _audienceLabel('${r['phone_number_visible_to']}'),
                      good: r['phone_number_visible_to'] != 'everybody',
                    ),
                  if (r['invites_visible_to'] != null)
                    _Fact(
                      icon: Icons.group_add_outlined,
                      label: 'Can add you to groups',
                      value: _audienceLabel('${r['invites_visible_to']}'),
                      good: r['invites_visible_to'] != 'everybody',
                    ),
                  if (r['self_destruct_after_days'] != null)
                    _Fact(icon: Icons.hourglass_bottom_rounded, label: 'Deleted if unused for', value: '${r['self_destruct_after_days']} days'),
                ],
              ),
              if (fine.isNotEmpty)
                Group(
                  label: 'Looks good',
                  children: [
                    for (final f in fine) Tile(leading: IconBadge(Icons.check_rounded, color: AppColors.success), title: f),
                  ],
                ),
              const SizedBox(height: Space.m),
              Text(
                'Two-step verification, the recovery email and your password are changed in Telegram\'s official app '
                '(Settings → Privacy and Security).',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _audienceLabel(String a) => switch (a) {
  'everybody' => 'Everybody',
  'contacts' => 'My contacts',
  _ => 'Nobody',
};

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value, this.good});
  final IconData icon;
  final String label, value;
  final bool? good;

  @override
  Widget build(BuildContext context) => Tile(
    leading: IconBadge(icon, color: good == null ? null : (good! ? AppColors.success : AppColors.warning)),
    title: label,
    trailing: Pill(value, color: good == null ? AppColors.text2 : (good! ? AppColors.success : AppColors.warning)),
  );
}

// ---- devices ------------------------------------------------------------------

class _Devices extends ConsumerStatefulWidget {
  const _Devices();

  @override
  ConsumerState<_Devices> createState() => _DevicesState();
}

class _DevicesState extends ConsumerState<_Devices> with AutomaticKeepAliveClientMixin {
  late Future<td.Sessions> _sessions = ref.read(toolRunnerProvider).activeSessions();

  @override
  bool get wantKeepAlive => true;

  void _reload() => setState(() => _sessions = ref.read(toolRunnerProvider).activeSessions());

  static IconData _icon(td.Session s) => switch (s.deviceType) {
    td.SessionDeviceTypeAndroid() => Icons.android_rounded,
    td.SessionDeviceTypeIphone() => Icons.phone_iphone_rounded,
    td.SessionDeviceTypeIpad() => Icons.tablet_mac_rounded,
    td.SessionDeviceTypeApple() || td.SessionDeviceTypeMac() => Icons.laptop_mac_rounded,
    td.SessionDeviceTypeWindows() => Icons.desktop_windows_rounded,
    td.SessionDeviceTypeLinux() || td.SessionDeviceTypeUbuntu() => Icons.computer_rounded,
    td.SessionDeviceTypeXbox() => Icons.sports_esports_outlined,
    td.SessionDeviceTypeChrome() || td.SessionDeviceTypeFirefox() || td.SessionDeviceTypeSafari() || td.SessionDeviceTypeEdge() || td.SessionDeviceTypeOpera() || td.SessionDeviceTypeBrave() || td.SessionDeviceTypeVivaldi() =>
      Icons.language_rounded,
    _ => Icons.devices_other_rounded,
  };

  static String _ago(int unix) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(unix * 1000));
    if (d.inMinutes < 2) return 'online';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays < 30) return '${d.inDays} d ago';
    return DateFormat('d MMM y').format(DateTime.fromMillisecondsSinceEpoch(unix * 1000));
  }

  Future<void> _end(td.Session? s) async {
    final ok = await confirm(
      context,
      title: s == null ? 'Log out all other devices?' : 'Log out this device?',
      body: s == null
          ? 'Every device and app except this phone will be logged out of your account.'
          : '${s.applicationName} on ${s.deviceModel.isEmpty ? s.platform : s.deviceModel} (${s.location}) will be logged out.',
      action: 'Log out',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(toolRunnerProvider).endSession(sessionId: s?.id, allOthers: s == null);
      if (mounted) showSnack(context, 'Logged out');
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t log it out: $e', icon: Icons.error_outline_rounded);
    }
    _reload();
  }

  void _details(td.Session s) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) {
      final fmt = DateFormat('d MMM y, HH:mm');
      Widget row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: ctx.text.bodySmall)),
            Expanded(child: Text(v.isEmpty ? '—' : v)),
          ],
        ),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(_icon(s), size: 44),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text('${s.applicationName} ${s.applicationVersion}', style: ctx.text.titleMedium)),
                ],
              ),
              const SizedBox(height: Space.m),
              row('Device', [s.deviceModel, s.platform, s.systemVersion].where((x) => x.isNotEmpty).join(' · ')),
              row('Location', s.location),
              row('IP address', s.ipAddress),
              row('Logged in', fmt.format(DateTime.fromMillisecondsSinceEpoch(s.logInDate * 1000))),
              row('Last active', fmt.format(DateTime.fromMillisecondsSinceEpoch(s.lastActiveDate * 1000))),
              row('App', s.isOfficialApplication ? 'Official Telegram app' : 'Unofficial app (API id ${s.apiId})'),
              if (!s.isCurrent) ...[
                const SizedBox(height: Space.m),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _end(s);
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out this device'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _tile(td.Session s) {
    final flags = [
      if (s.isUnconfirmed || s.isPasswordPending) Pill('New login', color: AppColors.danger),
      if (!s.isOfficialApplication) Pill('Unofficial', color: AppColors.warning),
    ];
    return Tile(
      leading: IconBadge(_icon(s), color: s.isCurrent ? AppColors.success : (flags.isNotEmpty ? AppColors.warning : null)),
      title: s.deviceModel.isEmpty ? s.applicationName : s.deviceModel,
      subtitle: '${s.applicationName} ${s.applicationVersion} · ${s.location.isEmpty ? 'Unknown place' : s.location}',
      below: flags.isEmpty ? null : Wrap(spacing: 6, children: flags),
      onTap: () => _details(s),
      trailing: s.isCurrent
          ? Pill('This phone', color: AppColors.success)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_ago(s.lastActiveDate), style: context.text.labelSmall),
                Icon(Icons.chevron_right_rounded, color: AppColors.text3),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<td.Sessions>(
      future: _sessions,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState('${snap.error}', onRetry: _reload);
        final r = snap.data;
        if (r == null) return const LoadingState('Finding your devices…');
        final current = r.sessions.where((s) => s.isCurrent).toList();
        final others = r.sessions.where((s) => !s.isCurrent).toList()..sort((a, b) => b.lastActiveDate.compareTo(a.lastActiveDate));
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
            children: [
              Group(label: 'This device', children: [for (final s in current) _tile(s)]),
              if (others.isNotEmpty) ...[
                Group(label: 'Other devices · ${others.length}', children: [for (final s in others) _tile(s)]),
                Group(
                  children: [
                    Tile(
                      leading: IconBadge(Icons.phonelink_erase_rounded, color: AppColors.danger),
                      title: 'Log out all other devices',
                      titleColor: AppColors.danger,
                      subtitle: 'Keeps only this phone',
                      onTap: () => _end(null),
                    ),
                  ],
                ),
              ],
              Group(
                label: 'Automatically',
                children: [
                  Tile(
                    leading: const IconBadge(Icons.timer_outlined),
                    title: 'Log out idle devices after',
                    subtitle: 'Devices unused this long are logged out',
                    trailing: DropdownButton<int>(
                      value: const [7, 30, 90, 180, 365].contains(r.inactiveSessionTtlDays) ? r.inactiveSessionTtlDays : null,
                      hint: Text('${r.inactiveSessionTtlDays} days'),
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(Radii.m),
                      items: [
                        for (final d in const [7, 30, 90, 180, 365])
                          DropdownMenuItem(value: d, child: Text(d < 30 ? '1 week' : (d < 365 ? '${d ~/ 30} months' : '1 year'))),
                      ],
                      onChanged: (d) async {
                        if (d == null) return;
                        await ref.read(toolRunnerProvider).run('set_session_options', {'inactive_days': d});
                        _reload();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---- privacy ------------------------------------------------------------------

typedef _Rules = ({String audience, List<int> always, List<int> never});

class _Privacy extends ConsumerStatefulWidget {
  const _Privacy();

  @override
  ConsumerState<_Privacy> createState() => _PrivacyState();
}

class _PrivacyState extends ConsumerState<_Privacy> with AutomaticKeepAliveClientMixin {
  final Map<String, _Rules> _rules = {};
  bool? _readDates, _strangers;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  static const _icons = <String, IconData>{
    'last_seen': Icons.schedule_rounded,
    'profile_photo': Icons.account_circle_outlined,
    'phone_number': Icons.phone_outlined,
    'bio': Icons.notes_rounded,
    'birthdate': Icons.cake_outlined,
    'invites': Icons.group_add_outlined,
    'calls': Icons.call_outlined,
    'p2p_calls': Icons.swap_calls_rounded,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final runner = ref.read(toolRunnerProvider);
    await Future.wait([
      for (final e in privacySettings.entries)
        runner.privacyRules(e.value.$2).then((r) {
          if (mounted) setState(() => _rules[e.key] = runner.readRules(r));
        }).catchError((Object _) {}),
    ]);
    try {
      _readDates = await runner.showsReadDates();
      _strangers = await runner.allowsNewChats();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _set(String key, String audience) async {
    final old = _rules[key];
    final runner = ref.read(toolRunnerProvider);
    setState(() => _rules[key] = (audience: audience, always: old?.always ?? const [], never: old?.never ?? const []));
    try {
      await runner.setPrivacyRules(
        privacySettings[key]!.$2,
        runner.makeRules(audience, always: old?.always ?? const [], never: old?.never ?? const []),
      );
    } catch (e) {
      if (old != null) setState(() => _rules[key] = old);
      if (mounted) showSnack(context, 'Couldn\'t change it: $e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _choose(String key) async {
    final r = _rules[key];
    if (r == null) return;
    final store = ref.read(telegramStoreProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(_icons[key] ?? Icons.lock_outline_rounded),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(privacySettings[key]!.$1, style: ctx.text.titleMedium)),
                ],
              ),
              const SizedBox(height: Space.m),
              for (final (value, label, icon) in const [
                ('everybody', 'Everybody', Icons.public_rounded),
                ('contacts', 'My contacts', Icons.contacts_outlined),
                ('nobody', 'Nobody', Icons.lock_outline_rounded),
              ])
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
                  tileColor: r.audience == value ? AppColors.tint.withValues(alpha: 0.10) : null,
                  leading: lead(Icon(icon)),
                  title: Text(label),
                  trailing: r.audience == value ? Icon(Icons.check_rounded, color: AppColors.accent) : null,
                  onTap: () => Navigator.pop(ctx, value),
                ),
              if (r.always.isNotEmpty || r.never.isNotEmpty) ...[
                const SizedBox(height: Space.s),
                if (r.always.isNotEmpty) Text('Always: ${r.always.map(store.userName).join(', ')}', style: ctx.text.bodySmall),
                if (r.never.isNotEmpty) Text('Never: ${r.never.map(store.userName).join(', ')}', style: ctx.text.bodySmall),
              ],
              const SizedBox(height: Space.s),
              Text('For exceptions, ask the assistant: "let only Liya see my last seen".', style: ctx.text.bodySmall),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != r.audience) await _set(key, picked);
  }

  Future<void> _toggle(String key, bool on) async {
    setState(() => key == 'read_dates' ? _readDates = on : _strangers = on);
    final r = await ref.read(toolRunnerProvider).run('set_privacy', {'setting': key, 'enabled': on});
    if (r.json['error'] != null && mounted) {
      setState(() => key == 'read_dates' ? _readDates = !on : _strangers = !on);
      showSnack(context, '${r.json['error']}', icon: Icons.error_outline_rounded);
    }
  }

  Widget _row(String key) {
    final r = _rules[key];
    final exceptions = (r?.always.length ?? 0) + (r?.never.length ?? 0);
    final color = switch (r?.audience) {
      'everybody' => AppColors.text2,
      'contacts' => AppColors.accent,
      'nobody' => AppColors.success,
      _ => AppColors.text3,
    };
    return Tile(
      leading: IconBadge(_icons[key] ?? Icons.lock_outline_rounded, color: r?.audience == 'everybody' ? AppColors.text2 : null),
      title: privacySettings[key]!.$1,
      subtitle: exceptions == 0 ? null : '$exceptions exception${exceptions == 1 ? '' : 's'}',
      trailing: r == null
          ? const SizedBox(width: 24, child: Center(child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 1.5))))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Pill(_audienceLabel(r.audience), color: color),
                Icon(Icons.chevron_right_rounded, color: AppColors.text3),
              ],
            ),
      onTap: r == null ? null : () => _choose(key),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    const see = ['last_seen', 'profile_photo', 'phone_number', 'bio', 'birthdate'];
    const can = ['invites', 'calls', 'p2p_calls'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
      children: [
        SizedBox(height: 2, child: _loading ? const LinearProgressIndicator(minHeight: 2) : null),
        if (_rules.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: StatStrip(
              stats: [
                for (final (aud, label) in const [('everybody', 'everybody'), ('contacts', 'contacts only'), ('nobody', 'nobody')])
                  ('${_rules.values.where((r) => r.audience == aud).length}', label),
              ],
            ),
          ),
        Group(label: 'Who can see my', children: [for (final k in see) _row(k)]),
        Group(label: 'Who can', children: [for (final k in can) _row(k)]),
        if (_readDates != null || _strangers != null)
          Group(
            label: 'Messages',
            children: [
              if (_readDates != null)
                Tile(
                  leading: const IconBadge(Icons.done_all_rounded),
                  title: 'Show my read times',
                  subtitle: 'If off, you don\'t see others\' either',
                  trailing: Switch(value: _readDates!, onChanged: (v) => _toggle('read_dates', v)),
                  onTap: () => _toggle('read_dates', !_readDates!),
                ),
              if (_strangers != null)
                Tile(
                  leading: const IconBadge(Icons.person_add_alt_1_outlined),
                  title: 'Strangers can message me',
                  subtitle: 'Turning this off needs Telegram Premium',
                  trailing: Switch(value: _strangers!, onChanged: (v) => _toggle('new_chats', v)),
                  onTap: () => _toggle('new_chats', !_strangers!),
                ),
            ],
          ),
      ],
    );
  }
}
