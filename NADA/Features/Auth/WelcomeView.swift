import SwiftUI

struct WelcomeView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Text("NADA!")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(NADATheme.ink)

                    Text("Not a Dating App")
                        .font(NADATheme.headlineFont)
                        .foregroundStyle(NADATheme.secondaryInk)

                    Text("Yakınındaki insanlarla takılmak için — flört için değil, arkadaşlık için.")
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }

                Spacer()

                VStack(spacing: 12) {
                    NavigationLink {
                        SignUpView()
                    } label: {
                        Text("Kayıt ol")
                    }
                    .buttonStyle(NADAPrimaryButtonStyle())

                    NavigationLink {
                        SignInView()
                    } label: {
                        Text("Giriş yap")
                    }
                    .buttonStyle(NADASecondaryButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NADATheme.paper)
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AuthManager())
}
