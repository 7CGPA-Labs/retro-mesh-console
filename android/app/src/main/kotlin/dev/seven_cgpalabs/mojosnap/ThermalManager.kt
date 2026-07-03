package dev.seven_cgpalabs.mojosnap

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log

class ThermalManager(private val context: Context) {
    private val TAG = "ThermalManager"
    private var powerManager: PowerManager? = null
    
    // Threshold state tracker to avoid spamming the JNI bridge
    private var isCurrentlyThrottled = false

    init {
        powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    }

    fun startMonitoring() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            powerManager?.addThermalStatusListener { status ->
                handleThermalStatus(status)
            }
            // Check initial state
            handleThermalStatus(powerManager?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE)
        } else {
            Log.w(TAG, "Thermal API not supported on this device (requires Android 10+)")
        }
    }

    private fun handleThermalStatus(status: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            when (status) {
                PowerManager.THERMAL_STATUS_SEVERE,
                PowerManager.THERMAL_STATUS_CRITICAL,
                PowerManager.THERMAL_STATUS_EMERGENCY,
                PowerManager.THERMAL_STATUS_SHUTDOWN -> {
                    if (!isCurrentlyThrottled) {
                        Log.w(TAG, "Thermal Warning Ceiling Breached (Status: $status). Downscaling resolution natively.")
                        isCurrentlyThrottled = true
                        setThermalScale(0.5f) // Downscale internal 3D rendering
                    }
                }
                PowerManager.THERMAL_STATUS_NONE,
                PowerManager.THERMAL_STATUS_LIGHT -> {
                    if (isCurrentlyThrottled) {
                        Log.i(TAG, "Thermal Recovery Floor Reached (Status: $status). Restoring resolution natively.")
                        isCurrentlyThrottled = false
                        setThermalScale(1.0f) // Restore internal 3D rendering
                    }
                }
                else -> {
                    // MODERATE status: maintain current state (hysteresis)
                }
            }
        }
    }

    // JNI Bridge to C++ OpenGL renderer
    private external fun setThermalScale(scale: Float)
}
