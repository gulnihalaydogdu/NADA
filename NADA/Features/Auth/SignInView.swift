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
                NADAAuthField(title: "Email", text: $email, focusedField: $focusedField, field: .email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                NADAAuthField(title: "Password", text: $password, isSecure: true, focusedField: $focusedField, field: .password)
                    .textContentType(.password)
            }

            if let error = auth.errorMessage {
                NADAAuthErrorBanner(message: error)
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
                if auth.isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign in")
                }
            }
            .buttonStyle(NADAPrimaryButtonStyle())
            .disabled(auth.isBusy || email.isEmpty || password.isEmpty || !auth.isFirebaseReady)

            if NADAAuthConfig.isAppleSignInEnabled {
                NADAAuthDivider(label: "or")

                AppleSignInButton(isLoading: auth.isBusy) {
                    focusedField = nil
                    Task { await AuthAppleSignIn.signIn(auth: auth, coordinator: appleCoordinator) }
                }
                .disabled(auth.isBusy || !auth.isFirebaseReady)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NADATheme.paper)
        .nadaAuthNavigationBar()
        .onAppear { auth.clearError() }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth { dismiss() }
        }
    }
}

#Preview {
    NavigationStack {
        SignInView()
            .environment(AuthManager())
    }
}
