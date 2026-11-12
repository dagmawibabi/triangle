package com.example.teleai

import android.content.Context
import android.os.SystemClock
import com.pravera.flutter_foreground_task.models.ForegroundServiceStatus
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/// TDLib, the watches and the assistant all run in the app's Dart isolate.
/// The engine that runs it belongs to the process, not to a screen: the
/// activity borrows it, and it can start with no screen at all — after a
/// reboot, or when Android restarts the process for the background service.
object MainEngine {
    private const val ENGINE_ID = "teleai_main"

    /// Settings written by Flutter's shared_preferences.
    private fun prefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun ensure(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        BriefWidget.attach(context, engine)
        DeviceChannel.attach(context, engine)
        ShareChannel.attach(context, engine)
        AppOpenChannel.attach(engine)
        AssistChannel.attach(context.applicationContext, engine)
        VoiceLevelChannel.attach(engine)
        NetChannel.attach(context, engine)
        ScreenControl.attach(context, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cache.put(ENGINE_ID, engine)
        return engine
    }

    /// "Start when the phone restarts".
    fun startsOnBoot(context: Context): Boolean = prefs(context).getBoolean("flutter.start_on_boot", false)

    /// Whether the app should be running now without a screen: always, or
    /// because its background service was running and didn't stop properly
    /// (Android killed the process, or the app was swiped away).
    fun wantedInBackground(context: Context): Boolean {
        val p = prefs(context)
        if (p.getBoolean("flutter.background_always", false)) return true
        if (!p.getBoolean("flutter.keep_alive", true)) return false
        return !ForegroundServiceStatus.getData(context).isCorrectlyStopped()
    }

    /// Shortly after boot the boot receiver decides, from its own setting.
    fun justBooted(): Boolean = SystemClock.elapsedRealtime() < 3 * 60 * 1000
}
