//
//  MMCoachApp.swift
//  MMCoach
//
//  Created by Edward Bender on 8/16/26.
//

import SwiftUI

@main
struct MMCoachApp: App {
    init() {
        BackendConfig.configureParse()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.michiganBlueText)
        }
    }
}
