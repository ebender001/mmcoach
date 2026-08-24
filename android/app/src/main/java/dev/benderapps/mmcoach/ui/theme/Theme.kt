package dev.benderapps.mmcoach.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = MichiganBlue,
    onPrimary = Color.White,
    secondary = Maize,
    onSecondary = MichiganBlue,
    background = WarmBackgroundLight,
    surface = Color.White,
    onSurface = MichiganBlueTextLight,
    onSurfaceVariant = SlateTextLight,
    tertiary = MutedTealLight,
)

private val DarkColors = darkColorScheme(
    primary = MichiganBlueTextDark,
    onPrimary = MichiganBlue,
    secondary = Maize,
    onSecondary = MichiganBlue,
    onSurfaceVariant = SlateTextDark,
    tertiary = MutedTealDark,
)

@Composable
fun MMCoachTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColors else LightColors
    MaterialTheme(
        colorScheme = colorScheme,
        typography = MMCoachTypography,
        content = content,
    )
}
