//
//  BackendConfig.swift
//  MMCoach
//
//  Back4App connection configuration and SDK bootstrap.
//

import Foundation
import ParseSwift

/// Back4App connection details and Parse-Swift bootstrap.
///
/// `applicationId` and `clientKey` are the app's public client credentials
/// (the mobile-app equivalent of a Firebase `GoogleService-Info.plist`) --
/// they identify this app to Back4App and are meant to ship inside the
/// client binary. They are **not** secrets. Never add the Master Key or
/// REST API Key here; those must stay server-side only.
enum BackendConfig {
    static let applicationId = "BpVzRIbSiAVGFo5V603geaEA6xlblztllwlIlZOd"
    static let clientKey = "Dpi9vjS6zHNG8meRcU7J0DKAegJWGhNgRPTSqOSc"
    static let serverURL = URL(string: "https://parseapi.back4app.com")!

    /// Configures the Parse-Swift SDK. Call once at app launch before any
    /// `BackendService` call is made.
    static func configureParse() {
        ParseSwift.initialize(applicationId: applicationId,
                               clientKey: clientKey,
                               serverURL: serverURL)
    }
}
