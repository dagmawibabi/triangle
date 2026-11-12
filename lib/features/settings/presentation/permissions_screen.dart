import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../app/theme.dart';
import '../../assistant/watch_engine.dart';
import '../../assistant/presentation/default_assistant_screen.dart';
import '../../device/device.dart';
import '../../device/net.dart';
import '../../screen/screen_control.dart';
import '../../screen/screen_control_screen.dart';

/// What Android lets Triangle do, why each matters, and how to fix it:
/// every runtime permission the app declares, and the special access the
/// person turns on in Android's settings (notification access, usage
/// access, Do Not Disturb, screen control). Rechecked whenever the app comes
/// back to the front, since the answers change in Android's own settings.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

const _mic = 'android.permission.RECORD_AUDIO';
const _camera = 'android.permission.CAMERA';
const _images = 'android.permission.READ_MEDIA_IMAGES';
const _videos = 'android.permission.READ_MEDIA_VIDEO';
const _selected = 'android.permission.READ_MEDIA_VISUAL_USER_SELECTED';
const _storage = 'android.permission.READ_EXTERNAL_STORAGE';
const _fine = 'android.permission.ACCESS_FINE_LOCATION';
const _coarse = 'android.permission.ACCESS_COARSE_LOCATION';
const _background = 'android.permission.ACCESS_BACKGROUND_LOCATION';
const _postNotifications = 'android.permission.POST_NOTIFICATIONS';

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> with WidgetsBindingObserver {
  bool? _notifications;
  bool? _battery;
  bool? _exactAlarms;
  LocationPermission? _location;
  Map<String, bool> _runtime = const {};
  int _sdk = 34;
  bool? _notificationAccess;
  bool? _usageAccess;
  bool? _dnd;
  bool? _screen;
  bool _asking = false;

  /// The photo permissions this Android version uses.
  List<String> get _media => _sdk >= 33 ? const [_images, _videos] : const [_storage];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<T?> _quiet<T>(Future<T> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _check() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final n = await FlutterForegroundTask.checkNotificationPermission();
      final b = Platform.isAndroid ? await FlutterForegroundTask.isIgnoringBatteryOptimizations : true;
      final a = await _android?.canScheduleExactNotifications() ?? true;
      final l = await Geolocator.checkPermission();
      final info = Platform.isAndroid ? await _quiet(Device.call<Map>('deviceInfo')) : null;
      final sdk = (info?['sdk'] as num?)?.toInt() ?? _sdk;
      final runtime = await Device.status([
        _mic,
        _camera,
        _images,
        _videos,
        _selected,
        _storage,
        _background,
        for (final p in Device.all) p.id,
      ]);
      final notificationAccess = Platform.isAndroid ? await _quiet(Net.notificationAccess()) : null;
      final usage = Platform.isAndroid ? await _quiet(Net.usageAccess()) : null;
      final dnd = Platform.isAndroid ? await _quiet(Device.call<bool>('dndAccess')) : null;
      final screen = ScreenControl.supported ? await _quiet(ScreenControl.status()) : null;
      if (!mounted) return;
      setState(() {
        _notifications = n == NotificationPermission.granted;
        _battery = b;
        _exactAlarms = a;
        _location = l;
        _sdk = sdk;
        _runtime = runtime;
        _notificationAccess = notificationAccess;
        _usageAccess = usage;
        _dnd = dnd;
        _screen = screen == null ? null : screen['enabled'] == true;
      });
    } catch (e) {
      debugPrint('[Permissions] $e');
    }
  }

  bool? _has(String p) => _runtime[p];
  bool? _all(List<String> ps) => ps.any((p) => _runtime[p] == null) ? null : ps.every((p) => _runtime[p] == true);

  /// Asks for runtime [permissions]; when Android won't show the prompt any
  /// more (denied twice), opens Triangle's app settings instead.
  Future<void> _ask(List<String> permissions) async {
    final r = await Device.request(permissions);
    if (permissions.any((p) => r[p] != true)) await Device.openAppSettings();
    await _check();
  }

  /// "Allow everything": one Android prompt after another for every runtime
  /// permission that isn't given yet. Special access needs its own switch.
  Future<void> _askAll() async {
    setState(() => _asking = true);
    try {
      final missing = [
        if (_sdk >= 33 && _notifications != true) _postNotifications,
        if (_has(_mic) != true) _mic,
        if (_has(_camera) != true) _camera,
        for (final p in _media)
          if (_has(p) != true) p,
        if (_location != LocationPermission.always && _location != LocationPermission.whileInUse) ...[_fine, _coarse],
        for (final p in Device.all)
          if (_has(p.id) != true) p.id,
      ];
      if (missing.isNotEmpty) await Device.request(missing);
      if (_battery == false) await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      if (_exactAlarms == false) await _android?.requestExactAlarmsPermission();
    } finally {
      if (mounted) setState(() => _asking = false);
      await _check();
    }
  }

  Future<void> _fixNotifications() async {
    final r = await FlutterForegroundTask.requestNotificationPermission();
    if (r == NotificationPermission.permanently_denied) await Geolocator.openAppSettings();
    await _check();
  }

  Future<void> _fixBattery() async {
    final ok = await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    if (!ok) await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    await _check();
  }

  Future<void> _fixAlarms() async {
    await _android?.requestExactAlarmsPermission();
    await _check();
  }

  Future<void> _fixLocation() async {
    if (await Geolocator.checkPermission() == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.requestPermission();
    }
    await _check();
  }

  /// Background location is asked only after location itself; Android 11+
  /// sends the person to settings to pick "Allow all the time".
  Future<void> _fixBackgroundLocation() async {
    if (_location != LocationPermission.always && _location != LocationPermission.whileInUse) {
      await _fixLocation();
      if (!mounted) return;
    }
    await _ask(const [_background]);
  }

  @override
  Widget build(BuildContext context) {
    final android = Platform.isAndroid;
    final locationOk = _location == null
        ? null
        : _location == LocationPermission.always || _location == LocationPermission.whileInUse;
    final mediaOk = _all(_media) == true || (_sdk >= 34 && _has(_selected) == true) ? true : _all(_media);
    final essentials = [_notifications, _battery, _exactAlarms];
    final missing = essentials.where((x) => x == false).length;
    final checked = essentials.every((x) => x != null);
    final runtimeChecks = [
      _has(_mic),
      _has(_camera),
      mediaOk,
      locationOk,
      for (final p in Device.all) _has(p.id),
    ];
    final notAllowed = runtimeChecks.where((x) => x == false).length + missing;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: Space.l, bottom: Space.s),
      child: Text(text.toUpperCase(), style: context.text.labelSmall),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        actions: [IconButton(tooltip: 'Check again', onPressed: _check, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          // At a glance: can watches and reminders work right now?
          Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(
              color: (missing == 0 ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: (missing == 0 ? AppColors.success : AppColors.warning).withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      !checked
                          ? Icons.hourglass_empty_rounded
                          : missing == 0
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      color: missing == 0 ? AppColors.success : AppColors.warning,
                      size: 30,
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            !checked
                                ? 'Checking…'
                                : missing == 0
                                ? 'Ready for the background'
                                : '$missing thing${missing == 1 ? '' : 's'} need${missing == 1 ? 's' : ''} attention',
                            style: context.text.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<WatchStatus>(
                            valueListenable: ref.read(watchEngineProvider).status,
                            builder: (context, st, _) => Text(
                              st.background
                                  ? 'The background service is running now.'
                                  : 'The background service isn\'t running right now.',
                              style: context.text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (android && notAllowed > 0) ...[
                  const SizedBox(height: Space.m),
                  FilledButton.icon(
                    onPressed: _asking ? null : _askAll,
                    icon: _asking
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.done_all_rounded),
                    label: Text('Allow all ($notAllowed)'),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Android asks for each one in turn; you can say no to any. Special access below has its own switch.',
                    style: context.text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          heading('For watches and reminders'),
          _PermissionCard(
            icon: Icons.battery_saver_outlined,
            title: 'Unrestricted battery',
            why: 'Android pauses apps that save battery. Without this, watches stop listening soon after the screen '
                'turns off, and the app can\'t start itself after a restart.',
            ok: _battery,
            action: 'Allow',
            onFix: _fixBattery,
          ),
          _PermissionCard(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            why: 'Shows what watches find, approvals they wait for, mentions and reminders. Watches still run without '
                'it, but quietly.',
            ok: _notifications,
            action: 'Allow',
            onFix: _fixNotifications,
          ),
          _PermissionCard(
            icon: Icons.alarm_rounded,
            title: 'Alarms & reminders',
            why: 'Lets reminders ring on the minute. Without it Android may deliver them a few minutes late.',
            ok: _exactAlarms,
            action: 'Allow',
            onFix: _fixAlarms,
          ),
          heading('Voice, camera and photos'),
          _PermissionCard(
            icon: Icons.mic_none_rounded,
            title: 'Microphone',
            why: 'Dictation, voice mode and recording voice messages.',
            ok: _has(_mic),
            action: 'Allow',
            onFix: () => _ask(const [_mic]),
          ),
          _PermissionCard(
            icon: Icons.photo_camera_outlined,
            title: 'Camera',
            why: 'Scanning QR codes and barcodes, and taking photos to send or ask about.',
            ok: _has(_camera),
            action: 'Allow',
            onFix: () => _ask(const [_camera]),
          ),
          _PermissionCard(
            icon: Icons.photo_library_outlined,
            title: 'Photos & videos',
            why: _sdk >= 34 && _has(_selected) == true && _all(_media) != true
                ? 'Only the photos you picked are shared. Allow all to see every recent photo in the attach sheet.'
                : 'The gallery in the attach sheet, so recent photos and videos are one tap away.',
            ok: mediaOk,
            action: 'Allow',
            onFix: () => _ask(_media),
          ),
          heading('Location'),
          _PermissionCard(
            icon: Icons.location_on_outlined,
            title: 'Location',
            why: 'Only when you ask the assistant to share your location or a live location, or for weather where you are.',
            ok: locationOk,
            action: _location == LocationPermission.deniedForever ? 'Open settings' : 'Allow',
            onFix: _fixLocation,
          ),
          if (android)
            _PermissionCard(
              icon: Icons.share_location_rounded,
              title: 'Location in the background',
              why: 'Keeps a live location you shared updating after you leave Triangle. Pick "Allow all the time".',
              ok: _location == LocationPermission.always ? true : _has(_background),
              action: 'Allow',
              onFix: _fixBackgroundLocation,
            ),
          if (android) ...[
            heading('Phone data for device tools'),
            for (final p in Device.all)
              _PermissionCard(
                icon: switch (p.id.split('.').last) {
                  'READ_SMS' => Icons.sms_outlined,
                  'SEND_SMS' => Icons.outgoing_mail,
                  'READ_CALL_LOG' => Icons.call_received_rounded,
                  'READ_CONTACTS' => Icons.contacts_outlined,
                  'READ_PHONE_STATE' => Icons.sim_card_outlined,
                  _ => Icons.call_outlined,
                },
                title: p.title,
                why: '${p.why} Asked the first time a tool needs it.',
                ok: _has(p.id),
                action: 'Allow',
                onFix: () => _ask([p.id]),
              ),
            heading('Special access'),
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text('Turned on with a switch in Android\'s settings; each opens the right page.', style: context.text.bodySmall),
            ),
            _PermissionCard(
              icon: Icons.notifications_active_outlined,
              title: 'Notification access',
              why: 'Lets the assistant read the notifications other apps post, when you ask what you missed.',
              ok: _notificationAccess,
              action: 'Turn on',
              onFix: () async {
                await Net.openNotificationAccess();
              },
            ),
            _PermissionCard(
              icon: Icons.hourglass_bottom_rounded,
              title: 'Usage access',
              why: 'Screen time, app usage and data used per app.',
              ok: _usageAccess,
              action: 'Turn on',
              onFix: () async {
                await Net.openUsageAccess();
              },
            ),
            _PermissionCard(
              icon: Icons.do_not_disturb_on_outlined,
              title: 'Do Not Disturb access',
              why: 'Lets the assistant switch the ringer to silent or vibrate when you ask.',
              ok: _dnd,
              action: 'Turn on',
              onFix: () async {
                await _quiet(Device.call<bool>('openDndAccess'));
              },
            ),
            _PermissionCard(
              icon: Icons.touch_app_outlined,
              title: 'Screen control',
              why: 'Lets the assistant read the screen and tap, type and scroll in other apps. Set it up, and pick apps '
                  'it may never touch, in Screen control.',
              ok: _screen,
              action: 'Set up',
              onFix: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScreenControlScreen())),
            ),
            _PermissionCard(
              icon: Icons.assistant_outlined,
              title: 'Default assistant',
              why: 'Opens Triangle when you long-press home or use the assistant gesture. Optional.',
              ok: null,
              action: 'Set up',
              onFix: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DefaultAssistantScreen())),
            ),
            const SizedBox(height: Space.s),
            Container(
              padding: const EdgeInsets.all(Space.l),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.text2),
                      const SizedBox(width: Space.s),
                      Expanded(child: Text('A switch is greyed out?', style: context.text.titleSmall)),
                    ],
                  ),
                  const SizedBox(height: Space.s),
                  Text(
                    'Android 13 and newer restricts notification access and accessibility for apps installed from an APK. '
                    'Open Triangle in Android settings, tap ⋮ (top right) → Allow restricted settings, then try the switch again.',
                    style: context.text.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: Space.m),
                  OutlinedButton.icon(
                    onPressed: Device.openAppSettings,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Open Triangle in Android settings'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.l),
          Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.phone_android_rounded, size: 18, color: AppColors.text2),
                    const SizedBox(width: Space.s),
                    Text('Phone makers\' battery savers', style: context.text.titleSmall),
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(
                  'Samsung, Xiaomi, Huawei, Oppo and others add their own battery savers on top of Android\'s. If '
                  'watches still stop, find Triangle in your phone\'s battery settings and set it to "Unrestricted" or '
                  '"No restrictions", allow auto-start, and lock it in the recent apps.',
                  style: context.text.bodySmall?.copyWith(height: 1.4),
                ),
                const SizedBox(height: Space.m),
                OutlinedButton.icon(
                  onPressed: Geolocator.openAppSettings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('Open Triangle in Android settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.why,
    required this.ok,
    required this.action,
    required this.onFix,
  });
  final IconData icon;
  final String title;
  final String why;
  final bool? ok;
  final String action;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final color = ok == null
        ? AppColors.text3
        : ok!
        ? AppColors.success
        : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.s)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: context.text.titleSmall)),
                    if (ok == true)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                          SizedBox(width: 4),
                          Text('Allowed', style: TextStyle(fontSize: 12, color: AppColors.success)),
                        ],
                      )
                    else
                      // A small pill beside the title, not a full-size button.
                      Material(
                        color: AppColors.accentDim,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: onFix,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            child: Text(
                              action,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(why, style: context.text.bodySmall?.copyWith(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
