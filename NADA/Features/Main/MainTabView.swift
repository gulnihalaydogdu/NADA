import SwiftUI

private enum MainTab: Hashable {
    case discover, likes, matches, profile
}

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SplashController.self) private var splash
    @Environment(PushRouter.self) private var pushRouter
    @State private var showsPushPrompt = false
    @State private var selectedTab: MainTab = .discover
    @State private var mutualMoment: MutualClickSnapshot?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Discover", systemImage: "sparkles", value: MainTab.discover) {
                DiscoverFeedView()
            }

            Tab("Clicks", systemImage: "heart", value: MainTab.likes) {
                LikesInboxView()
            }
            .badge(auth.incomingLikerCount)

            Tab("Mutuals", systemImage: "bubble.left.and.bubble.right", value: MainTab.matches) {
                MatchesListView()
            }

            Tab("Profile", systemImage: "person.crop.circle", value: MainTab.profile) {
                ProfileTabView()
            }
        }
        .tint(NADATheme.brand)
        .overlay {
            if let mutualMoment {
                MutualClickMomentView(snapshot: mutualMoment)
                    .padding(.horizontal, 44)
                    .offset(y: -28)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.28), value: mutualMoment)
        .environment(\.openMatchesTab) {
            selectedTab = .matches
        }
        .environment(\.presentMutualClickMoment, presentMutualClickMoment)
        .onAppear(perform: applyPendingPushRoute)
        .onChange(of: pushRouter.pending) { _, _ in
            applyPendingPushRoute()
        }
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

    @MainActor
    private func presentMutualClickMoment(_ snapshot: MutualClickSnapshot) async {
        guard mutualMoment == nil else {
            selectedTab = .matches
            return
        }
        mutualMoment = snapshot
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        selectedTab = .matches
        try? await Task.sleep(nanoseconds: 180_000_000)
        mutualMoment = nil
    }

    private func applyPendingPushRoute() {
        guard let route = pushRouter.consumeIfPresent() else { return }
        switch route {
        case .likes:
            selectedTab = .likes
        case .matches:
            selectedTab = .matches
        }
    }
}

private struct OpenMatchesTabKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openMatchesTab: () -> Void {
        get { self[OpenMatchesTabKey.self] }
        set { self[OpenMatchesTabKey.self] = newValue }
    }

    var presentMutualClickMoment: (MutualClickSnapshot) async -> Void {
        get { self[PresentMutualClickMomentKey.self] }
        set { self[PresentMutualClickMomentKey.self] = newValue }
    }
}

private struct PresentMutualClickMomentKey: EnvironmentKey {
    static let defaultValue: (MutualClickSnapshot) async -> Void = { _ in }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(SplashController())
        .environment(PushRouter.shared)
}
