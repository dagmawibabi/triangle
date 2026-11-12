package com.example.teleai

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Triangle as the phone's assistant: long-pressing the home button (or the
/// assistant gesture) opens it. Android sends ACTION_ASSIST to MainActivity;
/// this tells Flutter, which opens what Settings → Default assistant says.
/// An assist that arrives before Flutter is listening waits in [pending].
object AssistChannel {
    private const val CHANNEL = "teleai/assist"
    private var channel: MethodChannel? = null
    private var pending = false

    fun attach(context: Context, engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDefault" -> result.success(isDefault(context))
                    "openSettings" -> result.success(openSettings(DeviceChannel.activity ?: context))
                    "takePending" -> {
                        result.success(pending)
                        pending = false
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun isAssist(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_ASSIST || intent?.action == Intent.ACTION_VOICE_COMMAND

    /// Called with the activity's intent; true when it was an assist.
    fun handle(intent: Intent?): Boolean {
        if (!isAssist(intent)) return false
        pending = true
        channel?.invokeMethod("assist", mapOf("voice" to (intent?.action == Intent.ACTION_VOICE_COMMAND)))
        return true
    }

    private fun isDefault(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = context.getSystemService(RoleManager::class.java)
            if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
                return roles.isRoleHeld(RoleManager.ROLE_ASSISTANT)
            }
        }
        val current = Settings.Secure.getString(context.contentResolver, "assistant") ?: return false
        return current.startsWith("${context.packageName}/")
    }

    /// Android doesn't let apps ask for the assistant role in a dialog, so
    /// this opens the screen where the user picks it.
    private fun openSettings(context: Context): Boolean {
        val tries = listOf(
            Intent(Settings.ACTION_VOICE_INPUT_SETTINGS),
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in tries) {
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }
}
