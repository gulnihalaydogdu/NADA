import SwiftUI

enum WelcomeLayout {
    static let brandTopExtra: CGFloat = 32
    static let brandStackSpacing: CGFloat = 6
    static let wordmarkWidth: CGFloat = 151   // was 168 (−10%)
    static let taglineWidth: CGFloat = 207    // was 230 (−10%)
    /// Soft off-white for brand marks on the photo hero.
    static let brandInk = Color(red: 0.867, green: 0.867, blue: 0.867) // #DDDDDD
    static let copyStackSpacing: CGFloat = 10
    static let headlineSize: CGFloat = 32
    static let sublineSize: CGFloat = 16
    static let ctaHorizontalPadding: CGFloat = 24
    static let ctaStackSpacing: CGFloat = 14
    static let ctaBottomExtra: CGFloat = 20
    static let copyBottomPadding: CGFloat = 20
}

struct WelcomeView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let size = geometry.size
                let metrics = WelcomeLayoutMetrics(size: size, safeArea: geometry.safeAreaInsets)

                ZStack {
                    welcomeHeroBackground(size: size)

                    VStack(spacing: 0) {
                        welcomeBrandHeader(metrics: metrics)
                            .padding(.top, metrics.brandTopPadding)

                        Spacer(minLength: 0)

                        heroCopy(metrics: metrics)
                            .padding(.bottom, WelcomeLayout.copyBottomPadding)

                        ctaBlock(metrics: metrics)
                    }
                    .frame(width: size.width, height: size.height, alignment: .top)
                }
                .frame(width: size.width, height: size.height)
            }
            .ignoresSafeArea()
            .navigationBarHidden(true)
        }
    }

    /// Full-bleed photo centered in the screen bounds, then vignette + scrim.
    private func welcomeHeroBackground(size: CGSize) -> some View {
        ZStack {
            Color.black

            Image(WelcomeContent.heroImage)
                .resizable()
                .scaledToFill()
                // Explicit size + center alignment prevents the classic
                // scaledToFill leading/trailing crop shift in GeometryReader.
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

            // Stronger bottom scrim so headline + CTAs sit on near-black.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.40), location: 0),
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
    }

    private func welcomeBrandHeader(metrics: WelcomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.brandStackSpacing) {
            Image("WelcomeNADAWordmark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: metrics.wordmarkWidth, height: metrics.wordmarkHeight)
                .foregroundStyle(WelcomeLayout.brandInk)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .accessibilityLabel("NADA")

            Image("WelcomeNotADatingApp")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: metrics.taglineWidth, height: metrics.taglineHeight)
                .foregroundStyle(WelcomeLayout.brandInk.opacity(0.92))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
                .accessibilityLabel("Not a dating app")
        }
        .frame(maxWidth: .infinity)
    }

    private func heroCopy(metrics: WelcomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.copyStackSpacing) {
            Text(WelcomeContent.headline)
                .font(.system(size: metrics.headlineSize, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                .fixedSize(horizontal: false, vertical: true)

            Text(WelcomeContent.subline)
                .font(.system(size: metrics.sublineSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }

    private func ctaBlock(metrics: WelcomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.ctaStackSpacing) {
            if !auth.isFirebaseReady {
                Text("Add GoogleService-Info.plist to enable Firebase")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.72))
                    .multilineTextAlignment(.center)
            }

            NavigationLink {
                SignUpView()
            } label: {
                Text("Create account")
            }
            .buttonStyle(NADAPrimaryButtonStyle())

            NavigationLink {
                SignInView()
            } label: {
                signInPrompt
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, metrics.ctaHorizontalPadding)
        .padding(.bottom, metrics.ctaBottomPadding)
        .frame(maxWidth: .infinity)
    }

    private var signInPrompt: some View {
        HStack(spacing: 4) {
            Text("Already have an account?")
                .font(NADATheme.bodyFont)
                .foregroundStyle(.white.opacity(0.78))
            Text("Log in")
                .font(NADATheme.bodyFont.weight(.semibold))
                .foregroundStyle(.white)
                .underline()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
    }
}

private struct WelcomeLayoutMetrics {
    private static let wordmarkAspect: CGFloat = 346.0 / 150.0
    private static let taglineAspect: CGFloat = 468.0 / 60.0

    let brandTopPadding: CGFloat
    let brandStackSpacing: CGFloat
    let wordmarkWidth: CGFloat
    let wordmarkHeight: CGFloat
    let taglineWidth: CGFloat
    let taglineHeight: CGFloat
    let copyStackSpacing: CGFloat
    let headlineSize: CGFloat
    let sublineSize: CGFloat
    let ctaStackSpacing: CGFloat
    let ctaHorizontalPadding: CGFloat
    let ctaBottomPadding: CGFloat

    init(size: CGSize, safeArea: EdgeInsets) {
        let width = max(size.width, 393)
        let widthScale = min(max(width / 393, 0.9), 1.12)

        brandTopPadding = max(safeArea.top, 47) + WelcomeLayout.brandTopExtra
        brandStackSpacing = WelcomeLayout.brandStackSpacing
        wordmarkWidth = WelcomeLayout.wordmarkWidth * widthScale
        wordmarkHeight = wordmarkWidth / Self.wordmarkAspect
        taglineWidth = WelcomeLayout.taglineWidth * widthScale
        taglineHeight = taglineWidth / Self.taglineAspect
        copyStackSpacing = WelcomeLayout.copyStackSpacing
        headlineSize = WelcomeLayout.headlineSize * widthScale
        sublineSize = WelcomeLayout.sublineSize
        ctaStackSpacing = WelcomeLayout.ctaStackSpacing
        ctaHorizontalPadding = WelcomeLayout.ctaHorizontalPadding
        ctaBottomPadding = max(safeArea.bottom + WelcomeLayout.ctaBottomExtra, 32)
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environment(AuthManager())
        .task {
            FirebaseAuthService.configureAtLaunch()
        }
}
