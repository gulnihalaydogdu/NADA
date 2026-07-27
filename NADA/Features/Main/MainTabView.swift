import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            PlaceholderTabView(title: "Keşfet", systemImage: "sparkles")
                .tabItem { Label("Keşfet", systemImage: "sparkles") }

            PlaceholderTabView(title: "Beğeniler", systemImage: "heart")
                .tabItem { Label("Beğeniler", systemImage: "heart") }

            PlaceholderTabView(title: "Eşleşmeler", systemImage: "bubble.left.and.bubble.right")
                .tabItem { Label("Eşleşmeler", systemImage: "bubble.left.and.bubble.right") }

            ProfileTabView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        .tint(NADATheme.brand)
    }
}

private struct PlaceholderTabView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(NADATheme.brand)
            Text(title)
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)
            Text("Yakında")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NADATheme.paper)
    }
}

private struct ProfileTabView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        VStack(spacing: 16) {
            if let user = auth.currentUser {
                Text(user.displayName ?? user.email ?? "Kullanıcı")
                    .font(NADATheme.titleFont)
                    .foregroundStyle(NADATheme.ink)
                if let email = user.email {
                    Text(email)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }
            }

            Button("Çıkış yap") {
                auth.signOut()
            }
            .buttonStyle(NADASecondaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NADATheme.paper)
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
}
