@file:OptIn(ExperimentalStdlibApi::class)

package com.cardsagainsttv.viewmodel

import androidx.lifecycle.ViewModel
import com.cardsagainsttv.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.random.Random
import kotlin.ExperimentalStdlibApi

class GameViewModel : ViewModel() {

    private val _players = MutableStateFlow<List<Player>>(emptyList())
    val players: StateFlow<List<Player>> = _players

    private val _hands = MutableStateFlow<List<MutableList<String>>>(emptyList())
    val hands: StateFlow<List<MutableList<String>>> = _hands

    private val usedWhite = mutableSetOf<Int>()
    private val usedBlack = mutableSetOf<Int>()

    private val _currentBlack = MutableStateFlow<CompactBlack?>(null)
    val currentBlack: StateFlow<CompactBlack?> = _currentBlack

    private val _submissions = MutableStateFlow<List<Pair<Int, List<String>>>>(emptyList())
    val submissions: StateFlow<List<Pair<Int, List<String>>>> = _submissions

    private val _roundJudge = MutableStateFlow(0)
    val roundJudge: StateFlow<Int> = _roundJudge

    private val _phase = MutableStateFlow<GamePhase>(GamePhase.Waiting)
    val phase: StateFlow<GamePhase> = _phase

    private val _activePlayer = MutableStateFlow(0)
    val activePlayer: StateFlow<Int> = _activePlayer

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private var deck: CompactDeck? = null
    private var allWhite: List<String> = emptyList()

    private val handSize = 7
    private val winningScore = 5
    val maxCustomPerPlayer = 20

    fun setup(deck: CompactDeck, playerNames: List<String>) {
        this.deck = deck
        this.allWhite = deck.white
        _players.value = playerNames.map { Player(name = it) }
        _hands.value = List(_players.value.size) { mutableListOf() }
        usedWhite.clear(); usedBlack.clear()
        _submissions.value = emptyList()
        _roundJudge.value = 0
        _phase.value = GamePhase.Dealing
        _error.value = null
        dealInitialHands()
        startRound()
    }

    private fun dealInitialHands() {
        for (i in _players.value.indices) {
            _hands.value[i].clear()
            var tries = 0
            while (_hands.value[i].size < handSize && tries < handSize * 2) {
                tries++
                drawWhite()?.let { _hands.value[i].add(it) } ?: run {
                    _error.value = "Ran out of white cards."
                    return@run
                }
            }
        }
    }

    private fun drawWhite(): String? {
        val total = allWhite.size
        var attempts = 0
        while (attempts < 100 && usedWhite.size < total) {
            val idx = Random.nextInt(total)
            if (usedWhite.contains(idx)) {
                attempts++
                continue
            }
            usedWhite.add(idx)
            return allWhite[idx]
        }
        return null
    }

    private fun drawBlack(): CompactBlack? {
        val d = deck ?: return null
        val total = d.black.size
        var attempts = 0
        while (attempts < 100 && usedBlack.size < total) {
            val idx = Random.nextInt(total)
            if (usedBlack.contains(idx)) {
                attempts++
                continue
            }
            usedBlack.add(idx)
            return d.black[idx]
        }
        _error.value = "Ran out of black cards."
        return null
    }

    fun startRound() {
        val d = deck ?: return
        _error.value = null
        _currentBlack.value = drawBlack()
        if (_currentBlack.value == null) {
            _phase.value = GamePhase.Waiting
            return
        }
        _submissions.value = emptyList()
        _phase.value = GamePhase.Round
        _activePlayer.value = (_roundJudge.value + 1) % _players.value.size
        for (i in _players.value.indices) {
            while (_hands.value[i].size < handSize) {
                drawWhite()?.let { _hands.value[i].add(it) } ?: return
            }
        }
    }

    fun submitCard(playerIndex: Int, cardIndicesInHand: List<Int>) {
        val hand = _hands.value.getOrNull(playerIndex) ?: run {
            _error.value = "No hand"
            return
        }
        if (cardIndicesInHand.isEmpty()) {
            _error.value = "No card selected."
            return
        }

        // Keep order as picked by player
        val inOrder = cardIndicesInHand.sorted()
        val submitted = mutableListOf<String>()
        for (idx in inOrder.reversed()) { // remove safely from highest to lowest
            if (idx in hand.indices) {
                submitted.add(hand.removeAt(idx)) // append in correct order
            }
        }

        _hands.value = _hands.value.toList() // trigger recomposition
        _submissions.value = _submissions.value + (playerIndex to submitted)
        repeat(submitted.size) { refillHand(playerIndex) }
        advanceToNextPlayerOrJudge()
    }

    fun submitCustomCard(playerIndex: Int, texts: List<String>) {
        val p = _players.value.toMutableList()
        val cur = p[playerIndex]
        if (cur.customCardUses + texts.size <= maxCustomPerPlayer) {
            p[playerIndex] = cur.copy(customCardUses = cur.customCardUses + texts.size)
            _players.value = p
            _submissions.value = _submissions.value + (playerIndex to texts)
            advanceToNextPlayerOrJudge()
        } else {
            _error.value = "Custom card limit exceeded!"
        }
    }

    private fun advanceToNextPlayerOrJudge() {
        _activePlayer.value = (_activePlayer.value + 1) % _players.value.size
        if (_activePlayer.value == _roundJudge.value) {
            _activePlayer.value = (_activePlayer.value + 1) % _players.value.size
        }
        if (_submissions.value.size >= _players.value.size - 1) {
            _phase.value = GamePhase.Judging
            _activePlayer.value = _roundJudge.value
        }
    }

    private fun refillHand(playerIndex: Int) {
        drawWhite()?.let { _hands.value[playerIndex].add(it) }
    }

    fun pickWinner(submissionIndex: Int) {
        if (submissionIndex !in _submissions.value.indices) {
            _error.value = "Winner index out of bounds."
            return
        }
        val winner = _submissions.value[submissionIndex].first
        val p = _players.value.toMutableList()
        val cur = p[winner]
        p[winner] = cur.copy(score = cur.score + 1)
        _players.value = p
        val maxScore = _players.value.maxOfOrNull { it.score } ?: 0
        if (maxScore >= winningScore) {
            _phase.value = GamePhase.GameOver(_players.value.filter { it.score >= winningScore })
        } else {
            _phase.value = GamePhase.ShowWinner(winner)
            _roundJudge.value = (_roundJudge.value + 1) % _players.value.size
        }
    }

    fun playAgain() {
        // Reset scores but keep same players and deck
        val resetPlayers = _players.value.map { it.copy(score = 0, customCardUses = 0) }
        _players.value = resetPlayers

        // Clear used cards for a fresh game
        usedWhite.clear()
        usedBlack.clear()

        // Reset game state
        _submissions.value = emptyList()
        _roundJudge.value = 0
        _phase.value = GamePhase.Dealing
        _error.value = null

        // Deal new hands and start
        dealInitialHands()
        startRound()
    }

    private val _newGameRequested = MutableStateFlow(false)
    val newGameRequested: StateFlow<Boolean> = _newGameRequested

    fun newGame() {
        // Signal that new game was requested
        _newGameRequested.value = true

        // Reset everything to initial state
        _players.value = emptyList()
        _hands.value = emptyList()
        usedWhite.clear()
        usedBlack.clear()
        _currentBlack.value = null
        _submissions.value = emptyList()
        _roundJudge.value = 0
        _phase.value = GamePhase.Waiting
        _activePlayer.value = 0
        _error.value = null
        deck = null
        allWhite = emptyList()
    }

    fun onNewGameHandled() {
        _newGameRequested.value = false
    }
}
