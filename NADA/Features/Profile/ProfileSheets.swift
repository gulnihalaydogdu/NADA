import PhotosUI
import SwiftUI

enum ProfileRoute: String, Identifiable {
    case edit
    case settings
    case preview
    case photos
    case bits
    case about
    case hangoutEnergy
    case location

    var id: String { rawValue }

    init(section: ProfileSection) {
        switch section {
        case .photos: self = .photos
        case .bits: self = .bits
        case .about: self = .about
        case .hangoutEnergy: self = .hangoutEnergy
        case .location: self = .location
        }
    }
}

/// Shared sheet chrome: paper background, inline title, Done button.
struct ProfileSheetScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NADATheme.paper.ignoresSafeArea()

                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NADATheme.brandPressed)
                }
            }
        }
    }
}

struct ProfileHangoutEnergySheet: View {
    private let interests = ["Coffee", "Walks", "Games", "Music", "Food", "Movies", "Sports", "Art"]

    var body: some View {
        ProfileSheetScaffold(title: "Hangout energy") {
            VStack(alignment: .leading, spacing: 16) {
                Text("What you're up for when you meet someone new. Picking interests becomes editable in Week 2.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)

                FlowChips(items: interests)
            }
        }
    }
}

/// Wrapping chip row used for preview-only interest tags.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chipRow(items)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(chunked(items, size: 3), id: \.first) { row in
                    chipRow(row)
                }
            }
        }
    }

    private func chipRow(_ row: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(row, id: \.self) { item in
                Text(item)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(NADATheme.brandSoft, in: Capsule())
            }
        }
    }

    private func chunked(_ items: [String], size: Int) -> [[String]] {
        stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }
}

struct ProfileLocationSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var city = ""
    @State private var radiusKm: Double = 25
    @State private var localError: String?

    private var canSave: Bool {
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !auth.isBusy
    }

    var body: some View {
        ProfileSheetScaffold(title: "Location & distance") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("City")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)

                    TextField("Where are you based?", text: $city)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(NADATheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                    Text("Radius is a preview — saving it comes in Week 2.")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }

                if let message = localError ?? auth.errorMessage {
                    Text(message)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                }

                Button {
                    Task { await save() }
                } label: {
                    if auth.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save city")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(!canSave)
            }
        }
        .onAppear {
            auth.clearError()
            city = auth.currentUser?.city ?? ""
        }
    }

    private func save() async {
        localError = nil

        guard let gender = ProfileGender.fromStored(auth.currentUser?.gender),
              let name = auth.currentUser?.displayName,
              !name.isEmpty else {
            localError = "Add your name and gender in About you first."
            return
        }

        let ok = await auth.updateBasicProfile(displayName: name, gender: gender, city: city)
        if ok {
            dismiss()
        } else if auth.errorMessage == nil {
            localError = "Couldn't save your city. Try again."
        }
    }
}

struct ProfilePreviewSheet: View {
    @Environment(AuthManager.self) private var auth

    let bits: [Prompt]
    var answers: [PromptAnswer] = []

    private var promptById: [String: Prompt] {
        Dictionary(uniqueKeysWithValues: bits.map { ($0.id, $0) })
    }

    var body: some View {
        ProfileSheetScaffold(title: "Preview") {
            VStack(spacing: 18) {
                ProfileAvatarImage(urlString: auth.currentUser?.photoURL, size: 160)

                VStack(spacing: 6) {
                    Text(auth.currentUser?.displayName ?? "Your name")
                        .font(NADATheme.displayFont)
                        .foregroundStyle(NADATheme.ink)

                    HStack(spacing: 14) {
                        if let gender = ProfileGender.fromStored(auth.currentUser?.gender)?.title {
                            Label(gender, systemImage: "person")
                        }
                        if let city = auth.currentUser?.city, !city.isEmpty {
                            Label(city, systemImage: "mappin")
                        }
                    }
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Bits")
                        .font(NADATheme.headlineFont)
                        .foregroundStyle(NADATheme.ink)

                    if answers.isEmpty {
                        Text("Answer Bits on your profile — friends will see them here.")
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.secondaryInk)
                    } else {
                        ForEach(answers) { answer in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(promptById[answer.promptId]?.text ?? "Bit")
                                    .font(NADATheme.captionFont)
                                    .foregroundStyle(NADATheme.brandPressed)
                                Text(answer.answerText)
                                    .font(NADATheme.bodyFont)
                                    .foregroundStyle(NADATheme.ink)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("This is an early look at how friends will see you.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ProfileSettingsSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProfileSheetScaffold(title: "Settings") {
            VStack(alignment: .leading, spacing: 16) {
                if let email = auth.currentUser?.email {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signed in as")
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.secondaryInk)
                        Text(email)
                            .font(NADATheme.bodyFont)
                            .foregroundStyle(NADATheme.ink)
                    }
                }

                Button {
                    dismiss()
                    auth.signOut()
                } label: {
                    Text("Log out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NADASecondaryButtonStyle())

                Text("Notifications, privacy, and account settings come later.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }
        }
    }
}

struct ProfileEditSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var city = ""
    @State private var gender: ProfileGender?
    @State private var localError: String?

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && gender != nil
            && !auth.isBusy
    }

    var body: some View {
        ProfileSheetScaffold(title: "Edit profile") {
            VStack(alignment: .leading, spacing: 24) {
                Text("Keep these up to date so hangouts feel personal.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)

                ProfileBasicsForm(
                    displayName: $displayName,
                    city: $city,
                    gender: $gender,
                    errorMessage: localError ?? auth.errorMessage
                )

                Button {
                    Task { await save() }
                } label: {
                    if auth.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(!canSave)
            }
        }
        .onAppear {
            auth.clearError()
            displayName = auth.currentUser?.displayName ?? ""
            city = auth.currentUser?.city ?? ""
            gender = ProfileGender.fromStored(auth.currentUser?.gender)
        }
    }

    private func save() async {
        localError = nil
        guard let gender else {
            localError = "Please select a gender option."
            return
        }

        let ok = await auth.updateBasicProfile(
            displayName: displayName,
            gender: gender,
            city: city
        )
        if ok {
            dismiss()
        } else if auth.errorMessage == nil {
            localError = "Couldn't save your profile. Try again."
        }
    }
}
