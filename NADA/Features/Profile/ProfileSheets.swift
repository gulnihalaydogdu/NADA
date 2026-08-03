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

/// How friends will see you — Hinge-inspired stack:
/// name → primary photo → first Bit → essentials → remaining photos interleaved with Bits.
struct ProfilePreviewSheet: View {
    @Environment(AuthManager.self) private var auth

    let bits: [Prompt]
    var answers: [PromptAnswer] = []

    @State private var photos: [ProfilePhoto] = []
    @State private var isLoadingPhotos = false

    private var promptById: [String: Prompt] {
        Dictionary(uniqueKeysWithValues: bits.map { ($0.id, $0) })
    }

    private var sortedAnswers: [PromptAnswer] {
        answers.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var firstBit: (prompt: String, answer: String)? {
        guard let answer = sortedAnswers.first else { return nil }
        return (
            prompt: promptById[answer.promptId]?.text ?? "Bit",
            answer: answer.answerText
        )
    }

    private var essentialsModel: ProfileEssentialsCard.Model {
        ProfileEssentialsCard.Model(
            age: nil, // birth year not collected yet
            gender: ProfileGender.fromStored(auth.currentUser?.gender)?.title,
            city: auth.currentUser?.city,
            jobTitle: nil,
            university: nil,
            hangoutLookingFor: nil,
            openToGroups: nil
        )
    }

    /// After name / primary / first Bit / essentials: photo → bit → photo → bit → …
    private var interleavedBlocks: [ProfilePreviewBlock] {
        let remainingPhotos = Array(photos.dropFirst())
        let remainingBits = Array(sortedAnswers.dropFirst())
        var blocks: [ProfilePreviewBlock] = []
        var photoIndex = 0
        var bitIndex = 0

        while photoIndex < remainingPhotos.count || bitIndex < remainingBits.count {
            if photoIndex < remainingPhotos.count {
                blocks.append(.photo(remainingPhotos[photoIndex]))
                photoIndex += 1
            }
            if bitIndex < remainingBits.count {
                let answer = remainingBits[bitIndex]
                blocks.append(
                    .bit(
                        prompt: promptById[answer.promptId]?.text ?? "Bit",
                        answer: answer.answerText
                    )
                )
                bitIndex += 1
            }
        }
        return blocks
    }

    var body: some View {
        ProfileSheetScaffold(title: "Preview") {
            VStack(spacing: 14) {
                if isLoadingPhotos && photos.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    profileStack
                }

                Text("This is how friends will see you.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            await loadPhotos()
        }
    }

    @ViewBuilder
    private var profileStack: some View {
        // 1. Name (Active / pronouns later)
        Text(auth.currentUser?.displayName ?? "Your name")
            .font(NADATheme.displayFont)
            .foregroundStyle(NADATheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)

        // 2. Primary photo
        if let primary = photos.first {
            ProfilePreviewPhotoTile(urlString: primary.url)
        } else if let url = auth.currentUser?.photoURL, !url.isEmpty {
            ProfilePreviewPhotoTile(urlString: url)
        } else {
            ProfilePreviewPhotoTile(urlString: nil)
        }

        // 3. First Bit under the primary photo
        if let firstBit {
            ProfilePreviewBitCard(prompt: firstBit.prompt, answer: firstBit.answer)
        }

        // 4. Essentials (“about”) card
        ProfileEssentialsCard(model: essentialsModel)

        // 5. Remaining photos interleaved with remaining Bits
        if interleavedBlocks.isEmpty, firstBit == nil, photos.count <= 1 {
            Text("Add more photos and Bits — they’ll show up here like on Discover.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } else {
            ForEach(Array(interleavedBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .photo(let photo):
                    ProfilePreviewPhotoTile(urlString: photo.url)
                case .bit(let prompt, let answer):
                    ProfilePreviewBitCard(prompt: prompt, answer: answer)
                }
            }
        }
    }

    private func loadPhotos() async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        photos = await auth.fetchPhotos()
    }
}

private enum ProfilePreviewBlock {
    case photo(ProfilePhoto)
    case bit(prompt: String, answer: String)
}

/// Full-width square photo tile (Discover / Preview).
struct ProfilePreviewPhotoTile: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ZStack {
                            NADATheme.brandSoft
                            ProgressView()
                        }
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            NADATheme.brandSoft
            Image(systemName: "person.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(NADATheme.brand)
        }
    }
}

/// Hinge-style Bit card — content-height rectangle (not square); sans prompt + bold answer.
struct ProfilePreviewBitCard: View {
    let prompt: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NADATheme.brandPressed)
                .fixedSize(horizontal: false, vertical: true)

            Text(answer)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(NADATheme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview("Bit card") {
    ProfilePreviewBitCard(
        prompt: "I could stay up all night talking about",
        answer: "movies and series!!"
    )
    .padding(24)
    .background(NADATheme.paper)
}

#Preview("Preview stack") {
    ScrollView {
        VStack(spacing: 14) {
            Text("Defne")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NADATheme.brandSoft)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(NADATheme.brand)
                }

            ProfilePreviewBitCard(
                prompt: "I’m always down for",
                answer: "A spontaneous day trip with good playlists"
            )

            ProfileEssentialsCard(
                model: .init(
                    age: 21,
                    gender: "Woman",
                    city: "Istanbul",
                    jobTitle: "Student",
                    university: "Bilkent University",
                    hangoutLookingFor: "Looking for a travel-buddy from Istanbul",
                    openToGroups: nil
                )
            )

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NADATheme.surface)
                .aspectRatio(1, contentMode: .fit)

            ProfilePreviewBitCard(
                prompt: "The friend energy I bring",
                answer: "Planner + hype person combo"
            )
        }
        .padding(24)
    }
    .background(NADATheme.paper)
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
