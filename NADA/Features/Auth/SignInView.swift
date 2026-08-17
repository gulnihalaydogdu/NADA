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

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !auth.isBusy
            && auth.isFirebaseReady
            && !trimmedEmail.isEmpty
            && !password.isEmpty
    }

    var body: some View {
        ZStack {
            NADAScreenBackground(showBottomBlob: false)

            ScrollView {
                VStack(alignment: .leading, spacing: NADATheme.Layout.headerToContent) {
                    NADAOnboardingHeader(
                        title: "Welcome back",
                        subtitle: "Pick up where you left off."
                    )

                    VStack(spacing: NADATheme.Layout.fieldSpacing) {
                        NADAAuthField(
                            title: "Email",
                            text: $email,
                            placeholder: "you@email.com",
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
                            placeholder: "Your password",
                            isSecure: true,
                            submitLabel: .go,
                            onSubmit: { submit() },
                            focusedField: $focusedField,
                            field: .password
                        )
                        .textContentType(.password)
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
                        Text("Log in")
                    }
                }
                .nadaPrimaryCTA(enabled: canSubmit)
            }
        }
        .nadaAuthNavigationBar(showsSkip: false)
        .onAppear { auth.clearError() }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth { dismiss() }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            await auth.signInWithEmail(email: trimmedEmail, password: password)
        }
    }
}

#Preview {
    NavigationStack {
        SignInView()
            .environment(AuthManager())
    }
}
