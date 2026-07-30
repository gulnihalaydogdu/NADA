import SwiftUI

struct NADAAuthField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    var focusedField: FocusState<Field>.Binding
    let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .focused(focusedField, equals: field)
            .textFieldStyle(.plain)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct NADAAuthDivider: View {
    let label: String

    var body: some View {
        HStack {
            NADATheme.hairline.frame(height: 1)
            Text(label)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
            NADATheme.hairline.frame(height: 1)
        }
    }
}

struct NADAAuthErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(NADATheme.captionFont)
            .foregroundStyle(NADATheme.danger)
    }
}

struct NADABackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NADATheme.brandPressed)
                .frame(width: 36, height: 36)
                .background(NADATheme.brandSoft, in: Circle())
        }
        .accessibilityLabel("Back")
    }
}

extension View {
    /// Replaces the system back button with the coral NADA one and keeps the
    /// paper background visible behind the navigation bar.
    func nadaAuthNavigationBar() -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NADABackButton()
                }
            }
    }
}

enum AuthAppleSignIn {
    @MainActor
    static func signIn(auth: AuthManager, coordinator: AppleSignInCoordinator) async {
        do {
            let result = try await coordinator.signIn()
            await auth.signInWithApple(
                idToken: result.idToken,
                nonce: result.nonce,
                fullName: result.fullName
            )
        } catch AuthError.cancelled {
            // User dismissed sheet
        } catch {
            auth.presentError((error as? AuthError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
