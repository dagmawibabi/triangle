package com.example.teleai

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.TelephonyNetworkSpecifier
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import java.net.Inet4Address
import java.net.Inet6Address

/** Collects information about Wi-Fi, SIM cards and the active network. */
object NetInfo {

    fun cm(ctx: Context): ConnectivityManager = ctx.getSystemService(ConnectivityManager::class.java)
    private fun wm(ctx: Context): WifiManager = ctx.applicationContext.getSystemService(WifiManager::class.java)
    private fun tm(ctx: Context): TelephonyManager = ctx.getSystemService(TelephonyManager::class.java)

    fun has(ctx: Context, p: String) = ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED

    private inline fun <T> safe(block: () -> T): T? = try {
        block()
    } catch (_: Throwable) {
        null
    }

    // ------------------------------------------------------------------ SIMs

    @SuppressLint("MissingPermission")
    fun subscriptions(ctx: Context): List<SubscriptionInfo> {
        if (!has(ctx, Manifest.permission.READ_PHONE_STATE)) return emptyList()
        val sm = ctx.getSystemService(SubscriptionManager::class.java)
        return safe { sm.activeSubscriptionInfoList }?.sortedBy { it.simSlotIndex } ?: emptyList()
    }

    fun defaultDataSubId(): Int = SubscriptionManager.getDefaultDataSubscriptionId()

    fun sims(ctx: Context): List<Map<String, Any?>> {
        val def = defaultDataSubId()
        return subscriptions(ctx).map { simMap(ctx, it, def) }
    }

    @SuppressLint("MissingPermission")
    private fun simMap(ctx: Context, info: SubscriptionInfo, defData: Int): Map<String, Any?> {
        val tm = tm(ctx).createForSubscriptionId(info.subscriptionId)
        val m = mutableMapOf<String, Any?>(
            "subId" to info.subscriptionId,
            "slot" to info.simSlotIndex,
            "carrier" to (info.carrierName?.toString()?.ifBlank { null } ?: info.displayName?.toString()),
            "displayName" to info.displayName?.toString(),
            "isDefaultData" to (info.subscriptionId == defData),
            "isEmbedded" to info.isEmbedded,
            "countryIso" to info.countryIso,
            "mcc" to info.mccString,
            "mnc" to info.mncString,
            "roaming" to safe { tm.isNetworkRoaming },
            "operator" to safe { tm.networkOperatorName },
            "networkType" to networkTypeName(tm),
            "dataEnabled" to safe { tm.isDataEnabled },
        )
        m.putAll(cellSignal(tm))
        return m
    }

    private fun cellSignal(tm: TelephonyManager): Map<String, Any?> {
        val ss = safe { tm.signalStrength } ?: return emptyMap()
        val cs = ss.cellSignalStrengths.firstOrNull() ?: return mapOf("signalLevel" to ss.level)
        val dbm = cs.dbm.takeIf { it != Int.MAX_VALUE && it != Int.MIN_VALUE && it < 0 }
        return mapOf("signalDbm" to dbm, "signalLevel" to cs.level, "asu" to cs.asuLevel)
    }

    @SuppressLint("MissingPermission")
    fun networkTypeName(tm: TelephonyManager): String? {
        val t = safe { tm.dataNetworkType } ?: return null
        val base = when (t) {
            TelephonyManager.NETWORK_TYPE_NR -> "5G SA"
            TelephonyManager.NETWORK_TYPE_LTE -> "4G LTE"
            TelephonyManager.NETWORK_TYPE_HSPAP -> "3G H+"
            TelephonyManager.NETWORK_TYPE_HSPA, TelephonyManager.NETWORK_TYPE_HSDPA,
            TelephonyManager.NETWORK_TYPE_HSUPA -> "3G H"
            TelephonyManager.NETWORK_TYPE_UMTS, TelephonyManager.NETWORK_TYPE_EVDO_0,
            TelephonyManager.NETWORK_TYPE_EVDO_A, TelephonyManager.NETWORK_TYPE_EVDO_B,
            TelephonyManager.NETWORK_TYPE_TD_SCDMA -> "3G"
            TelephonyManager.NETWORK_TYPE_EDGE -> "2G EDGE"
            TelephonyManager.NETWORK_TYPE_GPRS, TelephonyManager.NETWORK_TYPE_CDMA,
            TelephonyManager.NETWORK_TYPE_1xRTT, TelephonyManager.NETWORK_TYPE_GSM -> "2G"
            TelephonyManager.NETWORK_TYPE_IWLAN -> "Wi-Fi calling"
            else -> null
        }
        if (t == TelephonyManager.NETWORK_TYPE_LTE) {
            // 5G NSA reports LTE as the data type; ServiceState reveals the NR leg.
            val s = safe { tm.serviceState?.toString() } ?: ""
            if (s.contains("nrState=CONNECTED") || s.contains("isNrAvailable=true")) return "5G NSA"
        }
        return base
    }

