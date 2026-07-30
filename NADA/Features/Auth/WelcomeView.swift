import SwiftUI

/// Tweak welcome screen layout here — all values are in points.
enum WelcomeLayout {
    // MARK: Logo block
    static let brandTopExtra: CGFloat = 8          // below safe area; ↑ moves logo down
    static let brandStackSpacing: CGFloat = 4      // gap between NADA and tagline
    static let wordmarkWidth: CGFloat = 190        // ↑ bigger NADA logo
    static let taglineWidth: CGFloat = 250         // ↑ bigger "Not a dating app"

    // MARK: Illustration
    static let gapAfterBrand: CGFloat = 8          // logo → sketch
    static let sketchHeightRatio: CGFloat = 0.36   // sketch height as % of screen
    static let sketchMinHeight: CGFloat = 220
    static let sketchMaxHeight: CGFloat = 330
    static let sketchHorizontalPadding: CGFloat = 6
    static let sketchShiftRatio: CGFloat = 0.10    // ↑ reveals more of the top

    // MARK: Dots and copy
    static let gapAfterSketch: CGFloat = 16        // sketch → dots
    static let gapAfterDots: CGFloat = 22          // dots → headline
    static let copyStackSpacing: CGFloat = 10
    static let headlineSize: CGFloat = 30
    static let sublineSize: CGFloat = 16

    // MARK: CTA dock
    static let minContentSpacer: CGFloat = 16      // copy → CTA; ↑ pushes CTA down
    static let ctaCornerRadius: CGFloat = 32
    static let ctaTopPadding: CGFloat = 24
    static let ctaBottomExtra: CGFloat = 16
    static let ctaHorizontalPadding: CGFloat = 24
    static let ctaStackSpacing: CGFloat = 12
}

struct WelcomeView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let metrics = WelcomeLayoutMetrics(
                    size: geometry.size,
                    safeArea: geometry.safeAreaInsets
                )

                ZStack {
                    NADAScreenBackground(showBottomBlob: false)

                    VStack(spacing: 0) {
                        welcomeBrandHeader(metrics: metrics)
                            .padding(.top, metrics.brandTopPadding)

                        WelcomeIllustration(
                            height: metrics.sketchHeight,
                            horizontalPadding: metrics.sketchHorizontalPadding,
                            verticalShift: metrics.sketchShift
                        )
                        .padding(.top, metrics.gapAfterBrand)

                        pageIndicator
                            .padding(.top, metrics.gapAfterSketch)

                        heroCopy(metrics: metrics)
                            .padding(.top, metrics.gapAfterDots)

                        Spacer(minLength: metrics.minContentSpacer)

                        ctaDock(metrics: metrics)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarHidden(true)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == 0 ? NADATheme.brand : NADATheme.hairline)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private func welcomeBrandHeader(metrics: WelcomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.brandStackSpacing) {
            Image("WelcomeNADAWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: metrics.wordmarkWidth, height: metrics.wordmarkHeight)
                .accessibilityLabel("NADA")

            Image("WelcomeNotADatingApp")
                .resizable()
                .scaledToFit()
                .frame(width: metrics.taglineWidth, height: metrics.taglineHeight)
                .accessibilityLabel("Not a dating app")
        }
        .frame(maxWidth: .infinity)
    }

    private func heroCopy(metrics: WelcomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.copyStackSpacing) {
            Text(WelcomeContent.headline)
                .font(.system(size: metrics.headlineSize, weight: .bold))
                .foregroundStyle(NADATheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(WelcomeContent.subline)
                .font(.system(size: metrics.sublineSize, weight: .regular))
                .foregroundStyle(NADATheme.warmSecondaryInk)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
    }

    private func ctaDock(metrics: WelcomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.ctaStackSpacing) {
            if !auth.isFirebaseReady {
                Text("Add GoogleService-Info.plist to enable Firebase")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
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
        .padding(.top, metrics.ctaTopPadding)
        .padding(.bottom, metrics.ctaBottomPadding)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: metrics.ctaCornerRadius,
                    topTrailing: metrics.ctaCornerRadius
                ),
                style: .continuous
            )
            .fill(NADATheme.surface.opacity(0.96))
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var signInPrompt: some View {
        HStack(spacing: 4) {
            Text("Already have an account?")
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)
            Text("Log in")
                .font(NADATheme.bodyFont.weight(.semibold))
                .foregroundStyle(NADATheme.brandPressed)
                .underline()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

private struct WelcomeLayoutMetrics {
    /// Intrinsic aspect ratios (width ÷ height) of the wordmark PNGs.
    private static let wordmarkAspect: CGFloat = 346.0 / 150.0
    private static let taglineAspect: CGFloat = 468.0 / 60.0

    let brandTopPadding: CGFloat
    let brandStackSpacing: CGFloat
    let wordmarkWidth: CGFloat
    let wordmarkHeight: CGFloat
    let taglineWidth: CGFloat
    let taglineHeight: CGFloat
    let gapAfterBrand: CGFloat
    let sketchHeight: CGFloat
    let sketchHorizontalPadding: CGFloat
    let sketchShift: CGFloat
    let gapAfterSketch: CGFloat
    let gapAfterDots: CGFloat
    let copyStackSpacing: CGFloat
    let headlineSize: CGFloat
    let sublineSize: CGFloat
    let minContentSpacer: CGFloat
    let ctaCornerRadius: CGFloat
    let ctaStackSpacing: CGFloat
    let ctaHorizontalPadding: CGFloat
    let ctaTopPadding: CGFloat
    let ctaBottomPadding: CGFloat

    init(size: CGSize, safeArea: EdgeInsets) {
        // Previews can report a zero size on the first pass.
        let height = max(size.height, 852)
        let width = max(size.width, 393)
        let widthScale = min(max(width / 393, 0.9), 1.12)

        brandTopPadding = max(safeArea.top, 47) + WelcomeLayout.brandTopExtra
        brandStackSpacing = WelcomeLayout.brandStackSpacing

        wordmarkWidth = WelcomeLayout.wordmarkWidth * widthScale
        wordmarkHeight = wordmarkWidth / Self.wordmarkAspect
        taglineWidth = WelcomeLayout.taglineWidth * widthScale
        taglineHeight = taglineWidth / Self.taglineAspect

        gapAfterBrand = WelcomeLayout.gapAfterBrand
        sketchHeight = min(
            max(height * WelcomeLayout.sketchHeightRatio, WelcomeLayout.sketchMinHeight),
            WelcomeLayout.sketchMaxHeight
        )
        sketchHorizontalPadding = WelcomeLayout.sketchHorizontalPadding
        sketchShift = sketchHeight * WelcomeLayout.sketchShiftRatio

        gapAfterSketch = WelcomeLayout.gapAfterSketch
        gapAfterDots = WelcomeLayout.gapAfterDots
        copyStackSpacing = WelcomeLayout.copyStackSpacing
        headlineSize = WelcomeLayout.headlineSize * widthScale
        sublineSize = WelcomeLayout.sublineSize

        minContentSpacer = WelcomeLayout.minContentSpacer
        ctaCornerRadius = WelcomeLayout.ctaCornerRadius
        ctaStackSpacing = WelcomeLayout.ctaStackSpacing
        ctaHorizontalPadding = WelcomeLayout.ctaHorizontalPadding
        ctaTopPadding = WelcomeLayout.ctaTopPadding
        ctaBottomPadding = max(safeArea.bottom + WelcomeLayout.ctaBottomExtra, 28)
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environment(AuthManager())
        .task {
            FirebaseAuthService.configureAtLaunch()
        }
}
