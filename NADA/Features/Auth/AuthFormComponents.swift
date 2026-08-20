import SwiftUI
import UIKit

struct NADAOnboardingHeader: View {
    let title: String
    let subtitle: String
    var titleToSubtitle: CGFloat = NADATheme.Layout.titleToSubtitle

    var body: some View {
        VStack(alignment: .leading, spacing: titleToSubtitle) {
            Text(title)
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NADAStickyFooter<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .padding(.horizontal, NADATheme.Layout.screenPadding)
        .padding(.top, NADATheme.Layout.footerTop)
        .padding(.bottom, NADATheme.Layout.footerBottom)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 24, topTrailing: 24),
                style: .continuous
            )
            .fill(NADATheme.surface.opacity(0.96))
            .ignoresSafeArea(edges: .bottom)
            .shadow(color: NADATheme.ink.opacity(0.04), radius: 10, y: -3)
        }
    }
}

struct NADAAuthField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    var placeholder: String? = nil
    var isSecure: Bool = false
    var errorMessage: String? = nil
    var hint: String? = nil
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil
    var focusedField: FocusState<Field>.Binding
    let field: Field

    @State private var isPasswordVisible = false

    private var isFocused: Bool {
        focusedField.wrappedValue == field
    }

    private var hasError: Bool {
        !(errorMessage?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NADATheme.captionFont)
                .foregroundStyle(hasError ? NADATheme.brandPressed : NADATheme.secondaryInk)

            HStack(spacing: 10) {
                Group {
                    if isSecure, !isPasswordVisible {
                        SecureField(placeholder ?? title, text: $text)
                    } else {
                        TextField(placeholder ?? title, text: $text)
                    }
                }
                .focused(focusedField, equals: field)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
                .textFieldStyle(.plain)
                .foregroundStyle(NADATheme.ink)

                if isSecure {
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NADATheme.secondaryInk)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, NADATheme.Layout.fieldHPadding)
            .frame(maxWidth: .infinity, minHeight: NADATheme.Layout.fieldMinHeight, alignment: .leading)
            .background(NADATheme.surface, in: RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused || hasError ? 1.5 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous))

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.brandPressed)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hint, !hint.isEmpty {
                Text(hint)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var borderColor: Color {
        if hasError { return NADATheme.brandPressed.opacity(0.55) }
        if isFocused { return NADATheme.brand.opacity(0.55) }
        return .clear
    }
}

struct NADAAuthDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            NADATheme.hairline.frame(height: 1)
            Text(label)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
            NADATheme.hairline.frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}

struct NADAAuthErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 1)
            Text(message)
                .font(NADATheme.captionFont)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(NADATheme.brandPressed)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            NADATheme.brandSoft,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

struct NADABackButton: View {
    var action: (() -> Void)? = nil
    var onHero = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if let action {
                action()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(onHero ? Color.white : NADATheme.brandPressed)
                .frame(width: NADATheme.Layout.backHit, height: NADATheme.Layout.backHit)
                .background(
                    onHero ? Color.white.opacity(0.2) : NADATheme.brandSoft,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .accessibilityLabel("Back")
    }
}

struct NADAOnboardingNavBar: View {
    var onHero = false
    var showsBack = true
    var showsSkip = true
    var skipTitle = "Skip"
    var isBusy = false
    var onBack: () -> Void
    var onSkip: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if showsBack {
                NADABackButton(action: onBack, onHero: onHero)
                    .disabled(isBusy)
            }

            Spacer(minLength: 8)

            if showsSkip {
                Button(skipTitle) {
                    onSkip?()
                }
                .buttonStyle(.plain)
                .font(NADATheme.bodyFont.weight(.semibold))
                .foregroundStyle(onHero ? Color.white : NADATheme.brandPressed)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .disabled(isBusy)
                .opacity(isBusy ? 0.55 : 1)
                .accessibilityLabel(skipTitle)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Shared 9-step meter from name through hangout preferences.
struct NADAOnboardingProgressBar: View {
    let currentIndex: Int

    private var total: Int { OnboardingSetupProgress.totalCount }

    var body: some View {
        VStack(spacing: 6) {
            Text("\(currentIndex + 1) of \(total)")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentIndex ? NADATheme.brand : NADATheme.brandSoft)
                        .frame(height: NADATheme.Layout.progressHeight)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(total)")
    }
}

enum OnboardingSetupProgress {
    static let basicsCount = 4
    static let totalCount = 9
}

extension View {
    /// Replaces the system back button with the coral NADA one and keeps the
    /// paper background visible behind the navigation bar.
    func nadaAuthNavigationBar(showsSkip: Bool = true) -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NADABackButton()
                }
                if showsSkip {
                    ToolbarItem(placement: .topBarTrailing) {
                        SkipToolbarButton()
                    }
                }
            }
    }
}

private struct SkipToolbarButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Skip") { dismiss() }
            .font(NADATheme.bodyFont.weight(.semibold))
            .foregroundStyle(NADATheme.brandPressed)
            .buttonStyle(.plain)
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

enum NADAKeyboard {
    static func resign() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    func nadaDismissKeyboardOnTap() -> some View {
        contentShape(Rectangle())
            .onTapGesture { NADAKeyboard.resign() }
    }
}
