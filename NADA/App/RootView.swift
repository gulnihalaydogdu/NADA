import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SplashController.self) private var splash
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            NADAScreenBackground()
            routedContent

            if splash.isShowingSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: splash.isShowingSplash)
        .task {
            auth.bootstrap()
            splash.handleColdStart()
        }
        .onChange(of: scenePhase) { _, current in
            splash.handleScenePhase(current)
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        if !auth.isAuthenticated {
            WelcomeView()
        } else if !auth.hasCompletedFriendsIntent {
            FriendsIntentView()
        } else {
            MainTabView()
        }
    }
}

#Preview {
    RootView()
        .environment(AuthManager())
        .environment(SplashController())
}
