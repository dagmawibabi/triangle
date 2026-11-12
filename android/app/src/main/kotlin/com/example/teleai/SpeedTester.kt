package com.example.teleai

import android.net.Network
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * [downCap]/[upCap] are hard byte limits per direction. Transfers also stop
 * early once throughput is stable for ~1 s after [minSeconds], so a typical
 * Eco test on a 100 Mbps link uses only a few MB.
 */
enum class TestProfile(
    val key: String, val seconds: Int, val minSeconds: Double, val threads: Int,
    val downCap: Long, val upCap: Long, val pings: Int,
) {
    PING("ping", 0, 0.0, 0, 0, 0, 10),
    ECO("eco", 4, 1.5, 2, 6L shl 20, 3L shl 20, 6),
    LIGHT("light", 6, 2.0, 3, 25L shl 20, 10L shl 20, 8),
    STANDARD("standard", 10, 3.0, 4, 100L shl 20, 40L shl 20, 12),
    HEAVY("heavy", 15, 5.0, 6, 400L shl 20, 150L shl 20, 20);

    val maxBytes get() = downCap + upCap

    companion object {
        fun of(k: String?) = entries.firstOrNull { it.key == k } ?: STANDARD
    }
}

class CancelledException : Exception("Cancelled")

/** Which measurements a test performs, e.g. "ping,download,upload". */
data class Metrics(val ping: Boolean, val download: Boolean, val upload: Boolean) {
    val key get() = listOfNotNull("ping".takeIf { ping }, "download".takeIf { download }, "upload".takeIf { upload }).joinToString(",")
    val latencyOnly get() = !download && !upload
    fun maxBytes(p: TestProfile) = (if (download) p.downCap else 0L) + (if (upload) p.upCap else 0L) + 64 * 1024

    companion object {
        val ALL = Metrics(true, true, true)
        val PING = Metrics(true, false, false)
        fun parse(s: String?): Metrics {
            val parts = (s ?: "").split(",").map { it.trim() }.toSet()
            val m = Metrics("ping" in parts, "download" in parts, "upload" in parts)
            return if (!m.ping && !m.download && !m.upload) ALL else m
        }
    }
}

/**
 * Multi-connection HTTP speed test against Cloudflare's speed test endpoints.
 * Every connection is opened through [network] so the test can be pinned to
 * Wi-Fi or a specific SIM even when it isn't the default route.
 */
