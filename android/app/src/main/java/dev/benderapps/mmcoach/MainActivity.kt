package dev.benderapps.mmcoach

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dev.benderapps.mmcoach.ui.screens.RootScreen
import dev.benderapps.mmcoach.ui.theme.MMCoachTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MMCoachTheme {
                RootScreen()
            }
        }
    }
}
