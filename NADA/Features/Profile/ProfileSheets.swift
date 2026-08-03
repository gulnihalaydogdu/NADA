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

struct ProfileBitsSheet: View {
    /// Optional seed from the parent; sheet always refreshes on open.
    var initialBits: [Prompt] = []

    @State private var bits: [Prompt] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCategory: Prompt.Category?

    private let promptService = FirestorePromptService()

    /// Only categories that actually have seeded bits, in catalog order.
    private var availableCategories: [Prompt.Category] {
        Prompt.Category.allCases.filter { category in
            bits.contains { $0.category == category }
        }
    }

    private var filteredBits: [Prompt] {
        guard let selectedCategory else { return bits }
        return bits.filter { $0.category == selectedCategory }
    }

    var body: some View {
        ProfileSheetScaffold(title: "Bits") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bits are the short answers friends read on your profile. Picking and writing answers lands in Week 2.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)

                if isLoading && bits.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else if let errorMessage, bits.isEmpty {
                    Text(errorMessage)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                } else if bits.isEmpty {
                    Text("No bits in the catalog yet. Seed the `prompts` collection in Firestore.")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                } else {
                    categoryChips

                    ForEach(filteredBits) { bit in
                        bitCard(bit)
                    }
                }
            }
        }
        .task {
            if bits.isEmpty { bits = initialBits }
            await reload()
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            bits = try await promptService.fetchActivePrompts(locale: "en")
        } catch {
            if bits.isEmpty {
                errorMessage = "Couldn't load bits. Check Firestore rules and the `prompts` seed."
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(availableCategories) { category in
                    chip(title: category.title, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -24)
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(NADATheme.captionFont)
            }
            .foregroundStyle(isSelected ? NADATheme.onBrand : NADATheme.warmSecondaryInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? NADATheme.brand : NADATheme.card, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : NADATheme.ink.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private func bitCard(_ bit: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bit.text)
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.ink)

            HStack(spacing: 8) {
                Text(bit.category.title)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.brandPressed)

                Text("Answering comes in Week 2")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Bits")
                        .font(NADATheme.headlineFont)
                        .foregroundStyle(NADATheme.ink)

                    if let firstBit = bits.first {
                        Text(firstBit.text)
                            .font(NADATheme.bodyFont)
                            .foregroundStyle(NADATheme.ink)
                    }

                    Text("Your answers will show here once bits open up in Week 2.")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
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
