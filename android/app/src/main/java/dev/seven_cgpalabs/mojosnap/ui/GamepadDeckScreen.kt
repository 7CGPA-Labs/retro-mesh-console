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

@Composable
fun GamepadDeckScreen(isHost: Boolean, romUri: Uri?, coreName: String, playerName: String, onExit: () -> Unit) {
    val context = LocalContext.current
    val mainActivity = context as? MainActivity
    var useAnalogStick by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var analogPos by remember { mutableStateOf(Offset.Zero) }
    
    DisposableEffect(Unit) {
        val activity = context as? Activity
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
        
        onDispose {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            if (isHost) {
                // stop host? (no method for this yet, but we could close sockets)
            } else {
                dev.seven_cgpalabs.mojosnap.NetworkManager.stopDiscovery()
            }
        }
    }

    LaunchedEffect(isHost) {
        if (isHost) {
            dev.seven_cgpalabs.mojosnap.NetworkManager.startHost(context, coreName, playerName)
        } else {
            dev.seven_cgpalabs.mojosnap.NetworkManager.onHostsDiscovered = { hosts ->
                val targetHost = hosts.find { (it["name"] as? String)?.contains(playerName) == true }
                if (targetHost != null) {
                    val ip = targetHost["ip"] as? String
                    if (ip != null) {
                        ConsoleLogger.log("Network", "Found host '$playerName' at $ip. Connecting...")
                        dev.seven_cgpalabs.mojosnap.NetworkManager.connectToServer(ip, 48293)
                        dev.seven_cgpalabs.mojosnap.NetworkManager.stopDiscovery()
                    }
                }
            }
            dev.seven_cgpalabs.mojosnap.NetworkManager.startDiscovery(context, playerName)
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
                    val coreFile = java.io.File(context.applicationInfo.nativeLibraryDir, "lib${coreName}_libretro_android.so")
                    if (coreFile.exists()) {
                        ConsoleLogger.log("Core", "Loading core: ${coreFile.absolutePath}")
                        val success = mainActivity?.loadGame(coreFile.absolutePath, tempFile.absolutePath)
                        ConsoleLogger.log("Core", "Load game result: $success")
                    } else {
                        ConsoleLogger.log("Core", "Core library not found: lib${coreName}_libretro_android.so")
                    }
                } catch (e: Exception) {
                    ConsoleLogger.log("Core", "Failed to load ROM: ${e.message}")
                }
            }
        }
    }

    if (showMenu) {
        AlertDialog(
            onDismissRequest = { showMenu = false },
            containerColor = Color(0xFF1E1E38),
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
                        TextButton(onClick = { showMenu = false; mainActivity?.shutdown(); onExit() }) {
                            Text(if (isHost) "Stop Emulation & Exit" else "Disconnect", color = Color(0xFFEF4444), fontWeight = FontWeight.Bold)
                        }
                    }
                }
            },
            confirmButton = {}
        )
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        val baseSize = (maxHeight.value * 0.22f).coerceIn(40f, 100f).dp
        val maxRadiusPx = with(LocalDensity.current) { (baseSize * 1.5f).toPx() - (baseSize * 0.3f).toPx() }
        val mHeight = maxHeight
        val isSnes = coreName.contains("snes") || coreName.contains("mgba")
        val isPs1 = coreName.contains("pcsx")
        val isGenesis = coreName.contains("genesis")
        
        Text(
            text = "Player: $playerName",
            color = Color.White.copy(alpha = 0.5f),
            fontSize = 12.sp,
            modifier = Modifier.align(Alignment.TopStart).padding(8.dp)
        )

        // Shoulders
        if (isSnes || isPs1) {
            ShoulderBtn("L" + if (isPs1) "1" else "", 8, mainActivity, Modifier.padding(start = if (isPs1) 172.dp else 36.dp, top = mHeight * 0.05f))
            ShoulderBtn("R" + if (isPs1) "1" else "", 9, mainActivity, Modifier.padding(end = if (isPs1) 172.dp else 36.dp, top = mHeight * 0.05f).align(Alignment.TopEnd))
        }
        if (isPs1) {
            ShoulderBtn("L2", 10, mainActivity, Modifier.padding(start = 36.dp, top = mHeight * 0.05f))
            ShoulderBtn("R2", 11, mainActivity, Modifier.padding(end = 36.dp, top = mHeight * 0.05f).align(Alignment.TopEnd))
        }

        // Analog toggle and Log UI
        Column(
            modifier = Modifier.align(Alignment.TopCenter).padding(top = mHeight * 0.15f),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .clickable { useAnalogStick = !useAnalogStick }
                    .background(if (useAnalogStick) Color(0xFFFF2E93).copy(0.2f) else Color.White.copy(0.12f), RoundedCornerShape(20.dp))
                    .border(2.dp, if (useAnalogStick) Color(0xFFFF2E93) else Color.White.copy(0.24f), RoundedCornerShape(20.dp))
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                Text(if (useAnalogStick) "ANALOG ON" else "D-PAD ON", color = if (useAnalogStick) Color(0xFFFF2E93) else Color.White.copy(0.54f), fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(10.dp))
            Box(
                modifier = Modifier
                    .size(120.dp, 40.dp)
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

        Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Box(modifier = Modifier.weight(1f).padding(start = 36.dp, top = if (isSnes || isPs1) mHeight * 0.15f else 0.dp), contentAlignment = Alignment.CenterStart) {
                if (useAnalogStick) {
                    Box(modifier = Modifier.size(baseSize * 3).background(Color(0xFF1E1E38).copy(0.5f), CircleShape).border(2.dp, Color.White.copy(0.24f), CircleShape)
                        .pointerInput(Unit) {
                            detectDragGestures(
                                onDragEnd = { 
                                    analogPos = Offset.Zero
                                    mainActivity?.setAnalogState(0, 0, 0, 0)
                                    mainActivity?.setAnalogState(0, 0, 1, 0)
                                },
                                onDrag = { _, dragAmount -> 
                                    val newPos = analogPos + dragAmount
                                    val dist = newPos.getDistance()
                                    analogPos = if (dist > maxRadiusPx) newPos * (maxRadiusPx / dist) else newPos
                                    val scaledX = if (maxRadiusPx > 0) (analogPos.x / maxRadiusPx * 32767f).toInt().coerceIn(-32767, 32767) else 0
                                    val scaledY = if (maxRadiusPx > 0) (analogPos.y / maxRadiusPx * 32767f).toInt().coerceIn(-32767, 32767) else 0
                                    mainActivity?.setAnalogState(0, 0, 0, scaledX)
                                    mainActivity?.setAnalogState(0, 0, 1, scaledY)
                                }
                            )
                        }, contentAlignment = Alignment.Center) {
                        Box(modifier = Modifier.offset(x = with(LocalDensity.current) { analogPos.x.toDp() }, y = with(LocalDensity.current) { analogPos.y.toDp() }).size(baseSize * 0.6f).background(Color(0xFF14142B), CircleShape).border(3.dp, Color(0xFFFF2E93), CircleShape))
                    }
                } else {
                    Box(modifier = Modifier.size(baseSize * 3)) {
                        GamepadBtn("▲", 0, baseSize, Modifier.align(Alignment.TopCenter), Color.White, mainActivity)
                        GamepadBtn("▼", 1, baseSize, Modifier.align(Alignment.BottomCenter), Color.White, mainActivity)
                        GamepadBtn("◀", 2, baseSize, Modifier.align(Alignment.CenterStart), Color.White, mainActivity)
                        GamepadBtn("▶", 3, baseSize, Modifier.align(Alignment.CenterEnd), Color.White, mainActivity)
                    }
                }
            }

            Box(modifier = Modifier.weight(1f).padding(end = 36.dp, top = if (isSnes || isPs1) mHeight * 0.15f else 0.dp), contentAlignment = Alignment.CenterEnd) {
                Box(modifier = Modifier.size(baseSize * 3)) {
                    when {
                        isGenesis -> {
                            Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.offset(x = (-12).dp)) {
                                    GamepadBtn("X", 6, baseSize * 0.85f, Modifier, Color.LightGray, mainActivity)
                                    GamepadBtn("Y", 7, baseSize * 0.85f, Modifier, Color.LightGray, mainActivity)
                                    GamepadBtn("Z", 8, baseSize * 0.85f, Modifier, Color.LightGray, mainActivity)
                                }
                                Spacer(modifier = Modifier.height(12.dp))
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.offset(x = 12.dp)) {
                                    GamepadBtn("A", 4, baseSize * 0.85f, Modifier, Color(0xFFE57373), mainActivity)
                                    GamepadBtn("B", 5, baseSize * 0.85f, Modifier, Color(0xFF81C784), mainActivity)
                                    GamepadBtn("C", 9, baseSize * 0.85f, Modifier, Color(0xFF4FC3F7), mainActivity)
                                }
                            }
                        }
                        isPs1 || isSnes -> {
                            GamepadBtn(if(isPs1) "△" else "X", 6, baseSize, Modifier.align(Alignment.TopCenter), Color.LightGray, mainActivity)
                            GamepadBtn(if(isPs1) "X" else "B", 5, baseSize, Modifier.align(Alignment.BottomCenter), Color.LightGray, mainActivity)
                            GamepadBtn(if(isPs1) "□" else "Y", 7, baseSize, Modifier.align(Alignment.CenterStart), Color.LightGray, mainActivity)
                            GamepadBtn(if(isPs1) "O" else "A", 4, baseSize, Modifier.align(Alignment.CenterEnd), Color.LightGray, mainActivity)
                        }
                        else -> {
                            Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                                GamepadBtn("B", 5, baseSize * 1.2f, Modifier.offset(y = 12.dp), Color(0xFFE57373), mainActivity)
                                Spacer(modifier = Modifier.width(24.dp))
                                GamepadBtn("A", 4, baseSize * 1.2f, Modifier.offset(y = (-12).dp), Color(0xFFE57373), mainActivity)
                            }
                        }
                    }
                }
            }
        }

        Column(modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                SystemBtn("SELECT", Icons.Default.SelectAll, Color.White.copy(0.7f), mainActivity, 13)
                SystemBtn("START", Icons.Default.PlayArrow, Color.White, mainActivity, 12)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                SystemBtn("CAST", Icons.Default.Cast, Color(0xFF00E5FF)) { 
                    dev.seven_cgpalabs.mojosnap.CastingAdapter(context as Activity).openSystemCastMenu() 
                }
                SystemBtn("MENU", Icons.Default.Menu, Color(0xFFFF2E93)) { showMenu = true; mainActivity?.togglePause() }
            }
        }
    }
}

