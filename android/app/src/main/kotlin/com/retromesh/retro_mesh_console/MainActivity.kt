package com.retromesh.retro_mesh_console

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.hardware.display.DisplayManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.retromesh.console/projection"
    private var presentationDialog: android.app.Presentation? = null

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSystemCastMenu" -> {
                    try {
                        val intent = Intent(Settings.ACTION_CAST_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent("android.settings.WIFI_DISPLAY_SETTINGS").apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("CAST_SETTINGS_FAILED", ex.message, null)
                        }
                    }
                }
                "startTVProjection" -> {
                    val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
                    val displays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
                    if (displays.isNotEmpty()) {
                        val externalDisplay = displays[0]
                        
                        // Spawn a custom presentation dialog pinned to the external monitor
                        presentationDialog = object : android.app.Presentation(this@MainActivity, externalDisplay) {
                            override fun onCreate(savedInstanceState: Bundle?) {
                                super.onCreate(savedInstanceState)
                                // Creates a simple text status screen for the cast target display
                                val tvTextView = android.widget.TextView(context).apply {
                                    text = "Retro Mesh Console: Projection Active\nWebGL TV Viewport Projected via Cast SDK"
                                    gravity = android.view.Gravity.CENTER
                                    textSize = 20f
                                    setTextColor(android.graphics.Color.WHITE)
                                    setBackgroundColor(android.graphics.Color.BLACK)
                                }
                                setContentView(tvTextView)
                            }
                        }
                        presentationDialog?.show()
                        result.success(true)
                    } else {
                        result.success(false) // Return false when no physical TV is connected
                    }
                }
                "stopTVProjection" -> {
                    presentationDialog?.dismiss()
                    presentationDialog = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
