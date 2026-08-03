import SwiftUI

/// Shared name / gender / city form used by the onboarding gate and Edit Profile sheet.
struct ProfileBasicsForm: View {
    @Binding var displayName: String
    @Binding var city: String
    @Binding var gender: ProfileGender?
    var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            profileTextField(
                title: "Display name",
                text: $displayName,
                placeholder: "What should friends call you?"
            )

            comboField(title: "Gender") {
                Menu {
                    ForEach(ProfileGender.allCases) { option in
                        Button(option.title) {
                            gender = option
                        }
                    }
                } label: {
                    comboLabel(
                        text: gender?.title,
                        placeholder: "Select gender"
                    )
                }
            }

            // City stays free-text for MVP — full country/city catalogs are a later decision.
            profileTextField(
                title: "City",
                text: $city,
                placeholder: "Where are you based?"
            )

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
            }
        }
    }

    private func profileTextField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NADATheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func comboField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
            content()
        }
    }

    private func comboLabel(text: String?, placeholder: String) -> some View {
        HStack {
            Text(text ?? placeholder)
                .font(NADATheme.bodyFont)
                .foregroundStyle(text == nil ? NADATheme.secondaryInk : NADATheme.ink)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NADATheme.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NADATheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
