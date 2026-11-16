package com.example.teleai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// The music player's notification as Android's own media player: a
/// MediaSession (so it shows as the player card in quick settings and on
/// the lock screen, with the cover, a seek bar and the buttons, and headset
/// buttons work) and a MediaStyle notification tied to it. Flutter sends
/// what's playing; the buttons come back to Flutter as actions.
object MediaSessionChannel {
    private const val CHANNEL = "teleai/media_session"
    private const val NOTIFY_CHANNEL = "teleai_player_session"
    private const val NOTIFY_ID = 7071
    private const val ACTION = "com.example.teleai.MEDIA_ACTION"

    private var channel: MethodChannel? = null
    private var session: MediaSession? = null
    private var receiver: BroadcastReceiver? = null
    private var art: Pair<String, Bitmap?>? = null

    fun attach(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "update" -> {
                            update(app, call.arguments as Map<*, *>)
                            result.success(true)
                        }
                        "clear" -> {
                            clear(app)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("media", e.message, null)
                }
            }
        }
    }

    private fun send(action: String, arg: Any? = null) {
        channel?.invokeMethod("action", mapOf("action" to action, "arg" to arg))
    }

    private fun ensureSession(context: Context): MediaSession {
        session?.let { return it }
        val s = MediaSession(context, "Triangle")
        s.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = send("play")
            override fun onPause() = send("pause")
            override fun onSkipToNext() = send("next")
            override fun onSkipToPrevious() = send("previous")
            override fun onStop() = send("stop")
            override fun onSeekTo(pos: Long) = send("seek", pos)
        })
        s.isActive = true
        session = s
        // Buttons on the notification (older Androids draw these).
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) {
                send(i?.getStringExtra("action") ?: return)
            }
        }
        val filter = IntentFilter(ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(r, filter)
        }
        receiver = r
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(NOTIFY_CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(NOTIFY_CHANNEL, "Player", NotificationManager.IMPORTANCE_LOW).apply {
                        description = "What's playing, with controls"
                        setShowBadge(false)
                        setSound(null, null)
                        enableVibration(false)
                    }
                )
            }
        }
        return s
    }

    private fun pending(context: Context, action: String, code: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            code,
            Intent(ACTION).setPackage(context.packageName).putExtra("action", action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun cover(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        art?.let { if (it.first == path) return it.second }
        val bmp = try {
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, o)
            var sample = 1
            while (o.outWidth / sample > 1024 || o.outHeight / sample > 1024) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (_: Exception) {
            null
        }
        art = path to bmp
        return bmp
    }

    private fun update(context: Context, a: Map<*, *>) {
        val s = ensureSession(context)
        val title = a["title"] as? String ?: ""
        val subtitle = a["subtitle"] as? String ?: ""
        val playing = a["playing"] as? Boolean ?: false
        val position = (a["position"] as? Number)?.toLong() ?: 0L
        val duration = (a["duration"] as? Number)?.toLong() ?: 0L
        val speed = (a["speed"] as? Number)?.toFloat() ?: 1f
        val hasNext = a["hasNext"] as? Boolean ?: false
        val hasPrevious = a["hasPrevious"] as? Boolean ?: true
        val bmp = cover(a["art"] as? String)

        val meta = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
        if (bmp != null) meta.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bmp)
        s.setMetadata(meta.build())

        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_STOP
        if (hasNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        if (hasPrevious) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, position, if (playing) speed else 0f)
                .build()
        )

        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, 0, it.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        fun button(icon: Int, label: String, action: String, code: Int) =
            Notification.Action.Builder(Icon.createWithResource(context, icon), label, pending(context, action, code)).build()

        val buttons = mutableListOf<Notification.Action>()
        val compact = mutableListOf<Int>()
        if (hasPrevious) {
            buttons += button(R.drawable.ic_media_prev_tri, "Previous", "previous", 1)
            compact += buttons.size - 1
        }
        buttons += if (playing) button(R.drawable.ic_media_pause_tri, "Pause", "pause", 2) else button(R.drawable.ic_media_play_tri, "Play", "play", 3)
        compact += buttons.size - 1
        if (hasNext) {
            buttons += button(R.drawable.ic_media_next_tri, "Next", "next", 4)
            compact += buttons.size - 1
        }
        buttons += button(R.drawable.ic_media_close_tri, "Close", "stop", 5)

        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, NOTIFY_CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context)
        b.setSmallIcon(R.drawable.ic_stat_triangle)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setOngoing(playing)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setDeleteIntent(pending(context, "stop", 6))
            .setStyle(Notification.MediaStyle().setMediaSession(s.sessionToken).setShowActionsInCompactView(*compact.toIntArray()))
        if (bmp != null) b.setLargeIcon(bmp)
        if (open != null) b.setContentIntent(open)
        buttons.forEach { b.addAction(it) }
        try {
            context.getSystemService(NotificationManager::class.java).notify(NOTIFY_ID, b.build())
        } catch (_: SecurityException) {
            // Notifications not allowed: the session still serves the lock
            // screen and headset buttons.
        }
    }

    private fun clear(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFY_ID)
        session?.let {
            it.isActive = false
            it.release()
        }
        session = null
        receiver?.let { try { context.unregisterReceiver(it) } catch (_: Exception) {} }
        receiver = null
        art = null
    }
}
