package com.cardsagainsttv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cardsagainsttv.ui.RootScreen
import com.cardsagainsttv.ui.theme.CardsAgainstTVTheme
import com.cardsagainsttv.viewmodel.DeckLoaderViewModel
import com.cardsagainsttv.viewmodel.GameViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)

        setContent {
            CardsAgainstTVTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val deckVm: DeckLoaderViewModel = viewModel()
                    val gameVm: GameViewModel = viewModel()
                    RootScreen(deckVm, gameVm)
                }
            }
        }
    }
}