class SpeedTester(
    private val network: Network?,
    private val profile: TestProfile,
    private val metrics: Metrics = Metrics.ALL,
    private val onProgress: (phase: String, mbps: Double, fraction: Double) -> Unit,
    /** Partial results as soon as they're known (isp, ping, download…). */
    private val onInfo: (Map<String, Any?>) -> Unit = {},
) {
    companion object {
        const val BASE = "https://speed.cloudflare.com"
    }

    @Volatile
    var cancelled = false
    private val totalBytes = AtomicLong(0)

    fun run(): MutableMap<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        val started = System.currentTimeMillis()
        try {
            val m = if (profile == TestProfile.PING) Metrics.PING else metrics
            out["metrics"] = m.key
            onProgress(if (m.ping) "ping" else if (m.download) "download" else "upload", 0.0, 0.0)
            meta(out)
            onInfo(out.toMap())
            if (m.ping) {
                ping(out)
                onInfo(mapOf("ping_ms" to out["ping_ms"], "jitter_ms" to out["jitter_ms"], "loss_pct" to out["loss_pct"]))
            }
            if (m.download) {
                check()
                out["download_mbps"] = transfer(upload = false)
                onInfo(mapOf("download_mbps" to out["download_mbps"]))
            }
            if (m.upload) {
                check()
                out["upload_mbps"] = transfer(upload = true)
                onInfo(mapOf("upload_mbps" to out["upload_mbps"]))
            }
        } catch (e: CancelledException) {
            out["error"] = "Cancelled"
        } catch (e: Exception) {
            out["error"] = "${e.javaClass.simpleName}: ${e.message ?: "unknown error"}"
        }
        out["bytes_used"] = totalBytes.get()
        out["duration_ms"] = System.currentTimeMillis() - started
        out["profile"] = profile.key
        return out
    }

    private fun check() {
        if (cancelled) throw CancelledException()
    }

    private fun open(url: String): HttpURLConnection {
        val u = URL(url)
        val c = (network?.openConnection(u) ?: u.openConnection()) as HttpURLConnection
        c.connectTimeout = 10_000
        c.readTimeout = 15_000
        c.useCaches = false
        c.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android) Triangle/1.0")
        c.setRequestProperty("Referer", "https://speed.cloudflare.com/")
        return c
    }

    private fun meta(out: MutableMap<String, Any?>) {
        try {
            val c = open("$BASE/meta")
            val body = c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            val j = JSONObject(body)
            out["client_ip"] = j.optString("clientIp").ifEmpty { null }
            out["isp"] = j.optString("asOrganization").ifEmpty { null }
            val colo = j.optString("colo")
            val city = j.optString("city")
            out["server"] = listOf("Cloudflare", colo, city).filter { it.isNotEmpty() }.joinToString(" · ")
            return
        } catch (_: Exception) {
        }
        try {
            val c = open("$BASE/cdn-cgi/trace")
            val body = c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            val kv = body.lines().mapNotNull { l -> l.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }.toMap()
            out["client_ip"] = kv["ip"]
            out["server"] = "Cloudflare · ${kv["colo"] ?: "?"}"
        } catch (_: Exception) {
            out["server"] = "Cloudflare"
        }
    }

    private fun ping(out: MutableMap<String, Any?>) {
        val samples = ArrayList<Double>()
        var fails = 0
        val n = profile.pings + 1
        val timing = Regex("dur=([0-9.]+)")
        for (i in 0 until n) {
            check()
            try {
                val t0 = System.nanoTime()
                val c = open("$BASE/__down?bytes=0")
                c.connectTimeout = 5000
                c.readTimeout = 5000
                c.inputStream.use { it.readBytes() }
                var ms = (System.nanoTime() - t0) / 1e6
                c.getHeaderField("Server-Timing")?.let { h ->
                    timing.find(h)?.groupValues?.get(1)?.toDoubleOrNull()?.let { d -> ms -= d }
                }
                // First request includes DNS + TCP + TLS handshake: discard it.
                if (i > 0) samples.add(max(ms, 0.1))
            } catch (e: Exception) {
                if (i > 0) fails++ else if (e is java.net.UnknownHostException) throw IOException("No internet (DNS failed)")
            }
            onProgress("ping", samples.lastOrNull() ?: 0.0, (i + 1).toDouble() / n)
        }
        if (samples.isEmpty()) throw IOException("No internet connectivity")
        val sorted = samples.sorted()
        out["ping_ms"] = sorted[sorted.size / 2]
        out["jitter_ms"] = if (samples.size > 1)
            (1 until samples.size).map { abs(samples[it] - samples[it - 1]) }.average() else 0.0
        out["loss_pct"] = fails * 100.0 / (n - 1)
    }

    private fun transfer(upload: Boolean): Double {
        val phase = if (upload) "upload" else "download"
        val counter = AtomicLong(0)
        val stop = AtomicBoolean(false)
        val errors = AtomicInteger(0)
        val budget = if (upload) profile.upCap else profile.downCap
        val durMs = profile.seconds * 1000L
        val payload = ByteArray(64 * 1024).also { Random.nextBytes(it) }
        val downChunk = min(25L shl 20, max(1L shl 20, budget / profile.threads))
        val upChunk = min(4L shl 20, max(256L shl 10, budget / profile.threads)).toInt()

        val workers = (0 until profile.threads).map { idx ->
            Thread {
                val buf = ByteArray(64 * 1024)
                while (!stop.get() && !cancelled) {
                    var conn: HttpURLConnection? = null
                    try {
                        if (!upload) {
                            conn = open("$BASE/__down?bytes=$downChunk")
                            conn.inputStream.use { ins ->
                                while (!stop.get() && !cancelled) {
                                    val r = ins.read(buf)
                                    if (r < 0) break
                                    counter.addAndGet(r.toLong())
                                }
                            }
                        } else {
                            conn = open("$BASE/__up")
                            conn.requestMethod = "POST"
                            conn.doOutput = true
                            conn.setFixedLengthStreamingMode(upChunk)
                            conn.setRequestProperty("Content-Type", "application/octet-stream")
                            conn.outputStream.use { os ->
                                var sent = 0
                                while (sent < upChunk && !stop.get() && !cancelled) {
                                    val w = min(payload.size, upChunk - sent)
                                    os.write(payload, 0, w)
                                    sent += w
                                    counter.addAndGet(w.toLong())
                                }
                            }
                            conn.responseCode
                            conn.inputStream.use { it.readBytes() }
                        }
                    } catch (e: Exception) {
                        if (stop.get() || cancelled) break
                        if (errors.incrementAndGet() > 12) break
                        try {
                            Thread.sleep(250)
                        } catch (_: InterruptedException) {
                            break
                        }
                    } finally {
                        if (stop.get() || cancelled) conn?.disconnect()
                    }
                }
            }.apply {
                isDaemon = true
                name = "tri-$phase-$idx"
                start()
            }
        }

        val start = System.nanoTime()
        val samples = ArrayList<Pair<Long, Long>>()
        samples.add(0L to 0L)
        val inst = ArrayList<Double>()
        val minMs = (profile.minSeconds * 1000).toLong()
        try {
            while (true) {
                Thread.sleep(200)
                val t = (System.nanoTime() - start) / 1_000_000
                val b = counter.get()
                samples.add(t to b)
                val ref = samples.lastOrNull { it.first <= t - 1000 } ?: samples.first()
                val now = (b - ref.second) * 8.0 / max(1L, t - ref.first) / 1000.0
                inst.add(now)
                onProgress(phase, now, min(1.0, max(t.toDouble() / durMs, b.toDouble() / budget)))
                if (cancelled) throw CancelledException()
                if (t >= durMs || b >= budget || workers.none { it.isAlive }) break
                // Early stop: last ~1 s of 1-second-window speeds within ±6 %.
                if (t >= minMs && inst.size >= 6) {
                    val last = inst.takeLast(5)
                    val mean = last.average()
                    if (mean > 0 && (last.max() - last.min()) / mean < 0.12) break
                }
            }
        } finally {
            stop.set(true)
            workers.forEach { it.join(1500) }
            totalBytes.addAndGet(counter.get())
        }

        val end = samples.last()
        if (end.second == 0L) throw IOException("$phase failed (no data transferred)")
        // Skip TCP slow-start: ignore the first 1.5 s (or 25% of a short run).
        val warmMs = min(1500L, (end.first * 0.25).toLong())
        val warm = samples.firstOrNull { it.first >= warmMs } ?: samples.first()
        val span = end.first - warm.first
        return if (span >= 500 && end.second > warm.second) {
            (end.second - warm.second) * 8.0 / span / 1000.0
        } else {
            end.second * 8.0 / max(1L, end.first) / 1000.0
        }
    }
}
