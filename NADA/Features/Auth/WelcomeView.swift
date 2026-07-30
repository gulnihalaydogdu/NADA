import SwiftUI

struct WelcomeView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        NavigationStack {
            ZStack {
                NADAWelcomeBackground()

                VStack(spacing: 0) {
                    welcomeBrandHeader
                        .frame(height: Layout.sketchTop - Layout.gapAboveSketch)

                    TabView(selection: $pageIndex) {
                        ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                            OnboardingSlideView(slide: slide, showsText: false, illustrationHeight: 270)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: Layout.sketchHeight)

                    pageIndicator
                        .padding(.top, 12)
                        .padding(.bottom, 14)

                    slideCopy

                    Spacer(minLength: 12)

                    ctaDock
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var welcomeBrandHeader: some View {
        VStack(spacing: 6) {
            Spacer(minLength: Layout.brandTopPadding)

            Image("WelcomeNADAWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 130)
                .accessibilityLabel("NADA")

            Image("WelcomeNotADatingApp")
                .resizable()
                .scaledToFit()
                .frame(width: 220)
                .accessibilityLabel("Not a dating app")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, Layout.gapAboveSketch)
    }

    private var slideCopy: some View {
        VStack(spacing: 10) {
            Text(slides[pageIndex].headline)
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
                .multilineTextAlignment(.center)

            Text(slides[pageIndex].subline)
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 28)
        .animation(.easeInOut(duration: 0.2), value: pageIndex)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { index in
                Capsule()
                    .fill(index == pageIndex ? NADATheme.coral : NADATheme.hairline)
                    .frame(width: index == pageIndex ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: pageIndex)
            }
        }
    }

    private var ctaDock: some View {
        VStack(spacing: 14) {
            if !auth.isFirebaseReady {
                firebaseSetupHint
            }

            NavigationLink {
                SignUpView()
            } label: {
                Text("Create account")
            }
            .buttonStyle(NADACoralPrimaryButtonStyle())

            NavigationLink {
                SignInView()
            } label: {
                signInPrompt
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .top) {
                NADATheme.surface.opacity(0.94)
                NADATheme.hairline.frame(height: 1)
            }
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
        .padding(.vertical, 4)
    }

    private var firebaseSetupHint: some View {
        Text("Add GoogleService-Info.plist to enable Firebase")
            .font(NADATheme.captionFont)
            .foregroundStyle(NADATheme.danger)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    WelcomeView()
        .environment(AuthManager())
}
