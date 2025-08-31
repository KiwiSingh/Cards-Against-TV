package com.cardsagainsttv.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cardsagainsttv.R
import com.cardsagainsttv.model.GamePhase
import com.cardsagainsttv.viewmodel.DeckLoaderViewModel
import com.cardsagainsttv.viewmodel.GameViewModel

enum class AppState { Loading, DeckSelection, PlayerCount, PlayerNames, Playing }

@Composable
fun RootScreen(loader: DeckLoaderViewModel, game: GameViewModel) {
    var appState by remember { mutableStateOf(AppState.Loading) }
    var numPlayers by remember { mutableStateOf(3) }
    val minPlayers = 3; val maxPlayers = 8
    var nameInputs by remember { mutableStateOf(List(numPlayers){""}) }

    val packs by loader.packs.collectAsState()
    val canContinue = loader.canContinue
    val error by loader.errorMessage.collectAsState()

    LaunchedEffect(Unit) {
        loader.load()
    }
    LaunchedEffect(packs) {
        if (packs.isNotEmpty() && appState == AppState.Loading) appState = AppState.DeckSelection
    }

    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Image(painterResource(R.drawable.catv_wide), contentDescription = null,
                modifier = Modifier.height(120.dp), contentScale = ContentScale.Fit)
            Spacer(Modifier.height(16.dp))
            if (error != null) Text("Deck load error: ${error}", color = MaterialTheme.colorScheme.error)
            when (appState) {
                AppState.Loading -> {
                    Text("Loading decks..."); CircularProgressIndicator()
                }
                AppState.DeckSelection -> DeckSelectionView(loader = loader, onContinue = {
                    if (canContinue) appState = AppState.PlayerCount
                })
                AppState.PlayerCount -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Number of players:"); Spacer(Modifier.width(12.dp))
                        Button(onClick = { if (numPlayers>minPlayers) { numPlayers--; nameInputs = List(numPlayers){""} } }) { Text("–") }
                        Spacer(Modifier.width(12.dp)); Text("$numPlayers")
                        Spacer(Modifier.width(12.dp))
                        Button(onClick = { if (numPlayers<maxPlayers) { numPlayers++; nameInputs = List(numPlayers){""} } }) { Text("+") }
                    }
                    Spacer(Modifier.height(16.dp))
                    Button(onClick = { appState = AppState.PlayerNames }) { Text("Continue") }
                }
                AppState.PlayerNames -> {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Enter Player Names", style = MaterialTheme.typography.titleLarge)
                        repeat(numPlayers) { i ->
                            OutlinedTextField(
                                value = nameInputs[i],
                                onValueChange = { v -> nameInputs = nameInputs.toMutableList().also{it[i]=v} },
                                label = { Text("Player ${i+1}") },
                                modifier = Modifier.fillMaxWidth().padding(vertical=4.dp)
                            )
                        }
                        Button(onClick = {
                            val deck = loader.deck.value
                            if (deck != null) {
                                game.setup(deck, nameInputs.map { it.trim().ifEmpty { "Player" } })
                                appState = AppState.Playing
                            }
                        }) { Text("Start Game") }
                    }
                }
                AppState.Playing -> GameScreen(game) {
                    // New game callback - return to deck selection
                    appState = AppState.DeckSelection
                }
            }
        }
    }
}

@Composable
fun DeckSelectionView(loader: DeckLoaderViewModel, onContinue: () -> Unit) {
    val packs by loader.packs.collectAsState()
    val selected by loader.selectedPackIds.collectAsState()

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Button(onClick = onContinue, enabled = loader.canContinue) { Text("Continue") }
            Row {
                TextButton(onClick = { loader.selectAll() }) { Text("Select All") }
                TextButton(onClick = { loader.selectNone() }) { Text("Select None") }
            }
        }
        Spacer(Modifier.height(8.dp))
        LazyColumn {
            itemsIndexed(packs.sortedBy { it.name }) { index, pack ->
                val actualIndex = packs.indexOf(pack)
                Card(
                    Modifier.fillMaxWidth().padding(vertical = 6.dp).clickable { loader.togglePack(actualIndex) }
                ) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(pack.name, style = MaterialTheme.typography.titleMedium)
                            Text("${pack.white.size} White • ${pack.black.size} Black", style = MaterialTheme.typography.bodySmall)
                        }
                        Checkbox(checked = selected.contains(actualIndex), onCheckedChange = { loader.togglePack(actualIndex) })
                    }
                }
            }
        }
    }
}

@Composable
fun GameScreen(game: GameViewModel, onNewGame: () -> Unit) {
    val players by game.players.collectAsState()
    val hands by game.hands.collectAsState()
    val currentBlack by game.currentBlack.collectAsState()
    val submissions by game.submissions.collectAsState()
    val roundJudge by game.roundJudge.collectAsState()
    val phase by game.phase.collectAsState()
    val active by game.activePlayer.collectAsState()
    val newGameRequested by game.newGameRequested.collectAsState()

    // Check if new game was requested
    LaunchedEffect(newGameRequested) {
        if (newGameRequested) {
            game.onNewGameHandled()
            onNewGame()
        }
    }

    when (phase) {
        is GamePhase.ShowWinner -> {
            val winnerIndex = (phase as GamePhase.ShowWinner).winnerIndex
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Text("Round Winner!", style = MaterialTheme.typography.headlineLarge)
                Spacer(Modifier.height(16.dp))
                Text("${players[winnerIndex].name}",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(8.dp))
                Text("Score: ${players[winnerIndex].score}", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(24.dp))
                Button(onClick = { game.startRound() }) { Text("Next Round") }
            }
        }
        is GamePhase.GameOver -> {
            val winners = (phase as GamePhase.GameOver).winners
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Text("Game Over!", style = MaterialTheme.typography.headlineLarge)
                Spacer(Modifier.height(16.dp))

                // Show winners
                winners.forEach { winner ->
                    Text("🏆 ${winner.name} wins with ${winner.score} points!",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary)
                }

                Spacer(Modifier.height(32.dp))

                // Game over buttons
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Button(
                        onClick = { game.playAgain() },
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                    ) {
                        Text("Play Again")
                    }
                    OutlinedButton(
                        onClick = { game.newGame() }
                    ) {
                        Text("New Game")
                    }
                }
            }
        }
        GamePhase.Judging -> JudgingView(
            players = players,
            submissions = submissions,
            judgeIndex = roundJudge,
            blackText = currentBlack?.text ?: "",
            pick = currentBlack?.pick ?: 1,
            onPick = { game.pickWinner(it) }
        )
        else -> RoundView(players, hands, currentBlack?.text ?: "", currentBlack?.pick ?: 1, active, roundJudge,
            onSubmit = { handIdxs -> game.submitCard(active, handIdxs) },
            onSubmitCustom = { texts -> game.submitCustomCard(active, texts) }
        )
    }
}

