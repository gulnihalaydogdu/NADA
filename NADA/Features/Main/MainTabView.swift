import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            PlaceholderTabView(
                title: "Discover",
                systemImage: "sparkles",
                message: "Nearby profiles will show up here. Coming in Week 3."
            )
            .tabItem { Label("Discover", systemImage: "sparkles") }

            PlaceholderTabView(
                title: "Likes",
                systemImage: "heart",
                message: "People who liked you will appear here."
            )
            .tabItem { Label("Likes", systemImage: "heart") }

            PlaceholderTabView(
                title: "Matches",
                systemImage: "bubble.left.and.bubble.right",
                message: "Chat with mutual matches here."
            )
            .tabItem { Label("Matches", systemImage: "bubble.left.and.bubble.right") }

            ProfileTabView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(NADATheme.brand)
    }
}

private struct PlaceholderTabView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ZStack {
            NADAScreenBackground()

            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(NADATheme.brand)
                    .padding(20)
                    .background(NADATheme.brandSoft)
                    .clipShape(Circle())

                Text(title)
                    .font(NADATheme.displayFont)
                    .foregroundStyle(NADATheme.ink)

                Text(message)
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}

private struct ProfileTabView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        ZStack {
            NADAScreenBackground()

            VStack(spacing: 20) {
                Image("SplashMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let user = auth.currentUser {
                    Text(user.displayName ?? user.email ?? "User")
                        .font(NADATheme.titleFont)
                        .foregroundStyle(NADATheme.ink)
                    if let email = user.email {
                        Text(email)
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.secondaryInk)
                    }
                }

                Text("Profile setup coming in Week 2.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)

                Button("Sign out") {
                    auth.signOut()
                }
                .buttonStyle(NADASecondaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
}
