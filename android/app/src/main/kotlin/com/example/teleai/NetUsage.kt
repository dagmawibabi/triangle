package com.example.teleai

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.graphics.Bitmap
import android.net.ConnectivityManager
import android.net.TrafficStats
import android.os.Process
import androidx.core.graphics.drawable.toBitmap
import java.io.ByteArrayOutputStream
import java.util.Calendar

/** Per-app, per-day, hotspot and per-SIM data usage. */
object NetUsage {

    private const val UID_TETHERING = NetworkStats.Bucket.UID_TETHERING
    private const val UID_REMOVED = NetworkStats.Bucket.UID_REMOVED
    private val types = listOf(ConnectivityManager.TYPE_WIFI to true, ConnectivityManager.TYPE_MOBILE to false)

    fun hasAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(AppOpsManager::class.java)
        val mode = ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        return if (mode == AppOpsManager.MODE_DEFAULT)
            ctx.checkCallingOrSelfPermission(android.Manifest.permission.PACKAGE_USAGE_STATS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        else mode == AppOpsManager.MODE_ALLOWED
    }

    private fun nsm(ctx: Context) = ctx.getSystemService(NetworkStatsManager::class.java)

    fun startOfDay(ts: Long): Long = Calendar.getInstance().apply {
        timeInMillis = ts
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun addDays(ts: Long, days: Int): Long = Calendar.getInstance().apply {
        timeInMillis = ts; add(Calendar.DAY_OF_YEAR, days)
    }.timeInMillis

    private class Agg { var wr = 0L; var wt = 0L; var mr = 0L; var mt = 0L }

    /** Usage per app between [start] and [end]. */
    fun apps(ctx: Context, start: Long, end: Long, withIcons: Boolean): List<Map<String, Any?>> {
        val nsm = nsm(ctx)
        val map = HashMap<Int, Agg>()
        for ((type, isWifi) in types) {
            val stats = try {
                nsm.querySummary(type, null, start, end)
            } catch (e: SecurityException) {
                throw e
            } catch (_: Exception) {
                null
            } ?: continue
            val b = NetworkStats.Bucket()
            while (stats.hasNextBucket()) {
                stats.getNextBucket(b)
                val a = map.getOrPut(b.uid) { Agg() }
                if (isWifi) { a.wr += b.rxBytes; a.wt += b.txBytes } else { a.mr += b.rxBytes; a.mt += b.txBytes }
            }
            stats.close()
        }
        return map.filter { (_, a) -> a.wr + a.wt + a.mr + a.mt > 0 }
            .map { (uid, a) ->
                appMeta(ctx, uid, withIcons) + mapOf(
                    "uid" to uid,
                    "wifiRx" to a.wr, "wifiTx" to a.wt, "mobileRx" to a.mr, "mobileTx" to a.mt,
                    "total" to a.wr + a.wt + a.mr + a.mt,
                )
            }
            .sortedByDescending { it["total"] as Long }
    }

    private val metaCache = HashMap<Int, Map<String, Any?>>()

    private fun appMeta(ctx: Context, uid: Int, withIcon: Boolean): Map<String, Any?> {
        metaCache[uid]?.let { if (!withIcon || it.containsKey("icon")) return it }
        val pm = ctx.packageManager
        val meta: Map<String, Any?> = when (uid) {
            UID_TETHERING -> mapOf("name" to "Hotspot & tethering", "package" to null, "special" to "tethering")
            UID_REMOVED -> mapOf("name" to "Removed apps", "package" to null, "special" to "removed")
            0 -> mapOf("name" to "Kernel / root", "package" to null, "special" to "system")
            1000 -> mapOf("name" to "Android system", "package" to "android", "special" to "system")
            else -> {
                val pkgs = try { pm.getPackagesForUid(uid) } catch (_: Exception) { null }
                if (pkgs.isNullOrEmpty()) {
                    mapOf("name" to (try { pm.getNameForUid(uid) } catch (_: Exception) { null } ?: "UID $uid"), "package" to null, "special" to "unknown")
                } else {
                    val pkg = pkgs.first()
                    val ai = try { pm.getApplicationInfo(pkg, 0) } catch (_: Exception) { null }
                    val label = ai?.let { pm.getApplicationLabel(it).toString() } ?: pkg
                    val m = mutableMapOf<String, Any?>(
                        "name" to if (pkgs.size > 1) "$label (+${pkgs.size - 1} shared)" else label,
                        "package" to pkg,
                        "system" to ((ai?.flags ?: 0) and android.content.pm.ApplicationInfo.FLAG_SYSTEM != 0),
                    )
                    if (withIcon && ai != null) {
                        m["icon"] = try {
                            val bmp = pm.getApplicationIcon(ai).toBitmap(96, 96, Bitmap.Config.ARGB_8888)
                            ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
                        } catch (_: Exception) { null }
                    }
                    m
                }
            }
        }
        metaCache[uid] = meta
        return meta
    }

    /** Device-wide Wi-Fi/mobile usage per local day, oldest first. */
    fun daily(ctx: Context, days: Int): List<Map<String, Any?>> {
        val nsm = nsm(ctx)
        val now = System.currentTimeMillis()
        val today = startOfDay(now)
        val out = ArrayList<Map<String, Any?>>()
        for (i in days - 1 downTo 0) {
            val s = addDays(today, -i)
            val e = minOf(addDays(s, 1), now)
            val row = mutableMapOf<String, Any?>("day" to s)
            for ((type, isWifi) in types) {
                val b = try { nsm.querySummaryForDevice(type, null, s, e) } catch (e: SecurityException) { throw e } catch (_: Exception) { null }
                val p = if (isWifi) "wifi" else "mobile"
                row["${p}Rx"] = b?.rxBytes ?: 0L
                row["${p}Tx"] = b?.txBytes ?: 0L
            }
            out.add(row)
        }
        return out
    }

    /** Hotspot / tethering usage per day plus totals. */
    fun hotspot(ctx: Context, days: Int): Map<String, Any?> {
        val nsm = nsm(ctx)
        val now = System.currentTimeMillis()
        val today = startOfDay(now)
        val start = addDays(today, -(days - 1))
        val perDay = LinkedHashMap<Long, LongArray>()
        for (i in 0 until days) perDay[addDays(start, i)] = LongArray(2)

        var detailed = true
        for ((type, _) in types) {
            try {
                val stats = nsm.queryDetailsForUid(type, null, start, now, UID_TETHERING)
                val b = NetworkStats.Bucket()
                while (stats.hasNextBucket()) {
                    stats.getNextBucket(b)
                    val d = startOfDay(b.startTimeStamp).coerceAtLeast(start)
                    perDay[d]?.let { it[0] += b.rxBytes; it[1] += b.txBytes }
                }
                stats.close()
            } catch (e: SecurityException) {
                detailed = false
            } catch (_: Exception) {
            }
        }
        if (!detailed) {
            // Fallback: per-day summaries filtered on the tethering UID.
            perDay.values.forEach { it[0] = 0; it[1] = 0 }
            for (d in perDay.keys) {
                val e = minOf(addDays(d, 1), now)
                for ((type, _) in types) {
                    val stats = try { nsm.querySummary(type, null, d, e) } catch (_: Exception) { null } ?: continue
                    val b = NetworkStats.Bucket()
                    while (stats.hasNextBucket()) {
                        stats.getNextBucket(b)
                        if (b.uid == UID_TETHERING) perDay[d]!!.let { it[0] += b.rxBytes; it[1] += b.txBytes }
                    }
                    stats.close()
                }
            }
        }
        val list = perDay.map { (d, v) -> mapOf("day" to d, "rx" to v[0], "tx" to v[1]) }
        fun sumLast(n: Int) = list.takeLast(n).sumOf { (it["rx"] as Long) + (it["tx"] as Long) }
        return mapOf(
            "enabled" to NetInfo.hotspotEnabled(ctx),
            "daily" to list,
            "today" to sumLast(1),
            "week" to sumLast(7),
            "month" to sumLast(30),
        )
    }
}
