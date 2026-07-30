package dev.seven_cgpalabs.mojosnap.ui

import android.app.Activity
import android.content.pm.ActivityInfo
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import dev.seven_cgpalabs.mojosnap.MainActivity
import dev.seven_cgpalabs.mojosnap.utils.ConsoleLogger
import androidx.compose.foundation.lazy.items
import kotlinx.coroutines.launch
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import android.view.WindowManager
import android.widget.Toast
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.style.TextAlign

@Composable
fun GamepadDeckScreen(isHost: Boolean, romUri: Uri?, coreName: String, playerName: String, onExit: () -> Unit) {
    val context = LocalContext.current
    val mainActivity = context as? MainActivity
    var useAnalogStick by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var analogPos by remember { mutableStateOf(Offset.Zero) }
    
    var discoveredHosts by remember { mutableStateOf(emptyList<Map<String, Any>>()) }
    var isConnected by remember { mutableStateOf(isHost) }
    var activeCore by remember { mutableStateOf(coreName) }
    val hostPin = remember { (100000..999999).random().toString() }
    
    var showPinEntryForHost by remember { mutableStateOf<Map<String, Any>?>(null) }
    var enteredPin by remember { mutableStateOf("") }
    var hasVibratedAtEdge by remember { mutableStateOf(false) }
    
    DisposableEffect(Unit) {
        val activity = context as? Activity
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        
        val castingAdapter = activity?.let { dev.seven_cgpalabs.mojosnap.CastingAdapter(it) }
        castingAdapter?.startMonitoring()
        
        onDispose {
            castingAdapter?.stopMonitoring()
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            mainActivity?.shutdown()
            if (isHost) {
                // stop host? (no method for this yet, but we could close sockets)
            } else {
                dev.seven_cgpalabs.mojosnap.NetworkManager.stopDiscovery()
            }
        }
    }

    LaunchedEffect(isHost) {
        if (isHost) {
            dev.seven_cgpalabs.mojosnap.NetworkManager.startHost(context, activeCore, playerName, hostPin)
        } else {
            dev.seven_cgpalabs.mojosnap.NetworkManager.onHostsDiscovered = { hosts ->
                discoveredHosts = hosts
            }
            dev.seven_cgpalabs.mojosnap.NetworkManager.startDiscovery(context)
        }
    }

    LaunchedEffect(romUri) {
        if (romUri != null) {
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                try {
                    val inputStream = context.contentResolver.openInputStream(romUri)
                    val tempFile = java.io.File(context.cacheDir, "temp_rom")
                    inputStream?.use { input ->
                        tempFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    val nativeLibDir = java.io.File(context.applicationInfo.nativeLibraryDir)
                    val regex = Regex(".*${activeCore}.*\\.so", RegexOption.IGNORE_CASE)
                    val coreFile = nativeLibDir.listFiles()?.firstOrNull { regex.matches(it.name) }
                    
                    if (coreFile != null && coreFile.exists()) {
                        ConsoleLogger.log("Core", "Loading core: ${coreFile.absolutePath}")
                        val success = mainActivity?.loadGame(coreFile.absolutePath, tempFile.absolutePath)
                        ConsoleLogger.log("Core", "Load game result: $success")
                    } else {
                        ConsoleLogger.log("Core", "Core library not found for: $activeCore")
                    }
                } catch (e: Exception) {
                    ConsoleLogger.log("Core", "Failed to load ROM: ${e.message}")
                }
            }
        }
    }

    if (!isConnected) {
        AlertDialog(
            onDismissRequest = { onExit() },
            containerColor = Color.Black,
            title = { Text("Select Host to Join", color = Color.White) },
            text = {
                if (discoveredHosts.isEmpty()) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        CircularProgressIndicator(color = Color(0xFF00E5FF))
                        Spacer(Modifier.height(16.dp))
                        Text("Scanning for hosts...", color = Color.White.copy(alpha = 0.7f))
                    }
                } else {
                    androidx.compose.foundation.lazy.LazyColumn {
                        items(discoveredHosts) { host ->
                            val hostName = host["name"] as? String ?: "Unknown"
                            TextButton(
                                onClick = {
                                    showPinEntryForHost = host
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(hostName, color = Color(0xFF00E5FF), fontSize = 18.sp)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { onExit() }) {
                    Text("CANCEL", color = Color(0xFFEF4444))
                }
            }
        )
    }

    if (showPinEntryForHost != null) {
        AlertDialog(
            onDismissRequest = { 
                showPinEntryForHost = null
                enteredPin = ""
            },
            containerColor = Color.Black,
            title = { 
                Text(
                    text = "Enter 6-Digit PIN", 
                    color = Color.White,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center,
                    fontWeight = FontWeight.Bold
                ) 
            },
            text = {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp)
                ) {
                    PinInput(
                        pin = enteredPin,
                        onPinChange = { enteredPin = it }
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val hostPinRequired = showPinEntryForHost!!["pin"] as? String ?: ""
                        if (enteredPin == hostPinRequired) {
                            val ip = showPinEntryForHost!!["ip"] as? String ?: ""
                            dev.seven_cgpalabs.mojosnap.NetworkManager.connectToServer(ip, 48293)
                            dev.seven_cgpalabs.mojosnap.NetworkManager.stopDiscovery()
                            activeCore = showPinEntryForHost!!["core"] as? String ?: "nes"
                            isConnected = true
                            showPinEntryForHost = null
                            enteredPin = ""
                        } else {
                            Toast.makeText(context, "Incorrect PIN", Toast.LENGTH_SHORT).show()
                            enteredPin = ""
                        }
                    },
                    enabled = enteredPin.length == 6
                ) {
                    Text("CONNECT", color = if (enteredPin.length == 6) Color(0xFF00E5FF) else Color.Gray)
                }
            },
            dismissButton = {
                TextButton(onClick = { 
                    showPinEntryForHost = null
                    enteredPin = ""
                }) {
                    Text("CANCEL", color = Color.White.copy(alpha = 0.54f))
                }
            }
        )
    }


    if (showMenu) {
        AlertDialog(
            onDismissRequest = { showMenu = false },
            containerColor = Color.Black,
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Menu, contentDescription = null, tint = if (isHost) Color(0xFFFF2E93) else Color(0xFF00E5FF))
                    Spacer(Modifier.width(10.dp))
                    Text(if (isHost) "CONSOLE MENU" else "CLIENT MENU", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
            },
            text = {
                LazyColumn {
                    item {
                        TextButton(onClick = { showMenu = false; mainActivity?.togglePause() }) {
                            Text("Resume Game", color = Color.White)
                        }
                    }
                    if (isHost) {
                        item {
                            TextButton(onClick = { showMenu = false; mainActivity?.resetGame() }) {
                                Text("Reset Game", color = Color.White)
                            }
                        }
                        item {
                            TextButton(onClick = { showMenu = false; mainActivity?.saveState(1, context.filesDir.absolutePath) }) {
                                Text("Quick Save (Slot 1)", color = Color.White)
                            }
                        }
                        item {
                            TextButton(onClick = { showMenu = false; mainActivity?.loadState(1, context.filesDir.absolutePath) }) {
                                Text("Quick Load (Slot 1)", color = Color.White)
                            }
                        }
                    }
                    item {
                        TextButton(onClick = { showMenu = false; onExit() }) {
                            Text(if (isHost) "Stop Emulation & Exit" else "Disconnect", color = Color(0xFFEF4444), fontWeight = FontWeight.Bold)
                        }
                    }
                }
            },
            confirmButton = {}
        )
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .safeDrawingPadding()
            .padding(horizontal = 24.dp, vertical = 8.dp)
    ) {
        val baseSize = (maxHeight.value * 0.22f).coerceIn(40f, 100f).dp
        val maxRadiusPx = with(LocalDensity.current) { (baseSize * 1.5f).toPx() - (baseSize * 0.3f).toPx() }
        Text(
            text = "Player: $playerName" + if (isHost) " | PIN: $hostPin" else "",
            color = Color.White.copy(alpha = 0.5f),
            fontSize = 12.sp,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 16.dp)
        )

        val isSnes = activeCore.contains("snes") || activeCore.contains("mgba")
        val isPs1 = activeCore.contains("pcsx")
        val isGenesis = activeCore.contains("genesis")


        // Analog toggle and Log UI
        Column(
            modifier = Modifier.align(Alignment.Center).offset(y = (-35).dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .clickable { useAnalogStick = !useAnalogStick }
                    .background(if (useAnalogStick) Color(0xFFFF2E93).copy(0.2f) else Color.White.copy(0.12f), RoundedCornerShape(16.dp))
                    .border(1.2.dp, if (useAnalogStick) Color(0xFFFF2E93) else Color.White.copy(0.24f), RoundedCornerShape(16.dp))
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                Text(
                    text = if (useAnalogStick) "ANALOG ON" else "D-PAD ON", 
                    color = if (useAnalogStick) Color(0xFFFF2E93) else Color.White.copy(0.54f), 
                    fontWeight = FontWeight.Bold,
                    fontSize = 11.sp
                )
            }
            if (dev.seven_cgpalabs.mojosnap.BuildConfig.DEBUG) {
                Spacer(Modifier.height(10.dp))
                Box(
                    modifier = Modifier
                        .size(160.dp, 120.dp)
                        .background(Color(0xFF87A96B), RoundedCornerShape(4.dp))
                        .border(2.dp, Color(0xFF1E2614), RoundedCornerShape(4.dp))
                        .padding(4.dp)
                ) {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(ConsoleLogger.logs) { log ->
                            Text(log, color = Color(0xFF1E2614), fontSize = 8.sp, fontWeight = FontWeight.Bold, lineHeight = 10.sp)
                        }
                    }
                }
            }
        }

        Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            // LEFT SIDE: L1/L2 shoulder column + D-pad or Analog stick
            Row(
                modifier = Modifier.weight(1f).padding(start = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Start
            ) {
                if (isSnes || isPs1) {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(end = 8.dp)
                    ) {
                        ShoulderBtn("L" + if (isPs1) "1" else "", 10, mainActivity, Modifier) // RETRO_DEVICE_ID_JOYPAD_L
                        if (isPs1) ShoulderBtn("L2", 12, mainActivity, Modifier) // RETRO_DEVICE_ID_JOYPAD_L2
                    }
                }
                Box(modifier = Modifier.padding(start = 16.dp), contentAlignment = Alignment.CenterStart) {
                    if (useAnalogStick) {
                        Box(modifier = Modifier.size(baseSize * 3).background(Color(0xFF1E1E38).copy(0.5f), CircleShape).border(2.dp, Color.White.copy(0.24f), CircleShape)
                            .pointerInput(Unit) {
                                detectDragGestures(
                                    onDragEnd = { 
                                        analogPos = Offset.Zero
                                        hasVibratedAtEdge = false
                                        mainActivity?.setAnalogState(0, 0, 0, 0)
                                        mainActivity?.setAnalogState(0, 0, 1, 0)
                                    },
                                    onDrag = { _, dragAmount -> 
                                        val newPos = analogPos + dragAmount
                                        val dist = newPos.getDistance()
                                        
                                        if (dist >= maxRadiusPx) {
                                            if (!hasVibratedAtEdge) {
                                                triggerStrongVibration(context)
                                                hasVibratedAtEdge = true
                                            }
                                        } else if (dist < maxRadiusPx * 0.9f) {
                                            hasVibratedAtEdge = false
                                        }
                                        
                                        analogPos = if (dist > maxRadiusPx) newPos * (maxRadiusPx / dist) else newPos
                                        val scaledX = if (maxRadiusPx > 0) (analogPos.x / maxRadiusPx * 32767f).toInt().coerceIn(-32767, 32767) else 0
                                        val scaledY = if (maxRadiusPx > 0) (analogPos.y / maxRadiusPx * 32767f).toInt().coerceIn(-32767, 32767) else 0
                                        mainActivity?.setAnalogState(0, 0, 0, scaledX)
                                        mainActivity?.setAnalogState(0, 0, 1, scaledY)
                                    }
                                )
                            }, contentAlignment = Alignment.Center) {
                            Box(modifier = Modifier.offset(x = with(LocalDensity.current) { analogPos.x.toDp() }, y = with(LocalDensity.current) { analogPos.y.toDp() }).size(baseSize * 0.8f).background(Color(0xFF14142B), CircleShape).border(3.dp, Color(0xFFFF2E93), CircleShape))
                        }
                    } else {
                        Box(modifier = Modifier.size(baseSize * 3)) {
                            GamepadBtn("▲", 4, baseSize, Modifier.align(Alignment.TopCenter), Color.White, mainActivity) // RETRO_DEVICE_ID_JOYPAD_UP
                            GamepadBtn("▼", 5, baseSize, Modifier.align(Alignment.BottomCenter), Color.White, mainActivity) // RETRO_DEVICE_ID_JOYPAD_DOWN
                            GamepadBtn("◀", 6, baseSize, Modifier.align(Alignment.CenterStart), Color.White, mainActivity) // RETRO_DEVICE_ID_JOYPAD_LEFT
                            GamepadBtn("▶", 7, baseSize, Modifier.align(Alignment.CenterEnd), Color.White, mainActivity) // RETRO_DEVICE_ID_JOYPAD_RIGHT
                        }
                    }
                }
            }

            // RIGHT SIDE: Action buttons + R1/R2 shoulder column
            Row(
                modifier = Modifier.weight(1f).padding(end = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.End
            ) {
                Box(modifier = Modifier.padding(end = 16.dp), contentAlignment = Alignment.CenterEnd) {
                    Box(modifier = Modifier.size(baseSize * 3)) {
                        when {
                            isGenesis -> {
                                Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.offset(x = (-12).dp)) {
                                        GamepadBtn("X", 10, baseSize * 0.85f, Modifier, Color(0xFFEF5350), mainActivity) // Genesis X → Lighter Red
                                        GamepadBtn("Y", 9, baseSize * 0.85f, Modifier, Color(0xFFFFCA28), mainActivity) // Genesis Y → Lighter Yellow
                                        GamepadBtn("Z", 11, baseSize * 0.85f, Modifier, Color(0xFF42A5F5), mainActivity) // Genesis Z → Lighter Blue
                                    }
                                    Spacer(modifier = Modifier.height(12.dp))
                                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.offset(x = 12.dp)) {
                                        GamepadBtn("A", 1, baseSize * 0.85f, Modifier, Color(0xFFE53935), mainActivity) // Genesis A → Red
                                        GamepadBtn("B", 0, baseSize * 0.85f, Modifier, Color(0xFFFFB300), mainActivity) // Genesis B → Yellow/Orange
                                        GamepadBtn("C", 8, baseSize * 0.85f, Modifier, Color(0xFF1E88E5), mainActivity) // Genesis C → Blue
                                    }
                                }
                            }
                            isPs1 -> {
                                GamepadBtn("△", 9, baseSize, Modifier.align(Alignment.TopCenter), Color(0xFF4CAF50), mainActivity) // Triangle - Green
                                GamepadBtn("✕", 0, baseSize, Modifier.align(Alignment.BottomCenter), Color(0xFF2196F3), mainActivity) // Cross - Blue
                                GamepadBtn("□", 1, baseSize, Modifier.align(Alignment.CenterStart), Color(0xFFE91E63), mainActivity) // Square - Pink
                                GamepadBtn("○", 8, baseSize, Modifier.align(Alignment.CenterEnd), Color(0xFFF44336), mainActivity) // Circle - Red
                            }
                            isSnes -> {
                                GamepadBtn("X", 9, baseSize, Modifier.align(Alignment.TopCenter), Color(0xFF1E88E5), mainActivity) // SNES X - Blue
                                GamepadBtn("B", 0, baseSize, Modifier.align(Alignment.BottomCenter), Color(0xFFFFEB3B), mainActivity) // SNES B - Yellow
                                GamepadBtn("Y", 1, baseSize, Modifier.align(Alignment.CenterStart), Color(0xFF4CAF50), mainActivity) // SNES Y - Green
                                GamepadBtn("A", 8, baseSize, Modifier.align(Alignment.CenterEnd), Color(0xFFE53935), mainActivity) // SNES A - Red
                            }
                            else -> {
                                Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                                    GamepadBtn("B", 0, baseSize * 1.2f, Modifier.offset(y = 12.dp), Color(0xFFE53935), mainActivity) // NES B → Classic Red
                                    Spacer(modifier = Modifier.width(24.dp))
                                    GamepadBtn("A", 8, baseSize * 1.2f, Modifier.offset(y = (-12).dp), Color(0xFFE53935), mainActivity) // NES A → Classic Red
                                }
                            }
                        }
                    }
                }
                if (isSnes || isPs1) {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(start = 8.dp)
                    ) {
                        ShoulderBtn("R" + if (isPs1) "1" else "", 11, mainActivity, Modifier) // RETRO_DEVICE_ID_JOYPAD_R
                        if (isPs1) ShoulderBtn("R2", 13, mainActivity, Modifier) // RETRO_DEVICE_ID_JOYPAD_R2
                    }
                }
            }
        }

        // CAST to top-left
        if (isHost) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 16.dp)
            ) {
                SystemBtn("CAST", Icons.Default.Cast, Color(0xFF00E5FF)) { 
                    dev.seven_cgpalabs.mojosnap.CastingAdapter(context as Activity).openSystemCastMenu() 
                }
            }
        }

        // MENU to top-right
        if (isHost) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(end = 16.dp, top = 16.dp)
            ) {
                SystemBtn("MENU", Icons.Default.Menu, Color(0xFFFF2E93)) { showMenu = true; mainActivity?.togglePause() }
            }
        }

        Row(
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(24.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            SystemBtn("SELECT", Icons.Default.SelectAll, Color.White.copy(0.7f), mainActivity, 2) // RETRO_DEVICE_ID_JOYPAD_SELECT
            SystemBtn("START", Icons.Default.PlayArrow, Color.White, mainActivity, 3) // RETRO_DEVICE_ID_JOYPAD_START
        }
    }
}

