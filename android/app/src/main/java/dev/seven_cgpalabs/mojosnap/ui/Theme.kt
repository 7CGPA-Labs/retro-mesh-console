package dev.seven_cgpalabs.mojosnap.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val PinkGlow = Color(0xFFFF2E93)
val CyanGlow = Color(0xFF00E5FF)
val BackgroundDark = Color(0xFF070714)
val BackgroundGradientMid = Color(0xFF0F0F28)
val SurfaceDark = Color(0xFF1E1E38)

val DarkColorScheme = darkColorScheme(
    primary = PinkGlow,
    secondary = CyanGlow,
    background = BackgroundDark,
    surface = SurfaceDark,
)

@Composable
fun MojoSnapTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        content = content
    )
}
