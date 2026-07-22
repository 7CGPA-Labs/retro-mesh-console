package dev.seven_cgpalabs.mojosnap.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ripple.rememberRipple
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Gamepad
import androidx.compose.material.icons.rounded.WifiFind

@Composable
fun RoleGateScreen(
    onHostSelected: () -> Unit,
    onJoinSelected: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        BackgroundDark,
                        BackgroundGradientMid,
                        BackgroundDark
                    )
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .widthIn(max = 400.dp)
                .padding(horizontal = 24.dp, vertical = 16.dp)
        ) {
            Header()
            Spacer(modifier = Modifier.height(24.dp))
            RoleCard(
                title = "START GAME CONSOLE",
                role = "PLAYER 1 / HOST CONSOLE",
                description = "Load a game ROM, connect to your television screen, and act as Player 1.",
                icon = Icons.Rounded.Gamepad,
                glowColor = PinkGlow,
                onClick = onHostSelected
            )
            Spacer(modifier = Modifier.height(28.dp))
            RoleCard(
                title = "JOIN ACTIVE CONSOLE",
                role = "PLAYER 2 / WIRELESS CLIENT",
                description = "Join an active game console session on the local network to play together as Player 2.",
                icon = Icons.Rounded.WifiFind,
                glowColor = CyanGlow,
                onClick = onJoinSelected
            )
            Spacer(modifier = Modifier.height(48.dp))
            Text(
                "Made with ♥ by 7CGPA Labs",
                color = Color.White.copy(alpha = 0.3f),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 2.sp
            )
        }
    }
}

@Composable
fun Header() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(80.dp)
                .background(BackgroundDark, CircleShape)
                .drawBehind {
                    drawCircle(
                        color = PinkGlow.copy(alpha = 0.3f),
                        radius = size.width / 2 + 30.dp.toPx()
                    )
                    drawCircle(
                        color = CyanGlow.copy(alpha = 0.2f),
                        radius = size.width / 2 + 40.dp.toPx()
                    )
                }
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            "MOJO SNAP",
            color = Color.White,
            fontSize = 38.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 4.sp
        )
        Text(
            "CONSOLE SYSTEM",
            color = CyanGlow,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 4.sp
        )
    }
}

@Composable
fun RoleCard(
    title: String,
    role: String,
    description: String,
    icon: ImageVector,
    glowColor: Color,
    onClick: () -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    Surface(
        color = Color(0xFF16162D).copy(alpha = 0.85f),
        shape = RoundedCornerShape(20.dp),
        shadowElevation = 8.dp,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .clickable(
                interactionSource = interactionSource,
                indication = rememberRipple(
                    color = glowColor.copy(alpha = 0.15f)
                ),
                onClick = onClick
            )
            .border(
                width = 1.5.dp,
                color = glowColor.copy(alpha = 0.25f),
                shape = RoundedCornerShape(20.dp)
            )
    ) {
        Row(
            modifier = Modifier.padding(24.dp),
            verticalAlignment = Alignment.Top
        ) {
            Box(
                modifier = Modifier
                    .background(glowColor.copy(alpha = 0.1f), RoundedCornerShape(14.dp))
                    .padding(12.dp)
            ) {
                Icon(icon, contentDescription = null, tint = glowColor, modifier = Modifier.size(32.dp))
            }
            Spacer(modifier = Modifier.width(20.dp))
            Column {
                Text(
                    role,
                    color = glowColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 1.5.sp
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    title,
                    color = Color.White,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.5.sp
                )
                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    description,
                    color = Color.White.copy(alpha = 0.65f),
                    fontSize = 13.sp,
                    lineHeight = 18.sp
                )
            }
        }
    }
}