    // ----------------------------------------------------------------- Wi-Fi

    @Suppress("DEPRECATION")
    fun wifi(ctx: Context, network: Network? = null): Map<String, Any?>? {
        val wm = wm(ctx)
        var info: WifiInfo? = safe { wm.connectionInfo }
        if ((info == null || info.networkId == -1) && network != null && Build.VERSION.SDK_INT >= 31) {
            info = cm(ctx).getNetworkCapabilities(network)?.transportInfo as? WifiInfo
        }
        if (info == null || info.rssi <= -127) return null
        val ssid = info.ssid?.trim('"')?.takeIf { it.isNotEmpty() && it != "<unknown ssid>" && it != WifiManager.UNKNOWN_SSID }
        val bssid = info.bssid?.takeIf { it != "02:00:00:00:00:00" }
        val freq = info.frequency
        val level = if (Build.VERSION.SDK_INT >= 30) wm.calculateSignalLevel(info.rssi) else WifiManager.calculateSignalLevel(info.rssi, 5)
        val maxLevel = if (Build.VERSION.SDK_INT >= 30) wm.maxSignalLevel else 4
        return mapOf(
            "ssid" to ssid,
            "bssid" to bssid,
            "rssi" to info.rssi,
            "level" to level,
            "maxLevel" to maxLevel,
            "linkSpeed" to info.linkSpeed,
            "txLinkSpeed" to info.txLinkSpeedMbps.takeIf { it > 0 },
            "rxLinkSpeed" to info.rxLinkSpeedMbps.takeIf { it > 0 },
            "frequency" to freq,
            "band" to band(freq),
            "channel" to channel(freq),
            "standard" to if (Build.VERSION.SDK_INT >= 30) wifiStandard(info.wifiStandard) else null,
        )
    }

    private fun band(f: Int) = when {
        f in 2400..2500 -> "2.4 GHz"
        f in 4900..5900 -> "5 GHz"
        f in 5925..7125 -> "6 GHz"
        f > 50000 -> "60 GHz"
        else -> null
    }

    private fun channel(f: Int) = when {
        f == 2484 -> 14
        f in 2412..2472 -> (f - 2407) / 5
        f in 4900..5900 -> (f - 5000) / 5
        f in 5925..7125 -> (f - 5950) / 5
        else -> null
    }

    private fun wifiStandard(s: Int) = when (s) {
        1 -> "Wi-Fi (legacy)"
        4 -> "Wi-Fi 4 (n)"
        5 -> "Wi-Fi 5 (ac)"
        6 -> "Wi-Fi 6 (ax)"
        7 -> "WiGig (ad)"
        8 -> "Wi-Fi 7 (be)"
        else -> null
    }

    fun hotspotEnabled(ctx: Context): Boolean? = safe {
        val m = WifiManager::class.java.getDeclaredMethod("isWifiApEnabled")
        m.isAccessible = true
        m.invoke(wm(ctx)) as Boolean
    }

    // ------------------------------------------------------ Network describe

    fun transportOf(caps: NetworkCapabilities?): String = when {
        caps == null -> "none"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
        else -> "other"
    }

    fun subIdOf(caps: NetworkCapabilities?): Int? {
        if (caps == null || Build.VERSION.SDK_INT < 30) return null
        return (caps.networkSpecifier as? TelephonyNetworkSpecifier)?.subscriptionId?.takeIf { it >= 0 }
    }

