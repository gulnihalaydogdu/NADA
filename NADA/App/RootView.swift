import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SplashController.self) private var splash
    @Environment(\.scenePhase) private var scenePhase

    /// Keeps the splash up until the stored session is known, so launch never
    /// routes through a screen the user has already completed.
    private var showsSplash: Bool {
        splash.isShowingSplash || !auth.isSessionResolved
    }

    var body: some View {
        Group {
            if showsSplash {
                LaunchSplashView()
            } else {
                ZStack {
                    NADAScreenBackground()
                    routedContent
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsSplash)
        .task {
            splash.handleColdStart()
            auth.bootstrap()
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
        } else if !auth.hasCompletedBasicProfile {
            BasicProfileSetupView()
        } else if !auth.hasCompletedProfileWizard {
            ProfileSetupWizardView()
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
