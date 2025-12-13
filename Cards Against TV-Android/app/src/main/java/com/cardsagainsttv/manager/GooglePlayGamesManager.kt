package com.cardsagainsttv.manager

import android.app.Activity
import android.content.Context
import android.util.Log
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.games.PlayGames
import com.google.android.gms.common.api.ApiException

/**
 * Simple Google Play Games Services manager for achievements
 */
class GooglePlayGamesManager private constructor() {

    // Track sign-in attempts to prevent loops
    private var signInAttemptCount = 0
    private val MAX_SIGN_IN_ATTEMPTS = 2

    companion object {
        private const val TAG = "PlayGamesManager"

        // Request codes for activity results
        const val RC_SIGN_IN = 9001
        const val RC_ACHIEVEMENT_UI = 9003

        // Achievement IDs - make sure this matches your Google Play Console
        const val ACHIEVEMENT_YER_A_WIZARD_MATE = "CgkIk_m47foFEAIQAQ"
        const val ACHIEVEMENT_ALL_I_WANT_FOR_CHRISTMAS = "CgkIk_m47foFEAIQAg"

        @Volatile
        private var INSTANCE: GooglePlayGamesManager? = null

        fun getInstance(): GooglePlayGamesManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: GooglePlayGamesManager().also { INSTANCE = it }
            }
        }
    }

    /**
     * Reset the sign-in counter
     * Call this when explicitly trying to sign in from a user action
     */
    fun resetSignInCounter() {
        signInAttemptCount = 0
        Log.d(TAG, "Sign-in counter reset")
    }

    /**
     * Initialize and sign in to Google Play Games if not already signed in
     * Simplified approach with better error handling
     */
    fun initializeAndSignIn(activity: Activity, callback: (Boolean) -> Unit) {
        try {
            // If we're already at max attempts, don't try again
            if (signInAttemptCount >= MAX_SIGN_IN_ATTEMPTS) {
                Log.w(TAG, "Too many sign-in attempts, aborting to prevent loops")
                callback(false)
                return
            }

            signInAttemptCount++

            // Check if Play Games app is installed
            val playGamesPackageName = "com.google.android.play.games"
            val playGamesInstalled = try {
                activity.packageManager.getPackageInfo(playGamesPackageName, 0)
                true
            } catch (e: Exception) {
                Log.e(TAG, "Google Play Games app not installed", e)
                false
            }

            if (!playGamesInstalled) {
                Log.w(TAG, "Google Play Games app not installed, skipping sign-in")
                callback(false)
                return
            }

            val gamesSignInClient = PlayGames.getGamesSignInClient(activity)

            // Use a simpler approach - just try to sign in
            gamesSignInClient.signIn()
                .addOnSuccessListener {
                    Log.d(TAG, "Successfully signed in to Play Games")
                    signInAttemptCount = 0 // Reset counter on success
                    callback(true)
                }
                .addOnFailureListener { e ->
                    if (e.message?.contains("DEVELOPER_ERROR") == true) {
                        Log.e(TAG, "Google Play Games configuration error. Please check your package name, SHA-1 fingerprint, and App ID in the Play Console.", e)
                    } else {
                        Log.e(TAG, "Failed to sign in to Play Games", e)
                    }
                    callback(false)
                }
        } catch (e: Exception) {
            Log.e(TAG, "Exception during sign-in process", e)
            callback(false)
        }
    }

    /**
     * Check if user is signed in to Google Play Games
     */
    fun isSignedIn(context: Context): Boolean {
        return try {
            val account = GoogleSignIn.getLastSignedInAccount(context)
            account != null
        } catch (e: Exception) {
            Log.e(TAG, "Error checking sign-in status", e)
            false
        }
    }

    /**
     * More reliable method to check Play Games authentication status
     */
    fun isPlayGamesSignedIn(activity: Activity, callback: (Boolean) -> Unit) {
        try {
            val gamesSignInClient = PlayGames.getGamesSignInClient(activity)
            gamesSignInClient.isAuthenticated.addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    val isAuthenticated = task.result.isAuthenticated
                    Log.d(TAG, "Play Games authentication status: $isAuthenticated")
                    callback(isAuthenticated)
                } else {
                    Log.e(TAG, "Failed to check Play Games authentication", task.exception)
                    callback(false)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking Play Games authentication", e)
            callback(false)
        }
    }

    /**
     * Unlock an achievement with simplified error handling
     */
    fun unlockAchievement(
        activity: Activity,
        achievementId: String,
        callback: ((Boolean, String?) -> Unit)? = null
    ) {
        try {
            val achievementsClient = PlayGames.getAchievementsClient(activity)

            // Just use the non-immediate method which is less likely to crash
            achievementsClient.unlock(achievementId)

            Log.d(TAG, "Achievement unlock request sent for: $achievementId")
            callback?.invoke(true, null)
        } catch (e: Exception) {
            Log.e(TAG, "Error unlocking achievement: $achievementId", e)
            callback?.invoke(false, e.message)
        }
    }

    /**
     * Unlock the "Yer' a wizard, mate" achievement with automatic sign-in
     */
    fun unlockWizardAchievement(activity: Activity, callback: ((Boolean, String?) -> Unit)? = null) {
        Log.d(TAG, "Attempting to unlock wizard achievement")

        // Check if we're already signed in first
        isPlayGamesSignedIn(activity) { isSignedIn ->
            Log.d(TAG, "Current Play Games sign-in status: $isSignedIn")

            if (isSignedIn) {
                unlockAchievement(activity, ACHIEVEMENT_YER_A_WIZARD_MATE, callback)
            } else {
                Log.d(TAG, "Not signed in, trying to sign in first")
                initializeAndSignIn(activity) { signInSuccess ->
                    if (signInSuccess) {
                        Log.d(TAG, "Sign-in successful, now unlocking achievement")
                        unlockAchievement(activity, ACHIEVEMENT_YER_A_WIZARD_MATE, callback)
                    } else {
                        Log.e(TAG, "Failed to sign in, cannot unlock achievement")
                        callback?.invoke(false, "Failed to sign in to Play Games")
                    }
                }
            }
        }
    }

    /**
     * Unlock the "All I Want For Christmas Is You" achievement with automatic sign-in
     */
    fun unlockChristmasAchievement(activity: Activity, callback: ((Boolean, String?) -> Unit)? = null) {
        Log.d(TAG, "Attempting to unlock Christmas achievement")

        isPlayGamesSignedIn(activity) { isSignedIn ->
            Log.d(TAG, "Current Play Games sign-in status: $isSignedIn")

            if (isSignedIn) {
                unlockAchievement(activity, ACHIEVEMENT_ALL_I_WANT_FOR_CHRISTMAS, callback)
            } else {
                Log.d(TAG, "Not signed in, trying to sign in first")
                initializeAndSignIn(activity) { signInSuccess ->
                    if (signInSuccess) {
                        Log.d(TAG, "Sign-in successful, now unlocking achievement")
                        unlockAchievement(activity, ACHIEVEMENT_ALL_I_WANT_FOR_CHRISTMAS, callback)
                    } else {
                        Log.e(TAG, "Failed to sign in, cannot unlock achievement")
                        callback?.invoke(false, "Failed to sign in to Play Games")
                    }
                }
            }
        }
    }

    /**
     * Force unlock the wizard achievement even if not signed in
     * This is a last resort method for debugging
     */
    fun forceUnlockWizardAchievement(activity: Activity, callback: ((Boolean, String?) -> Unit)? = null) {
        Log.d(TAG, "FORCE UNLOCK: Attempting to unlock wizard achievement regardless of sign-in")

        // First check if we're actually signed in to Google Play Games
        isPlayGamesSignedIn(activity) { isSignedIn ->
            if (isSignedIn) {
                Log.d(TAG, "FORCE UNLOCK: User is signed in, using standard unlock method")

                try {
                    // Use the achievementsClient to properly register with Google Play Games
                    val achievementsClient = PlayGames.getAchievementsClient(activity)

                    // First try to unlock immediately
                    achievementsClient.unlock(ACHIEVEMENT_YER_A_WIZARD_MATE)
                    Log.d(TAG, "FORCE UNLOCK: Achievement unlock request sent")

                    // Now try to get the achievementsIntent to make sure API is working
                    achievementsClient.achievementsIntent
                        .addOnSuccessListener {
                            Log.d(TAG, "FORCE UNLOCK: Successfully verified achievements API connection")
                            callback?.invoke(true, null)
                        }
                        .addOnFailureListener { e ->
                            Log.e(TAG, "FORCE UNLOCK: Failed to verify achievements API, but unlock might have worked", e)
                            callback?.invoke(true, null) // Assume it worked even if we can't verify
                        }
                } catch (e: Exception) {
                    Log.e(TAG, "FORCE UNLOCK: Error unlocking achievement", e)
                    callback?.invoke(false, e.message)
                }
            } else {
                // Not signed in, try to sign in first
                Log.d(TAG, "FORCE UNLOCK: User not signed in, attempting sign-in first")

                initializeAndSignIn(activity) { signInSuccess ->
                    if (signInSuccess) {
                        Log.d(TAG, "FORCE UNLOCK: Sign-in successful, now unlocking achievement")

                        try {
                            val achievementsClient = PlayGames.getAchievementsClient(activity)
                            achievementsClient.unlock(ACHIEVEMENT_YER_A_WIZARD_MATE)
                            Log.d(TAG, "FORCE UNLOCK: Achievement unlock request sent after sign-in")
                            callback?.invoke(true, null)
                        } catch (e: Exception) {
                            Log.e(TAG, "FORCE UNLOCK: Error unlocking achievement after sign-in", e)
                            callback?.invoke(false, e.message)
                        }
                    } else {
                        Log.e(TAG, "FORCE UNLOCK: Failed to sign in, cannot unlock achievement")
                        callback?.invoke(false, "Failed to sign in to Google Play Games")

                        // Show a message to let the user know they should sign in
                        try {
                            // Use Activity's context to show a toast
                            android.widget.Toast.makeText(
                                activity,
                                "Please sign in to Google Play Games to unlock achievements",
                                android.widget.Toast.LENGTH_LONG
                            ).show()
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to show toast", e)
                        }
                    }
                }
            }
        }
    }

    /**
     * Show the achievements UI with simplified error handling
     */
    fun showAchievements(activity: Activity) {
        try {
            PlayGames.getAchievementsClient(activity)
                .achievementsIntent
                .addOnSuccessListener { intent ->
                    try {
                        activity.startActivityForResult(intent, RC_ACHIEVEMENT_UI)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error starting achievements activity", e)
                    }
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to get achievements intent", e)
                }
        } catch (e: Exception) {
            Log.e(TAG, "Error showing achievements", e)
        }
    }
}