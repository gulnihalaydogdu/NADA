//
//  NADAApp.swift
//  NADA
//

import SwiftUI

@main
struct NADAApp: App {
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
        }
    }
}
