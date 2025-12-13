package com.cardsagainsttv.viewmodel

import android.app.Activity
import android.app.Application
import android.content.Context
import android.util.Log
import android.widget.Toast
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.cardsagainsttv.manager.GooglePlayGamesManager
import com.cardsagainsttv.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.io.InputStream

private val json = Json {
    ignoreUnknownKeys = true
    isLenient = true
    coerceInputValues = true
}

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

    private val _searchText = MutableStateFlow("")
    val searchText: StateFlow<String> = _searchText

    // Track when "select none" was just called
    private val _justSelectedNone = MutableStateFlow(false)
    val justSelectedNone: StateFlow<Boolean> = _justSelectedNone

    val errorMessage = MutableStateFlow<String?>(null)
    val isLoading = MutableStateFlow(false)

    // Track Google Play Games sign-in state to avoid repeated prompts
    private val _isSigningIn = MutableStateFlow(false)
    private val _isSignedIn = MutableStateFlow(false)
    private val _hasTriedSignIn = MutableStateFlow(false)

    val isSigningIn: StateFlow<Boolean> = _isSigningIn
    val isSignedIn: StateFlow<Boolean> = _isSignedIn
    val hasTriedSignIn: StateFlow<Boolean> = _hasTriedSignIn

    // Store the preference to track if achievement was already unlocked
    private val sharedPrefs = app.getSharedPreferences("achievements", Context.MODE_PRIVATE)
    private val PREF_WIZARD_ACHIEVEMENT = "wizard_achievement_unlocked"
    private val PREF_CHRISTMAS_ACHIEVEMENT = "christmas_achievement_unlocked"

    // Google Play Games Manager
    private val playGamesManager = GooglePlayGamesManager.getInstance()

    val canContinue: Boolean get() = _selectedPackIds.value.isNotEmpty()

    val filteredPacks: StateFlow<List<DeckPack>> = combine(_packs, _searchText) { packs, search ->
        if (search.isEmpty()) {
            packs.sortedBy { it.name }
        } else {
            packs.filter { pack ->
                pack.name.contains(search, ignoreCase = true)
            }.sortedBy { it.name }
        }
    }.stateIn(
        scope = viewModelScope,
        started = kotlinx.coroutines.flow.SharingStarted.WhileSubscribed(5000),
        initialValue = emptyList()
    )

    fun updateSearchText(text: String) {
        _searchText.value = text
    }

    fun load() {
        if (isLoading.value || _packs.value.isNotEmpty()) return
        viewModelScope.launch {
            isLoading.value = true
            try {
                val jsonStr = getApplication<Application>().assets.open("cah-all-compact.json").use(InputStream::readBytes).toString(Charsets.UTF_8)
                val jsonElement = Json.parseToJsonElement(jsonStr)
                val jsonObject = jsonElement.jsonObject

                jsonObject["white"]?.let { element ->
                    _allWhite.value = json.decodeFromJsonElement<List<String>>(element)
                }
                jsonObject["black"]?.let { element ->
                    _allBlack.value = json.decodeFromJsonElement<List<CompactBlack>>(element)
                }
                jsonObject["packs"]?.let { element ->
                    _packs.value = json.decodeFromJsonElement<List<DeckPack>>(element)
                }
                _selectedPackIds.value = _packs.value.indices.toSet() // Select all by default
                createCombinedDeck()
            } catch (e: Exception) {
                errorMessage.value = "Failed to load deck: ${e.message}"
            } finally {
                isLoading.value = false
            }
        }
    }

    /**
     * Initialize Google Play Games when the activity is available
     * Simplified approach with better error handling
     */
    fun initializePlayGames(activity: Activity) {
        if (_isSigningIn.value) {
            Log.d("DeckLoader", "Sign-in already in progress, not starting another")
            return
        }

        Log.d("DeckLoader", "Starting Google Play Games sign-in")
        _isSigningIn.value = true
        _hasTriedSignIn.value = true

        playGamesManager.initializeAndSignIn(activity) { success ->
            Log.d("DeckLoader", "Google Play Games sign-in result: $success")
            _isSigningIn.value = false
            _isSignedIn.value = success

            if (success) {
                Log.d("DeckLoader", "Sign-in successful, checking for achievements")
                checkForAchievementsInCurrentSelection(activity)
            } else {
                val prefs = getApplication<Application>().getSharedPreferences("gpg_prefs", Context.MODE_PRIVATE)
                val hasShownSignInMessage = prefs.getBoolean("has_shown_sign_in_message", false)

                if (!hasShownSignInMessage) {
                    Log.d("DeckLoader", "Showing sign-in failed message")
                    showToast("Play Games sign-in failed. Achievements won't be tracked.")
                    prefs.edit().putBoolean("has_shown_sign_in_message", true).apply()
                }
            }
        }
    }

    fun togglePack(activity: Activity, index: Int) {
        val s = _selectedPackIds.value.toMutableSet()
        if (s.contains(index)) {
            s.remove(index)
        } else {
            s.add(index)
            _justSelectedNone.value = false
            // Let the GooglePlayGamesManager handle the sign-in check
            checkForAchievement(activity, index)
        }
        _selectedPackIds.value = s
        createCombinedDeck()
    }

    fun selectAll(activity: Activity) {
        _selectedPackIds.value = _packs.value.indices.toSet()
        _justSelectedNone.value = false
        createCombinedDeck()
        // Let the GooglePlayGamesManager handle the sign-in check
        checkForAchievementsInCurrentSelection(activity)
    }

    fun selectNone() {
        _selectedPackIds.value = emptySet()
        _justSelectedNone.value = true
        createCombinedDeck()
        Log.d("DeckLoader", "All packs deselected, marked justSelectedNone=true")
    }

    private fun checkForAchievement(activity: Activity, packIndex: Int) {
        if (packIndex >= 0 && packIndex < _packs.value.size) {
            val pack = _packs.value[packIndex]
            if (isCardsAgainstMugglesPack(pack)) {
                unlockWizardAchievement(activity)
            }
            if (isCardsAgainstChristmasPack(pack)) {
                unlockChristmasAchievement(activity)
            }
        }
    }

    private fun checkForAchievementsInCurrentSelection(activity: Activity) {
        val hasMugglesPack = _selectedPackIds.value.any { index ->
            index >= 0 && index < _packs.value.size && isCardsAgainstMugglesPack(_packs.value[index])
        }
        if (hasMugglesPack) {
            unlockWizardAchievement(activity)
        }

        val hasChristmasPack = _selectedPackIds.value.any { index ->
            index >= 0 && index < _packs.value.size && isCardsAgainstChristmasPack(_packs.value[index])
        }
        if (hasChristmasPack) {
            unlockChristmasAchievement(activity)
        }
    }

    private fun isCardsAgainstMugglesPack(pack: DeckPack): Boolean {
        return pack.name.lowercase().contains("muggles")
    }

    private fun isCardsAgainstChristmasPack(pack: DeckPack): Boolean {
        return pack.name.lowercase().contains("christmas")
    }

    private fun unlockWizardAchievement(activity: Activity) {
        val wasAlreadyUnlocked = sharedPrefs.getBoolean(PREF_WIZARD_ACHIEVEMENT, false)
        if (wasAlreadyUnlocked) {
            showToast("Wizard achievement already unlocked!")
            return
        }

        playGamesManager.unlockWizardAchievement(activity) { success, error ->
            viewModelScope.launch {
                if (success) {
                    sharedPrefs.edit().putBoolean(PREF_WIZARD_ACHIEVEMENT, true).apply()
                    showToast("🧙‍♂️ Achievement Unlocked: Yer' a wizard, mate!")
                } else {
                    Log.e("DeckLoader", "Failed to unlock wizard achievement: $error")
                }
            }
        }
    }

    private fun unlockChristmasAchievement(activity: Activity) {
        val wasAlreadyUnlocked = sharedPrefs.getBoolean(PREF_CHRISTMAS_ACHIEVEMENT, false)
        if (wasAlreadyUnlocked) {
            showToast("Christmas achievement already unlocked!")
            return
        }

        playGamesManager.unlockChristmasAchievement(activity) { success, error ->
            viewModelScope.launch {
                if (success) {
                    sharedPrefs.edit().putBoolean(PREF_CHRISTMAS_ACHIEVEMENT, true).apply()
                    showToast("🎄 Achievement Unlocked: All I Want For Christmas Is You!")
                } else {
                    Log.e("DeckLoader", "Failed to unlock Christmas achievement: $error")
                }
            }
        }
    }

    private fun showToast(message: String) {
        Toast.makeText(getApplication<Application>(), message, Toast.LENGTH_SHORT).show()
    }

    fun showAchievements(activity: Activity) {
        playGamesManager.showAchievements(activity)
    }

    fun offerToSignIn(activity: Activity) {
        if (!_isSigningIn.value) {
            try {
                val dialog = androidx.appcompat.app.AlertDialog.Builder(activity)
                    .setTitle("Google Play Games")
                    .setMessage("Sign in to Google Play Games to unlock achievements?")
                    .setPositiveButton("Sign In") { _, _ ->
                        initializePlayGames(activity)
                    }
                    .setNegativeButton("Not Now", null)
                    .create()
                dialog.show()
            } catch (e: Exception) {
                Log.e("DeckLoader", "Error showing sign-in dialog", e)
                showToast("Failed to show sign-in dialog")
            }
        } else {
            showToast("Sign-in already in progress")
        }
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