@Composable
fun RoundView(
    players: List<com.cardsagainsttv.model.Player>,
    hands: List<MutableList<String>>,
    blackText: String,
    pick: Int,
    activeIndex: Int,
    judgeIndex: Int,
    onSubmit: (List<Int>) -> Unit,
    onSubmitCustom: (List<String>) -> Unit
) {
    val hand = hands.getOrNull(activeIndex) ?: emptyList()
    var selected by remember { mutableStateOf(setOf<Int>()) }
    var customInputs by remember { mutableStateOf(List(pick){""}) }
    var showCustomCards by remember { mutableStateOf(false) }
    val submitButtonFocusRequester = remember { FocusRequester() }

    // Clear selections when active player changes
    LaunchedEffect(activeIndex) {
        selected = setOf()
        customInputs = List(pick){""}
        showCustomCards = false
    }

    Column(Modifier.fillMaxSize().padding(8.dp)) {
        // Player Status Section - Always visible
        Card(
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
        ) {
            Column(Modifier.padding(12.dp)) {
                Text("Current Player: ${players[activeIndex].name}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer)
                Text("Judge: ${players[judgeIndex].name}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer)

                // Show scores
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    players.forEach { player ->
                        Text("${player.name}: ${player.score}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer)
                    }
                }
            }
        }

        // Black Card
        Card(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
            Column(Modifier.padding(12.dp)) {
                Text(blackText, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("Pick $pick", style = MaterialTheme.typography.labelLarge)
            }
        }

        // Main content area - use regular Column with scroll instead of LazyColumn
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
        ) {
            // Hand Cards
            Text("Your Cards:", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))
            hand.forEachIndexed { idx, card ->
                val isSelected = selected.contains(idx)
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 2.dp)
                        .clickable {
                            selected = if (isSelected) {
                                selected - idx
                            } else {
                                if (selected.size < pick) selected + idx else selected
                            }
                        },
                    colors = CardDefaults.cardColors(
                        containerColor = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface
                    )
                ) {
                    Text(
                        text = card,
                        modifier = Modifier.padding(12.dp),
                        color = if (isSelected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
                    )
                }
            }

            Spacer(Modifier.height(16.dp))

            // Action Buttons
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                Button(
                    onClick = { onSubmit(selected.toList()) },
                    enabled = selected.size == pick,
                    modifier = Modifier
                        .focusRequester(submitButtonFocusRequester)
                        .weight(1f)
                ) {
                    Text("Submit Selected")
                }

                Spacer(Modifier.width(8.dp))

                Button(
                    onClick = { showCustomCards = !showCustomCards },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (showCustomCards) "Hide Custom" else "Use Custom")
                }
            }

            // Custom Cards Section - only show when toggled
            if (showCustomCards) {
                Spacer(Modifier.height(16.dp))
                Text("Custom Cards:", style = MaterialTheme.typography.titleMedium)
                repeat(pick) { i ->
                    OutlinedTextField(
                        value = customInputs[i],
                        onValueChange = { newValue ->
                            customInputs = customInputs.toMutableList().also { list -> list[i] = newValue }
                        },
                        label = { Text("Custom Card #${i+1}") },
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)
                    )
                }
                Button(
                    onClick = { onSubmitCustom(customInputs.filter { it.isNotBlank() }) },
                    enabled = customInputs.all { it.isNotBlank() },
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                ) {
                    Text("Submit Custom Cards")
                }
            }
        }
    }
}

@Composable
fun JudgingView(
    players: List<com.cardsagainsttv.model.Player>,
    submissions: List<Pair<Int,List<String>>>,
    judgeIndex: Int,
    blackText: String,
    pick: Int,
    onPick: (Int) -> Unit
) {
    Column(Modifier.fillMaxSize().padding(8.dp)) {
        // Judge Status
        Card(
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
        ) {
            Column(Modifier.padding(12.dp)) {
                Text("You are the Judge: ${players[judgeIndex].name}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSecondaryContainer)
                Text("Choose the winning submission:",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSecondaryContainer)
            }
        }

        // Black Card (Question)
        Card(
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
        ) {
            Column(Modifier.padding(12.dp)) {
                Text(blackText, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("Pick $pick", style = MaterialTheme.typography.labelLarge)
            }
        }

        LazyColumn {
            itemsIndexed(submissions) { idx, sub ->
                Card(Modifier.fillMaxWidth().padding(vertical=6.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(sub.second.joinToString(" / "), textAlign = TextAlign.Start)
                        Spacer(Modifier.height(8.dp))
                        Button(onClick = { onPick(idx) }) { Text("Pick as Winner") }
                    }
                }
            }
        }
    }
}
