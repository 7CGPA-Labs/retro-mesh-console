package dev.seven_cgpalabs.mojosnap

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import dev.seven_cgpalabs.mojosnap.ui.GamepadDeckScreen
import dev.seven_cgpalabs.mojosnap.ui.MojoSnapTheme
import dev.seven_cgpalabs.mojosnap.ui.RoleGateScreen

class MainActivity : ComponentActivity() {
    private lateinit var thermalManager: ThermalManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        thermalManager = ThermalManager(this)
        thermalManager.startMonitoring()

        setContent {
            MojoSnapTheme {
                var currentScreen by remember { mutableStateOf("RoleGate") }

                when (currentScreen) {
                    "RoleGate" -> RoleGateScreen(
                        onHostSelected = { currentScreen = "GamepadDeck" },
                        onJoinSelected = { currentScreen = "GamepadDeck" }
                    )
                    "GamepadDeck" -> GamepadDeckScreen()
                }
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
