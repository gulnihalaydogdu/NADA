import SwiftUI

struct SignUpView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var appleCoordinator = AppleSignInCoordinator()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
        case confirmPassword
    }

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var body: some View {
        ZStack {
            NADATheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create your account")
                        .font(NADATheme.titleFont)
                        .foregroundStyle(NADATheme.ink)
                    Text("Match with people to hang out with — not for dating.")
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }

                VStack(spacing: 16) {
                    authField(title: "Email", text: $email, field: .email, isSecure: false)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    authField(title: "Password (min. 6 characters)", text: $password, field: .password, isSecure: true)
                        .textContentType(.newPassword)

                    authField(title: "Confirm password", text: $confirmPassword, field: .confirmPassword, isSecure: true)
                        .textContentType(.newPassword)

                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords don't match.")
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.danger)
                    }
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                }

                Button {
                    focusedField = nil
                    Task {
                        await auth.signUpWithEmail(
                            email: email.trimmingCharacters(in: .whitespaces),
                            password: password
                        )
                    }
                } label: {
                    if auth.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign up")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(auth.isLoading || email.isEmpty || !passwordsMatch || !auth.isFirebaseReady)

                if NADAAuthConfig.isAppleSignInEnabled {
                    dividerLabel("or")

                    AppleSignInButton(isLoading: auth.isLoading) {
                        focusedField = nil
                        Task { await handleAppleSignIn() }
                    }
                    .disabled(auth.isLoading || !auth.isFirebaseReady)
                }
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
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
    private func authField(
        title: String,
        text: Binding<String>,
        field: Field,
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            Group {
                if isSecure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .focused($focusedField, equals: field)
            .textFieldStyle(.plain)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        SignUpView()
            .environment(AuthManager())
    }
}
