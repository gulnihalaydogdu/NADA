import SwiftUI

/// Soft multi-step shell after basics: Photos → Bits → Preferences (W1-12).
/// Photo saves via Storage; Bits/Preferences are placeholders until Week 2.
struct ProfileSetupWizardView: View {
    @Environment(AuthManager.self) private var auth

    @State private var step: Step = .photos
    @State private var catalogBits: [Prompt] = []
    @State private var bitsLoadError: String?
    @State private var isLoadingBits = false
    @State private var radiusKm: Double = 25
    @State private var localError: String?

    private let promptService = FirestorePromptService()

    private enum Step: Int, CaseIterable {
        case photos = 0
        case bits = 1
        case preferences = 2

        var title: String {
            switch self {
            case .photos: return "Photos"
            case .bits: return "Bits"
            case .preferences: return "Preferences"
            }
        }

        var headline: String {
            switch self {
            case .photos: return "Add a photo"
            case .bits: return "Bits you'll answer"
            case .preferences: return "Hangout preferences"
            }
        }

        var subtitle: String {
            switch self {
            case .photos:
                return "One clear photo helps friends recognize you. You can change it anytime in Profile."
            case .bits:
                return "These are the questions on your profile. Answering them comes in Week 2 — peek now, skip if you want."
            case .preferences:
                return "City is already set. Radius and interests land in Week 2 — this step is a preview."
            }
        }
    }

    var body: some View {
        ZStack {
            NADAScreenBackground()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(step.headline)
                                .font(NADATheme.displayFont)
                                .foregroundStyle(NADATheme.ink)
                            Text(step.subtitle)
                                .font(NADATheme.bodyFont)
                                .foregroundStyle(NADATheme.warmSecondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        stepContent

                        if let message = localError ?? auth.errorMessage {
                            Text(message)
                                .font(NADATheme.captionFont)
                                .foregroundStyle(NADATheme.danger)
                        }
                    }
                    .padding(24)
                }

                footer
            }
        }
        .task(id: step) {
            if step == .bits {
                await loadBitsCatalog()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if step != .photos {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NADATheme.ink)
                            .frame(width: 36, height: 36)
                            .background(NADATheme.surface, in: Circle())
                    }
                    .accessibilityLabel("Back")
                }

                Spacer()

                Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? NADATheme.brand : NADATheme.brandSoft)
                        .frame(height: 4)
                }
            }

            Text(step.title)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.brandPressed)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .photos:
            photosStep
        case .bits:
            bitsStep
        case .preferences:
            preferencesStep
        }
    }

    private var photosStep: some View {
        VStack(spacing: 16) {
            ProfileAvatarPicker(size: 170)
                .frame(maxWidth: .infinity)

            Text(auth.currentUser?.photoURL == nil ? "Tap to choose a photo" : "Looking good — continue or change it")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .frame(maxWidth: .infinity)
        }
    }

    private var bitsStep: some View {
        Group {
            if isLoadingBits {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let bitsLoadError {
                Text(bitsLoadError)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(.red.opacity(0.85))
            } else if catalogBits.isEmpty {
                Text("No bits seeded yet. You can continue and answer them later.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(catalogBits) { bit in
                        Text(bit.text)
                            .font(NADATheme.bodyFont)
                            .foregroundStyle(NADATheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("City")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                Text(auth.currentUser?.city?.isEmpty == false ? (auth.currentUser?.city ?? "") : "Not set")
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.ink)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Discover radius")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                    Spacer()
                    Text("\(Int(radiusKm)) km")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.warmSecondaryInk)
                }
                Slider(value: $radiusKm, in: 5...80, step: 5)
                    .tint(NADATheme.brand)
                Text("Preview only — not saved yet.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Interests")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                Text("Coffee · Walks · Games · Music · Food")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                Text("Interest picks come in Week 2.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task { await advance() }
            } label: {
                if auth.isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(step == .preferences ? "Finish" : "Continue")
                }
            }
            .buttonStyle(NADAPrimaryButtonStyle())
            .disabled(auth.isBusy)

            Button {
                Task { await skipOrFinish() }
            } label: {
                Text(step == .preferences ? "Skip for now" : "Skip this step")
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.brandPressed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(auth.isBusy)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 28, topTrailing: 28),
                style: .continuous
            )
            .fill(NADATheme.surface.opacity(0.96))
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func goBack() {
        localError = nil
        auth.clearError()
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func advance() async {
        localError = nil
        if step == .preferences {
            await finishWizard()
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func skipOrFinish() async {
        localError = nil
        auth.clearError()
        if step == .preferences {
            await finishWizard()
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func finishWizard() async {
        let ok = await auth.completeProfileWizard()
        if !ok, auth.errorMessage == nil {
            localError = "Couldn't finish setup. Try again."
        }
    }

    private func loadBitsCatalog() async {
        isLoadingBits = true
        bitsLoadError = nil
        defer { isLoadingBits = false }

        do {
            catalogBits = try await promptService.fetchActivePrompts(locale: "en")
        } catch {
            bitsLoadError = "Couldn't load bits. You can still continue."
            catalogBits = []
        }
    }
}

#Preview {
    ProfileSetupWizardView()
        .environment(AuthManager())
}
