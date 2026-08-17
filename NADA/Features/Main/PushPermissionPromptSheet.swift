import SwiftUI

/// In-app Enable / Skip card. The iOS permission alert only runs after Turn on.
struct PushPermissionPromptSheet: View {
    var onEnable: () async -> Void
    var onSkip: () -> Void

    @State private var isEnabling = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(NADATheme.brand)
                .padding(18)
                .background(NADATheme.brandSoft, in: Circle())
                .padding(.top, 8)

            VStack(spacing: 10) {
                Text("Hear when someone likes you")
                    .font(NADATheme.displayFont)
                    .foregroundStyle(NADATheme.ink)
                    .multilineTextAlignment(.center)

                Text("We’ll ping you when a hangout like lands. Skip anytime — we won’t keep asking.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                Button {
                    guard !isEnabling else { return }
                    isEnabling = true
                    Task {
                        await onEnable()
                        isEnabling = false
                    }
                } label: {
                    Text(isEnabling ? "Turning on…" : "Turn on notifications")
                }
                .buttonStyle(NADAPrimaryButtonStyle(isEnabled: !isEnabling))
                .disabled(isEnabling)

                Button("Skip", action: onSkip)
                    .buttonStyle(NADASecondaryButtonStyle())
                    .disabled(isEnabling)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isEnabling)
    }
}
