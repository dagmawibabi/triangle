package com.example.teleai

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/// The image tools, all on the phone: details, resize, crop, compress,
/// convert between JPEG/PNG/WebP, and background removal with ML Kit's
/// on-device subject segmentation. Every call reads `path` and, except
/// "info", writes a new file at `out` without touching the original.
object ImageOps {
    private val pool = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val op = call.argument<String>("op") ?: ""
        val path = call.argument<String>("path") ?: ""
        pool.execute {
            try {
                if (!File(path).exists()) throw IllegalArgumentException("No image at $path")
                if (op == "remove_background") {
                    removeBackground(call, path, result)
                    return@execute
                }
                val r = when (op) {
                    "info" -> info(path)
                    "video_frames" -> videoFrames(call, path)
                    "resize", "crop", "compress", "convert" -> transform(op, call, path)
                    else -> throw IllegalArgumentException("Unknown image operation $op")
                }
                main.post { result.success(r) }
            } catch (e: OutOfMemoryError) {
                main.post { result.error("failed", "That image is too large to edit on this phone.", null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun bounds(path: String): Pair<Int, Int> {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, o)
        var w = o.outWidth
        var h = o.outHeight
        if (w <= 0 && Build.VERSION.SDK_INT >= 28) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { d, info, _ ->
                w = info.size.width; h = info.size.height
                d.setTargetSize(1, 1)
            }
        }
        val rot = rotation(path)
        return if (rot == 90 || rot == 270) h to w else w to h
    }

    private fun rotation(path: String): Int = try {
        when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
    } catch (_: Exception) { 0 }

    private fun mimeOf(path: String): String {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, o)
        return o.outMimeType ?: when (path.substringAfterLast('.').lowercase()) {
            "heic", "heif" -> "image/heic"
            "avif" -> "image/avif"
            else -> "application/octet-stream"
        }
    }

    /// Decodes upright, scaled down while decoding when [maxSide] allows.
    private fun decode(path: String, maxSide: Int = 0): Bitmap {
        if (Build.VERSION.SDK_INT >= 28) {
            return ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { d, info, _ ->
                d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                d.isMutableRequired = true
                val w = info.size.width
                val h = info.size.height
                if (maxSide > 0 && max(w, h) > maxSide) {
                    val s = maxSide.toDouble() / max(w, h)
                    d.setTargetSize(max(1, (w * s).roundToInt()), max(1, (h * s).roundToInt()))
                }
            }
        }
        val (w, h) = bounds(path)
        var sample = 1
        if (maxSide > 0) while (max(w, h) / (sample * 2) >= maxSide) sample *= 2
        val bmp = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample; inMutable = true })
            ?: throw IllegalArgumentException("That file isn't an image this phone can read.")
        val rot = rotation(path)
        if (rot == 0) return bmp
        return Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(rot.toFloat()) }, true)
    }

    private fun info(path: String): Map<String, Any?> {
        val (w, h) = bounds(path)
        if (w <= 0) throw IllegalArgumentException("That file isn't an image this phone can read.")
        val exif = try { ExifInterface(path) } catch (_: Exception) { null }
        val latLong = FloatArray(2)
        val hasGps = exif?.getLatLong(latLong) == true
        return mapOf(
            "width" to w,
            "height" to h,
            "bytes" to File(path).length(),
            "mime" to mimeOf(path),
            "camera" to listOfNotNull(exif?.getAttribute(ExifInterface.TAG_MAKE), exif?.getAttribute(ExifInterface.TAG_MODEL)).joinToString(" ").ifBlank { null },
            "taken" to exif?.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL),
            "rotation" to rotation(path),
            "has_location" to hasGps,
            "latitude" to if (hasGps) latLong[0].toDouble() else null,
            "longitude" to if (hasGps) latLong[1].toDouble() else null,
        )
    }

    private fun formatOf(name: String?, path: String): String = when ((name ?: "").lowercase()) {
        "jpg", "jpeg" -> "jpeg"
        "png" -> "png"
        "webp" -> "webp"
        "" -> when (mimeOf(path)) {
            "image/png" -> "png"
            "image/webp" -> "webp"
            else -> "jpeg"
        }
        else -> throw IllegalArgumentException("Can save as jpeg, png or webp, not $name.")
    }

    private fun encode(bmp: Bitmap, format: String, quality: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val f = when (format) {
            "png" -> Bitmap.CompressFormat.PNG
            "webp" -> if (Build.VERSION.SDK_INT >= 30) {
                if (quality >= 100) Bitmap.CompressFormat.WEBP_LOSSLESS else Bitmap.CompressFormat.WEBP_LOSSY
            } else @Suppress("DEPRECATION") Bitmap.CompressFormat.WEBP
            else -> Bitmap.CompressFormat.JPEG
        }
        // JPEG has no transparency: flatten onto white rather than black.
        val src = if (format == "jpeg" && bmp.hasAlpha()) {
            Bitmap.createBitmap(bmp.width, bmp.height, Bitmap.Config.ARGB_8888).also {
                Canvas(it).apply { drawColor(Color.WHITE); drawBitmap(bmp, 0f, 0f, null) }
            }
        } else bmp
        src.compress(f, quality.coerceIn(1, 100), out)
        return out.toByteArray()
    }

    private fun transform(op: String, call: MethodCall, path: String): Map<String, Any?> {
        val out = call.argument<String>("out") ?: throw IllegalArgumentException("No output path")
        val (ow, oh) = bounds(path)
        if (ow <= 0) throw IllegalArgumentException("That file isn't an image this phone can read.")
        var format = formatOf(call.argument<String>("format"), path)
        var quality = call.argument<Int>("quality") ?: if (op == "compress") 75 else 90
        var bmp: Bitmap

        when (op) {
            "resize" -> {
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val maxSide = call.argument<Int>("max_side") ?: 0
                val percent = call.argument<Double>("percent") ?: 0.0
                val fit = call.argument<String>("fit") ?: "contain"
                var tw: Int
                var th: Int
                when {
                    percent > 0 -> { tw = (ow * percent / 100).roundToInt(); th = (oh * percent / 100).roundToInt() }
                    maxSide > 0 -> { val s = min(1.0, maxSide.toDouble() / max(ow, oh)); tw = (ow * s).roundToInt(); th = (oh * s).roundToInt() }
                    width > 0 && height > 0 -> { tw = width; th = height }
                    width > 0 -> { tw = width; th = (oh * width.toDouble() / ow).roundToInt() }
                    height > 0 -> { th = height; tw = (ow * height.toDouble() / oh).roundToInt() }
                    else -> throw IllegalArgumentException("Give width, height, max_side or percent.")
                }
                tw = tw.coerceIn(1, 12000); th = th.coerceIn(1, 12000)
                val src = decode(path, if (tw <= ow && th <= oh) max(tw, th) * 2 else 0)
                bmp = if (width > 0 && height > 0 && fit != "stretch") {
                    // contain: fits inside; cover: fills and trims the overflow.
                    val s = if (fit == "cover") max(tw.toDouble() / src.width, th.toDouble() / src.height)
                            else min(tw.toDouble() / src.width, th.toDouble() / src.height)
                    val sw = max(1, (src.width * s).roundToInt())
                    val sh = max(1, (src.height * s).roundToInt())
                    val scaled = Bitmap.createScaledBitmap(src, sw, sh, true)
                    if (fit == "cover") Bitmap.createBitmap(scaled, max(0, (sw - tw) / 2), max(0, (sh - th) / 2), min(tw, sw), min(th, sh)) else scaled
                } else Bitmap.createScaledBitmap(src, tw, th, true)
            }
            "crop" -> {
                val src = decode(path)
                val w = src.width
                val h = src.height
                val aspect = call.argument<String>("aspect")
                val r: Rect = if (!aspect.isNullOrBlank()) {
                    val parts = aspect.split(':', 'x', '/').mapNotNull { it.trim().toDoubleOrNull() }
                    if (parts.size != 2 || parts[0] <= 0 || parts[1] <= 0) throw IllegalArgumentException("aspect looks like 1:1 or 16:9.")
                    val want = parts[0] / parts[1]
                    val (cw, ch) = if (w.toDouble() / h > want) (h * want).roundToInt() to h else w to (w / want).roundToInt()
                    val gravity = call.argument<String>("gravity") ?: "center"
                    val x = when (gravity) { "left" -> 0; "right" -> w - cw; else -> (w - cw) / 2 }
                    val y = when (gravity) { "top" -> 0; "bottom" -> h - ch; else -> (h - ch) / 2 }
                    Rect(x, y, x + cw, y + ch)
                } else {
                    // Pixels, or fractions of the picture when all are 0..1.
                    val x = call.argument<Double>("x") ?: 0.0
                    val y = call.argument<Double>("y") ?: 0.0
                    val cw = call.argument<Double>("width") ?: 0.0
                    val ch = call.argument<Double>("height") ?: 0.0
                    val frac = listOf(x, y, cw, ch).all { it in 0.0..1.0 } && (cw > 0 || ch > 0)
                    val px = { v: Double, total: Int -> if (frac) (v * total).roundToInt() else v.roundToInt() }
                    val l = px(x, w).coerceIn(0, w - 1)
                    val t = px(y, h).coerceIn(0, h - 1)
                    val rw = (if (cw > 0) px(cw, w) else w - l).coerceIn(1, w - l)
                    val rh = (if (ch > 0) px(ch, h) else h - t).coerceIn(1, h - t)
                    Rect(l, t, l + rw, t + rh)
                }
                bmp = Bitmap.createBitmap(src, r.left, r.top, r.width(), r.height())
            }
            "compress" -> {
                val maxSide = call.argument<Int>("max_side") ?: 0
                bmp = decode(path, maxSide)
                if (maxSide > 0 && max(bmp.width, bmp.height) > maxSide) {
                    val s = maxSide.toDouble() / max(bmp.width, bmp.height)
                    bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * s).roundToInt(), (bmp.height * s).roundToInt(), true)
                }
                if (format == "png" && call.argument<String>("format") == null) format = if (bmp.hasAlpha()) "webp" else "jpeg"
                val targetKb = call.argument<Int>("target_kb") ?: 0
                if (targetKb > 0 && format != "png") {
                    // Lower the quality, then the size, until it fits.
                    var bytes = encode(bmp, format, quality)
                    var lo = 10
                    var hi = quality
                    while (bytes.size > targetKb * 1024 && hi - lo > 2) {
                        val mid = (lo + hi) / 2
                        val b = encode(bmp, format, mid)
                        if (b.size > targetKb * 1024) hi = mid else { lo = mid; bytes = b; quality = mid }
                    }
                    var guard = 0
                    while (bytes.size > targetKb * 1024 && guard++ < 6 && max(bmp.width, bmp.height) > 320) {
                        bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * 0.8).roundToInt(), (bmp.height * 0.8).roundToInt(), true)
                        quality = max(lo, 40)
                        bytes = encode(bmp, format, quality)
                    }
                    File(out).writeBytes(bytes)
                    return done(out, bmp, format, quality, ow, oh, path)
                }
            }
            else -> bmp = decode(path) // convert
        }
        File(out).writeBytes(encode(bmp, format, quality))
        return done(out, bmp, format, quality, ow, oh, path)
    }

    private fun done(out: String, bmp: Bitmap, format: String, quality: Int, ow: Int, oh: Int, path: String) = mapOf(
        "path" to out,
        "width" to bmp.width,
        "height" to bmp.height,
        "bytes" to File(out).length(),
        "format" to format,
        "quality" to if (format == "png") null else quality,
        "original_width" to ow,
        "original_height" to oh,
        "original_bytes" to File(path).length(),
        "original_mime" to mimeOf(path),
    )

    private fun removeBackground(call: MethodCall, path: String, result: MethodChannel.Result) {
        val out = call.argument<String>("out") ?: throw IllegalArgumentException("No output path")
        val (ow, oh) = bounds(path)
        val src = decode(path, 2048)
        val segmenter = SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder().enableForegroundBitmap().build()
        )
        segmenter.process(InputImage.fromBitmap(src, 0))
            .addOnSuccessListener(pool) { r ->
                try {
                    val fg = r.foregroundBitmap
                    if (fg == null) {
                        main.post { result.error("failed", "No subject was found to keep in that picture.", null) }
                        return@addOnSuccessListener
                    }
                    val bg = call.argument<String>("background")
                    val format = if (bg.isNullOrBlank() || bg == "transparent") "png" else formatOf(call.argument<String>("format") ?: "jpeg", path)
                    val final = if (bg.isNullOrBlank() || bg == "transparent") fg else {
                        val color = try { Color.parseColor(if (bg.startsWith("#")) bg else when (bg) { "white" -> "#FFFFFF"; "black" -> "#000000"; else -> bg }) }
                                    catch (_: Exception) { Color.WHITE }
                        Bitmap.createBitmap(fg.width, fg.height, Bitmap.Config.ARGB_8888).also {
                            Canvas(it).apply { drawColor(color); drawBitmap(fg, 0f, 0f, Paint(Paint.ANTI_ALIAS_FLAG)) }
                        }
                    }
                    File(out).writeBytes(encode(final, format, 95))
                    val res = done(out, final, format, 95, ow, oh, path) + mapOf("background" to (bg ?: "transparent"))
                    main.post { result.success(res) }
                } catch (e: Exception) {
                    main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
                } finally {
                    segmenter.close()
                }
            }
            .addOnFailureListener(pool) { e ->
                segmenter.close()
                val msg = e.message ?: ""
                main.post {
                    result.error(
                        "failed",
                        if (msg.contains("download", true) || msg.contains("module", true))
                            "The background-removal model is still downloading through Google Play services. Try again in a minute."
                        else "Couldn't remove the background: ${msg.ifBlank { e.javaClass.simpleName }}",
                        null,
                    )
                }
            }
    }

    /// Evenly spaced stills of a short video (a Telegram GIF is a silent
    /// MP4; video stickers are WebM), so the assistant can see it move.
    /// Writes JPEGs into `out` and returns their paths with each one's time.
    private fun videoFrames(call: MethodCall, path: String): Map<String, Any?> {
        val count = (call.argument<Int>("count") ?: 6).coerceIn(1, 12)
        val maxWidth = (call.argument<Int>("max_width") ?: 768).coerceIn(64, 2048)
        val dir = File(call.argument<String>("out") ?: throw IllegalArgumentException("No folder for the frames"))
        dir.mkdirs()
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            val duration = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val width = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            // The middle of each of `count` equal slices, so the first and
            // last frames (often blank or a fade) are skipped.
            val times = if (duration <= 0L || count == 1) listOf(duration / 2) else (0 until count).map { duration * (2 * it + 1) / (2 * count) }
            val frames = mutableListOf<Map<String, Any>>()
            for ((i, ms) in times.withIndex()) {
                val bmp = r.getFrameAtTime(ms * 1000, MediaMetadataRetriever.OPTION_CLOSEST) ?: continue
                val scaled = if (bmp.width > maxWidth) {
                    Bitmap.createScaledBitmap(bmp, maxWidth, max(1, (bmp.height * maxWidth.toDouble() / bmp.width).roundToInt()), true)
                } else bmp
                val f = File(dir, "frame_${System.nanoTime()}_$i.jpg")
                f.outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 85, it) }
                if (scaled !== bmp) scaled.recycle()
                bmp.recycle()
                frames.add(mapOf("path" to f.path, "at_ms" to ms))
            }
            if (frames.isEmpty()) throw IllegalArgumentException("Couldn't read any frames from this video.")
            return mapOf("frames" to frames, "duration_ms" to duration, "width" to width, "height" to height)
        } finally {
            r.release()
        }
    }
}
