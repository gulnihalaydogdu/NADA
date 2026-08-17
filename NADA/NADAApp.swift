import SwiftUI
import UIKit
import FirebaseCore

@main
struct NADAApp: App {
    @State private var authManager = AuthManager()
    @State private var splashController = SplashController()

    init() {
        FirebaseAuthService.configureAtLaunch()

        URLCache.shared = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 80 * 1024 * 1024
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
