package com.example.teleai

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.graphics.drawable.toBitmap
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/// SIM cards and the connection, speed tests, data usage per app, and the
/// phone's notifications, for the assistant's network and notification
/// tools. Speed tests run off the main thread and report progress back
/// with "speedProgress" calls ({id, phase, mbps, fraction}).
@SuppressLint("NewApi")
object NetChannel {
    private const val CHANNEL = "teleai/net"
    private val main = Handler(Looper.getMainLooper())
    private val pool = Executors.newCachedThreadPool()
    private val tests = ConcurrentHashMap<String, SpeedTester>()
    private val icons = ConcurrentHashMap<String, ByteArray>()

    fun attach(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (Build.VERSION.SDK_INT < 29) {
                result.error("unsupported", "This needs Android 10 or newer.", null)
                return@setMethodCallHandler
            }
            // Everything here may block (network, usage queries): off the main thread.
            fun work(block: () -> Any?) = pool.execute {
                try {
                    val v = block()
                    main.post { result.success(v) }
                } catch (e: SecurityException) {
                    main.post { result.error("access", e.message ?: "Not allowed", null) }
                } catch (e: Exception) {
                    main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
                }
            }
            when (call.method) {
                "snapshot" -> work { NetInfo.snapshot(app) }
                "speedTest" -> {
                    val id = call.argument<String>("id") ?: "test"
                    val profile = TestProfile.of(call.argument<String>("profile"))
                    val metrics = Metrics.parse(call.argument<String>("metrics"))
                    work {
                        val active = NetInfo.cm(app).activeNetwork
                        val network = NetInfo.describe(app, active)
                        val tester = SpeedTester(active, profile, metrics, { phase, mbps, fraction ->
                            main.post {
                                channel.invokeMethod("speedProgress", mapOf("id" to id, "phase" to phase, "mbps" to mbps, "fraction" to fraction))
                            }
                        }, { info ->
                            main.post { channel.invokeMethod("speedProgress", mapOf("id" to id, "info" to info)) }
                        })
                        tests[id] = tester
                        try {
                            tester.run() + network
                        } finally {
                            tests.remove(id)
                        }
                    }
                }
                "cancelSpeedTest" -> {
                    tests[call.argument<String>("id") ?: ""]?.cancelled = true
                    result.success(true)
                }
                "usageAccess" -> result.success(NetUsage.hasAccess(app))
                "openUsageAccess" -> {
                    val i = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                        data = Uri.parse("package:${app.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    try {
                        app.startActivity(i)
                    } catch (_: Exception) {
                        app.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                    result.success(true)
                }
                "appUsage" -> work {
                    if (!NetUsage.hasAccess(app)) throw SecurityException("usage access")
                    val start = (call.argument<Number>("start") ?: 0).toLong()
                    val end = (call.argument<Number>("end") ?: System.currentTimeMillis()).toLong()
                    NetUsage.apps(app, start, end, false)
                }
                "dailyUsage" -> work {
                    if (!NetUsage.hasAccess(app)) throw SecurityException("usage access")
                    NetUsage.daily(app, call.argument<Int>("days") ?: 7)
                }
                "hotspotUsage" -> work {
                    if (!NetUsage.hasAccess(app)) throw SecurityException("usage access")
                    NetUsage.hotspot(app, call.argument<Int>("days") ?: 7)
                }
                "appIcon" -> work { icon(app, call.argument<String>("package") ?: "") }
                "notificationAccess" -> result.success(NotificationReader.enabled(app))
                "openNotificationAccess" -> {
                    app.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "notifications" -> work {
                    NotificationReader.list(
                        app,
                        since = (call.argument<Number>("since") ?: 0).toLong(),
                        pkg = call.argument<String>("package"),
                        query = call.argument<String>("query"),
                        limit = call.argument<Int>("limit") ?: 100,
                    )
                }
                "clearNotifications" -> work { NotificationReader.clear(app); true }
                else -> result.notImplemented()
            }
        }
    }

    /// An installed app's icon as PNG bytes, 96 px, cached.
    private fun icon(ctx: Context, pkg: String): ByteArray? {
        if (pkg.isEmpty()) return null
        icons[pkg]?.let { return it }
        return try {
            val d = ctx.packageManager.getApplicationIcon(pkg)
            val bmp = d.toBitmap(96, 96, Bitmap.Config.ARGB_8888)
            ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray().also { icons[pkg] = it }
        } catch (_: Exception) {
            null
        }
    }
}
