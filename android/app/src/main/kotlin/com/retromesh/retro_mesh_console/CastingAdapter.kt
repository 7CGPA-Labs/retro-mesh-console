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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CastingAdapter(
    private val activity: Activity,
    messenger: BinaryMessenger
) {

    private val handler = Handler(Looper.getMainLooper())
    private val displayManager = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    
    private var presentationDialog: Presentation? = null

    init {
        val channel = MethodChannel(messenger, "com.retromesh.console/projection")
        channel.setMethodCallHandler { call, result ->
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
                "startWebServer" -> {
                    val ip = WebCaster.startServer()
                    result.success(ip)
                }
                "stopWebServer" -> {
                    WebCaster.stopServer()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openSystemCastMenu() {
        handler.post {
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
                            
                            val container = android.widget.FrameLayout(context).apply {
                                setBackgroundColor(android.graphics.Color.BLACK)
                            }
                            val surfaceView = android.view.SurfaceView(context)
                            surfaceView.holder.addCallback(object : android.view.SurfaceHolder.Callback {
                                override fun surfaceCreated(holder: android.view.SurfaceHolder) {
                                    NativeRender.setTvSurface(holder.surface)
                                }
                                override fun surfaceChanged(holder: android.view.SurfaceHolder, format: Int, width: Int, height: Int) {}
                                override fun surfaceDestroyed(holder: android.view.SurfaceHolder) {
                                    NativeRender.setTvSurface(null)
                                }
                            })
                            
                            container.addView(surfaceView, android.widget.FrameLayout.LayoutParams(
                                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                                android.view.ViewGroup.LayoutParams.MATCH_PARENT
                            ).apply {
                                gravity = android.view.Gravity.CENTER
                            })
                            
                            // Force 4:3 Aspect Ratio
                            container.addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
                                val w = right - left
                                val h = bottom - top
                                val targetW: Int
                                val targetH: Int
                                if (w * 3 > h * 4) { // TV is wider than 4:3 (e.g. 16:9)
                                    targetH = h
                                    targetW = h * 4 / 3
                                } else {
                                    targetW = w
                                    targetH = w * 3 / 4
                                }
                                val params = surfaceView.layoutParams
                                if (params.width != targetW || params.height != targetH) {
                                    params.width = targetW
                                    params.height = targetH
                                    surfaceView.layoutParams = params
                                }
                            }
                            
                            setContentView(container)
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
