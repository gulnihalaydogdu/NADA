import SwiftUI

private enum MainTab: Hashable {
    case discover, likes, matches, profile
}

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SplashController.self) private var splash
    @State private var showsPushPrompt = false
    @State private var selectedTab: MainTab = .discover

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Discover", systemImage: "sparkles", value: MainTab.discover) {
                DiscoverFeedView()
            }

            Tab("Likes", systemImage: "heart", value: MainTab.likes) {
                LikesInboxView()
            }
            .badge(auth.incomingLikerCount)

            Tab("Matches", systemImage: "bubble.left.and.bubble.right", value: MainTab.matches) {
                PlaceholderTabView(
                    title: "Matches",
                    systemImage: "bubble.left.and.bubble.right",
                    message: "Chat with mutual matches here."
                )
            }

            Tab("Profile", systemImage: "person.crop.circle", value: MainTab.profile) {
                ProfileTabView()
            }
        }
        .tint(NADATheme.brand)
        .task(id: pushRegistrationToken) {
            guard !splash.isShowingSplash, auth.isDiscoverLaunchReady else { return }
            showsPushPrompt = await auth.shouldOfferPushPrompt()
        }
        .sheet(isPresented: $showsPushPrompt) {
            PushPermissionPromptSheet(
                onEnable: {
                    await auth.enablePushFromPrompt()
                    showsPushPrompt = false
                },
                onSkip: {
                    showsPushPrompt = false
                }
            )
        }
    }

    private var pushRegistrationToken: String {
        "\(splash.isShowingSplash ? "1" : "0")|\(auth.isDiscoverLaunchReady ? "1" : "0")"
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
        .environment(SplashController())
}
