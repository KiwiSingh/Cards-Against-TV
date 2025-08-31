package com.cardsagainsttv.model

import kotlinx.serialization.*

@Serializable
data class CompactBlack(val text: String, val pick: Int)

@Serializable
data class CompactDeck(
    val white: List<String>,
    val black: List<CompactBlack>,
    val name: String? = null,
    val id: String? = null
)

@Serializable
data class DeckPack(
    val name: String,
    val white: List<Int>,
    val black: List<Int>,
    val official: Boolean? = null
)

@Serializable
data class DeckCollection(
    val packs: List<DeckPack>? = null,
    val white: List<String>? = null,
    val black: List<CompactBlack>? = null
)

data class Player(
    val id: String = java.util.UUID.randomUUID().toString(),
    val name: String,
    val score: Int = 0,
    val customCardUses: Int = 0
)

sealed class GamePhase {
    object Waiting : GamePhase()
    object Dealing : GamePhase()
    object Round : GamePhase()
    object Judging : GamePhase()
    data class ShowWinner(val winnerIndex: Int) : GamePhase()
    data class GameOver(val winners: List<Player>) : GamePhase()
}
