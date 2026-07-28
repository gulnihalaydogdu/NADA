import SwiftUI

struct WelcomeView: View {
    @Environment(AuthManager.self) private var auth
    @State private var pageIndex = 0

    private let slides = OnboardingSlide.welcomePages

    var body: some View {
        NavigationStack {
            ZStack {
                NADAScreenBackground()

                VStack(spacing: 0) {
                    brandBadge
                        .padding(.top, 16)

                    TabView(selection: $pageIndex) {
                        ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                            OnboardingSlideView(slide: slide)
                                .tag(index)
                                .padding(.top, 24)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxHeight: .infinity)

                    pageIndicator
                        .padding(.bottom, 20)

                    if !auth.isFirebaseReady {
                        firebaseSetupHint
                            .padding(.bottom, 8)
                    }

                    VStack(spacing: 16) {
                        NavigationLink {
                            SignUpView()
                        } label: {
                            Text("Get started")
                        }
                        .buttonStyle(NADAPrimaryButtonStyle())

                        NavigationLink {
                            SignInView()
                        } label: {
                            Text("I already have an account")
                        }
                        .buttonStyle(NADATextLinkButtonStyle())
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var brandBadge: some View {
        Text("Not a Dating App!")
            .font(NADATheme.captionFont.weight(.semibold))
            .foregroundStyle(NADATheme.brandPressed)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(NADATheme.brandSoft)
            .clipShape(Capsule())
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { index in
                Capsule()
                    .fill(index == pageIndex ? NADATheme.brand : NADATheme.hairline)
                    .frame(width: index == pageIndex ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: pageIndex)
            }
        }
    }

    private var firebaseSetupHint: some View {
        Text("Add GoogleService-Info.plist to enable Firebase")
            .font(NADATheme.captionFont)
            .foregroundStyle(NADATheme.danger)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }
}

#Preview {
    WelcomeView()
        .environment(AuthManager())
}
