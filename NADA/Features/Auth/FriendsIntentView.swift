import SwiftUI

struct FriendsIntentView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(NADATheme.brand)

                Text("Burada ne arıyorsun?")
                    .font(NADATheme.titleFont)
                    .foregroundStyle(NADATheme.ink)

                Text("NADA sadece arkadaşlık ve birlikte vakit geçirmek için. Flört veya dating beklentisi yok.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                auth.hasCompletedFriendsIntent = true
            } label: {
                Text("Arkadaşlık ve takılma için buradayım")
            }
            .buttonStyle(NADAPrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NADATheme.paper)
    }
}

#Preview {
    FriendsIntentView()
        .environment(AuthManager())
}
