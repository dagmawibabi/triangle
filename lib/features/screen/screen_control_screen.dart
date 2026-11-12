import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../device/device.dart';
import '../settings/presentation/approvals_screen.dart';
import 'screen_control.dart';

/// Settings → Screen control: turning on Triangle's accessibility service,
/// what the assistant can and can't do with it, and the apps it may never
/// touch.
class ScreenControlScreen extends ConsumerStatefulWidget {
  const ScreenControlScreen({super.key});

  @override
  ConsumerState<ScreenControlScreen> createState() => _ScreenControlScreenState();
}

class _ScreenControlScreenState extends ConsumerState<ScreenControlScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android's Accessibility settings: see whether it's on now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await ScreenControl.status();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      if (mounted) setState(() => _status = const {'enabled': false});
    }
  }

  Future<void> _turnOn() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Turn on screen control?'),
        content: const Text(
          'Android will ask you to allow "Triangle screen control". It lets the assistant see what\'s on your screen and '
          'tap, type and scroll in other apps when you ask it to.\n\n'
          'Android warns that this gives full control of the device: that\'s true of every accessibility app. Triangle '
          'never reads or types passwords, never acts in Triangle itself or Android\'s permission screens, skips the apps '
          'you put off limits, asks before each tap or typing (unless you change that in Approvals), and logs every '
          'action in the activity log.\n\n'
          'In the list, tap Installed apps (or Downloaded apps) → Triangle screen control → turn it on.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Open settings')),
        ],
      ),
    );
    if (go == true) await ScreenControl.openSettings();
  }

  Future<void> _addOffLimits() async {
    final raw = await Device.call<List>('apps', {'system': false});
    final apps = Device.list(raw)..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
    if (!mounted) return;
    final have = ref.read(screenOffLimitsProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => _AppPicker(apps: [for (final a in apps) if (!have.contains(a['package'])) a]),
    );
    if (picked != null) await ref.read(screenOffLimitsProvider.notifier).add(picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final on = s?['enabled'] == true;
    final running = s?['running'] == true;
    final offLimits = ref.watch(screenOffLimitsProvider).toList()..sort();
    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
          child: Text(title.toUpperCase(), style: context.text.labelSmall),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        ),
      ],
    );
    Widget point(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? AppColors.text2),
          const SizedBox(width: Space.m),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Screen control')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
            children: [
              Container(
                padding: const EdgeInsets.all(Space.xl),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.xl),
                  border: Border.all(color: on ? AppColors.success.withValues(alpha: 0.45) : AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: (on ? AppColors.success : AppColors.text3).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(Radii.m),
                          ),
                          child: Icon(Icons.touch_app_rounded, color: on ? AppColors.success : AppColors.text2),
                        ),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s == null ? 'Checking…' : (on ? (running ? 'Screen control is on' : 'On, starting…') : 'Screen control is off'),
                                style: context.text.titleMedium,
                              ),
                              Text(
                                !Platform.isAndroid
                                    ? 'Needs the Android app.'
                                    : on
                                    ? 'Ask the assistant to do something in any app: "Turn on dark mode in YouTube".'
                                    : 'Let the assistant see your screen and use other apps for you.',
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (Platform.isAndroid) ...[
                      const SizedBox(height: Space.l),
                      SizedBox(
                        width: double.infinity,
                        child: on
                            ? OutlinedButton.icon(
                                onPressed: ScreenControl.openSettings,
                                icon: const Icon(Icons.settings_accessibility_rounded),
                                label: const Text('Accessibility settings'),
                              )
                            : FilledButton.icon(
                                onPressed: _turnOn,
                                icon: const Icon(Icons.power_settings_new_rounded),
                                label: const Text('Turn on'),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              section('What it can do', [
                const SizedBox(height: Space.s),
                point(Icons.view_quilt_outlined, 'Read what\'s on the screen in any app: text, buttons, fields and switches.'),
                point(Icons.touch_app_outlined, 'Tap, long-press, type, scroll and swipe, and press Back, Home and Recents.'),
                point(Icons.screenshot_monitor_rounded, 'Take a screenshot to look at pictures and maps (Android 11 and newer).'),
                point(Icons.apps_rounded, 'Open apps and wait for them to load, then check each step worked.'),
                const SizedBox(height: Space.s),
              ]),
              section('What it never does', [
                const SizedBox(height: Space.s),
                point(Icons.password_rounded, 'Read or type passwords: password fields are hidden and refuse typing.', color: AppColors.success),
                point(Icons.block_rounded, 'Act in Triangle itself, so it can\'t approve its own actions, or on Android\'s permission and install screens.', color: AppColors.success),
                point(Icons.front_hand_outlined, 'Tap, type or swipe without asking you, unless you change that in Approvals. Scrolling and Back don\'t ask.', color: AppColors.success),
                point(Icons.history_rounded, 'Act without a record: every action is in Settings → Activity log.', color: AppColors.success),
                ListTile(
                  leading: Icon(Icons.rule_rounded, color: AppColors.text2),
                  title: const Text('Approvals'),
                  subtitle: Text('Choose what asks first', style: context.text.bodySmall),
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ApprovalsScreen())),
                ),
              ]),
              section('Off limits', [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
                  child: Text(
                    'Apps the assistant can never read or use, like your banking or password apps.',
                    style: context.text.bodySmall,
                  ),
                ),
                for (final p in offLimits)
                  ListTile(
                    leading: Icon(Icons.do_not_touch_outlined, color: AppColors.text2),
                    title: Text(p, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: 'Allow again',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => ref.read(screenOffLimitsProvider.notifier).remove(p),
                    ),
                  ),
                if (Platform.isAndroid)
                  ListTile(
                    leading: Icon(Icons.add_rounded, color: AppColors.accent),
                    title: Text('Add an app', style: TextStyle(color: AppColors.accent)),
                    onTap: _addOffLimits,
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks an installed app, by name, with a search box.
class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.apps});
  final List<Map<String, dynamic>> apps;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final a in widget.apps)
        if (q.isEmpty || '${a['name']}'.toLowerCase().contains(q) || '${a['package']}'.toLowerCase().contains(q)) a,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Search apps', prefixIcon: Icon(Icons.search_rounded)),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final a = shown[i];
                    final icon = a['icon_path'];
                    return ListTile(
                      leading: icon is String && icon.isNotEmpty && File(icon).existsSync()
                          ? ClipRRect(borderRadius: BorderRadius.circular(Radii.s), child: Image.file(File(icon), width: 36, height: 36))
                          : const Icon(Icons.android_rounded),
                      title: Text('${a['name']}'),
                      subtitle: Text('${a['package']}', style: context.text.bodySmall),
                      onTap: () => Navigator.pop(context, '${a['package']}'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
