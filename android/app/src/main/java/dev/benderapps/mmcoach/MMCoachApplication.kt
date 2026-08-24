package dev.benderapps.mmcoach

import android.app.Application
import com.parse.Parse
import com.parse.ParseObject
import dev.benderapps.mmcoach.models.User
import dev.benderapps.mmcoach.services.BackendConfig

class MMCoachApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Must run before Parse.initialize -- see User.kt.
        ParseObject.registerSubclass(User::class.java)
        Parse.initialize(
            Parse.Configuration.Builder(this)
                .applicationId(BackendConfig.APPLICATION_ID)
                .clientKey(BackendConfig.CLIENT_KEY)
                .server(BackendConfig.SERVER_URL)
                .build()
        )
    }
}
