import SwiftUI

struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var appleCoordinator = AppleSignInCoordinator()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome back")
                    .font(NADATheme.titleFont)
                    .foregroundStyle(NADATheme.ink)
                Text("Pick up where you left off.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            VStack(spacing: 16) {
                authField(title: "Email", text: $email, field: .email, isSecure: false)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                authField(title: "Password", text: $password, field: .password, isSecure: true)
                    .textContentType(.password)
            }

            if let error = auth.errorMessage {
                Text(error)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
            }

            Button {
                focusedField = nil
                Task {
                    await auth.signInWithEmail(
                        email: email.trimmingCharacters(in: .whitespaces),
                        password: password
                    )
                }
            } label: {
                if auth.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign in")
                }
            }
            .buttonStyle(NADAPrimaryButtonStyle())
            .disabled(auth.isLoading || email.isEmpty || password.isEmpty || !auth.isFirebaseReady)

            if NADAAuthConfig.isAppleSignInEnabled {
                dividerLabel("or")

                AppleSignInButton(isLoading: auth.isLoading) {
                    focusedField = nil
                    Task { await handleAppleSignIn() }
                }
                .disabled(auth.isLoading || !auth.isFirebaseReady)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        SignInView()
            .environment(AuthManager())
    }
}
