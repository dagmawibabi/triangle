import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../settings/data/settings.dart';

/// Local notifications for watches, and the quiet ongoing notification that
/// keeps the app alive in the background while watches are on.
class AppNotifier {
  AppNotifier({this.isQuiet});

  /// True inside the user's quiet hours: nothing pops up then.
  final bool Function()? isQuiet;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 100;

  /// Conversation ids from tapped notifications, for the chat screen.
  final taps = StreamController<String>.broadcast();

  static const _channel = 'teleai_watches';
  static const _icon = 'ic_stat_triangle';

  Future<void> init() async {
    if (_ready || !(Platform.isAndroid || Platform.isIOS)) return;
    _ready = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) taps.add(id);
      },
    );
    // A tap that started the app.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && payload != null && payload.isNotEmpty) {
      Future<void>.delayed(const Duration(seconds: 2), () => taps.add(payload));
    }
  }

  /// Whether Android lets the app post notifications; null off Android.
  Future<bool?> permitted() async {
    await init();
    return _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
  }

  /// Whether reminders can ring at the exact minute; null off Android.
  Future<bool?> exactAlarms() async {
    await init();
    return _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.canScheduleExactNotifications();
  }

  Future<void> requestPermission() async {
    await init();
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      // No screen to ask from (a background start).
      debugPrint('[Notify] permission: $e');
    }
  }

  /// Shows a notification; tapping it opens [conversationId] when given.
  Future<void> show(String title, String body, {String? conversationId}) async {
    if (isQuiet?.call() ?? false) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        payload: conversationId,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel,
            'Watches',
            channelDescription: 'New messages and updates from your watches',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[Notify] $e');
    }
  }

  // ---- scheduled ------------------------------------------------------------

  static const _reminderChannel = 'teleai_reminders';
  bool _tzReady = false;

  /// Has Android show a reminder at [at], even if the app isn't running by
  /// then. Quiet hours and the Notifications setting don't apply: the person
  /// asked for this one. Exact when Android allows it, else within minutes.
  Future<void> schedule(int id, DateTime at, String title, String body, {String? conversationId}) async {
    await init();
    if (!_ready) return;
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? true;
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        payload: conversationId,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _reminderChannel,
            'Reminders',
            channelDescription: 'Reminders and scheduled jobs you asked for',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[Notify] schedule: $e');
    }
  }

  Future<void> cancel(int id) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  /// Asks Android 12+ to allow exact alarms, so reminders fire on the minute.
  Future<void> requestExactAlarms() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null || (await android.canScheduleExactNotifications() ?? true)) return;
    await android.requestExactAlarmsPermission();
  }

  // ---- keep alive -----------------------------------------------------------

  bool _alive = false;
  bool _asked = false;
  bool _taskReady = false;
  bool? _taskMinimised;

  /// Whether the background service is running, as last checked.
  bool get alive => _alive;

  /// Starts or stops the ongoing notification that keeps the process
  /// running while the app is in the background. TDLib, the watches and the
  /// assistant all live in the app's process, so this is all they need.
  ///
  /// This doesn't depend on the "Notifications" setting: that one is about
  /// alerts for what watches find. Android only keeps a background service
  /// running reliably when its ongoing notification may be shown and the
  /// app isn't battery-optimised, so both are asked for once here.
  ///
  /// [notice] is how it shows: [BackgroundNotice.minimised] uses a channel
  /// Android folds away without a status bar icon; [BackgroundNotice.off]
  /// runs no service at all, so Android may stop the app in the background.
  Future<void> keepAlive(bool on, {int watches = 0, BackgroundNotice notice = BackgroundNotice.shown}) async {
    final title = watches > 0 ? 'Triangle is watching' : 'Triangle is running';
    final text = watches > 0 ? '$watches watch${watches == 1 ? '' : 'es'} on' : 'Ready in the background';
    if (!Platform.isAndroid) return;
    if (notice == BackgroundNotice.off) on = false;
    final minimised = notice == BackgroundNotice.minimised;
    try {
      // A channel's importance is fixed once made, so each look has its own.
      if (_taskMinimised != minimised) {
        if (_taskReady && await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
          _alive = false;
        }
        _taskReady = false;
      }
      if (!_taskReady) {
        _taskReady = true;
        _taskMinimised = minimised;
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: minimised ? 'teleai_keep_alive_min' : 'teleai_keep_alive',
            channelName: minimised ? 'Running (minimised)' : 'Watching',
            channelDescription: 'Shown while Triangle watches your chats in the background',
            channelImportance: minimised ? NotificationChannelImportance.MIN : NotificationChannelImportance.LOW,
            priority: minimised ? NotificationPriority.MIN : NotificationPriority.LOW,
            onlyAlertOnce: true,
            showWhen: false,
          ),
          iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            allowWakeLock: true,
            allowWifiLock: true,
          ),
        );
      }
      // A service still running from before the app's isolate restarted.
      _alive = await FlutterForegroundTask.isRunningService;
      if (on && !_asked) {
        _asked = true;
        try {
          if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
            await FlutterForegroundTask.requestNotificationPermission();
          }
          if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
            await FlutterForegroundTask.requestIgnoreBatteryOptimization();
          }
        } catch (e) {
          // No screen to ask from (a background start); ask next time.
          _asked = false;
          debugPrint('[KeepAlive] permissions: $e');
        }
      }
      if (on && !_alive) {
        final r = await FlutterForegroundTask.startService(
          serviceId: 5107,
          serviceTypes: const [ForegroundServiceTypes.specialUse],
          notificationTitle: title,
          notificationText: text,
          notificationIcon: const NotificationIcon(metaDataName: 'com.triangle.STAT_ICON'),
          callback: keepAliveEntryPoint,
        );
        _alive = r is ServiceRequestSuccess;
      } else if (on && _alive) {
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
      } else if (!on && _alive) {
        await FlutterForegroundTask.stopService();
        _alive = false;
      }
    } catch (e) {
      debugPrint('[KeepAlive] $e');
    }
  }
}

/// The service's own isolate has nothing to do: the work happens in the
/// app's isolate, which the service keeps alive.
@pragma('vm:entry-point')
void keepAliveEntryPoint() => FlutterForegroundTask.setTaskHandler(_IdleHandler());

class _IdleHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

final appNotifierProvider = Provider<AppNotifier>(
  (ref) => AppNotifier(isQuiet: () => ref.read(settingsProvider).isQuietNow),
);
