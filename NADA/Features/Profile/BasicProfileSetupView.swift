import SwiftUI

/// After friends intent: name (required), then gender, age, and city — one field per
/// screen. Skip advances to the next field, not into the app. Discover stays gated
/// until `isProfileComplete`.
struct BasicProfileSetupView: View {
    @Environment(AuthManager.self) private var auth

    @State private var step: Step = .name
    @State private var displayName = ""
    @State private var city = ""
    @State private var gender: ProfileGender?
    @State private var dateOfBirth: Date?
    @State private var localError: String?

    private enum Step: Int, CaseIterable {
        case name
        case gender
        case age
        case city

        var field: ProfileBasicsField {
            switch self {
            case .name: return .displayName
            case .gender: return .gender
            case .age: return .age
            case .city: return .city
            }
        }

        var headerTitle: String {
            switch self {
            case .name: return "What should friends call you?"
            case .gender, .age:
                return "A few basics"
            case .city:
                return "Where are you from?"
            }
        }

        var headerSubtitle: String {
            switch self {
            case .name:
                return "This is the name on your profile."
            case .gender:
                return "Friends will see this on your profile."
            case .age:
                return "Friends only see your age, not your birthday."
            case .city:
                return "This is the hometown on your profile."
            }
        }
    }

    private var canContinue: Bool {
        guard !auth.isBusy else { return false }
        switch step {
        case .name:
            return !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .gender:
            return gender != nil
        case .age:
            guard let dateOfBirth else { return false }
            return ProfileAge.isAtLeastMinimumAge(dateOfBirth)
        case .city:
            return !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Match the name step so later basics screens sit in the same place.
    private var headerTopPadding: CGFloat { 20 }

    private var headerTitleToSubtitle: CGFloat { 12 }

    private var headerToFieldSpacing: CGFloat {
        step == .gender ? 36 : 28
    }

    var body: some View {
        ZStack {
            NADAScreenBackground()

            VStack(spacing: 0) {
                NADAOnboardingNavBar(
                    showsSkip: step != .name,
                    isBusy: auth.isBusy,
                    onBack: goBack,
                    onSkip: { Task { await advance(requiringCurrentField: false) } }
                )
                .padding(.horizontal, NADATheme.Layout.screenPadding)
                .padding(.top, 12)

                NADAOnboardingProgressBar(currentIndex: step.rawValue)
                    .padding(.horizontal, NADATheme.Layout.screenPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .nadaDismissKeyboardOnTap()

                ScrollView {
                    VStack(alignment: .leading, spacing: headerToFieldSpacing) {
                        NADAOnboardingHeader(
                            title: step.headerTitle,
                            subtitle: step.headerSubtitle,
                            titleToSubtitle: headerTitleToSubtitle
                        )
                        .nadaDismissKeyboardOnTap()

                        ProfileBasicsForm(
                            displayName: $displayName,
                            city: $city,
                            gender: $gender,
                            dateOfBirth: $dateOfBirth,
                            errorMessage: localError ?? auth.errorMessage,
                            visibleFields: [step.field],
                            autofocusDisplayName: step == .name,
                            onDisplayNameSubmit: step == .name
                                ? { Task { await advance(requiringCurrentField: true) } }
                                : nil,
                            autofocusCity: step == .city,
                            onCitySubmit: step == .city
                                ? { Task { await advance(requiringCurrentField: true) } }
                                : nil
                        )

                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 240)
                            .nadaDismissKeyboardOnTap()
                    }
                    .padding(.horizontal, NADATheme.Layout.screenPadding)
                    .padding(.top, headerTopPadding)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.always)
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NADAStickyFooter {
                Button {
                    Task { await advance(requiringCurrentField: true) }
                } label: {
                    if auth.isBusy {
                        ProgressView()
                            .tint(NADATheme.onBrand)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Continue")
                    }
                }
                .nadaPrimaryCTA(enabled: canContinue)
            }
        }
        .onAppear {
            auth.clearError()
            seedFromCurrentUser()
            if auth.isRevisitingBasicProfile {
                step = .city
            }
        }
    }

    private func goBack() {
        localError = nil
        auth.clearError()
        if step == .name {
            Task { await auth.reopenFriendsIntent() }
            return
        }
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func advance(requiringCurrentField: Bool) async {
        localError = nil
        auth.clearError()
        if requiringCurrentField, !canContinue { return }

        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
            return
        }

        await save()
    }

    private func seedFromCurrentUser() {
        displayName = auth.currentUser?.displayName ?? ""
        city = auth.currentUser?.city ?? ""
        gender = ProfileGender.fromStored(auth.currentUser?.gender)
        dateOfBirth = auth.currentUser?.dateOfBirth
    }

    private func save() async {
        localError = nil
        if let dateOfBirth, !ProfileAge.isAtLeastMinimumAge(dateOfBirth) {
            localError = "You must be \(ProfileAge.minimumAge) or older to use NADA."
            return
        }

        let ok = await auth.completeBasicProfileOnboarding(
            displayName: displayName,
            gender: gender,
            city: city,
            dateOfBirth: dateOfBirth
        )
        if !ok, auth.errorMessage == nil {
            localError = "Couldn't save your profile. Try again."
        }
    }
}

#Preview {
    BasicProfileSetupView()
        .environment(AuthManager())
}
