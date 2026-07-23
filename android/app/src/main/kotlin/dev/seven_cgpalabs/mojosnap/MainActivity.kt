package dev.seven_cgpalabs.mojosnap

import android.content.Context

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "dev.seven_cgpalabs.mojosnap/projection"
    private var presentationDialog: android.app.Presentation? = null

    private lateinit var thermalManager: ThermalManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        thermalManager = ThermalManager(this)
        thermalManager.startMonitoring()
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CastingAdapter(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.seven_cgpalabs.mojosnap/wifi").setMethodCallHandler { call, result ->
            if (call.method == "getWifiRssi") {
                try {
                    val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                    val info = wifiManager.connectionInfo
                    if (info != null && info.rssi != -127) {
                        result.success(info.rssi)
                    } else {
                        // Mock RSSI if location permissions are missing
                        result.success(-58)
                    }
                } catch (e: Exception) {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
        // No texture rendering on Flutter side anymore

        val systemChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.seven_cgpalabs.mojosnap/system")
        
        NetworkManager.onHostsDiscovered = { hosts ->
            runOnUiThread {
                systemChannel.invokeMethod("onHostsDiscovered", hosts)
            }
        }
        
        NetworkManager.onHostDisconnected = {
            runOnUiThread {
                systemChannel.invokeMethod("onHostDisconnected", null)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.seven_cgpalabs.mojosnap/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "startHost" -> {
                    val coreName = call.argument<String>("core") ?: "nes"
                    val playerName = call.argument<String>("playerName") ?: "Player 1"
                    NetworkManager.startHost(applicationContext, coreName, playerName)
                    result.success(null)
                }
                "stopHost" -> {
                    NetworkManager.stop()
                    result.success(null)
                }
                "startDiscovery" -> {
                    NetworkManager.startDiscovery(applicationContext)
                    result.success(null)
                }
                "stopDiscovery" -> {
                    NetworkManager.stopDiscovery()
                    result.success(null)
                }
                "connectToHost" -> {
                    val ip = call.argument<String>("ip") ?: ""
                    NetworkManager.connectToServer(ip, 48293)
                    result.success(null)
                }
                "sendInput" -> {
                    val buttonId = call.argument<Int>("buttonId") ?: 0
                    val pressed = call.argument<Boolean>("pressed") ?: false
                    NetworkManager.sendInput(buttonId, pressed)
                    result.success(null)
                }
                "keepScreenOn" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    if (enable) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

object NativeRender {
    init {
        System.loadLibrary("native_render")
    }
    external fun setFlutterSurface(surface: android.view.Surface?)
    external fun setTvSurface(surface: android.view.Surface?)
}
