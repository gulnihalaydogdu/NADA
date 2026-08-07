import SwiftUI

/// Mandatory gate after friends intent — cannot dismiss until name, gender, birthday (18+), and city are saved.
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A few basics")
                                .font(NADATheme.displayFont)
                                .foregroundStyle(NADATheme.ink)
                            Text("Name, gender, birthday, and city — so hangouts feel personal. NADA is 18+. Friends only see your age, not your full birthday.")
                                .font(NADATheme.bodyFont)
                                .foregroundStyle(NADATheme.warmSecondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ProfileBasicsForm(
                            displayName: $displayName,
                            city: $city,
                            gender: $gender,
                            dateOfBirth: $dateOfBirth,
                            errorMessage: localError ?? auth.errorMessage
                        )
                    }
                    .padding(24)
                }

                Button {
                    Task { await save() }
                } label: {
                    if auth.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(!canSave)
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
        dateOfBirth = auth.currentUser?.dateOfBirth ?? ProfileAge.maximumSelectableDate()
    }

    private func save() async {
        localError = nil
        guard let gender else {
            localError = "Please select a gender option."
            return
        }
        guard let dateOfBirth else {
            localError = "Please add your birthday."
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
