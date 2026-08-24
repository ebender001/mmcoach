package dev.benderapps.mmcoach.services

/**
 * Back4App connection details -- the Android counterpart to
 * `App/BackendConfig.swift` in the iOS app. Same Back4App application, so
 * these are the same public client credentials as the iOS client ships
 * (not secrets; the Master Key stays server-side only). Parse SDK
 * bootstrap itself lives in [dev.benderapps.mmcoach.MMCoachApplication].
 */
object BackendConfig {
    const val APPLICATION_ID = "BpVzRIbSiAVGFo5V603geaEA6xlblztllwlIlZOd"
    const val CLIENT_KEY = "Dpi9vjS6zHNG8meRcU7J0DKAegJWGhNgRPTSqOSc"
    const val SERVER_URL = "https://parseapi.back4app.com"
}
