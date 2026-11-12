package com.example.teleai

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar

/// Screen time from Android's usage stats: how long each app was on screen,
/// per day and per hour, how often it was opened, and how often the phone
/// was unlocked. Needs usage access (the same switch as data usage).
///
/// Foreground time is rebuilt from usage events, which Android keeps for
/// about a week or so; older days fall back to the daily summaries.
object ScreenTime {

    private fun startOfDay(ts: Long): Long = Calendar.getInstance().apply {
        timeInMillis = ts
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun nextDay(ts: Long): Long = Calendar.getInstance().apply {
        timeInMillis = ts; add(Calendar.DAY_OF_YEAR, 1)
    }.timeInMillis

    private class Day(val start: Long) {
        val apps = HashMap<String, Long>()
        val launches = HashMap<String, Int>()
        val hours = LongArray(24)
        var unlocks = 0
        var firstUse = 0L
    }

    /// Packages that aren't "using the phone": the home screen, the system
    /// UI and this app's own background work.
    private fun ignored(ctx: Context): Set<String> {
        val pm = ctx.packageManager
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val launchers = pm.queryIntentActivities(home, 0).map { it.activityInfo.packageName }
        return (launchers + listOf("com.android.systemui", "android")).toSet()
    }

    /// Splits [from]..[to] of [pkg] across days and hours.
    private fun add(days: List<Day>, pkg: String, from: Long, to: Long) {
        if (to <= from) return
        for (d in days) {
            val end = nextDay(d.start)
            val a = maxOf(from, d.start)
            val b = minOf(to, end)
            if (b <= a) continue
            d.apps[pkg] = (d.apps[pkg] ?: 0L) + (b - a)
            if (d.firstUse == 0L || a < d.firstUse) d.firstUse = a
            var t = a
            while (t < b) {
                val cal = Calendar.getInstance().apply { timeInMillis = t }
                val h = cal.get(Calendar.HOUR_OF_DAY)
                cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0); cal.add(Calendar.HOUR_OF_DAY, 1)
                val stop = minOf(b, cal.timeInMillis)
                d.hours[h] += stop - t
                t = stop
            }
        }
    }

