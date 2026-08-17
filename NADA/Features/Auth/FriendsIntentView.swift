import SwiftUI

struct FriendsIntentView: View {
    @Environment(AuthManager.self) private var auth
    @State private var showLeaveConfirm = false

    private enum Layout {
        static let heroImage = "FriendsIntentHero"
        static let brandInk = Color(red: 0.867, green: 0.867, blue: 0.867) // #DDDDDD
        static let headlineSize: CGFloat = 28
        static let sublineSize: CGFloat = 16
        static let copyStackSpacing: CGFloat = 10
        static let ctaHorizontal: CGFloat = 24
        static let ctaStackSpacing: CGFloat = 14
        static let ctaBottomExtra: CGFloat = 20
        static let copyBottomPadding: CGFloat = 20
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let topPad = max(geometry.safeAreaInsets.top, 47) + 24
            let bottomPad = max(geometry.safeAreaInsets.bottom + Layout.ctaBottomExtra, 32)

            ZStack(alignment: .top) {
                heroBackground(size: size)

                VStack(spacing: 0) {
                    Spacer(minLength: topPad)

                    Spacer(minLength: 0)

                    copyBlock
                        .padding(.bottom, Layout.copyBottomPadding)

                    ctaBlock
                        .padding(.horizontal, Layout.ctaHorizontal)
                        .padding(.bottom, bottomPad)
                }
                .frame(width: size.width, height: size.height, alignment: .top)

                NADAOnboardingNavBar(
                    onHero: true,
                    isBusy: auth.isBusy,
                    onBack: { showLeaveConfirm = true },
                    onSkip: { Task { await auth.skipRemainingOnboarding() } }
                )
                .padding(.horizontal, 20)
                .padding(.top, max(geometry.safeAreaInsets.top, 47) + 4)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .confirmationDialog("Leave setup?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll be logged out. Your account stays — log in anytime to finish.")
        }
    }

    private func heroBackground(size: CGSize) -> some View {
        ZStack {
            Color.black

            Image(Layout.heroImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height, alignment: .center)
                .clipped()

            RadialGradient(
                colors: [
                    .clear,
                    .black.opacity(0.22),
                    .black.opacity(0.62)
                ],
                center: .center,
                startRadius: 30,
                endRadius: max(size.width, size.height) * 0.72
            )
            .frame(width: size.width, height: size.height)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .black.opacity(0.08), location: 0.28),
                    .init(color: .black.opacity(0.20), location: 0.48),
                    .init(color: .black.opacity(0.55), location: 0.68),
                    .init(color: .black.opacity(0.82), location: 0.84),
                    .init(color: .black.opacity(0.92), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var copyBlock: some View {
        VStack(spacing: Layout.copyStackSpacing) {
            Text("You're here for friendship.")
                .font(.system(size: Layout.headlineSize, weight: .bold))
                .foregroundStyle(Layout.brandInk)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                .fixedSize(horizontal: false, vertical: true)

            Text("NADA is for friendship, shared plans and good company — never dating or flirting.")
                .font(.system(size: Layout.sublineSize, weight: .medium))
                .foregroundStyle(Layout.brandInk.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
    }

    private var ctaBlock: some View {
        Button {
            Task { await auth.completeFriendsIntent() }
        } label: {
            if auth.isBusy {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: NADATheme.Layout.ctaMinHeight)
            } else {
                Text("Continue")
            }
        }
        .buttonStyle(NADAPrimaryButtonStyle(isEnabled: !auth.isBusy))
        .allowsHitTesting(!auth.isBusy)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    FriendsIntentView()
        .environment(AuthManager())
}
