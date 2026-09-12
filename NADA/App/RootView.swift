import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SplashController.self) private var splash
    @Environment(\.scenePhase) private var scenePhase

    /// Keeps the splash up until the stored session is known, and — when launching
    /// into Discover — until the first feed photo is in cache.
    private var showsSplash: Bool {
        splash.isShowingSplash || !auth.isSessionResolved || !auth.isDiscoverLaunchReady
    }

    var body: some View {
        ZStack {
            if auth.isSessionResolved {
                ZStack {
                    NADAScreenBackground()
                    routedContent
                }
            }

            if showsSplash {
                LaunchSplashView()
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
        } else if auth.hasCompletedProfileWizard {
            MainTabView()
        } else if !auth.hasCompletedBasicProfile || auth.isRevisitingBasicProfile {
            BasicProfileSetupView()
        } else {
            ProfileSetupWizardView()
        }
    }
}

#Preview {
    RootView()
        .environment(AuthManager())
        .environment(SplashController())
        .environment(PushRouter.shared)
}