@Composable
fun ShoulderBtn(label: String, buttonId: Int, mainActivity: MainActivity?, modifier: Modifier) {
    val context = LocalContext.current
    Box(modifier = modifier.size(48.dp, 80.dp).background(Color.Black, RoundedCornerShape(16.dp)).border(2.dp, Color.White.copy(0.24f), RoundedCornerShape(16.dp)).pointerInput(Unit) { detectTapGestures(onPress = { triggerStrongVibration(context); mainActivity?.setButtonState(0, buttonId, true); tryAwaitRelease(); mainActivity?.setButtonState(0, buttonId, false) }) }, contentAlignment = Alignment.Center) {
        Text(label, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun GamepadBtn(label: String, buttonId: Int, size: androidx.compose.ui.unit.Dp, modifier: Modifier, color: Color, mainActivity: MainActivity?) {
    val context = LocalContext.current
    Box(modifier = modifier.size(size).background(color.copy(0.12f), CircleShape).border(2.5.dp, color, CircleShape).pointerInput(Unit) { detectTapGestures(onPress = { triggerStrongVibration(context); mainActivity?.setButtonState(0, buttonId, true); tryAwaitRelease(); mainActivity?.setButtonState(0, buttonId, false) }) }, contentAlignment = Alignment.Center) {
        Text(label, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun SystemBtn(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, mainActivity: MainActivity? = null, buttonId: Int = -1, onClick: (() -> Unit)? = null) {
    val context = LocalContext.current
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.pointerInput(Unit) {
        detectTapGestures(onPress = {
            triggerStrongVibration(context)
            if (buttonId != -1) mainActivity?.setButtonState(0, buttonId, true)
            onClick?.invoke()
            tryAwaitRelease()
            if (buttonId != -1) mainActivity?.setButtonState(0, buttonId, false)
        })
    }) {
        Box(modifier = Modifier.size(64.dp, 32.dp).background(color.copy(0.1f), RoundedCornerShape(16.dp)).border(1.dp, color.copy(0.3f), RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(label, color = color, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Suppress("DEPRECATION")
fun triggerStrongVibration(context: android.content.Context) {
    try {
        val vibrator = context.getSystemService(android.content.Context.VIBRATOR_SERVICE) as android.os.Vibrator
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            vibrator.vibrate(android.os.VibrationEffect.createOneShot(70, android.os.VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            vibrator.vibrate(70)
        }
    } catch (e: Exception) {}
}

@Composable
fun PinInput(
    pin: String,
    onPinChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val maxLength = 6
    val focusRequester = remember { FocusRequester() }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                indication = null
            ) { focusRequester.requestFocus() },
        contentAlignment = Alignment.Center
    ) {
        androidx.compose.foundation.text.BasicTextField(
            value = pin,
            onValueChange = { newVal ->
                if (newVal.length <= maxLength && newVal.all { it.isDigit() }) {
                    onPinChange(newVal)
                }
            },
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                keyboardType = androidx.compose.ui.text.input.KeyboardType.Number
            ),
            modifier = Modifier
                .size(1.dp)
                .focusRequester(focusRequester)
                .graphicsLayer { alpha = 0f }
        )

        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            for (i in 0 until maxLength) {
                val isFocused = i == pin.length
                val char = pin.getOrNull(i)
                val text = if (char != null) char.toString() else ""

                val borderColor = when {
                    isFocused -> Color(0xFF00E5FF)
                    text.isNotEmpty() -> Color(0xFFFF2E93).copy(alpha = 0.8f)
                    else -> Color.White.copy(alpha = 0.15f)
                }

                val glowModifier = if (isFocused) {
                    Modifier.shadow(8.dp, RoundedCornerShape(8.dp), spotColor = Color(0xFF00E5FF))
                } else {
                    Modifier
                }

                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .then(glowModifier)
                        .background(Color(0xFF13132B), RoundedCornerShape(8.dp))
                        .border(
                            width = if (isFocused) 2.dp else 1.5.dp,
                            color = borderColor,
                            shape = RoundedCornerShape(8.dp)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = text,
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        delay(300)
        focusRequester.requestFocus()
    }
}
