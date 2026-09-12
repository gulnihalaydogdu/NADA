import SwiftUI
import UIKit

/// Shared name / gender / birthday / city form used by the onboarding gate and Edit Profile sheet.
/// Hangout essentials (job, university, looking-for) are collected after signup, not on this gate.
enum ProfileBasicsField: Hashable {
    case displayName
    case gender
    case age
    case city
}

struct ProfileBasicsForm: View {
    @Binding var displayName: String
    @Binding var city: String
    @Binding var gender: ProfileGender?
    @Binding var dateOfBirth: Date?
    var jobTitle: Binding<String>? = nil
    var university: Binding<String>? = nil
    var hangoutLookingFor: Binding<String>? = nil
    var errorMessage: String?
    /// Defaults to the full form (Edit Profile). Onboarding shows one field at a time.
    var visibleFields: [ProfileBasicsField] = [.displayName, .gender, .age, .city]
    var autofocusDisplayName = false
    var onDisplayNameSubmit: (() -> Void)? = nil
    var autofocusCity = false
    var onCitySubmit: (() -> Void)? = nil

    @State private var isBirthdayPickerPresented = false
    @State private var pickerDraftDate: Date?

    private func shows(_ field: ProfileBasicsField) -> Bool {
        visibleFields.contains(field)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NADATheme.Layout.fieldSpacing) {
            if shows(.displayName) {
                ProfileLimitedTextField(
                    title: "Display name",
                    text: $displayName,
                    placeholder: "What should friends call you?",
                    autofocus: autofocusDisplayName,
                    submitLabel: onDisplayNameSubmit == nil ? nil : .continue,
                    textContentType: .name,
                    onSubmit: onDisplayNameSubmit
                )
            }

            if shows(.gender) {
                genderTiles
            }

            if shows(.age) {
                birthdayField
            }

            // Hometown stays free-text for MVP — full country/city catalogs are a later decision.
            if shows(.city) {
                ProfileLimitedTextField(
                    title: "Hometown",
                    text: $city,
                    placeholder: "Istanbul, London…",
                    autofocus: autofocusCity,
                    submitLabel: onCitySubmit == nil ? nil : .continue,
                    textContentType: .addressCity,
                    onSubmit: onCitySubmit
                )
            }

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
            Text("Birthday")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            Button {
                isBirthdayPickerPresented = true
            } label: {
                HStack(spacing: 10) {
                    Text(birthdayCapsuleLabel)
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
            .accessibilityLabel("Birthday")
            .accessibilityHint("Opens birthday picker")
            .accessibilityValue(birthdayCapsuleLabel)

            if let dateOfBirth, visibleFields == [.age] {
                agePreviewCard(for: dateOfBirth)
            } else {
                Text("Friends only see your age, not your birthday.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var birthdayCapsuleLabel: String {
        if let dateOfBirth {
            return Self.birthdayFormatter.string(from: dateOfBirth)
        }
        return "Add your birthday"
    }

    private static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func agePreviewCard(for dateOfBirth: Date) -> some View {
        let years = ProfileAge.age(from: dateOfBirth)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Friends will see \(years).")
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)

            Text("Hangouts feel more natural with people around the same age. Your birthday stays private.")
            .font(NADATheme.bodyFont)
            .foregroundStyle(NADATheme.warmSecondaryInk)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            NADATheme.card,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(NADATheme.ink.opacity(0.06), lineWidth: 1)
        )
        .padding(.top, 8)
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

    private var genderTiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gender")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(ProfileGender.allCases) { option in
                    let isSelected = gender == option
                    Button {
                        gender = option
                    } label: {
                        Text(option.title)
                            .font(NADATheme.bodyFont)
                            .foregroundStyle(NADATheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, 20)
                            .background(
                                isSelected ? NADATheme.brandSoft : NADATheme.surface,
                                in: RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: NADATheme.Layout.fieldRadius, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? NADATheme.brand.opacity(0.55) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                NADATheme.card,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(NADATheme.ink.opacity(0.06), lineWidth: 1)
            )
        }
        .padding(.horizontal, 8)
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
    var autofocus = false
    var submitLabel: SubmitLabel? = nil
    var textContentType: UITextContentType? = nil
    var onSubmit: (() -> Void)? = nil

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
            .nadaDismissKeyboardOnTap()

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
            .nadaSubmitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .nadaTextContentType(textContentType)
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
        .task(id: autofocus) {
            guard autofocus else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            isFocused = true
        }
    }
}

private extension View {
    @ViewBuilder
    func nadaSubmitLabel(_ label: SubmitLabel?) -> some View {
        if let label {
            self.submitLabel(label)
        } else {
            self
        }
    }

    @ViewBuilder
    func nadaTextContentType(_ type: UITextContentType?) -> some View {
        if let type {
            self.textContentType(type)
        } else {
            self
        }
    }
}
