import SwiftUI
import UIKit
import FirebaseCore

@main
struct NADAApp: App {
    @State private var authManager = AuthManager()
    @State private var splashController = SplashController()

    init() {
        FirebaseAuthService.configureAtLaunch()

        UIWindow.appearance().backgroundColor = UIColor(
            red: 0.969,
            green: 0.961,
            blue: 0.980,
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
