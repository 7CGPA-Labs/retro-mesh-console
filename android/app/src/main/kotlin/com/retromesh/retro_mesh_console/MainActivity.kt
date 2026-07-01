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
        CastingAdapter(this, flutterEngine.dartExecutor.binaryMessenger)
        AudioAdapter(flutterEngine.dartExecutor.binaryMessenger)
    }
}
