//
//  MMCoachApp.swift
//  MMCoach
//
//  Created by Edward Bender on 8/16/26.
//

import SwiftUI
import TipKit

@main
struct MMCoachApp: App {
    init() {
        BackendConfig.configureParse()
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault),
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.michiganBlueText)
        }
    }
}
