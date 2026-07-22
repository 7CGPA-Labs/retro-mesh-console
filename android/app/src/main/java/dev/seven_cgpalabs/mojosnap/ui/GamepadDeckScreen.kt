package dev.seven_cgpalabs.mojosnap.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Gamepad
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

@Composable
fun GamepadDeckScreen() {
    var useAnalogStick by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        // Analog Toggle
        Row(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 40.dp)
                .background(
                    if (useAnalogStick) PinkGlow.copy(alpha = 0.2f) else Color.White.copy(alpha = 0.12f),
                    RoundedCornerShape(20.dp)
                )
                .border(
                    2.dp,
                    if (useAnalogStick) PinkGlow else Color.White.copy(alpha = 0.24f),
                    RoundedCornerShape(20.dp)
                )
                .clickable { useAnalogStick = !useAnalogStick }
                .padding(horizontal = 24.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                if (useAnalogStick) Icons.Filled.Gamepad else Icons.Filled.DirectionsWalk,
                contentDescription = null,
                tint = if (useAnalogStick) PinkGlow else Color.White.copy(alpha = 0.54f),
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                if (useAnalogStick) "ANALOG ON" else "D-PAD ON",
                color = if (useAnalogStick) PinkGlow else Color.White.copy(alpha = 0.54f),
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp
            )
        }

        // Left Side Controls
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .padding(start = 36.dp)
        ) {
            if (useAnalogStick) {
                AnalogStick(
                    sizeDp = 120f,
                    onAnalogUpdate = { x, y -> /* send x, y */ }
                )
            } else {
                DPad()
            }
        }

        // Right Side Controls (Action Buttons)
        ActionCluster(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(end = 36.dp)
        )
    }
}

@Composable
fun DPad() {
    Box(modifier = Modifier.size(120.dp)) {
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .size(40.dp, 40.dp)
                .background(Color(0xFF1E1E38), RoundedCornerShape(8.dp))
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .size(40.dp, 40.dp)
                .background(Color(0xFF1E1E38), RoundedCornerShape(8.dp))
        )
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(40.dp, 40.dp)
                .background(Color(0xFF1E1E38), RoundedCornerShape(8.dp))
        )
        Box(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .size(40.dp, 40.dp)
                .background(Color(0xFF1E1E38), RoundedCornerShape(8.dp))
        )
        Box(
            modifier = Modifier
                .align(Alignment.Center)
                .size(40.dp, 40.dp)
                .background(Color(0xFF1E1E38))
        )
    }
}

@Composable
fun ActionCluster(modifier: Modifier = Modifier) {
    Box(modifier = modifier.size(120.dp)) {
        ActionButton(modifier = Modifier.align(Alignment.TopCenter), label = "Y", color = Color(0xFF00E5FF))
        ActionButton(modifier = Modifier.align(Alignment.BottomCenter), label = "A", color = Color(0xFF00E5FF))
        ActionButton(modifier = Modifier.align(Alignment.CenterStart), label = "X", color = PinkGlow)
        ActionButton(modifier = Modifier.align(Alignment.CenterEnd), label = "B", color = PinkGlow)
    }
}

@Composable
fun ActionButton(modifier: Modifier = Modifier, label: String, color: Color) {
    Box(
        modifier = modifier
            .size(48.dp)
            .background(Color(0xFF1E1E38), CircleShape)
            .border(2.dp, color.copy(alpha = 0.5f), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(label, color = color, fontWeight = FontWeight.Bold, fontSize = 20.sp)
    }
}

@Composable
fun AnalogStick(
    sizeDp: Float,
    onAnalogUpdate: (Float, Float) -> Unit
) {
    var offset by remember { mutableStateOf(Offset.Zero) }

    Box(
        modifier = Modifier
            .size(sizeDp.dp)
            .background(Color(0xFF1E1E38).copy(alpha = 0.5f), CircleShape)
            .border(2.dp, Color.White.copy(alpha = 0.24f), CircleShape)
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = { },
                    onDragEnd = {
                        offset = Offset.Zero
                        onAnalogUpdate(0f, 0f)
                    },
                    onDragCancel = {
                        offset = Offset.Zero
                        onAnalogUpdate(0f, 0f)
                    },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        val newOffset = offset + dragAmount
                        val distance = sqrt(newOffset.x * newOffset.x + newOffset.y * newOffset.y)
                        val radiusPx = (sizeDp.dp.toPx()) / 2
                        
                        offset = if (distance > radiusPx) {
                            val angle = atan2(newOffset.y, newOffset.x)
                            Offset(cos(angle) * radiusPx, sin(angle) * radiusPx)
                        } else {
                            newOffset
                        }
                        
                        onAnalogUpdate(offset.x / radiusPx, offset.y / radiusPx)
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .offset { IntOffset(offset.x.toInt(), offset.y.toInt()) }
                .size((sizeDp / 2.5f).dp)
                .background(Color(0xFF14142B), CircleShape)
                .border(3.dp, PinkGlow, CircleShape)
                .shadow(10.dp, CircleShape, ambientColor = PinkGlow.copy(alpha = 0.3f))
        )
    }
}
