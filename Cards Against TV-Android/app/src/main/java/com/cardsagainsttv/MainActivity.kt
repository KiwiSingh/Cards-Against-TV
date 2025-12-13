package com.cardsagainsttv

import android.os.Bundle
import android.util.Log
import android.widget.Toast
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
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.games.PlayGamesSdk
import com.google.android.gms.games.PlayGames

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        PlayGamesSdk.initialize(this) // Good place for SDK initialization

        // Explicitly initialize Google Play Games
        Log.d("MainActivity", "Initializing Google Play Games")
        authenticateUser()

        setContent {
            CardsAgainstTVTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    // ViewModel instantiation simplified
                    val deckVm: DeckLoaderViewModel = viewModel()
                    val gameVm: GameViewModel = viewModel() // Assuming GameViewModel also has a compatible constructor or no-arg factory

                    // Pass 'this' (MainActivity instance) to RootScreen if it needs to
                    // pass it down to ViewModels for functions requiring an Activity context.
                    RootScreen(deckVm, gameVm, this)
                }
            }
        }
    }

    // The authenticateUser and getPlayerInfo methods can remain as they are.
    // Ensure they are called when appropriate (e.g., on a button click, or after SDK init).
    // Note: These methods use 'this' for context, which is correct as 'this' refers to MainActivity.

    private fun authenticateUser() {
        // PlayGames import is needed here
        val gamesSignInClient = PlayGames.getGamesSignInClient(this)

        Log.d("MainActivity", "Checking Google Play Games authentication")
        gamesSignInClient.isAuthenticated.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val isAuthenticated = task.result.isAuthenticated
                Log.d("MainActivity", "isAuthenticated check result: $isAuthenticated")

                if (isAuthenticated) {
                    Log.d("MainActivity", "User is authenticated, getting player info")
                    getPlayerInfo()
                } else {
                    Log.d("MainActivity", "User is not authenticated via Play Games, attempting sign-in")
                    // Trigger sign-in flow automatically
                    gamesSignInClient.signIn().addOnCompleteListener { signInTask ->
                        if (signInTask.isSuccessful) {
                            Log.d("MainActivity", "Sign-in successful")
                            getPlayerInfo()
                        } else {
                            Log.e("MainActivity", "Sign-in failed", signInTask.exception)

                            // Show error for debugging
                            val exception = signInTask.exception
                            if (exception != null) {
                                Log.e("MainActivity", "Sign-in exception: ${exception.message}")
                                if (exception is ApiException) {
                                    Log.e("MainActivity", "ApiException status code: ${exception.statusCode}")
                                }
                            }

                            Toast.makeText(this, "Failed to sign in to Google Play Games", Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            } else {
                Log.e("MainActivity", "Play Games isAuthenticated check failed", task.exception)
                Toast.makeText(this, "Failed to check Play Games authentication", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun getPlayerInfo() {
        // PlayGames import is needed here
        val playersClient = PlayGames.getPlayersClient(this)
        Log.d("MainActivity", "Getting player info")

        playersClient.currentPlayer.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val player = task.result
                // Check if player is not null (it can be if not signed in or error)
                if (player != null) {
                    val playerId = player.playerId
                    val playerName = player.displayName
                    Log.d("MainActivity", "Player authenticated - ID: $playerId, Name: $playerName")

                    // Show success toast for debugging
                    Toast.makeText(this, "Signed in as: $playerName", Toast.LENGTH_SHORT).show()

                    // Store or use the player information as needed
                } else {
                    Log.w("MainActivity", "Player object is null even after successful task.")
                    Toast.makeText(this, "Failed to get player info", Toast.LENGTH_SHORT).show()
                }
            } else {
                Log.e("MainActivity", "Failed to get player info", task.exception)
                Toast.makeText(this, "Failed to get player info", Toast.LENGTH_SHORT).show()
            }
        }
    }
}