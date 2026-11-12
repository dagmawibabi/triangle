package com.example.teleai

import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.accessibilityservice.GestureDescription
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/// Lets the assistant see and use other apps, once the person turns on
/// Triangle under Settings → Accessibility. It reads the screen as a list of
/// elements (text, buttons, fields), and taps, types, scrolls, swipes and
/// presses Back or Home.
///
/// Hard limits, whatever Dart asks: password fields are never read or typed
/// into, and nothing is read or done in Triangle itself (it could approve its
/// own actions), Android's permission and install screens, or the apps the
/// person listed as off limits.
@SuppressLint("NewApi")
class ScreenControl : AccessibilityService() {

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val pkg = event.packageName?.toString() ?: return
            // The keyboard and the status bar aren't "the app on screen".
            if (pkg != "com.android.systemui" && !pkg.contains("inputmethod") && !pkg.contains("keyboard")) {
                lastPackage = pkg
                lastActivity = event.className?.toString()
            }
        }
        changes++
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "teleai/screen"
        @Volatile var instance: ScreenControl? = null
        @Volatile private var lastPackage: String? = null
        @Volatile private var lastActivity: String? = null
        @Volatile private var changes = 0L
        private val main = Handler(Looper.getMainLooper())
        private val pool = Executors.newSingleThreadExecutor()

        /// The elements of the last read, by the ids the assistant was given.
        private val nodes = HashMap<Int, AccessibilityNodeInfo>()

        /// Never read or touched, whatever the person allowed.
        private val alwaysOff = setOf(
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
        )

        fun enabled(ctx: Context): Boolean {
            val flat = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val me = ComponentName(ctx, ScreenControl::class.java)
            return flat.split(":").any { ComponentName.unflattenFromString(it) == me }
        }

        fun attach(context: Context, engine: FlutterEngine) {
            val app = context.applicationContext
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
                fun work(block: () -> Any?) = pool.execute {
                    try {
                        val v = block()
                        main.post { result.success(v) }
                    } catch (e: Refused) {
                        main.post { result.error("refused", e.message, null) }
                    } catch (e: Exception) {
                        main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
                    }
                }
                val blocked = (call.argument<List<String>>("blocked") ?: emptyList()).toSet()
                when (call.method) {
                    "status" -> result.success(status(app))
                    "openSettings" -> {
                        val i = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        app.startActivity(i)
                        result.success(true)
                    }
                    "read" -> work {
                        read(app, blocked, call.argument<Boolean>("all") ?: false, call.argument<Int>("limit") ?: 250, call.argument<String>("query"))
                    }
                    "tap" -> work { act(app, blocked) { s -> s.tap(call.argument<Int>("id"), call.argument<String>("text"), call.argument<Double>("x"), call.argument<Double>("y"), call.argument<Boolean>("long") ?: false) } }
                    "type" -> work { act(app, blocked) { s -> s.type(call.argument<Int>("id"), call.argument<String>("text") ?: "", call.argument<Boolean>("replace") ?: true, call.argument<Boolean>("submit") ?: false) } }
                    "scroll" -> work { act(app, blocked) { s -> s.scroll(call.argument<Int>("id"), call.argument<String>("direction") ?: "down") } }
                    "swipe" -> work {
                        act(app, blocked) { s ->
                            s.swipe(
                                call.argument<Double>("x1") ?: 0.5, call.argument<Double>("y1") ?: 0.7,
                                call.argument<Double>("x2") ?: 0.5, call.argument<Double>("y2") ?: 0.3,
                                (call.argument<Int>("ms") ?: 350).toLong(),
                            )
                        }
                    }
                    "press" -> work { act(app, blocked, allowAnywhere = true) { s -> s.press(call.argument<String>("key") ?: "back") } }
                    "screenshot" -> work { screenshot(app, blocked) }
                    "wait" -> work { waitFor(app, blocked, call.argument<String>("text"), (call.argument<Int>("ms") ?: 5000).toLong()) }
                    else -> result.notImplemented()
                }
            }
        }

        private class Refused(message: String) : Exception(message)

        private fun service(): ScreenControl =
            instance ?: throw Refused("Screen control is off. Turn on Triangle in Settings → Accessibility.")

        private fun label(ctx: Context, pkg: String?): String {
            if (pkg == null) return ""
            return try {
                val pm = ctx.packageManager
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (_: Exception) {
                pkg
            }
        }

        private fun status(ctx: Context): Map<String, Any?> = mapOf(
            "enabled" to enabled(ctx),
            "running" to (instance != null),
            "package" to current(),
            "app" to label(ctx, current()),
            "screenshots" to (Build.VERSION.SDK_INT >= 30),
        )

        /// The app in front: the active window's, else the last one opened.
        private fun current(): String? = instance?.rootInActiveWindow?.packageName?.toString() ?: lastPackage

        private fun check(ctx: Context, pkg: String?, blocked: Set<String>) {
            if (pkg == null) return
            if (pkg == ctx.packageName) throw Refused("That's Triangle itself: it can't read or use its own screens.")
            if (pkg in alwaysOff) throw Refused("Android's permission and install screens are off limits.")
            if (pkg in blocked) throw Refused("${label(ctx, pkg)} is on the off-limits list in Settings → Screen control.")
        }

        /// The app's window: the active one, or the top application window.
        private fun root(s: ScreenControl): AccessibilityNodeInfo? {
            s.rootInActiveWindow?.let { return it }
            return s.windows.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }?.root
        }

        private fun role(n: AccessibilityNodeInfo): String {
            val c = n.className?.toString()?.substringAfterLast('.') ?: return "view"
            return when {
                n.isEditable || c.contains("EditText") -> "field"
                n.isCheckable && c.contains("Switch") -> "switch"
                n.isCheckable -> "checkbox"
                c.contains("Button") -> "button"
                c.contains("Image") -> "image"
                c.contains("RecyclerView") || c.contains("ListView") || c.contains("ScrollView") -> "list"
                c.contains("TextView") -> "text"
                c.contains("WebView") -> "web"
                else -> c.lowercase()
            }
        }

        private fun read(ctx: Context, blocked: Set<String>, all: Boolean, limit: Int, query: String?): Map<String, Any?> {
            val s = service()
            val root = root(s) ?: throw Refused("Nothing readable is on the screen right now.")
            val pkg = root.packageName?.toString()
            check(ctx, pkg, blocked)
            synchronized(nodes) { nodes.clear() }
            val out = ArrayList<Map<String, Any?>>()
            val screen = Rect()
            root.getBoundsInScreen(screen)
            val q = query?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
            var next = 1
            var hiddenPasswords = 0
            fun walk(n: AccessibilityNodeInfo?, depth: Int) {
                if (n == null || out.size >= limit || depth > 60) return
                if (!n.isVisibleToUser) return
                val text = n.text?.toString()?.trim().orEmpty()
                val desc = n.contentDescription?.toString()?.trim().orEmpty()
                val hint = if (Build.VERSION.SDK_INT >= 26) n.hintText?.toString()?.trim().orEmpty() else ""
                val actionable = n.isClickable || n.isLongClickable || n.isEditable || n.isScrollable || n.isCheckable
                val meaningful = text.isNotEmpty() || desc.isNotEmpty() || hint.isNotEmpty()
                val matches = q == null || text.lowercase().contains(q) || desc.lowercase().contains(q) || hint.lowercase().contains(q)
                if ((actionable || meaningful || all) && matches) {
                    val id = next++
                    synchronized(nodes) { nodes[id] = n }
                    val b = Rect()
                    n.getBoundsInScreen(b)
                    if (n.isPassword) hiddenPasswords++
                    out.add(
                        linkedMapOf<String, Any?>(
                            "id" to id,
                            "role" to role(n),
                            // A password is never read, only that the field holds one.
                            "text" to (if (n.isPassword) (if (text.isEmpty()) "" else "••••") else text.take(300)),
                            "label" to desc.take(200).ifEmpty { null },
                            "hint" to hint.ifEmpty { null },
                            "view" to n.viewIdResourceName?.substringAfter(":id/")?.ifEmpty { null },
                            "clickable" to n.isClickable,
                            "editable" to n.isEditable,
                            "scrollable" to n.isScrollable,
                            "checked" to (if (n.isCheckable) n.isChecked else null),
                            "disabled" to !n.isEnabled,
                            "focused" to n.isFocused,
                            "password" to n.isPassword,
                            "bounds" to listOf(b.left, b.top, b.right, b.bottom),
                        ).filterValues { it != null && it != false && it != "" },
                    )
                }
                for (i in 0 until n.childCount) walk(n.getChild(i), depth + 1)
            }
            walk(root, 0)
            return mapOf(
                "package" to pkg,
                "app" to label(ctx, pkg),
                "screen" to (if (pkg == lastPackage) lastActivity?.substringAfterLast('.') else null),
                "width" to screen.width(),
                "height" to screen.height(),
                "count" to out.size,
                "truncated" to (out.size >= limit),
                "password_fields" to hiddenPasswords,
                "elements" to out,
            )
        }

        /// Runs an action in the app on screen, after the off-limits checks,
        /// then waits for the screen to settle and says where it ended up.
        private fun act(ctx: Context, blocked: Set<String>, allowAnywhere: Boolean = false, block: (ScreenControl) -> Map<String, Any?>): Map<String, Any?> {
            val s = service()
            if (!allowAnywhere) check(ctx, root(s)?.packageName?.toString(), blocked)
            val before = changes
            val r = block(s)
            settle(before)
            val pkg = current()
            return r + mapOf("app_now" to label(ctx, pkg), "package_now" to pkg, "screen_changed" to (changes != before))
        }

        /// Waits until the screen stops changing (at most about 2 s).
        private fun settle(before: Long) {
            val start = SystemClock.uptimeMillis()
            SystemClock.sleep(250)
            var last = changes
            while (SystemClock.uptimeMillis() - start < 2000) {
                SystemClock.sleep(200)
                if (changes == last && changes != before) break
                last = changes
            }
        }

        private fun node(id: Int?): AccessibilityNodeInfo? {
            if (id == null) return null
            val n = synchronized(nodes) { nodes[id] } ?: throw Refused("No element $id: read the screen again (ids change with every read).")
            n.refresh()
            return n
        }

        private fun waitFor(ctx: Context, blocked: Set<String>, text: String?, ms: Long): Map<String, Any?> {
            val s = service()
            val start = SystemClock.uptimeMillis()
            val before = changes
            val q = text?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
            while (SystemClock.uptimeMillis() - start < ms.coerceIn(200, 20000)) {
                val root = root(s)
                if (q == null) {
                    if (changes != before) {
                        settle(changes)
                        break
                    }
                } else if (root != null && !root.findAccessibilityNodeInfosByText(q).isNullOrEmpty()) {
                    check(ctx, root.packageName?.toString(), blocked)
                    return mapOf("found" to true, "waited_ms" to SystemClock.uptimeMillis() - start, "app" to label(ctx, root.packageName?.toString()))
                }
                SystemClock.sleep(250)
            }
            val pkg = current()
            return mapOf(
                "found" to (q == null && changes != before),
                "waited_ms" to SystemClock.uptimeMillis() - start,
                "app" to label(ctx, pkg),
            )
        }

        private fun screenshot(ctx: Context, blocked: Set<String>): Map<String, Any?> {
            val s = service()
            check(ctx, root(s)?.packageName?.toString(), blocked)
            if (Build.VERSION.SDK_INT < 30) throw Refused("Screenshots need Android 11 or newer; read the screen instead.")
            val latch = CountDownLatch(1)
            var bitmap: Bitmap? = null
            var error: String? = null
            s.takeScreenshot(Display.DEFAULT_DISPLAY, ctx.mainExecutor, object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(shot: AccessibilityService.ScreenshotResult) {
                    try {
                        val hw = Bitmap.wrapHardwareBuffer(shot.hardwareBuffer, shot.colorSpace)
                        bitmap = hw?.copy(Bitmap.Config.ARGB_8888, false)
                        shot.hardwareBuffer.close()
                    } catch (e: Exception) {
                        error = e.message
                    }
                    latch.countDown()
                }

                override fun onFailure(errorCode: Int) {
                    error = if (errorCode == AccessibilityService.ERROR_TAKE_SCREENSHOT_SECURE_WINDOW) "This app doesn't allow screenshots." else "Screenshot failed ($errorCode)."
                    latch.countDown()
                }
            })
            latch.await(5, TimeUnit.SECONDS)
            val b = bitmap ?: throw Refused(error ?: "Screenshot timed out.")
            val dir = File(ctx.cacheDir, "screens").apply { mkdirs() }
            dir.listFiles()?.sortedBy { it.lastModified() }?.dropLast(10)?.forEach { it.delete() }
            val f = File(dir, "screen_${System.currentTimeMillis()}.jpg")
            FileOutputStream(f).use { b.compress(Bitmap.CompressFormat.JPEG, 82, it) }
            return mapOf("image_path" to f.absolutePath, "width" to b.width, "height" to b.height, "app" to label(ctx, current()))
        }
    }

    // ---- actions, on the service --------------------------------------------------

    private fun bounds(n: AccessibilityNodeInfo): Rect = Rect().also { n.getBoundsInScreen(it) }

    private fun describe(n: AccessibilityNodeInfo): String =
        (n.text?.toString()?.takeIf { it.isNotBlank() && !n.isPassword } ?: n.contentDescription?.toString() ?: n.viewIdResourceName?.substringAfter(":id/") ?: "the element").take(80)

    /// Taps an element (by id, or the first whose text matches), or a point
    /// given as fractions of the screen (0-1).
    fun tap(id: Int?, text: String?, x: Double?, y: Double?, long: Boolean): Map<String, Any?> {
        var target = node(id)
        if (target == null && !text.isNullOrBlank()) {
            val root = rootInActiveWindow ?: throw Refused("Nothing on the screen to tap.")
            target = root.findAccessibilityNodeInfosByText(text).firstOrNull { it.isVisibleToUser }
                ?: throw Refused("Nothing that says \"$text\" is on the screen.")
        }
        if (target != null) {
            val name = describe(target)
            // The element, or the nearest ancestor that takes the tap.
            var n: AccessibilityNodeInfo? = target
            var depth = 0
            while (n != null && depth < 6) {
                val ok = if (long) n.isLongClickable else n.isClickable
                if (ok && n.isEnabled) {
                    if (n.performAction(if (long) AccessibilityNodeInfo.ACTION_LONG_CLICK else AccessibilityNodeInfo.ACTION_CLICK)) {
                        return mapOf("tapped" to name, "long" to long)
                    }
                    break
                }
                n = n.parent
                depth++
            }
            // Not clickable as an element: tap where it is.
            val b = bounds(target)
            gesture(b.exactCenterX(), b.exactCenterY(), b.exactCenterX(), b.exactCenterY(), if (long) 650 else 60)
            return mapOf("tapped" to name, "long" to long, "by" to "position")
        }
        if (x == null || y == null) throw Refused("Give an element id, its text, or x and y.")
        val m = resources.displayMetrics
        val px = (x.coerceIn(0.0, 1.0) * m.widthPixels).toFloat()
        val py = (y.coerceIn(0.0, 1.0) * m.heightPixels).toFloat()
        gesture(px, py, px, py, if (long) 650 else 60)
        return mapOf("tapped" to "the point (${"%.2f".format(x)}, ${"%.2f".format(y)})", "long" to long, "by" to "position")
    }

    fun type(id: Int?, text: String, replace: Boolean, submit: Boolean): Map<String, Any?> {
        val field = node(id) ?: rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: throw Refused("No text field is selected: give the field's id from a screen read.")
        if (field.isPassword) throw Refused("That's a password field. Passwords are typed by the person, never by the assistant.")
        if (!field.isEditable) throw Refused("${describe(field)} isn't a text field.")
        field.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        field.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val existing = field.text?.toString()?.takeIf { Build.VERSION.SDK_INT < 26 || field.hintText?.toString() != it }.orEmpty()
        val value = if (replace) text else existing + text
        val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value) }
        if (!field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) throw Refused("The app didn't accept the text.")
        var submitted = false
        if (submit && Build.VERSION.SDK_INT >= 30) {
            field.refresh()
            submitted = field.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
        }
        return mapOf("typed" to text.length, "into" to describe(field), "replaced" to replace, "submitted" to submitted)
    }

    fun scroll(id: Int?, direction: String): Map<String, Any?> {
        val forward = direction == "down" || direction == "right"
        var n = node(id)
        if (n == null) {
            // The largest scrollable thing on screen.
            val root = rootInActiveWindow
            var best: AccessibilityNodeInfo? = null
            var area = 0
            fun walk(x: AccessibilityNodeInfo?, depth: Int) {
                if (x == null || depth > 60) return
                if (x.isScrollable && x.isVisibleToUser) {
                    val b = bounds(x)
                    if (b.width() * b.height() > area) {
                        area = b.width() * b.height()
                        best = x
                    }
                }
                for (i in 0 until x.childCount) walk(x.getChild(i), depth + 1)
            }
            walk(root, 0)
            n = best
        }
        if (n != null && (direction == "up" || direction == "down")) {
            val done = n.performAction(if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
            if (done) return mapOf("scrolled" to direction)
        }
        // A swipe across the middle of the screen (or of the element).
        val m = resources.displayMetrics
        val b = n?.let { bounds(it) } ?: Rect(0, 0, m.widthPixels, m.heightPixels)
        val cx = b.exactCenterX()
        val cy = b.exactCenterY()
        val dx = b.width() * 0.3f
        val dy = b.height() * 0.3f
        when (direction) {
            "down" -> gesture(cx, cy + dy, cx, cy - dy, 350)
            "up" -> gesture(cx, cy - dy, cx, cy + dy, 350)
            "right" -> gesture(cx + dx, cy, cx - dx, cy, 300)
            else -> gesture(cx - dx, cy, cx + dx, cy, 300)
        }
        return mapOf("scrolled" to direction, "by" to "swipe")
    }

    fun swipe(x1: Double, y1: Double, x2: Double, y2: Double, ms: Long): Map<String, Any?> {
        val m = resources.displayMetrics
        fun px(v: Double, size: Int) = (v.coerceIn(0.0, 1.0) * size).toFloat()
        gesture(px(x1, m.widthPixels), px(y1, m.heightPixels), px(x2, m.widthPixels), px(y2, m.heightPixels), ms.coerceIn(50, 3000))
        return mapOf("swiped" to true)
    }

    fun press(key: String): Map<String, Any?> {
        val action = when (key) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            "quick_settings" -> GLOBAL_ACTION_QUICK_SETTINGS
            "lock" -> if (Build.VERSION.SDK_INT >= 28) GLOBAL_ACTION_LOCK_SCREEN else throw Refused("Locking needs Android 9 or newer.")
            else -> throw Refused("Unknown key $key.")
        }
        if (!performGlobalAction(action)) throw Refused("Android didn't do $key.")
        return mapOf("pressed" to key)
    }

    /// A tap (start = end) or a swipe, waited on.
    private fun gesture(x1: Float, y1: Float, x2: Float, y2: Float, ms: Long) {
        val path = Path().apply {
            moveTo(x1.coerceAtLeast(0f), y1.coerceAtLeast(0f))
            lineTo(x2.coerceAtLeast(0f), y2.coerceAtLeast(0f))
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, ms.coerceAtLeast(1))
        val latch = CountDownLatch(1)
        var ok = false
        main.post {
            val sent = dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    ok = true
                    latch.countDown()
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    latch.countDown()
                }
            }, null)
            if (!sent) latch.countDown()
        }
        latch.await(ms + 3000, TimeUnit.MILLISECONDS)
        if (!ok) throw Refused("Android didn't perform the gesture.")
    }
}
