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
                        NADAAuthField(title: "Email", text: $email, focusedField: $focusedField, field: .email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        NADAAuthField(title: "Password (min. 6 characters)", text: $password, isSecure: true, focusedField: $focusedField, field: .password)
                            .textContentType(.newPassword)

                        NADAAuthField(title: "Confirm password", text: $confirmPassword, isSecure: true, focusedField: $focusedField, field: .confirmPassword)
                            .textContentType(.newPassword)

                        if !confirmPassword.isEmpty && !passwordsMatch {
                            NADAAuthErrorBanner(message: "Passwords don't match.")
                        }
                    }

                    if let error = auth.errorMessage {
                        NADAAuthErrorBanner(message: error)
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
                        if auth.isBusy {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign up")
                        }
                    }
                    .buttonStyle(NADAPrimaryButtonStyle())
                    .disabled(auth.isBusy || email.isEmpty || !passwordsMatch || !auth.isFirebaseReady)

                    if NADAAuthConfig.isAppleSignInEnabled {
                        NADAAuthDivider(label: "or")

                        AppleSignInButton(isLoading: auth.isBusy) {
                            focusedField = nil
                            Task { await AuthAppleSignIn.signIn(auth: auth, coordinator: appleCoordinator) }
                        }
                        .disabled(auth.isBusy || !auth.isFirebaseReady)
                    }
                }
                .padding(24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .nadaAuthNavigationBar()
        .onAppear { auth.clearError() }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth { dismiss() }
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(AuthManager())
    }
}
