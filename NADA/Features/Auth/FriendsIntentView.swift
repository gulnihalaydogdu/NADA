import SwiftUI

struct FriendsIntentView: View {
    @Environment(AuthManager.self) private var auth

    private enum Layout {
        static let topPadding: CGFloat = 12
        static let sketchHeight: CGFloat = 290
        static let sketchHorizontal: CGFloat = 20
        static let gapAfterSketch: CGFloat = 16
        static let copyStackSpacing: CGFloat = 10
        static let minSpacer: CGFloat = 24
        static let ctaHorizontal: CGFloat = 24
        static let ctaTop: CGFloat = 24
        static let ctaBottom: CGFloat = 36
        static let ctaCornerRadius: CGFloat = 32
        static let sublineSize: CGFloat = 17
    }

    var body: some View {
        ZStack {
            NADAScreenBackground()

            VStack(spacing: 0) {
                contentBlock
                    .padding(.top, Layout.topPadding)

                Spacer(minLength: Layout.minSpacer)

                ctaDock
            }
        }
    }

    private var contentBlock: some View {
        VStack(spacing: Layout.gapAfterSketch) {
            Image("SketchFriendsIntent")
                .resizable()
                .scaledToFit()
                .frame(height: Layout.sketchHeight)
                .padding(.horizontal, Layout.sketchHorizontal)
                .accessibilityHidden(true)

            VStack(spacing: Layout.copyStackSpacing) {
                Text("You're here for friendship.")
                    .font(NADATheme.displayFont)
                    .foregroundStyle(NADATheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("NADA is for friendship, shared plans and good company — never dating or flirting.")
                    .font(.system(size: Layout.sublineSize, weight: .regular))
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var ctaDock: some View {
        Button {
            Task { await auth.completeFriendsIntent() }
        } label: {
            if auth.isBusy {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Continue")
            }
        }
        .buttonStyle(NADAPrimaryButtonStyle())
        .disabled(auth.isBusy)
        .padding(.horizontal, Layout.ctaHorizontal)
        .padding(.top, Layout.ctaTop)
        .padding(.bottom, Layout.ctaBottom)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: Layout.ctaCornerRadius,
                    topTrailing: Layout.ctaCornerRadius
                ),
                style: .continuous
            )
            .fill(NADATheme.surface.opacity(0.96))
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    FriendsIntentView()
        .environment(AuthManager())
}
