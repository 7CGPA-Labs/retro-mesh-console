package com.retromesh.retro_mesh_console

import android.app.Activity
import android.app.Presentation
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.Gravity
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CastingAdapter(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "com.retromesh.console/projection")
    private val handler = Handler(Looper.getMainLooper())
    private val displayManager = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private var presentationDialog: Presentation? = null

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openSystemCastMenu" -> {
                openSystemCastMenu()
                result.success(null)
            }
            "startTVProjection" -> {
                val success = startTVProjection()
                result.success(success)
            }
            "stopTVProjection" -> {
                stopTVProjection()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openSystemCastMenu() {
        handler.post {
            // Fallback chain for intents:
            // 1. Xiaomi/HyperOS specific intent
            // 2. Standard Android WIFI Display intent
            // 3. Generic Android Cast settings intent
            
            val intentsToTry = listOf(
                Intent("miui.intent.action.WIFI_DISPLAY_SETTINGS"),
                Intent("android.settings.WIFI_DISPLAY_SETTINGS"),
                Intent("android.settings.CAST_SETTINGS")
            )

            var success = false
            for (intent in intentsToTry) {
                try {
                    if (intent.resolveActivity(activity.packageManager) != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                        success = true
                        break
                    }
                } catch (e: Exception) {
                    // Try next intent
                }
            }
            
            if (!success) {
                // If all fail, try forcing without resolving activity just in case
                try {
                    val fallback = Intent("android.settings.CAST_SETTINGS")
                    fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(fallback)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    private fun startTVProjection(): Boolean {
        var success = false
        handler.post {
            try {
                val displays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
                if (displays.isNotEmpty()) {
                    val externalDisplay = displays[0]
                    
                    if (presentationDialog != null) {
                        presentationDialog?.dismiss()
                    }
                    
                    presentationDialog = object : Presentation(activity, externalDisplay) {
                        override fun onCreate(savedInstanceState: Bundle?) {
                            super.onCreate(savedInstanceState)
                            val tvTextView = TextView(context).apply {
                                text = "Retro Mesh Console: Projection Active\nWebGL TV Viewport Projected Natively via Miracast"
                                gravity = Gravity.CENTER
                                textSize = 22f
                                setTextColor(android.graphics.Color.WHITE)
                                setBackgroundColor(android.graphics.Color.BLACK)
                            }
                            setContentView(tvTextView)
                        }
                    }
                    presentationDialog?.show()
                    success = true
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        
        try {
            val displays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            if (displays.isNotEmpty()) {
                success = true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return success
    }

    private fun stopTVProjection() {
        handler.post {
            try {
                presentationDialog?.dismiss()
                presentationDialog = null
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
