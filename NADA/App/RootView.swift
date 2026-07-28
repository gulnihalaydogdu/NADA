import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        ZStack {
            NADAScreenBackground()

            if auth.isBootstrapped {
                routedContent
                    .transition(.opacity)
            } else {
                bootSplash
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isBootstrapped)
        .animation(.easeInOut(duration: 0.25), value: auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: auth.hasCompletedFriendsIntent)
        .task {
            auth.bootstrap()
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

    private var bootSplash: some View {
        VStack(spacing: 12) {
            Image("NADALogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Not a Dating App!")
                .font(NADATheme.captionFont.weight(.semibold))
                .foregroundStyle(NADATheme.brandPressed)
        }
    }
}

#Preview {
    RootView()
        .environment(AuthManager())
}
