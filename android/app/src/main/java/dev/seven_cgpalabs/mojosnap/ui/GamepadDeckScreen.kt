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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

@Composable
fun GamepadDeckScreen(isHost: Boolean, romUri: Uri?, coreName: String, playerName: String, onExit: () -> Unit) {
    val context = LocalContext.current
    var isConnectingTv by remember { mutableStateOf(isHost) }
    var useAnalogStick by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var analogPos by remember { mutableStateOf(Offset.Zero) }
    
    DisposableEffect(Unit) {
        val activity = context as? Activity
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
        onDispose {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    LaunchedEffect(Unit) {
        if (isHost) {
            delay(1500) // Mocking TV connection wait
            isConnectingTv = false
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
                Column {
                    TextButton(onClick = { showMenu = false }) {
                        Text("Resume Game", color = Color.White)
                    }
                    if (isHost) {
                        TextButton(onClick = { showMenu = false }) {
                            Text("Reset Game", color = Color.White)
                        }
                        TextButton(onClick = { showMenu = false }) {
                            Text("Quick Save (Slot 1)", color = Color.White)
                        }
                        TextButton(onClick = { showMenu = false }) {
                            Text("Quick Load (Slot 1)", color = Color.White)
                        }
                    }
                    TextButton(onClick = { showMenu = false; onExit() }) {
                        Text(if (isHost) "Stop Emulation & Exit" else "Disconnect", color = Color(0xFFEF4444), fontWeight = FontWeight.Bold)
                    }
                }
            },
            confirmButton = {}
        )
    }

    if (isConnectingTv) {
        Box(modifier = Modifier.fillMaxSize().background(Color(0xFF070714)), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(color = Color(0xFFFF2E93))
                Spacer(Modifier.height(32.dp))
                Text("WAITING FOR TELEVISION...", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(12.dp))
                Text("Please select your wireless display or Smart TV in the system cast overlay.", color = Color.White.copy(alpha = 0.5f))
            }
        }
        return
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        val baseSize = (maxHeight.value * 0.22f).coerceIn(40f, 100f).dp
        val mHeight = maxHeight
        val isSnes = coreName.contains("snes") || coreName.contains("mgba")
        val isPs1 = coreName.contains("pcsx")
        val isGenesis = coreName.contains("genesis")

        // Shoulders
        if (isSnes || isPs1) {
            ShoulderBtn("L" + if (isPs1) "1" else "", Modifier.padding(start = if (isPs1) 172.dp else 36.dp, top = mHeight * 0.05f))
            ShoulderBtn("R" + if (isPs1) "1" else "", Modifier.padding(end = if (isPs1) 172.dp else 36.dp, top = mHeight * 0.05f).align(Alignment.TopEnd))
        }
        if (isPs1) {
            ShoulderBtn("L2", Modifier.padding(start = 36.dp, top = mHeight * 0.05f))
            ShoulderBtn("R2", Modifier.padding(end = 36.dp, top = mHeight * 0.05f).align(Alignment.TopEnd))
        }

        // Analog toggle
        Box(
            modifier = Modifier.align(Alignment.TopCenter).padding(top = mHeight * 0.15f)
                .clickable { useAnalogStick = !useAnalogStick }
                .background(if (useAnalogStick) Color(0xFFFF2E93).copy(0.2f) else Color.White.copy(0.12f), RoundedCornerShape(20.dp))
                .border(2.dp, if (useAnalogStick) Color(0xFFFF2E93) else Color.White.copy(0.24f), RoundedCornerShape(20.dp))
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text(if (useAnalogStick) "ANALOG ON" else "D-PAD ON", color = if (useAnalogStick) Color(0xFFFF2E93) else Color.White.copy(0.54f), fontWeight = FontWeight.Bold)
        }

        Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Box(modifier = Modifier.padding(start = 36.dp, top = if (isSnes || isPs1) mHeight * 0.15f else 0.dp)) {
                if (useAnalogStick) {
                    Box(modifier = Modifier.size(baseSize * 3).background(Color(0xFF1E1E38).copy(0.5f), CircleShape).border(2.dp, Color.White.copy(0.24f), CircleShape)
                        .pointerInput(Unit) {
                            detectDragGestures(
                                onDragEnd = { analogPos = Offset.Zero },
                                onDrag = { change, dragAmount -> 
                                    analogPos += dragAmount
                                }
                            )
                        }, contentAlignment = Alignment.Center) {
                        Box(modifier = Modifier.offset(x = analogPos.x.dp, y = analogPos.y.dp).size(baseSize * 0.6f).background(Color(0xFF14142B), CircleShape).border(3.dp, Color(0xFFFF2E93), CircleShape))
                    }
                } else {
                    Box(modifier = Modifier.size(baseSize * 3)) {
                        GamepadBtn("U", baseSize, Modifier.align(Alignment.TopCenter), Color.White)
                        GamepadBtn("D", baseSize, Modifier.align(Alignment.BottomCenter), Color.White)
                        GamepadBtn("L", baseSize, Modifier.align(Alignment.CenterStart), Color.White)
                        GamepadBtn("R", baseSize, Modifier.align(Alignment.CenterEnd), Color.White)
                    }
                }
            }

            Box(modifier = Modifier.padding(end = 36.dp, top = if (isSnes || isPs1) mHeight * 0.15f else 0.dp)) {
                Box(modifier = Modifier.size(baseSize * 3)) {
                    when {
                        isGenesis -> {
                            GamepadBtn("X", baseSize, Modifier.align(Alignment.TopStart).padding(start = 10.dp), Color.LightGray)
                            GamepadBtn("Y", baseSize, Modifier.align(Alignment.TopCenter), Color.LightGray)
                            GamepadBtn("Z", baseSize, Modifier.align(Alignment.TopEnd).padding(end = 10.dp), Color.LightGray)
                            GamepadBtn("A", baseSize, Modifier.align(Alignment.BottomStart).padding(start = 10.dp), Color(0xFFE57373))
                            GamepadBtn("B", baseSize, Modifier.align(Alignment.BottomCenter), Color(0xFF81C784))
                            GamepadBtn("C", baseSize, Modifier.align(Alignment.BottomEnd).padding(end = 10.dp), Color(0xFF4FC3F7))
                        }
                        isPs1 || isSnes -> {
                            GamepadBtn(if(isPs1) "△" else "X", baseSize, Modifier.align(Alignment.TopCenter), Color.LightGray)
                            GamepadBtn(if(isPs1) "X" else "B", baseSize, Modifier.align(Alignment.BottomCenter), Color.LightGray)
                            GamepadBtn(if(isPs1) "□" else "Y", baseSize, Modifier.align(Alignment.CenterStart), Color.LightGray)
                            GamepadBtn(if(isPs1) "O" else "A", baseSize, Modifier.align(Alignment.CenterEnd), Color.LightGray)
                        }
                        else -> {
                            GamepadBtn("B", baseSize, Modifier.align(Alignment.BottomStart).padding(bottom = 20.dp, start = 20.dp), Color(0xFFE57373))
                            GamepadBtn("A", baseSize, Modifier.align(Alignment.TopEnd).padding(top = 20.dp, end = 20.dp), Color(0xFFE57373))
                        }
                    }
                }
            }
        }

        Row(modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            SystemBtn("SELECT", Icons.Default.SelectAll, Color.White.copy(0.7f)) {}
            SystemBtn("START", Icons.Default.PlayArrow, Color.White) {}
            SystemBtn("MENU", Icons.Default.Menu, Color(0xFFFF2E93)) { showMenu = true }
        }
    }
}

@Composable
fun ShoulderBtn(label: String, modifier: Modifier) {
    Box(modifier = modifier.size(120.dp, 48.dp).background(Color(0xFF1E1E38), RoundedCornerShape(16.dp)).border(2.dp, Color.White.copy(0.24f), RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
        Text(label, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun GamepadBtn(label: String, size: androidx.compose.ui.unit.Dp, modifier: Modifier, color: Color) {
    Box(modifier = modifier.size(size).background(color.copy(0.12f), CircleShape).border(2.5.dp, color, CircleShape).pointerInput(Unit) { detectTapGestures() }, contentAlignment = Alignment.Center) {
        Text(label, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun SystemBtn(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { onClick() }) {
        Box(modifier = Modifier.size(48.dp, 24.dp).background(color.copy(0.1f), RoundedCornerShape(12.dp)).border(1.dp, color.copy(0.3f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(16.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(label, color = color, fontSize = 10.sp, fontWeight = FontWeight.Bold)
    }
}