@Composable
fun ShoulderBtn(label: String, buttonId: Int, mainActivity: MainActivity?, modifier: Modifier) {
    Box(modifier = modifier.size(120.dp, 48.dp).background(Color(0xFF1E1E38), RoundedCornerShape(16.dp)).border(2.dp, Color.White.copy(0.24f), RoundedCornerShape(16.dp)).pointerInput(Unit) { detectTapGestures(onPress = { mainActivity?.setButtonState(0, buttonId, true); tryAwaitRelease(); mainActivity?.setButtonState(0, buttonId, false) }) }, contentAlignment = Alignment.Center) {
        Text(label, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun GamepadBtn(label: String, buttonId: Int, size: androidx.compose.ui.unit.Dp, modifier: Modifier, color: Color, mainActivity: MainActivity?) {
    Box(modifier = modifier.size(size).background(color.copy(0.12f), CircleShape).border(2.5.dp, color, CircleShape).pointerInput(Unit) { detectTapGestures(onPress = { mainActivity?.setButtonState(0, buttonId, true); tryAwaitRelease(); mainActivity?.setButtonState(0, buttonId, false) }) }, contentAlignment = Alignment.Center) {
        Text(label, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun SystemBtn(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, mainActivity: MainActivity? = null, buttonId: Int = -1, onClick: (() -> Unit)? = null) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.pointerInput(Unit) {
        detectTapGestures(onPress = {
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
