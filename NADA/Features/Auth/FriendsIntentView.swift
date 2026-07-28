import SwiftUI

struct FriendsIntentView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        ZStack {
            NADAScreenBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    Image("SketchFriendsIntent")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 220)
                        .padding(.horizontal, 32)

                    Text("You're here for friendship.")
                        .font(NADATheme.displayFont)
                        .foregroundStyle(NADATheme.ink)
                        .multilineTextAlignment(.center)

                    Text("NADA is for hangouts and good company only. No romance, no flirting expectations — and we take that seriously.")
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button {
                    Task { await auth.completeFriendsIntent() }
                } label: {
                    if auth.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Got it, continue")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(auth.isLoading)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
    }
}

#Preview {
    FriendsIntentView()
        .environment(AuthManager())
}
