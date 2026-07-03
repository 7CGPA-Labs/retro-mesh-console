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
        val textureRegistry = flutterEngine.renderer
        val textureEntry = textureRegistry.createSurfaceTexture()
        val surfaceTexture = textureEntry.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(256, 224) // Native resolution for crisp rendering
        val surface = android.view.Surface(surfaceTexture)
        NativeRender.setFlutterSurface(surface)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.seven_cgpalabs.mojosnap/texture").setMethodCallHandler { call, result ->
            if (call.method == "getTextureId") {
                result.success(textureEntry.id())
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.seven_cgpalabs.mojosnap/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "startHost" -> {
                    NetworkManager.startHost(applicationContext)
                    result.success(null)
                }
                "startClient" -> {
                    NetworkManager.startClient(applicationContext)
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
