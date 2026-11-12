package com.example.teleai

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/// A FlutterFragmentActivity (local_auth's biometric prompt needs a
/// fragment activity) would destroy its engine (and so the isolate TDLib,
/// the watches and the assistant run in) whenever the activity goes away:
/// back out of the app, swipe it from recents, or let Android reclaim it.
/// So the activity borrows the process's engine (see [MainEngine]), which
/// may already be running in the background, and leaves it running.
class MainActivity : FlutterFragmentActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = MainEngine.ensure(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DeviceChannel.activity = this
        BriefWidget.handle(intent)
        ShareChannel.handle(this, intent)
        AssistChannel.handle(intent)
        // Opened from the launcher on a fresh screen (not restored after a
        // rotation, and not a notification, widget or share, which say
        // where to go themselves).
        val launcher = intent?.action == Intent.ACTION_MAIN && intent?.hasCategory(Intent.CATEGORY_LAUNCHER) == true
        if (savedInstanceState == null && launcher) AppOpenChannel.opened()
    }

    override fun onResume() {
        super.onResume()
        DeviceChannel.activity = this
    }

    override fun onDestroy() {
        if (DeviceChannel.activity === this) DeviceChannel.activity = null
        super.onDestroy()
    }

    /// Answers to the device tools' permission requests.
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (!DeviceChannel.onPermissionResult(requestCode, permissions, grantResults)) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    /// The brief widget was tapped, or something was shared, while the app
    /// was open.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        BriefWidget.handle(intent)
        ShareChannel.handle(this, intent)
        AssistChannel.handle(intent)
    }
}
