package dev.seven_cgpalabs.mojosnap

import android.os.Bundle
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import dev.seven_cgpalabs.mojosnap.ui.GamepadDeckScreen
import dev.seven_cgpalabs.mojosnap.ui.MojoSnapTheme
import dev.seven_cgpalabs.mojosnap.ui.RoleGateScreen

class MainActivity : ComponentActivity() {
    private lateinit var thermalManager: ThermalManager

    external fun setButtonState(port: Int, buttonId: Int, pressed: Boolean)
    external fun setAnalogState(port: Int, index: Int, id: Int, value: Int)
    external fun togglePause()
    external fun resetGame()
    external fun shutdown()
    external fun saveState(slot: Int, saveDir: String): Boolean
    external fun loadState(slot: Int, saveDir: String): Boolean
    external fun loadGame(coreDir: String, romPath: String): Boolean

    companion object {
        init {
            System.loadLibrary("native_render")
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isDown = event.action == KeyEvent.ACTION_DOWN
        val buttonId = when (event.keyCode) {
            KeyEvent.KEYCODE_BUTTON_A -> 0 // RetroPad B (Bottom)
            KeyEvent.KEYCODE_BUTTON_B -> 8 // RetroPad A (Right)
            KeyEvent.KEYCODE_BUTTON_X -> 1 // RetroPad Y (Left)
            KeyEvent.KEYCODE_BUTTON_Y -> 9 // RetroPad X (Top)
            KeyEvent.KEYCODE_BUTTON_L1 -> 10 // RetroPad L
            KeyEvent.KEYCODE_BUTTON_R1 -> 11 // RetroPad R
            KeyEvent.KEYCODE_BUTTON_L2 -> 12 // RetroPad L2
            KeyEvent.KEYCODE_BUTTON_R2 -> 13 // RetroPad R2
            KeyEvent.KEYCODE_BUTTON_THUMBL -> 14 // RetroPad L3
            KeyEvent.KEYCODE_BUTTON_THUMBR -> 15 // RetroPad R3
            KeyEvent.KEYCODE_BUTTON_START -> 3 // RetroPad START
            KeyEvent.KEYCODE_BUTTON_SELECT -> 2 // RetroPad SELECT
            KeyEvent.KEYCODE_DPAD_UP -> 4 // RetroPad UP
            KeyEvent.KEYCODE_DPAD_DOWN -> 5 // RetroPad DOWN
            KeyEvent.KEYCODE_DPAD_LEFT -> 6 // RetroPad LEFT
            KeyEvent.KEYCODE_DPAD_RIGHT -> 7 // RetroPad RIGHT
            else -> -1
        }
        if (buttonId != -1) {
            setButtonState(0, buttonId, isDown)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_CLASS_JOYSTICK)) {
            val x = event.getAxisValue(MotionEvent.AXIS_X)
            val y = event.getAxisValue(MotionEvent.AXIS_Y)
            val hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X)
            val hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
            
            // Analog stick
            val scaledX = (x * 32767f).toInt().coerceIn(-32767, 32767)
            val scaledY = (y * 32767f).toInt().coerceIn(-32767, 32767)
            setAnalogState(0, 0, 0, scaledX)
            setAnalogState(0, 0, 1, scaledY)
            
            // D-Pad from Hat Axis
            setButtonState(0, 6, hatX < -0.5f) // LEFT
            setButtonState(0, 7, hatX > 0.5f)  // RIGHT
            setButtonState(0, 4, hatY < -0.5f) // UP
            setButtonState(0, 5, hatY > 0.5f)  // DOWN

            // Triggers as L2 / R2 buttons if analog
            val lTrigger = event.getAxisValue(MotionEvent.AXIS_LTRIGGER).coerceAtLeast(event.getAxisValue(MotionEvent.AXIS_BRAKE))
            val rTrigger = event.getAxisValue(MotionEvent.AXIS_RTRIGGER).coerceAtLeast(event.getAxisValue(MotionEvent.AXIS_GAS))
            if (lTrigger > 0.5f) setButtonState(0, 12, true)
            if (rTrigger > 0.5f) setButtonState(0, 13, true)
            
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        androidx.core.view.WindowInsetsControllerCompat(window, window.decorView).let { controller ->
            controller.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        thermalManager = ThermalManager(this)
        thermalManager.startMonitoring()

        setContent {
            MojoSnapTheme {
                var currentScreen by remember { mutableStateOf("RoleGate") }
                var isHostState by remember { mutableStateOf(false) }
                var romUriState by remember { mutableStateOf<android.net.Uri?>(null) }
                var coreNameState by remember { mutableStateOf("") }
                var playerNameState by remember { mutableStateOf("") }

                when (currentScreen) {
                    "RoleGate" -> RoleGateScreen(
                        onNavigateToGamepad = { isHost, romUri, coreName, playerName ->
                            isHostState = isHost
                            romUriState = romUri
                            coreNameState = coreName
                            playerNameState = playerName
                            currentScreen = "GamepadDeck"
                        }
                    )
                    "GamepadDeck" -> GamepadDeckScreen(
                        isHost = isHostState,
                        romUri = romUriState,
                        coreName = coreNameState,
                        playerName = playerNameState,
                        onExit = { currentScreen = "RoleGate" }
                    )
                }
            }
        }
    }
}

object NativeRender {
    init {
        System.loadLibrary("native_render")
    }
    external fun setTvSurface(surface: android.view.Surface?)
}
