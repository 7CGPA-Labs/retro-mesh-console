package com.retromesh.retro_mesh_console

import android.content.Context
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
