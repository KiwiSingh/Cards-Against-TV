package com.cardsagainsttv.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.cardsagainsttv.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import kotlinx.serialization.decodeFromString
import java.io.InputStream

class DeckLoaderViewModel(app: Application) : AndroidViewModel(app) {

    private val _allWhite = MutableStateFlow<List<String>>(emptyList())
    val allWhite: StateFlow<List<String>> = _allWhite

    private val _allBlack = MutableStateFlow<List<CompactBlack>>(emptyList())
    val allBlack: StateFlow<List<CompactBlack>> = _allBlack

    private val _packs = MutableStateFlow<List<DeckPack>>(emptyList())
    val packs: StateFlow<List<DeckPack>> = _packs

    private val _selectedPackIds = MutableStateFlow<Set<Int>>(emptySet())
    val selectedPackIds: StateFlow<Set<Int>> = _selectedPackIds

    private val _deck = MutableStateFlow<CompactDeck?>(null)
    val deck: StateFlow<CompactDeck?> = _deck

    val errorMessage = MutableStateFlow<String?>(null)
    val isLoading = MutableStateFlow(false)

    val canContinue: Boolean get() = _selectedPackIds.value.isNotEmpty()

    fun load() {
        if (isLoading.value || _packs.value.isNotEmpty()) return
        viewModelScope.launch {
            isLoading.value = true
            try {
                val jsonStr = getApplication<Application>().assets.open("cah-all-compact.json").use(InputStream::readBytes).toString(Charsets.UTF_8)
                val jsonElement = Json.parseToJsonElement(jsonStr)
                val jsonObject = jsonElement.jsonObject

                jsonObject["white"]?.let { element ->
                    _allWhite.value = Json.decodeFromJsonElement<List<String>>(element)
                }
                jsonObject["black"]?.let { element ->
                    _allBlack.value = Json.decodeFromJsonElement<List<CompactBlack>>(element)
                }
                jsonObject["packs"]?.let { element ->
                    _packs.value = Json.decodeFromJsonElement<List<DeckPack>>(element)
                }
                // select all by default
                _selectedPackIds.value = _packs.value.indices.toSet()
                createCombinedDeck()
            } catch (e: Exception) {
                errorMessage.value = "Failed to load deck: ${e.message}"
            } finally {
                isLoading.value = false
            }
        }
    }

    fun togglePack(index: Int) {
        val s = _selectedPackIds.value.toMutableSet()
        if (s.contains(index)) s.remove(index) else s.add(index)
        _selectedPackIds.value = s
        createCombinedDeck()
    }
    fun selectAll() {
        _selectedPackIds.value = _packs.value.indices.toSet()
        createCombinedDeck()
    }
    fun selectNone() {
        _selectedPackIds.value = emptySet()
        createCombinedDeck()
    }

    private fun createCombinedDeck() {
        val whiteIdx = sortedSetOf<Int>()
        val blackIdx = sortedSetOf<Int>()
        _packs.value.forEachIndexed { i, p ->
            if (_selectedPackIds.value.contains(i)) {
                whiteIdx.addAll(p.white)
                blackIdx.addAll(p.black)
            }
        }
        val white = whiteIdx.mapNotNull { _allWhite.value.getOrNull(it) }
        val black = blackIdx.mapNotNull { _allBlack.value.getOrNull(it) }
        _deck.value = CompactDeck(white, black, "Selected Decks", "combined")
    }
}