import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DiscoverFeedView()
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

#Preview {
    MainTabView()
        .environment(AuthManager())
}
