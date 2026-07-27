import SwiftUI

struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var appleCoordinator = AppleSignInCoordinator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tekrar hoş geldin")
                        .font(NADATheme.titleFont)
                        .foregroundStyle(NADATheme.ink)
                    Text("Arkadaşlık ve takılma — dating değil.")
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }

                VStack(spacing: 16) {
                    authField(title: "E-posta", text: $email, isSecure: false)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    authField(title: "Şifre", text: $password, isSecure: true)
                        .textContentType(.password)
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                }

                Button {
                    Task {
                        await auth.signInWithEmail(email: email.trimmingCharacters(in: .whitespaces), password: password)
                    }
                } label: {
                    if auth.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Giriş yap")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(auth.isLoading || email.isEmpty || password.isEmpty)

                dividerLabel("veya")

                AppleSignInButton(isLoading: auth.isLoading) {
                    Task { await handleAppleSignIn() }
                }
            }
            .padding(24)
        }
        .background(NADATheme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { auth.clearError() }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth { dismiss() }
        }
    }

    private func handleAppleSignIn() async {
        do {
            let result = try await appleCoordinator.signIn()
            await auth.signInWithApple(
                idToken: result.idToken,
                nonce: result.nonce,
                fullName: result.fullName
            )
        } catch AuthError.cancelled {
            // dismissed
        } catch {
            auth.presentError((error as? AuthError)?.errorDescription ?? error.localizedDescription)
        }
    }

    @ViewBuilder
    private func authField(title: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .padding(14)
            .background(NADATheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func dividerLabel(_ text: String) -> some View {
        HStack {
            NADATheme.hairline.frame(height: 1)
            Text(text)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
            NADATheme.hairline.frame(height: 1)
        }
    }
}

#Preview {
    NavigationStack {
        SignInView()
            .environment(AuthManager())
    }
}
