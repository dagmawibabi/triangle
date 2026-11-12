package com.example.teleai

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.Settings
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.Inet4Address
import java.net.Inet6Address
import android.bluetooth.BluetoothManager
import android.location.LocationManager
import android.nfc.NfcAdapter

/// The phone itself, for the assistant's device tools (lib/features/device):
/// text messages, call log and contacts, installed apps, specs, battery and
/// network, and actions such as calling, the flashlight, volume, alarms and
/// media keys. Every call answers with a map; a missing Android permission
/// comes back as the error "permission" with the permissions needed, which
/// Flutter asks for with "request".
object DeviceChannel {
    private const val CHANNEL = "teleai/device"
    private const val REQUEST_CODE = 7311

    /// The activity on screen, for permission dialogs and starting apps.
    var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private var pendingPermissions: List<String> = emptyList()
    private var torchOn = false

    fun attach(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                handle(app, call, result)
            } catch (e: SecurityException) {
                result.error("permission", e.message, null)
            } catch (e: Exception) {
                result.error("failed", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun granted(context: Context, permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /// Answers "permission" when any of [permissions] is missing.
    private fun need(context: Context, result: MethodChannel.Result, vararg permissions: String): Boolean {
        val missing = permissions.filter { !granted(context, it) }
        if (missing.isEmpty()) return true
        result.error("permission", "Android permission needed: ${missing.joinToString()}", missing)
        return false
    }

    fun onPermissionResult(requestCode: Int, permissions: Array<out String>, grants: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val r = pending ?: return true
        pending = null
        val map = HashMap<String, Boolean>()
        for (p in pendingPermissions) map[p] = false
        for (i in permissions.indices) map[permissions[i]] = grants.getOrNull(i) == PackageManager.PERMISSION_GRANTED
        r.success(map)
        return true
    }

    private fun start(context: Context, intent: Intent) {
        val a = activity
        if (a != null) {
            a.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    @SuppressLint("MissingPermission")
    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> {
                val list = call.argument<List<String>>("permissions") ?: emptyList()
                result.success(list.associateWith { granted(context, it) })
            }
            "request" -> {
                val list = call.argument<List<String>>("permissions") ?: emptyList()
                val a = activity
                if (a == null) {
                    result.error("background", "Open Triangle to allow this.", null)
                    return
                }
                val missing = list.filter { !granted(context, it) }
                if (missing.isEmpty()) {
                    result.success(list.associateWith { true })
                    return
                }
                pending?.success(emptyMap<String, Boolean>())
                pending = result
                pendingPermissions = missing
                ActivityCompat.requestPermissions(a, missing.toTypedArray(), REQUEST_CODE)
            }
            "openAppSettings" -> {
                start(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
                result.success(true)
            }
            // Do Not Disturb access: needed to change the ringer mode.
            "dndAccess" -> {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                result.success(nm.isNotificationPolicyAccessGranted)
            }
            "openDndAccess" -> {
                start(context, Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                result.success(true)
            }
            "screenTime" -> {
                val days = call.argument<Int>("days") ?: 7
                val end = call.argument<Number>("end")?.toLong()
                Thread {
                    try {
                        val r = ScreenTime.query(context, days, end)
                        android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(r) }
                    } catch (e: SecurityException) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post { result.error("usage_access", "Usage access is off.", null) }
                    } catch (e: Exception) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
                    }
                }.start()
            }
            "imageOp" -> ImageOps.handle(call, result)
            "deviceInfo" -> result.success(deviceInfo(context))
            "battery" -> result.success(battery(context))
            "network" -> result.success(network(context))
            "apps" -> result.success(apps(context, call.argument<Boolean>("system") ?: false, call.argument<String>("query")))
            "openApp" -> {
                val pkg = call.argument<String>("package") ?: ""
                val intent = context.packageManager.getLaunchIntentForPackage(pkg)
                if (intent == null) {
                    result.error("failed", "No app $pkg that can be opened.", null)
                } else {
                    start(context, intent)
                    result.success(true)
                }
            }
            "sms" -> if (need(context, result, Manifest.permission.READ_SMS)) result.success(sms(context, call))
            "sendSms" -> if (need(context, result, Manifest.permission.SEND_SMS)) {
                val to = call.argument<String>("to") ?: ""
                val text = call.argument<String>("text") ?: ""
                val manager = if (Build.VERSION.SDK_INT >= 31) context.getSystemService(SmsManager::class.java) else @Suppress("DEPRECATION") SmsManager.getDefault()
                val parts = manager.divideMessage(text)
                manager.sendMultipartTextMessage(to, null, parts, null, null)
                result.success(mapOf("sent" to true, "parts" to parts.size))
            }
            "callLog" -> if (need(context, result, Manifest.permission.READ_CALL_LOG)) result.success(callLog(context, call))
            "contacts" -> if (need(context, result, Manifest.permission.READ_CONTACTS)) result.success(contacts(context, call.argument<String>("query") ?: "", call.argument<Int>("limit") ?: 30))
            "call" -> {
                val number = call.argument<String>("number") ?: ""
                val direct = (call.argument<Boolean>("direct") ?: true) && granted(context, Manifest.permission.CALL_PHONE)
                val uri = Uri.parse("tel:" + Uri.encode(number))
                start(context, Intent(if (direct) Intent.ACTION_CALL else Intent.ACTION_DIAL, uri))
                result.success(mapOf("calling" to direct, "dialer_opened" to !direct))
            }
            "openSms" -> {
                val number = call.argument<String>("number") ?: ""
                start(context, Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + Uri.encode(number))))
                result.success(true)
            }
            "flashlight" -> {
                val camera = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                val id = camera.cameraIdList.firstOrNull {
                    camera.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                }
                if (id == null) {
                    result.error("failed", "This phone has no flashlight.", null)
                } else {
                    val on = call.argument<Boolean>("on") ?: !torchOn
                    camera.setTorchMode(id, on)
                    torchOn = on
                    result.success(mapOf("on" to on))
                }
            }
            "vibrate" -> {
                val ms = (call.argument<Int>("ms") ?: 400).toLong().coerceIn(10, 5000)
                val v = if (Build.VERSION.SDK_INT >= 31) {
                    (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                } else {
                    @Suppress("DEPRECATION") context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
                if (Build.VERSION.SDK_INT >= 26) {
                    v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION") v.vibrate(ms)
                }
                result.success(mapOf("ms" to ms))
            }
            "volume" -> result.success(volume(context, call))
            "ringer" -> {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val mode = when (call.argument<String>("mode")) {
                    "silent" -> AudioManager.RINGER_MODE_SILENT
                    "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
                    else -> AudioManager.RINGER_MODE_NORMAL
                }
                try {
                    audio.ringerMode = mode
                    result.success(mapOf("mode" to call.argument<String>("mode")))
                } catch (e: SecurityException) {
                    start(context, Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    result.error("failed", "Android needs Do Not Disturb access for Triangle to change this; its settings were opened.", null)
                }
            }
            "media" -> {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val code = when (call.argument<String>("action")) {
                    "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                    "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                    "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                    "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                    "stop" -> KeyEvent.KEYCODE_MEDIA_STOP
                    else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                }
                audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
                result.success(mapOf("sent" to (call.argument<String>("action") ?: "toggle"), "music_playing" to audio.isMusicActive))
            }
            "alarm" -> {
                val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                    putExtra(AlarmClock.EXTRA_HOUR, call.argument<Int>("hour") ?: 7)
                    putExtra(AlarmClock.EXTRA_MINUTES, call.argument<Int>("minute") ?: 0)
                    call.argument<String>("label")?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it) }
                    call.argument<List<Int>>("days")?.takeIf { it.isNotEmpty() }?.let { putExtra(AlarmClock.EXTRA_DAYS, ArrayList(it)) }
                    putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                }
                start(context, intent)
                result.success(mapOf("set" to true))
            }
            "timer" -> {
                val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                    putExtra(AlarmClock.EXTRA_LENGTH, (call.argument<Int>("seconds") ?: 60).coerceIn(1, 86400))
                    call.argument<String>("label")?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it) }
                    putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                }
                start(context, intent)
                result.success(mapOf("set" to true))
            }
            "openSettings" -> {
                val page = call.argument<String>("page")
                // Android 10+ lets apps show the system's own switches in a
                // panel over the app (apps can no longer flip them).
                val panel = if (Build.VERSION.SDK_INT >= 29) when (page) {
                    "panel_internet" -> Settings.Panel.ACTION_INTERNET_CONNECTIVITY
                    "panel_wifi" -> Settings.Panel.ACTION_WIFI
                    "panel_nfc" -> Settings.Panel.ACTION_NFC
                    else -> null
                } else null
                if (panel != null) {
                    start(context, Intent(panel))
                    result.success(true)
                    return
                }
                val action = when (page) {
                    "panel_internet" -> Settings.ACTION_WIRELESS_SETTINGS
                    "panel_wifi" -> Settings.ACTION_WIFI_SETTINGS
                    "panel_nfc" -> Settings.ACTION_NFC_SETTINGS
                    "vpn" -> Settings.ACTION_VPN_SETTINGS
                    "data_usage" -> if (Build.VERSION.SDK_INT >= 28) Settings.ACTION_DATA_USAGE_SETTINGS else Settings.ACTION_WIRELESS_SETTINGS
                    "network" -> Settings.ACTION_WIRELESS_SETTINGS
                    "wifi" -> Settings.ACTION_WIFI_SETTINGS
                    "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                    "mobile_data" -> Settings.ACTION_DATA_ROAMING_SETTINGS
                    "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
                    "battery" -> Intent.ACTION_POWER_USAGE_SUMMARY
                    "display" -> Settings.ACTION_DISPLAY_SETTINGS
                    "sound" -> Settings.ACTION_SOUND_SETTINGS
                    "storage" -> Settings.ACTION_INTERNAL_STORAGE_SETTINGS
                    "apps" -> Settings.ACTION_APPLICATION_SETTINGS
                    "airplane" -> Settings.ACTION_AIRPLANE_MODE_SETTINGS
                    "hotspot" -> "android.settings.TETHER_SETTINGS"
                    "nfc" -> Settings.ACTION_NFC_SETTINGS
                    "dnd" -> Settings.ACTION_ZEN_MODE_PRIORITY_SETTINGS
                    else -> Settings.ACTION_SETTINGS
                }
                start(context, Intent(action))
                result.success(true)
            }
            "keepScreenOn" -> {
                val a = activity
                if (a == null) {
                    result.error("background", "Triangle isn't on screen.", null)
                } else {
                    val on = call.argument<Boolean>("on") ?: true
                    a.runOnUiThread {
                        if (on) a.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) else a.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(mapOf("on" to on))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun deviceInfo(context: Context): Map<String, Any?> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val data = StatFs(Environment.getDataDirectory().path)
        val metrics = context.resources.displayMetrics
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "hardware" to Build.HARDWARE,
            "soc" to if (Build.VERSION.SDK_INT >= 31) "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}" else Build.BOARD,
            "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "security_patch" to Build.VERSION.SECURITY_PATCH,
            "build" to Build.DISPLAY,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "cpu_cores" to Runtime.getRuntime().availableProcessors(),
            "ram_total" to mem.totalMem,
            "ram_available" to mem.availMem,
            "low_memory" to mem.lowMemory,
            "storage_total" to data.totalBytes,
            "storage_free" to data.availableBytes,
            "screen_width_px" to metrics.widthPixels,
            "screen_height_px" to metrics.heightPixels,
            "density_dpi" to metrics.densityDpi,
            "uptime_ms" to SystemClock.elapsedRealtime(),
            "battery" to battery(context),
        )
    }

    private fun battery(context: Context): Map<String, Any?> {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val sticky = context.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = sticky?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val health = sticky?.getIntExtra(BatteryManager.EXTRA_HEALTH, 0) ?: 0
        return mapOf(
            "level" to bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL),
            "full" to (status == BatteryManager.BATTERY_STATUS_FULL),
            "plugged" to when (plugged) {
                BatteryManager.BATTERY_PLUGGED_AC -> "charger"
                BatteryManager.BATTERY_PLUGGED_USB -> "usb"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
                else -> null
            },
            "temperature_c" to (sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10.0,
            "voltage_mv" to sticky?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0),
            "health" to when (health) {
                BatteryManager.BATTERY_HEALTH_GOOD -> "good"
                BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheating"
                BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
                BatteryManager.BATTERY_HEALTH_COLD -> "cold"
                BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over voltage"
                else -> "unknown"
            },
            "technology" to sticky?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY),
            "power_saver" to (context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager).isPowerSaveMode,
        )
    }

    @SuppressLint("MissingPermission")
    private fun network(context: Context): Map<String, Any?> {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork
        val caps = net?.let { cm.getNetworkCapabilities(it) }
        val link = net?.let { cm.getLinkProperties(it) }
        val transport = when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
            else -> "other"
        }
        val out = mutableMapOf<String, Any?>(
            "connected" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true),
            "validated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "type" to transport,
            "vpn" to (caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true),
            "metered" to cm.isActiveNetworkMetered,
            "down_kbps" to caps?.linkDownstreamBandwidthKbps,
            "up_kbps" to caps?.linkUpstreamBandwidthKbps,
            "ip_addresses" to link?.linkAddresses?.map { it.address.hostAddress },
            "ipv4" to link?.linkAddresses?.firstOrNull { it.address is Inet4Address }?.address?.hostAddress,
            "dns" to link?.dnsServers?.map { it.hostAddress },
            "interface" to link?.interfaceName,
            "private_dns" to if (Build.VERSION.SDK_INT >= 28) link?.privateDnsServerName else null,
            "private_dns_active" to if (Build.VERSION.SDK_INT >= 28) link?.isPrivateDnsActive else null,
            "airplane_mode" to (Settings.Global.getInt(context.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0) != 0),
            "ipv6" to link?.linkAddresses?.firstOrNull { it.address is Inet6Address && !it.address.isLinkLocalAddress }?.address?.hostAddress,
            "gateway" to link?.routes?.firstOrNull { it.isDefaultRoute && it.gateway != null }?.gateway?.hostAddress,
            "domains" to link?.domains,
            "mtu" to if (Build.VERSION.SDK_INT >= 29) link?.mtu?.takeIf { it > 0 } else null,
            "not_vpn_restricted" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED) == true),
            "captive_portal" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) == true),
        )
        // What each radio is set to, for the sheet's switches. Each read is
        // allowed without extra permissions on current Android; any that
        // isn't on this phone is left out.
        out["toggles"] = toggles(context)
        if (transport == "wifi") {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION") val info = wm.connectionInfo
            val ssid = info?.ssid?.trim('"')
            out["wifi"] = mapOf(
                // Android hides the name without location permission.
                "ssid" to if (ssid == null || ssid == "<unknown ssid>") null else ssid,
                "signal_dbm" to info?.rssi,
                "signal_bars" to info?.rssi?.let { @Suppress("DEPRECATION") WifiManager.calculateSignalLevel(it, 5) },
                "link_mbps" to info?.linkSpeed,
                "frequency_mhz" to info?.frequency,
                "band" to info?.frequency?.let { if (it > 5900) "6 GHz" else if (it > 4900) "5 GHz" else "2.4 GHz" },
                "name_hidden" to (ssid == null || ssid == "<unknown ssid>"),
                "channel" to info?.frequency?.let { f ->
                    when {
                        f == 2484 -> 14
                        f in 2412..2472 -> (f - 2407) / 5
                        f in 5000..5895 -> (f - 5000) / 5
                        f in 5925..7125 -> (f - 5950) / 5
                        else -> null
                    }
                },
                "standard" to if (Build.VERSION.SDK_INT >= 30) when (info?.wifiStandard) {
                    4 -> "Wi-Fi 4 (802.11n)"
                    5 -> "Wi-Fi 5 (802.11ac)"
                    6 -> "Wi-Fi 6 (802.11ax)"
                    7 -> "WiGig (802.11ad)"
                    8 -> "Wi-Fi 7 (802.11be)"
                    1 -> "802.11a/b/g"
                    else -> null
                } else null,
                "max_link_mbps" to if (Build.VERSION.SDK_INT >= 30) info?.maxSupportedRxLinkSpeedMbps?.takeIf { it > 0 } else null,
                "tx_mbps" to if (Build.VERSION.SDK_INT >= 29) info?.txLinkSpeedMbps?.takeIf { it > 0 } else null,
                "rx_mbps" to if (Build.VERSION.SDK_INT >= 29) info?.rxLinkSpeedMbps?.takeIf { it > 0 } else null,
            )
        }
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        out["carrier"] = tm.networkOperatorName.ifEmpty { null }
        out["sim_country"] = tm.simCountryIso.ifEmpty { null }
        out["roaming"] = try {
            tm.isNetworkRoaming
        } catch (e: Exception) {
            null
        }
        // 0 (none) to 4 (great), the same bars the status bar shows.
        out["cell_signal_level"] = if (Build.VERSION.SDK_INT >= 28) try {
            tm.signalStrength?.level
        } catch (e: Exception) {
            null
        } else null
        out["operator_country"] = tm.networkCountryIso.ifEmpty { null }
        return out
    }

    private fun toggles(context: Context): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        out["airplane"] = Settings.Global.getInt(context.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0) != 0
        out["wifi"] = try {
            (context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).isWifiEnabled
        } catch (e: Exception) {
            null
        }
        out["mobile_data"] = if (Build.VERSION.SDK_INT >= 26) try {
            (context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager).isDataEnabled
        } catch (e: Exception) {
            null
        } else null
        out["bluetooth"] = try {
            (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter?.isEnabled
        } catch (e: Exception) {
            null
        }
        out["nfc"] = try {
            NfcAdapter.getDefaultAdapter(context)?.isEnabled
        } catch (e: Exception) {
            null
        }
        out["location"] = try {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            if (Build.VERSION.SDK_INT >= 28) lm.isLocationEnabled else lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
        } catch (e: Exception) {
            null
        }
        return out
    }

    private fun appIcon(context: Context, info: ApplicationInfo, pm: PackageManager): String? = try {
        val dir = File(context.cacheDir, "app_icons").apply { mkdirs() }
        val file = File(dir, "${info.packageName}.png")
        if (!file.exists()) {
            val d = info.loadIcon(pm)
            val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            d.setBounds(0, 0, 96, 96)
            d.draw(canvas)
            FileOutputStream(file).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        file.path
    } catch (e: Exception) {
        null
    }

    private fun apps(context: Context, system: Boolean, query: String?): List<Map<String, Any?>> {
        val pm = context.packageManager
        val launchable = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .map { it.activityInfo.packageName }.toSet()
        val q = query?.trim()?.lowercase().orEmpty()
        @Suppress("DEPRECATION")
        val all = pm.getInstalledApplications(0)
        return all.mapNotNull { info ->
            val isSystem = info.flags and ApplicationInfo.FLAG_SYSTEM != 0 && info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP == 0
            if (isSystem && !system && info.packageName !in launchable) return@mapNotNull null
            if (!system && isSystem) return@mapNotNull null
            val label = info.loadLabel(pm).toString()
            if (q.isNotEmpty() && !label.lowercase().contains(q) && !info.packageName.contains(q)) return@mapNotNull null
            @Suppress("DEPRECATION")
            val pkg = try { pm.getPackageInfo(info.packageName, 0) } catch (e: Exception) { null }
            mapOf(
                "name" to label,
                "package" to info.packageName,
                "version" to pkg?.versionName,
                "installed" to pkg?.firstInstallTime,
                "updated" to pkg?.lastUpdateTime,
                "system" to isSystem,
                "can_open" to (info.packageName in launchable),
                "icon_path" to appIcon(context, info, pm),
            )
        }.sortedBy { (it["name"] as String).lowercase() }
    }

    private fun sms(context: Context, call: MethodCall): List<Map<String, Any?>> {
        val box = call.argument<String>("box") ?: "inbox"
        val uri = when (box) {
            "sent" -> Telephony.Sms.Sent.CONTENT_URI
            "all" -> Telephony.Sms.CONTENT_URI
            else -> Telephony.Sms.Inbox.CONTENT_URI
        }
        // The finance sync reads the inbox in bulk; everything else gets 200 at most.
        val limit = (call.argument<Int>("limit") ?: 30).coerceIn(1, if (call.argument<Boolean>("bulk") == true) 5000 else 200)
        val clauses = mutableListOf<String>()
        val args = mutableListOf<String>()
        call.argument<String>("address")?.takeIf { it.isNotBlank() }?.let {
            clauses.add("${Telephony.Sms.ADDRESS} LIKE ?")
            args.add("%${it.filter { c -> c.isDigit() || c.isLetter() }.takeLast(9)}%")
        }
        call.argument<String>("query")?.takeIf { it.isNotBlank() }?.let {
            clauses.add("${Telephony.Sms.BODY} LIKE ?")
            args.add("%$it%")
        }
        call.argument<Number>("since")?.let {
            clauses.add("${Telephony.Sms.DATE} >= ?")
            args.add(it.toLong().toString())
        }
        if (call.argument<Boolean>("unread_only") == true) clauses.add("${Telephony.Sms.READ} = 0")
        val out = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            uri,
            arrayOf(Telephony.Sms._ID, Telephony.Sms.THREAD_ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.READ, Telephony.Sms.TYPE),
            clauses.joinToString(" AND ").ifEmpty { null },
            args.toTypedArray(),
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            while (c.moveToNext() && out.size < limit) {
                val address = c.getString(2)
                out.add(
                    mapOf(
                        "id" to c.getLong(0),
                        "thread_id" to c.getLong(1),
                        "address" to address,
                        "name" to contactName(context, address),
                        "body" to c.getString(3),
                        "date" to c.getLong(4),
                        "read" to (c.getInt(5) == 1),
                        "sent" to (c.getInt(6) == Telephony.Sms.MESSAGE_TYPE_SENT),
                    ),
                )
            }
        }
        return out
    }

    private val names = HashMap<String, String?>()

    private fun contactName(context: Context, number: String?): String? {
        if (number.isNullOrBlank() || !granted(context, Manifest.permission.READ_CONTACTS)) return null
        return names.getOrPut(number) {
            try {
                context.contentResolver.query(
                    Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number)),
                    arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            } catch (e: Exception) {
                null
            }
        }
    }

    private fun callLog(context: Context, call: MethodCall): List<Map<String, Any?>> {
        // The call history analysis reads the whole log in bulk; other uses get 200 at most.
        val bulk = call.argument<Boolean>("bulk") == true
        val limit = (call.argument<Int>("limit") ?: 30).coerceIn(1, if (bulk) 50000 else 200)
        val type = call.argument<String>("type")
        val clauses = mutableListOf<String>()
        when (type) {
            "missed" -> clauses.add("${CallLog.Calls.TYPE} = ${CallLog.Calls.MISSED_TYPE}")
            "incoming" -> clauses.add("${CallLog.Calls.TYPE} = ${CallLog.Calls.INCOMING_TYPE}")
            "outgoing" -> clauses.add("${CallLog.Calls.TYPE} = ${CallLog.Calls.OUTGOING_TYPE}")
        }
        call.argument<Number>("since")?.let { clauses.add("${CallLog.Calls.DATE} >= ${it.toLong()}") }
        val where = clauses.joinToString(" AND ").ifEmpty { null }
        val out = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE, CallLog.Calls.DATE, CallLog.Calls.DURATION),
            where,
            null,
            "${CallLog.Calls.DATE} DESC",
        )?.use { c ->
            while (c.moveToNext() && out.size < limit) {
                out.add(
                    mapOf(
                        "number" to c.getString(0),
                        "name" to (c.getString(1) ?: contactName(context, c.getString(0))),
                        "type" to when (c.getInt(2)) {
                            CallLog.Calls.INCOMING_TYPE -> "incoming"
                            CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                            CallLog.Calls.MISSED_TYPE -> "missed"
                            CallLog.Calls.REJECTED_TYPE -> "rejected"
                            CallLog.Calls.BLOCKED_TYPE -> "blocked"
                            else -> "other"
                        },
                        "date" to c.getLong(3),
                        "seconds" to c.getLong(4),
                    ),
                )
            }
        }
        return out
    }

    private fun contacts(context: Context, query: String, limit: Int): List<Map<String, Any?>> {
        val out = LinkedHashMap<String, MutableMap<String, Any?>>()
        val uri = if (query.isBlank()) ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        else Uri.withAppendedPath(ContactsContract.CommonDataKinds.Phone.CONTENT_FILTER_URI, Uri.encode(query))
        context.contentResolver.query(
            uri,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.TYPE,
                ContactsContract.CommonDataKinds.Phone.STARRED,
            ),
            null,
            null,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0)
                val entry = out.getOrPut(id) {
                    if (out.size >= limit.coerceIn(1, 300)) return@use
                    mutableMapOf("name" to c.getString(1), "numbers" to mutableListOf<Map<String, Any?>>(), "starred" to (c.getInt(4) == 1))
                }
                @Suppress("UNCHECKED_CAST")
                (entry["numbers"] as MutableList<Map<String, Any?>>).add(
                    mapOf(
                        "number" to c.getString(2),
                        "label" to ContactsContract.CommonDataKinds.Phone.getTypeLabel(context.resources, c.getInt(3), "").toString(),
                    ),
                )
            }
        }
        return out.values.toList()
    }

    private fun volume(context: Context, call: MethodCall): Map<String, Any?> {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val streams = mapOf(
            "media" to AudioManager.STREAM_MUSIC,
            "ring" to AudioManager.STREAM_RING,
            "alarm" to AudioManager.STREAM_ALARM,
            "notification" to AudioManager.STREAM_NOTIFICATION,
            "call" to AudioManager.STREAM_VOICE_CALL,
        )
        val name = call.argument<String>("stream") ?: "media"
        val stream = streams[name] ?: AudioManager.STREAM_MUSIC
        val percent = call.argument<Int>("percent")
        val max = audio.getStreamMaxVolume(stream)
        if (percent != null) {
            audio.setStreamVolume(stream, (max * percent.coerceIn(0, 100) / 100.0).toInt(), AudioManager.FLAG_SHOW_UI)
        } else if (call.argument<Boolean>("mute") == true) {
            audio.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, AudioManager.FLAG_SHOW_UI)
        } else if (call.argument<Boolean>("unmute") == true) {
            audio.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, AudioManager.FLAG_SHOW_UI)
        }
        return mapOf(
            "stream" to name,
            "levels" to streams.mapValues { (_, s) -> (audio.getStreamVolume(s) * 100 / audio.getStreamMaxVolume(s).coerceAtLeast(1)) },
            "ringer" to when (audio.ringerMode) {
                AudioManager.RINGER_MODE_SILENT -> "silent"
                AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                else -> "normal"
            },
        )
    }
}
