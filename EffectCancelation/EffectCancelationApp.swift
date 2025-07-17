//
//  EffectCancelationApp.swift
//  EffectCancelation
//
//  Created by Marcus Wu on 2025/7/17.
//

import SwiftUI

@main
struct EffectCancelationApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(store: .init(initialState: .init()) {
                ContentFeature()
            })
        }
    }
}
