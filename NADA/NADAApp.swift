import SwiftUI
import UIKit
import FirebaseCore

@main
struct NADAApp: App {
    @State private var authManager = AuthManager()
    @State private var splashController = SplashController()

    init() {
        FirebaseAuthService.configureAtLaunch()

        // AsyncImage + ImagePrefetcher ride the shared URLCache; the tiny default
        // (~a few MB) evicts Discover photos almost immediately. 64MB RAM / 256MB disk
        // keeps recently seen profiles instant and offline-friendly.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )

        UIWindow.appearance().backgroundColor = UIColor(
            red: 0.980,
            green: 0.973,
            blue: 0.965,
            alpha: 1
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .environment(splashController)
        }
    }
}