    /// Usage for the [days] days ending today (or ending on [endDay]).
    fun query(ctx: Context, days: Int, endDay: Long?): Map<String, Any?> {
        if (!NetUsage.hasAccess(ctx)) throw SecurityException("usage access")
        val usm = ctx.getSystemService(UsageStatsManager::class.java)
        val now = System.currentTimeMillis()
        val lastStart = startOfDay(endDay ?: now)
        val list = ArrayList<Day>()
        var s = lastStart
        for (i in 0 until days.coerceIn(1, 35)) {
            list.add(0, Day(s))
            s = Calendar.getInstance().apply { timeInMillis = s; add(Calendar.DAY_OF_YEAR, -1) }.timeInMillis
        }
        val rangeStart = list.first().start
        val rangeEnd = minOf(nextDay(lastStart), now)
        val skip = ignored(ctx)

        // Rebuild foreground spans from events. Start a little early so an
        // app already open at midnight is counted from midnight.
        val open = HashMap<String, Long>()
        val lastUsed = HashMap<String, Long>()
        val lastClosed = HashMap<String, Long>()
        var current: String? = null
        var screenOn = true
        val events = usm.queryEvents(rangeStart - 3 * 3600_000L, rangeEnd)
        val e = UsageEvents.Event()
        var earliestEvent = Long.MAX_VALUE
        fun close(pkg: String, at: Long) {
            val from = open.remove(pkg) ?: return
            lastClosed[pkg] = at
            add(list, pkg, maxOf(from, rangeStart), minOf(at, rangeEnd))
        }
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            val pkg = e.packageName ?: continue
            val t = e.timeStamp
            if (t < earliestEvent) earliestEvent = t
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    if (pkg in skip) { current?.let { close(it, t) }; current = null; continue }
                    if (current != null && current != pkg) close(current!!, t)
                    if (!open.containsKey(pkg)) {
                        open[pkg] = t
                        // Moving between an app's own screens isn't opening it again.
                        if (t >= rangeStart && t - (lastClosed[pkg] ?: 0L) > 5000) {
                            list.lastOrNull { it.start <= t }?.let { d -> d.launches[pkg] = (d.launches[pkg] ?: 0) + 1 }
                        }
                    }
                    current = pkg
                    lastUsed[pkg] = t
                }
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> {
                    if (pkg == current || open.containsKey(pkg)) {
                        close(pkg, t)
                        if (pkg == current) current = null
                        lastUsed[pkg] = t
                    }
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    screenOn = false
                    for (p in open.keys.toList()) close(p, t)
                    current = null
                }
                UsageEvents.Event.SCREEN_INTERACTIVE -> screenOn = true
                UsageEvents.Event.KEYGUARD_HIDDEN -> if (t >= rangeStart) {
                    list.lastOrNull { it.start <= t }?.let { it.unlocks++ }
                }
            }
        }
        if (screenOn) for (p in open.keys.toList()) close(p, rangeEnd)

        // Days older than the event history: Android's daily summaries.
        val summarized = ArrayList<Long>()
        if (earliestEvent != Long.MAX_VALUE) {
            for (d in list) {
                if (nextDay(d.start) > earliestEvent || d.apps.isNotEmpty()) continue
                val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, d.start, nextDay(d.start))
                for (st in stats) {
                    if (st.packageName in skip || st.totalTimeInForeground <= 0) continue
                    if (st.firstTimeStamp < d.start - 3600_000L || st.firstTimeStamp >= nextDay(d.start)) continue
                    d.apps[st.packageName] = (d.apps[st.packageName] ?: 0L) + st.totalTimeInForeground
                }
                if (d.apps.isNotEmpty()) summarized.add(d.start)
            }
        }

        val pm = ctx.packageManager
        val names = HashMap<String, Pair<String, Boolean>>()
        fun meta(pkg: String): Pair<String, Boolean> = names.getOrPut(pkg) {
            try {
                val info = pm.getApplicationInfo(pkg, 0)
                pm.getApplicationLabel(info).toString() to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0 && pm.getLaunchIntentForPackage(pkg) == null)
            } catch (_: PackageManager.NameNotFoundException) {
                pkg to false
            }
        }
        val category = HashMap<String, String?>()
        fun cat(pkg: String): String? = category.getOrPut(pkg) {
            if (Build.VERSION.SDK_INT < 26) return@getOrPut null
            try {
                when (pm.getApplicationInfo(pkg, 0).category) {
                    ApplicationInfo.CATEGORY_GAME -> "games"
                    ApplicationInfo.CATEGORY_AUDIO -> "music & audio"
                    ApplicationInfo.CATEGORY_VIDEO -> "video"
                    ApplicationInfo.CATEGORY_IMAGE -> "photos"
                    ApplicationInfo.CATEGORY_SOCIAL -> "social"
                    ApplicationInfo.CATEGORY_NEWS -> "news"
                    ApplicationInfo.CATEGORY_MAPS -> "maps & travel"
                    ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
                    else -> null
                }
            } catch (_: Exception) { null }
        }

        return mapOf(
            "days" to list.map { d ->
                mapOf(
                    "date" to d.start,
                    "total" to d.apps.values.sum(),
                    "unlocks" to d.unlocks,
                    "first_use" to if (d.firstUse > 0) d.firstUse else null,
                    "hours" to d.hours.toList(),
                    "summary_only" to (d.start in summarized),
                    "apps" to d.apps.entries.sortedByDescending { it.value }.map { (pkg, ms) ->
                        mapOf("package" to pkg, "ms" to ms, "launches" to (d.launches[pkg] ?: 0))
                    },
                )
            },
            "apps" to list.flatMap { it.apps.keys }.toSet().map { pkg ->
                val m = meta(pkg)
                mapOf("package" to pkg, "name" to m.first, "category" to cat(pkg), "last_used" to lastUsed[pkg])
            },
            "history_from" to if (earliestEvent == Long.MAX_VALUE) null else earliestEvent,
        )
    }
}
