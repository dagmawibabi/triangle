package com.example.teleai

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/// Keeps the phone's notifications for the assistant's notification tool,
/// once the person turns on notification access for Triangle. Only what
/// people would read: titles, texts and chat messages, from the last three
/// days, kept in the app's own files and never sent anywhere by itself.
class NotificationReader : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            record(applicationContext, sbn)
        } catch (_: Throwable) {
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        try {
            dismissed(applicationContext, sbn.key)
        } catch (_: Throwable) {
        }
    }

    companion object {
        private const val FILE = "notifications.json"
        private const val KEEP_MS = 3L * 24 * 60 * 60 * 1000
        private const val MAX = 1500
        private val lock = Any()
        private var cache: MutableList<JSONObject>? = null
        private val labels = HashMap<String, String>()

        fun enabled(ctx: Context): Boolean {
            val flat = Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners") ?: return false
            val me = ComponentName(ctx, NotificationReader::class.java)
            return flat.split(":").any { ComponentName.unflattenFromString(it) == me }
        }

        private fun file(ctx: Context) = File(ctx.filesDir, FILE)

        private fun load(ctx: Context): MutableList<JSONObject> {
            cache?.let { return it }
            val list = mutableListOf<JSONObject>()
            try {
                val f = file(ctx)
                if (f.exists()) {
                    val arr = JSONArray(f.readText())
                    for (i in 0 until arr.length()) list.add(arr.getJSONObject(i))
                }
            } catch (_: Exception) {
            }
            cache = list
            return list
        }

        private fun save(ctx: Context, list: List<JSONObject>) {
            try {
                val arr = JSONArray()
                list.forEach { arr.put(it) }
                file(ctx).writeText(arr.toString())
            } catch (_: Exception) {
            }
        }

        private fun label(ctx: Context, pkg: String): String = labels.getOrPut(pkg) {
            try {
                val pm = ctx.packageManager
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (_: Exception) {
                pkg
            }
        }

        private fun isSystem(ctx: Context, pkg: String): Boolean = try {
            (ctx.packageManager.getApplicationInfo(pkg, 0).flags and ApplicationInfo.FLAG_SYSTEM) != 0
        } catch (_: Exception) {
            false
        }

        private fun text(extras: Bundle, key: String): String? = extras.getCharSequence(key)?.toString()?.trim()?.ifEmpty { null }

        fun record(ctx: Context, sbn: StatusBarNotification) {
            val n = sbn.notification ?: return
            if (sbn.packageName == ctx.packageName) return
            // Ongoing ones (music, downloads, navigation) and group headers aren't news.
            if (sbn.isOngoing || (n.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
            val e = n.extras ?: return
            val title = text(e, Notification.EXTRA_TITLE) ?: text(e, Notification.EXTRA_CONVERSATION_TITLE)
            val body = text(e, Notification.EXTRA_BIG_TEXT) ?: text(e, Notification.EXTRA_TEXT)
            val messages = JSONArray()
            @Suppress("DEPRECATION")
            e.getParcelableArray(Notification.EXTRA_MESSAGES)?.forEach { p ->
                val b = p as? Bundle ?: return@forEach
                val t = b.getCharSequence("text")?.toString() ?: return@forEach
                val who = b.getCharSequence("sender")?.toString()
                    ?: (b.get("sender_person") as? android.app.Person)?.name?.toString()
                messages.put(JSONObject().put("sender", who ?: JSONObject.NULL).put("text", t).put("time", b.getLong("time")))
            }
            if (title == null && body == null && messages.length() == 0) return
            val item = JSONObject()
                .put("key", sbn.key)
                .put("package", sbn.packageName)
                .put("app", label(ctx, sbn.packageName))
                .put("title", title ?: JSONObject.NULL)
                .put("text", body ?: JSONObject.NULL)
                .put("sub", text(e, Notification.EXTRA_SUB_TEXT) ?: JSONObject.NULL)
                .put("category", n.category ?: JSONObject.NULL)
                .put("time", sbn.postTime)
                .put("system", isSystem(ctx, sbn.packageName))
                .put("conversation", e.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION) || messages.length() > 0)
            if (messages.length() > 0) item.put("messages", messages)
            synchronized(lock) {
                val list = load(ctx)
                // The same notification updated with nothing new: keep one.
                val last = list.lastOrNull { it.optString("key") == sbn.key }
                if (last != null && last.optString("text") == item.optString("text") && last.optString("title") == item.optString("title")) return
                list.add(item)
                val cutoff = System.currentTimeMillis() - KEEP_MS
                list.removeAll { it.optLong("time") < cutoff }
                while (list.size > MAX) list.removeAt(0)
                save(ctx, list)
            }
        }

        fun dismissed(ctx: Context, key: String) {
            synchronized(lock) {
                val list = load(ctx)
                var changed = false
                for (it in list) {
                    if (it.optString("key") == key && !it.has("dismissed")) {
                        it.put("dismissed", System.currentTimeMillis())
                        changed = true
                    }
                }
                if (changed) save(ctx, list)
            }
        }

        fun list(ctx: Context, since: Long, pkg: String?, query: String?, limit: Int): List<Map<String, Any?>> {
            val q = query?.trim()?.lowercase()?.ifEmpty { null }
            val p = pkg?.trim()?.lowercase()?.ifEmpty { null }
            val items = synchronized(lock) { load(ctx).toList() }
            return items.asReversed()
                .asSequence()
                .filter { it.optLong("time") >= since }
                .filter { p == null || it.optString("package").lowercase().contains(p) || it.optString("app").lowercase().contains(p) }
                .filter { q == null || it.toString().lowercase().contains(q) }
                .take(limit.coerceIn(1, 1000))
                .map { toMap(it) }
                .toList()
        }

        fun clear(ctx: Context) {
            synchronized(lock) {
                cache = mutableListOf()
                file(ctx).delete()
            }
        }

        private fun toMap(o: JSONObject): Map<String, Any?> {
            val m = HashMap<String, Any?>()
            for (k in o.keys()) {
                val v = o.get(k)
                m[k] = when (v) {
                    JSONObject.NULL -> null
                    is JSONArray -> (0 until v.length()).map { i ->
                        val x = v.getJSONObject(i)
                        mapOf("sender" to x.opt("sender")?.takeIf { it != JSONObject.NULL }, "text" to x.optString("text"), "time" to x.optLong("time"))
                    }
                    else -> v
                }
            }
            return m
        }
    }
}
