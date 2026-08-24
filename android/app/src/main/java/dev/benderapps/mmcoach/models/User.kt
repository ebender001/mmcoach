package dev.benderapps.mmcoach.models

import com.parse.ParseUser

/**
 * The app's Parse User type. Mirrors iOS `Models/User.swift`. `ParseUser`
 * already covers username/email/password/authData; the only MVP-specific
 * addition is `googleUserIdentifier`, the stable id repeat Google
 * sign-ins are matched back to this account on (the Android counterpart
 * to iOS's `appleUserIdentifier` -- see [dev.benderapps.mmcoach.models.AuthenticatedUser]).
 *
 * Must be registered with `ParseObject.registerSubclass(User::class.java)`
 * before `Parse.initialize(...)`, same lifecycle point as the iOS
 * `ParseSwift.initialize` call in `MMCoachApplication`.
 */
class User : ParseUser() {
    var googleUserIdentifier: String?
        get() = getString(KEY_GOOGLE_USER_IDENTIFIER)
        set(value) {
            if (value != null) put(KEY_GOOGLE_USER_IDENTIFIER, value) else remove(KEY_GOOGLE_USER_IDENTIFIER)
        }

    companion object {
        private const val KEY_GOOGLE_USER_IDENTIFIER = "googleUserIdentifier"
    }
}
