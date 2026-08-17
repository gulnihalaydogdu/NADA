import SwiftUI

/// After friends intent: name, gender, birthday (18+), and city. Skip enters the app;
/// Discover stays gated until `isProfileComplete`.
struct BasicProfileSetupView: View {
    @Environment(AuthManager.self) private var auth

    @State private var displayName = ""
    @State private var city = ""
    @State private var gender: ProfileGender?
    @State private var dateOfBirth: Date?
    @State private var localError: String?

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && gender != nil
            && dateOfBirth != nil
            && !auth.isBusy
    }

    var body: some View {
        ZStack {
            NADAScreenBackground()

            VStack(spacing: 0) {
                NADAOnboardingNavBar(
                    isBusy: auth.isBusy,
                    onBack: { Task { await auth.reopenFriendsIntent() } },
                    onSkip: { Task { await auth.skipRemainingOnboarding() } }
                )
                .padding(.horizontal, NADATheme.Layout.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: NADATheme.Layout.headerToContent) {
                        NADAOnboardingHeader(
                            title: "A few basics",
                            subtitle: "Name, gender, age, and city — so hangouts feel personal. Friends only see your age."
                        )

                        ProfileBasicsForm(
                            displayName: $displayName,
                            city: $city,
                            gender: $gender,
                            dateOfBirth: $dateOfBirth,
                            errorMessage: localError ?? auth.errorMessage
                        )
                    }
                    .padding(.horizontal, NADATheme.Layout.screenPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NADAStickyFooter {
                Button {
                    Task { await save() }
                } label: {
                    if auth.isBusy {
                        ProgressView()
                            .tint(NADATheme.onBrand)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Continue")
                    }
                }
                .nadaPrimaryCTA(enabled: canSave)
            }
        }
        .onAppear {
            auth.clearError()
            seedFromCurrentUser()
        }
    }

    private func seedFromCurrentUser() {
        displayName = auth.currentUser?.displayName ?? ""
        city = auth.currentUser?.city ?? ""
        gender = ProfileGender.fromStored(auth.currentUser?.gender)
        dateOfBirth = auth.currentUser?.dateOfBirth
    }

    private func save() async {
        localError = nil
        guard let gender else {
            localError = "Select a gender option."
            return
        }
        guard let dateOfBirth else {
            localError = "Add your age to continue."
            return
        }
        guard ProfileAge.isAtLeastMinimumAge(dateOfBirth) else {
            localError = "You must be \(ProfileAge.minimumAge) or older to use NADA."
            return
        }

        let ok = await auth.updateBasicProfile(
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
