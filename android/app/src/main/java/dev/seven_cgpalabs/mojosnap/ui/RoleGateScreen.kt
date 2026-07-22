package dev.seven_cgpalabs.mojosnap.ui

import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Gamepad
import androidx.compose.material.icons.filled.WifiFind
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.animation.core.animateFloat
@Composable
fun RoleGateScreen(onNavigateToGamepad: (isHost: Boolean, romUri: Uri?, coreName: String, playerName: String) -> Unit) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var showPlayerNameDialog by remember { mutableStateOf(false) }
    var playerName by remember { mutableStateOf("Player 1") }
    var showLoading by remember { mutableStateOf(false) }

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            showLoading = true
            coroutineScope.launch {
                try {
                    val coreName = CoreRouter.resolveCore(uri.lastPathSegment ?: "unknown.nes").substringBefore("_")
                    onNavigateToGamepad(true, uri, coreName, playerName)
                } catch (e: Exception) {
                    Toast.makeText(context, "Failed to load ROM", Toast.LENGTH_SHORT).show()
                } finally {
                    showLoading = false
                }
            }
        }
    }

    var isHostSelection by remember { mutableStateOf(true) }

    if (showPlayerNameDialog) {
        AlertDialog(
            onDismissRequest = { showPlayerNameDialog = false },
            containerColor = Color(0xFF1E1E38),
            title = { Text("Enter Your Player Name", color = Color.White) },
            text = {
                OutlinedTextField(
                    value = playerName,
                    onValueChange = { playerName = it },
                    colors = TextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedContainerColor = Color.Transparent,
                        unfocusedContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color(0xFF00E5FF),
                        unfocusedIndicatorColor = Color(0xFFFF2E93)
                    )
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showPlayerNameDialog = false
                    filePickerLauncher.launch(arrayOf("*/*"))
                }) {
                    Text("NEXT", color = Color(0xFF00E5FF))
                }
            },
            dismissButton = {
                TextButton(onClick = { showPlayerNameDialog = false }) {
                    Text("CANCEL", color = Color.White.copy(alpha = 0.54f))
                }
            }
        )
    }

    if (showLoading) {
        AlertDialog(
            onDismissRequest = {},
            containerColor = Color(0xFF1E1E38).copy(alpha = 0.9f),
            title = { Text("Extracting core binaries...", color = Color.White, fontSize = 16.sp) },
            text = { CircularProgressIndicator(color = Color(0xFFFF2E93)) },
            confirmButton = {}
        )
    }

    val titleScale = remember { androidx.compose.animation.core.Animatable(0f) }
    LaunchedEffect(Unit) {
        titleScale.animateTo(
            targetValue = 1f,
            animationSpec = androidx.compose.animation.core.tween(
                durationMillis = 3500,
                easing = androidx.compose.animation.core.FastOutSlowInEasing
            )
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF070714))
    ) {
        StarfieldBackground()
        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .width(400.dp)
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF070714))
                    .shadow(30.dp, CircleShape, spotColor = Color(0xFFFF2E93).copy(alpha = 0.3f)),
                contentAlignment = Alignment.Center
            ) {
                androidx.compose.foundation.Image(
                    painter = androidx.compose.ui.res.painterResource(id = dev.seven_cgpalabs.mojosnap.R.drawable.app_icon),
                    contentDescription = "App Icon",
                    modifier = Modifier.fillMaxSize()
                        .graphicsLayer { alpha = 0.99f }
                        .drawWithContent {
                            drawContent()
                            drawRect(
                                brush = Brush.radialGradient(
                                    colors = listOf(Color.Black, Color.Transparent),
                                    radius = size.minDimension / 1.5f
                                ),
                                blendMode = androidx.compose.ui.graphics.BlendMode.DstIn
                            )
                        }
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            Column(
                modifier = Modifier.graphicsLayer {
                    scaleX = titleScale.value
                    scaleY = titleScale.value
                },
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("MOJO SNAP", color = Color(0xFFFFD700), fontSize = 38.sp, fontWeight = FontWeight.Black, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, letterSpacing = 4.sp)
                Text("CONSOLE SYSTEM", color = Color(0xFF00E5FF), fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, letterSpacing = 4.sp)
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Host Card
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { 
                        isHostSelection = true
                        showPlayerNameDialog = true 
                    },
                colors = CardDefaults.cardColors(containerColor = Color(0xFF16162D).copy(alpha = 0.85f)),
                shape = RoundedCornerShape(20.dp),
                border = androidx.compose.foundation.BorderStroke(1.5.dp, Color(0xFFFF2E93).copy(alpha = 0.25f))
            ) {
                Row(modifier = Modifier.padding(24.dp)) {
                    Icon(
                        imageVector = Icons.Default.Gamepad,
                        contentDescription = null,
                        tint = Color(0xFFFF2E93),
                        modifier = Modifier.size(32.dp)
                    )
                    Spacer(modifier = Modifier.width(20.dp))
                    Column {
                        Text("PLAYER 1 / HOST CONSOLE", color = Color(0xFFFF2E93), fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp)
                        Spacer(modifier = Modifier.height(6.dp))
                        Text("START GAME CONSOLE", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.height(10.dp))
                        Text("Load a game ROM, connect to your television screen, and act as Player 1.", color = Color.White.copy(alpha = 0.65f), fontSize = 13.sp)
                    }
                }
            }

            Spacer(modifier = Modifier.height(28.dp))

            // Client Card
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        onNavigateToGamepad(false, null, "client", "")
                    },
                colors = CardDefaults.cardColors(containerColor = Color(0xFF16162D).copy(alpha = 0.85f)),
                shape = RoundedCornerShape(20.dp),
                border = androidx.compose.foundation.BorderStroke(1.5.dp, Color(0xFF00E5FF).copy(alpha = 0.25f))
            ) {
                Row(modifier = Modifier.padding(24.dp)) {
                    Icon(
                        imageVector = Icons.Default.WifiFind,
                        contentDescription = null,
                        tint = Color(0xFF00E5FF),
                        modifier = Modifier.size(32.dp)
                    )
                    Spacer(modifier = Modifier.width(20.dp))
                    Column {
                        Text("PLAYER 2 / WIRELESS CLIENT", color = Color(0xFF00E5FF), fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp)
                        Spacer(modifier = Modifier.height(6.dp))
                        Text("JOIN ACTIVE CONSOLE", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.height(10.dp))
                        Text("Join an active game console session on the local network to play together as Player 2.", color = Color.White.copy(alpha = 0.65f), fontSize = 13.sp)
                    }
                }
            }

            Spacer(modifier = Modifier.height(48.dp))
            Text("Made with ♥ by 7CGPA Labs", color = Color.White.copy(alpha = 0.3f), fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
        }
    }
}

@Composable
fun StarfieldBackground() {
    val infiniteTransition = androidx.compose.animation.core.rememberInfiniteTransition()
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.2f,
        targetValue = 1f,
        animationSpec = androidx.compose.animation.core.infiniteRepeatable(
            animation = androidx.compose.animation.core.tween(1500, easing = androidx.compose.animation.core.LinearEasing),
            repeatMode = androidx.compose.animation.core.RepeatMode.Reverse
        )
    )

    val stars = remember {
        List(100) {
            androidx.compose.ui.geometry.Offset(kotlin.random.Random.nextFloat(), kotlin.random.Random.nextFloat()) to kotlin.random.Random.nextFloat() * 4f
        }
    }

    androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
        stars.forEachIndexed { index, (pos, radius) ->
            val starAlpha = (alpha + (index % 10) * 0.1f) % 1f
            drawCircle(
                color = Color.White.copy(alpha = starAlpha.coerceIn(0.2f, 1f)),
                radius = radius,
                center = androidx.compose.ui.geometry.Offset(pos.x * size.width, pos.y * size.height)
            )
        }
    }
}
