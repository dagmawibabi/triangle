package com.example.teleai

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Picture-in-picture for videos: Flutter asks to go into a small window
/// (or says a video is playing, so leaving the app does it on its own), and
/// is told when the window opens and closes, to show only the video.
object PipChannel {
    private const val CHANNEL = "teleai/pip"
    private var channel: MethodChannel? = null
    var activity: Activity? = null

    /// A video is playing: leaving the app goes to picture-in-picture.
    private var auto = false
    private var ratio = Rational(16, 9)

    fun attach(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "supported" -> result.success(supported())
                    "enter" -> {
                        setRatio(call.argument<Int>("w"), call.argument<Int>("h"))
                        result.success(enter())
                    }
                    "setAuto" -> {
                        auto = call.argument<Boolean>("enabled") ?: false
                        setRatio(call.argument<Int>("w"), call.argument<Int>("h"))
                        applyParams()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun setRatio(w: Int?, h: Int?) {
        if (w == null || h == null || w <= 0 || h <= 0) return
        // Android allows between 1:2.39 and 2.39:1.
        val r = w.toDouble() / h
        ratio = when {
            r > 2.39 -> Rational(239, 100)
            r < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(w, h)
        }
    }

    private fun supported(): Boolean {
        val a = activity ?: return false
        return Build.VERSION.SDK_INT >= 26 && a.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun params(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < 26) return null
        val b = PictureInPictureParams.Builder().setAspectRatio(ratio)
        if (Build.VERSION.SDK_INT >= 31) {
            b.setAutoEnterEnabled(auto)
            b.setSeamlessResizeEnabled(true)
        }
        return b.build()
    }

    private fun applyParams() {
        val a = activity ?: return
        if (!supported() || Build.VERSION.SDK_INT < 26) return
        try {
            a.setPictureInPictureParams(params()!!)
        } catch (_: Exception) {}
    }

    fun enter(): Boolean {
        val a = activity ?: return false
        if (!supported() || Build.VERSION.SDK_INT < 26) return false
        return try {
            a.enterPictureInPictureMode(params()!!)
        } catch (_: Exception) {
            false
        }
    }

    /// Leaving the app (home, recents) while a video plays, on Androids
    /// that don't enter on their own.
    fun onUserLeaveHint() {
        if (auto && Build.VERSION.SDK_INT in 26..30) enter()
    }

    fun changed(inPip: Boolean) {
        channel?.invokeMethod("changed", inPip)
    }
}