    /** Fields describing a network, using the same keys as the results table. */
    fun describe(ctx: Context, network: Network?, subHint: Int? = null): MutableMap<String, Any?> {
        val m = mutableMapOf<String, Any?>()
        val caps = network?.let { safe { cm(ctx).getNetworkCapabilities(it) } }
        val transport = transportOf(caps)
        m["transport"] = transport
        when (transport) {
            "wifi" -> {
                val w = wifi(ctx, network)
                val ssid = w?.get("ssid") as String?
                m["ssid"] = ssid
                m["bssid"] = w?.get("bssid")
                m["wifi_freq"] = w?.get("frequency")
                m["wifi_standard"] = w?.get("standard")
                m["link_speed"] = w?.get("linkSpeed")
                m["signal_dbm"] = w?.get("rssi")
                m["signal_level"] = w?.get("level")
                m["network_key"] = "wifi:${ssid ?: "unknown"}"
                m["label"] = "Wi-Fi · ${ssid ?: "Unknown network"}"
            }
            "cellular" -> {
                val subId = subHint ?: subIdOf(caps) ?: defaultDataSubId()
                val info = subscriptions(ctx).firstOrNull { it.subscriptionId == subId }
                val sim = info?.let { simMap(ctx, it, defaultDataSubId()) }
                val slot = (sim?.get("slot") as Int?)
                val carrier = sim?.get("carrier") as String? ?: safe { tm(ctx).networkOperatorName }?.ifBlank { null }
                m["sub_id"] = subId
                m["sim_slot"] = slot?.plus(1)
                m["carrier"] = carrier
                m["network_type"] = sim?.get("networkType") ?: safe { networkTypeName(tm(ctx).createForSubscriptionId(subId)) }
                m["signal_dbm"] = sim?.get("signalDbm")
                m["signal_level"] = sim?.get("signalLevel")
                val slotText = slot?.let { "SIM ${it + 1}" } ?: "Mobile"
                m["network_key"] = "sim:${slot?.plus(1) ?: 0}:${carrier ?: "unknown"}"
                m["label"] = "$slotText · ${carrier ?: "Unknown carrier"}"
            }
            "ethernet" -> {
                m["network_key"] = "ethernet"; m["label"] = "Ethernet"
            }
            "none" -> {
                m["network_key"] = "offline"; m["label"] = "No connection"
            }
            else -> {
                m["network_key"] = transport; m["label"] = transport.uppercase()
            }
        }
        return m
    }

    /** Interface / IP / DNS / Wi-Fi band for a specific network (shown live during tests). */
    fun linkDetails(ctx: Context, network: Network?): Map<String, Any?>? {
        if (network == null) return null
        val lp = safe { cm(ctx).getLinkProperties(network) } ?: return null
        val m = mutableMapOf<String, Any?>(
            "iface" to lp.interfaceName,
            "ipv4" to lp.linkAddresses.firstOrNull { it.address is Inet4Address }?.address?.hostAddress,
            "dns" to lp.dnsServers.mapNotNull { it.hostAddress }.joinToString(", "),
        )
        val caps = safe { cm(ctx).getNetworkCapabilities(network) }
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) {
            wifi(ctx, network)?.let { m["band"] = it["band"]; m["channel"] = it["channel"] }
        }
        return m
    }

    // -------------------------------------------------------------- Snapshot

    @SuppressLint("MissingPermission")
    fun snapshot(ctx: Context): Map<String, Any?> {
        val cm = cm(ctx)
        val active = cm.activeNetwork
        val caps = active?.let { safe { cm.getNetworkCapabilities(it) } }
        val lp: LinkProperties? = active?.let { safe { cm.getLinkProperties(it) } }
        val vpn = safe {
            @Suppress("DEPRECATION")
            cm.allNetworks.any { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
        } ?: false

        val activeMap: Map<String, Any?>? = if (active == null) null else {
            val d = describe(ctx, active)
            d + mapOf(
                "validated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
                "metered" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true),
                "downKbps" to caps?.linkDownstreamBandwidthKbps,
                "upKbps" to caps?.linkUpstreamBandwidthKbps,
                "iface" to lp?.interfaceName,
                "ipv4" to lp?.linkAddresses?.firstOrNull { it.address is Inet4Address }?.address?.hostAddress,
                "ipv6" to lp?.linkAddresses?.firstOrNull { it.address is Inet6Address && !it.address.isLinkLocalAddress }?.address?.hostAddress,
                "dns" to lp?.dnsServers?.mapNotNull { it.hostAddress },
                "privateDns" to lp?.privateDnsServerName,
            )
        }

        val wm = wm(ctx)
        val wifiEnabled = safe { wm.isWifiEnabled } ?: false
        val wifiMap = if (wifiEnabled) wifi(ctx, active) else null
        val wifiConnected = safe {
            @Suppress("DEPRECATION")
            cm.allNetworks.any { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true }
        } ?: false

        return mapOf(
            "active" to activeMap,
            "vpn" to vpn,
            "wifiEnabled" to wifiEnabled,
            "wifiConnected" to wifiConnected,
            "wifi" to if (wifiConnected) wifiMap else null,
            "sims" to sims(ctx),
            "phonePermission" to has(ctx, Manifest.permission.READ_PHONE_STATE),
            "locationPermission" to has(ctx, Manifest.permission.ACCESS_FINE_LOCATION),
            "defaultDataSubId" to defaultDataSubId(),
            "hotspot" to hotspotEnabled(ctx),
            "airplane" to (Settings.Global.getInt(ctx.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1),
        )
    }
}
