import SwiftUI

struct SignUpView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var appleCoordinator = AppleSignInCoordinator()
    @State private var showEmailHint = false
    @State private var showPasswordHint = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
        case confirmPassword
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        let parts = trimmedEmail.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else { return false }
        return trimmedEmail.count >= 5
    }

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var isPasswordLongEnough: Bool {
        password.count >= 6
    }

    private var canSubmit: Bool {
        !auth.isBusy
            && auth.isFirebaseReady
            && isEmailValid
            && isPasswordLongEnough
            && passwordsMatch
    }

    private var emailError: String? {
        guard showEmailHint, !trimmedEmail.isEmpty, !isEmailValid else { return nil }
        return "Enter a valid email, like you@email.com."
    }

    private var passwordError: String? {
        guard showPasswordHint, !password.isEmpty, !isPasswordLongEnough else { return nil }
        return "Use at least 6 characters."
    }

    private var confirmError: String? {
        guard !confirmPassword.isEmpty, !passwordsMatch else { return nil }
        return "Those passwords don’t match."
    }

    var body: some View {
        ZStack {
            NADAScreenBackground(showBottomBlob: false)

            ScrollView {
                VStack(alignment: .leading, spacing: NADATheme.Layout.headerToContent) {
                    NADAOnboardingHeader(
                        title: "Create your account",
                        subtitle: "Hang out with people nearby — not for dating."
                    )

                    VStack(spacing: NADATheme.Layout.fieldSpacing) {
                        NADAAuthField(
                            title: "Email",
                            text: $email,
                            placeholder: "you@email.com",
                            errorMessage: emailError,
                            submitLabel: .next,
                            onSubmit: { focusedField = .password },
                            focusedField: $focusedField,
                            field: .email
                        )
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        NADAAuthField(
                            title: "Password",
                            text: $password,
                            placeholder: "At least 6 characters",
                            isSecure: true,
                            errorMessage: passwordError,
                            hint: password.isEmpty ? "Min. 6 characters" : nil,
                            submitLabel: .next,
                            onSubmit: { focusedField = .confirmPassword },
                            focusedField: $focusedField,
                            field: .password
                        )
                        .textContentType(.newPassword)

                        NADAAuthField(
                            title: "Confirm password",
                            text: $confirmPassword,
                            placeholder: "Re-enter password",
                            isSecure: true,
                            errorMessage: confirmError,
                            submitLabel: .go,
                            onSubmit: { submit() },
                            focusedField: $focusedField,
                            field: .confirmPassword
                        )
                        .textContentType(.newPassword)
                    }

                    if let error = auth.errorMessage {
                        NADAAuthErrorBanner(message: error)
                    }

                    if NADAAuthConfig.isAppleSignInEnabled {
                        NADAAuthDivider(label: "or")
                        AppleSignInButton(isLoading: auth.isBusy) {
                            focusedField = nil
                            Task { await AuthAppleSignIn.signIn(auth: auth, coordinator: appleCoordinator) }
                        }
                        .disabled(auth.isBusy || !auth.isFirebaseReady)
                    }
                }
                .padding(.horizontal, NADATheme.Layout.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NADAStickyFooter {
                Button {
                    submit()
                } label: {
                    if auth.isBusy {
                        ProgressView()
                            .tint(NADATheme.onBrand)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create account")
                    }
                }
                .nadaPrimaryCTA(enabled: canSubmit)
            }
        }
        .nadaAuthNavigationBar(showsSkip: false)
        .onAppear { auth.clearError() }
        .onChange(of: focusedField) { oldValue, _ in
            if oldValue == .email { showEmailHint = true }
            if oldValue == .password { showPasswordHint = true }
        }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth { dismiss() }
        }
    }

    private func submit() {
        showEmailHint = true
        showPasswordHint = true
        guard canSubmit else { return }
        focusedField = nil
        Task {
            await auth.signUpWithEmail(email: trimmedEmail, password: password)
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(AuthManager())
    }
}
