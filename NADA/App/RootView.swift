import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            if !auth.isAuthenticated {
                WelcomeView()
            } else if !auth.hasCompletedFriendsIntent {
                FriendsIntentView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: auth.hasCompletedFriendsIntent)
    }
}

#Preview {
    RootView()
        .environment(AuthManager())
}
