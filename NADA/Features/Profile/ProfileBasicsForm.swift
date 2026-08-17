import SwiftUI

/// Shared name / gender / birthday / city form used by the onboarding gate and Edit Profile sheet.
/// Hangout essentials (job, university, looking-for) are collected after signup, not on this gate.
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
        VStack(alignment: .leading, spacing: NADATheme.Layout.fieldSpacing) {
            ProfileLimitedTextField(
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
            ProfileLimitedTextField(
                title: "City",
                text: $city,
                placeholder: "Where are you based?"
            )

            if let jobTitle, let university, let hangoutLookingFor {
                ProfileHangoutEssentialsForm(
                    jobTitle: jobTitle,
                    university: university,
                    hangoutLookingFor: hangoutLookingFor
                )
            }

            if let errorMessage, !errorMessage.isEmpty {
                NADAAuthErrorBanner(message: errorMessage)
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
                .padding(.horizontal, NADATheme.Layout.fieldHPadding)
                .frame(maxWidth: .infinity, minHeight: NADATheme.Layout.fieldMinHeight, alignment: .leading)
                .background(
                    NADATheme.surface,
                    in: RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Age")
            .accessibilityHint("Opens birthday picker")

            Text("Friends only see your age, not your birthday. NADA is \(ProfileAge.minimumAge)+.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ageCapsuleLabel: String {
        if let dateOfBirth {
            return "\(ProfileAge.age(from: dateOfBirth))"
        }
        return "Add your age"
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
        .padding(.horizontal, NADATheme.Layout.fieldHPadding)
        .frame(maxWidth: .infinity, minHeight: NADATheme.Layout.fieldMinHeight, alignment: .leading)
        .background(
            NADATheme.surface,
            in: RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous)
        )
    }
}

/// Job, university, and hangout looking-for — asked after signup (wizard + Edit), never on the basics gate.
struct ProfileHangoutEssentialsForm: View {
    @Binding var jobTitle: String
    @Binding var university: String
    @Binding var hangoutLookingFor: String
    var showsSectionHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: NADATheme.Layout.fieldSpacing) {
            if showsSectionHeader {
                Text("On your Discover card")
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.ink)
                    .padding(.top, 4)

                Text("Optional — friends see these under your photos. Skip anything that doesn’t fit.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProfileLimitedTextField(
                title: "Job / role",
                text: $jobTitle,
                placeholder: "Student, designer, barista…",
                maxLength: NADAUser.maxJobTitleLength
            )

            ProfileLimitedTextField(
                title: "University",
                text: $university,
                placeholder: "Last or current school",
                maxLength: NADAUser.maxUniversityLength
            )

            ProfileLimitedTextField(
                title: "Hangout looking-for",
                text: $hangoutLookingFor,
                placeholder: "Looking for a travel-buddy from Istanbul",
                maxLength: NADAUser.maxHangoutLookingForLength,
                axis: .vertical,
                hint: "A short line about the kind of hangout or buddy you want."
            )
        }
    }
}

private struct ProfileLimitedTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var maxLength: Int? = nil
    var axis: Axis = .horizontal
    var hint: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                if let maxLength {
                    Spacer()
                    Text("\(min(text.count, maxLength))/\(maxLength)")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }
            }

            Group {
                if axis == .vertical {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(2...4)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .focused($isFocused)
            .textInputAutocapitalization(axis == .vertical ? .sentences : .words)
            .autocorrectionDisabled()
            .padding(.horizontal, NADATheme.Layout.fieldHPadding)
            .padding(.vertical, axis == .vertical ? 14 : 0)
            .frame(maxWidth: .infinity, minHeight: axis == .vertical ? 88 : NADATheme.Layout.fieldMinHeight, alignment: .leading)
            .background(NADATheme.surface, in: RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous)
                    .strokeBorder(isFocused ? NADATheme.brand.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
            .onChange(of: text) { _, newValue in
                guard let maxLength, newValue.count > maxLength else { return }
                text = String(newValue.prefix(maxLength))
            }

            if let hint {
                Text(hint)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
