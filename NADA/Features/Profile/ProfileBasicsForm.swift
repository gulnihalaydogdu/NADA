import SwiftUI

/// Shared name / gender / birthday / city form used by the onboarding gate and Edit Profile sheet.
/// Hangout essentials (job, university, looking-for) are edit-only so the basics gate stays short.
struct ProfileBasicsForm: View {
    @Binding var displayName: String
    @Binding var city: String
    @Binding var gender: ProfileGender?
    @Binding var dateOfBirth: Date?
    var jobTitle: Binding<String>? = nil
    var university: Binding<String>? = nil
    var hangoutLookingFor: Binding<String>? = nil
    var errorMessage: String?

    @State private var isBirthdayPickerPresented = false
    @State private var pickerDraftDate: Date?

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

            birthdayField

            // City stays free-text for MVP — full country/city catalogs are a later decision.
            profileTextField(
                title: "City",
                text: $city,
                placeholder: "Where are you based?"
            )

            if let jobTitle, let university, let hangoutLookingFor {
                hangoutEssentialsFields(
                    jobTitle: jobTitle,
                    university: university,
                    hangoutLookingFor: hangoutLookingFor
                )
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
            }
        }
        .sheet(isPresented: $isBirthdayPickerPresented) {
            birthdayPickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .onAppear {
                    pickerDraftDate = dateOfBirth ?? ProfileAge.maximumSelectableDate()
                }
        }
    }

    private var birthdayField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Age")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            Button {
                isBirthdayPickerPresented = true
            } label: {
                HStack(spacing: 10) {
                    Text(ageCapsuleLabel)
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(dateOfBirth == nil ? NADATheme.secondaryInk : NADATheme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NADATheme.secondaryInk)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NADATheme.surface, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Age")
            .accessibilityHint("Opens birthday picker")

            Text("You must be \(ProfileAge.minimumAge)+. Friends only see your age, not your birthday.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ageCapsuleLabel: String {
        if let dateOfBirth {
            return "\(ProfileAge.age(from: dateOfBirth))"
        }
        return "dd/mm/yyyy"
    }

    private var birthdayPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("When’s your birthday?")
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                DatePicker(
                    "Birthday",
                    selection: birthDateBinding,
                    in: ProfileAge.minimumSelectableDate()...ProfileAge.maximumSelectableDate(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .tint(NADATheme.brand)

                Text("Friends will see your age (\(displayedAgeText)), not this date.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .background(NADATheme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dateOfBirth = pickerDraftDate ?? ProfileAge.maximumSelectableDate()
                        isBirthdayPickerPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(NADATheme.brandPressed)
                }
            }
        }
    }

    private var displayedAgeText: String {
        let date = pickerDraftDate ?? dateOfBirth ?? ProfileAge.maximumSelectableDate()
        return "\(ProfileAge.age(from: date))"
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { pickerDraftDate ?? ProfileAge.maximumSelectableDate() },
            set: { pickerDraftDate = $0 }
        )
    }

    private func hangoutEssentialsFields(
        jobTitle: Binding<String>,
        university: Binding<String>,
        hangoutLookingFor: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("On your Discover card")
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)
                .padding(.top, 4)

            Text("Optional — friends see these under your photos. Skip anything that doesn’t fit.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            profileTextField(
                title: "Job / role",
                text: jobTitle,
                placeholder: "Student, designer, barista…",
                maxLength: NADAUser.maxJobTitleLength
            )

            profileTextField(
                title: "University",
                text: university,
                placeholder: "Last or current school",
                maxLength: NADAUser.maxUniversityLength
            )

            profileTextField(
                title: "Hangout looking-for",
                text: hangoutLookingFor,
                placeholder: "Looking for a travel-buddy from Istanbul",
                maxLength: NADAUser.maxHangoutLookingForLength,
                axis: .vertical,
                hint: "A short line about the kind of hangout or buddy you want."
            )
        }
    }

    private func profileTextField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        maxLength: Int? = nil,
        axis: Axis = .horizontal,
        hint: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                if let maxLength {
                    Spacer()
                    Text("\(min(text.wrappedValue.count, maxLength))/\(maxLength)")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }
            }

            Group {
                if axis == .vertical {
                    TextField(placeholder, text: text, axis: .vertical)
                        .lineLimit(2...4)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .textInputAutocapitalization(axis == .vertical ? .sentences : .words)
            .autocorrectionDisabled()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: text.wrappedValue) { _, newValue in
                guard let maxLength, newValue.count > maxLength else { return }
                text.wrappedValue = String(newValue.prefix(maxLength))
            }

            if let hint {
                Text(hint)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
