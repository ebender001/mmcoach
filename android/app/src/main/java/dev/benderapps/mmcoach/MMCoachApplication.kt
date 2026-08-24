package dev.benderapps.mmcoach

import android.app.Application
import com.parse.Parse
import dev.benderapps.mmcoach.services.BackendConfig

class MMCoachApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Parse.initialize(
            Parse.Configuration.Builder(this)
                .applicationId(BackendConfig.APPLICATION_ID)
                .clientKey(BackendConfig.CLIENT_KEY)
                .server(BackendConfig.SERVER_URL)
                .build()
        )
    }
}
