import PhotosUI
import SwiftUI
import UIKit

enum ProfileRoute: String, Identifiable {
    case edit
    case settings
    case preview
    case photos
    case bits
    case interests
    case about
    case location

    var id: String { rawValue }

    init(section: ProfileSection) {
        switch section {
        case .photos: self = .photos
        case .bits: self = .bits
        case .interests: self = .interests
        case .about: self = .about
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

/// Shared discover-preferences fields — used by Profile sheet and setup wizard.
struct ProfilePreferencesForm: View {
    private enum PickerRoute: String, Identifiable {
        case gender

        var id: String { rawValue }
    }

    @Binding var city: String
    @Binding var radiusKm: Double
    @Binding var lookingFor: UserPreferences.LookingForGender
    @Binding var minAge: Double
    @Binding var maxAge: Double
    @Binding var approxLatitude: Double?
    @Binding var approxLongitude: Double?
    @Binding var detectionError: String?

    var isBusy = false
    var autoDetectLocationOnAppear = false

    @State private var pickerRoute: PickerRoute?
    @State private var isDetectingLocation = false
    @State private var didAutoDetect = false
    @State private var locationService = ApproximateLocationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            peopleCard
            placeCard
        }
        .sheet(item: $pickerRoute) { route in
            switch route {
            case .gender:
                PreferenceOptionPicker(
                    title: "Friends who are",
                    subtitle: "Pick who shows up in Discover.",
                    options: UserPreferences.LookingForGender.allCases,
                    label: \.title,
                    selection: Binding(
                        get: { [lookingFor] },
                        set: { if let first = $0.first { lookingFor = first } }
                    )
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .task(id: autoDetectLocationOnAppear) {
            guard autoDetectLocationOnAppear, !didAutoDetect else { return }
            didAutoDetect = true
            await detectApproximateLocation()
        }
    }

    private var peopleCard: some View {
        preferenceCard(title: "Who you'll meet") {
            comboRow(
                icon: "person.2",
                title: "Friends who are",
                value: lookingFor.title
            ) {
                pickerRoute = .gender
            }

            cardDivider

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Age range", systemImage: "calendar")
                        .labelStyle(PreferenceLabelStyle())
                    Spacer()
                    Text("\(Int(minAge))–\(Int(maxAge))")
                        .font(NADATheme.headlineFont)
                        .foregroundStyle(NADATheme.ink)
                }

                AgeRangeSlider(
                    minValue: $minAge,
                    maxValue: $maxAge,
                    bounds: Double(UserPreferences.absoluteMinAge)...Double(UserPreferences.absoluteMaxAge),
                    step: 1
                )
                .frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var placeCard: some View {
        preferenceCard(title: "Where") {
            VStack(alignment: .leading, spacing: 10) {
                Label("City", systemImage: "mappin.and.ellipse")
                    .labelStyle(PreferenceLabelStyle())

                TextField("Type your city — e.g. Istanbul", text: $city)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(NADATheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: city) { _, _ in
                        approxLatitude = nil
                        approxLongitude = nil
                    }

                Button {
                    Task { await detectApproximateLocation() }
                } label: {
                    HStack(spacing: 8) {
                        if isDetectingLocation {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(isDetectingLocation ? "Finding approximate area…" : "Use approximate location")
                            .font(NADATheme.captionFont)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(NADATheme.brandPressed)
                }
                .buttonStyle(.plain)
                .disabled(isDetectingLocation || isBusy)

                Text(autoDetectLocationOnAppear
                    ? "We’ll ask for location here to suggest your city. You can always type it instead."
                    : "Typing is enough — location permission is optional.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            cardDivider

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Discover radius", systemImage: "dot.radiowaves.left.and.right")
                        .labelStyle(PreferenceLabelStyle())
                    Spacer()
                    Text("\(Int(radiusKm)) km")
                        .font(NADATheme.headlineFont)
                        .foregroundStyle(NADATheme.ink)
                }

                Slider(
                    value: $radiusKm,
                    in: Double(ProfileLocation.minimumRadiusKm)...Double(ProfileLocation.maximumRadiusKm),
                    step: Double(ProfileLocation.radiusStepKm)
                )
                .tint(NADATheme.brand)

                Text("We never show a precise pin — only your city and distance.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private func preferenceCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(NADATheme.secondaryInk)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(NADATheme.ink.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(NADATheme.ink.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 18)
    }

    private func comboRow(
        icon: String,
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: icon)
                    .labelStyle(PreferenceLabelStyle())

                Spacer(minLength: 12)

                Text(value)
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NADATheme.secondaryInk)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func detectApproximateLocation() async {
        detectionError = nil
        isDetectingLocation = true
        defer { isDetectingLocation = false }

        do {
            let place = try await locationService.requestApproximatePlace()
            if let detectedCity = place.city, !detectedCity.isEmpty {
                city = detectedCity
            }
            approxLatitude = place.latitude
            approxLongitude = place.longitude
            if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detectionError = "Found your area, but not a city name — type it in."
            }
        } catch {
            detectionError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't get your approximate location. Type your city instead."
        }
    }
}

struct ProfilePreferencesSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var city = ""
    @State private var radiusKm: Double = Double(ProfileLocation.defaultRadiusKm)
    @State private var lookingFor: UserPreferences.LookingForGender = .everyone
    @State private var minAge: Double = Double(UserPreferences.defaultMinAge)
    @State private var maxAge: Double = Double(UserPreferences.defaultMaxAge)
    @State private var approxLatitude: Double?
    @State private var approxLongitude: Double?
    @State private var localError: String?

    private var canSave: Bool {
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !auth.isBusy
    }

    var body: some View {
        ProfileSheetScaffold(title: "Discover preferences") {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose who you’d like to meet for hangouts nearby.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)

                ProfilePreferencesForm(
                    city: $city,
                    radiusKm: $radiusKm,
                    lookingFor: $lookingFor,
                    minAge: $minAge,
                    maxAge: $maxAge,
                    approxLatitude: $approxLatitude,
                    approxLongitude: $approxLongitude,
                    detectionError: $localError,
                    isBusy: auth.isBusy
                )

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
                        Text("Save preferences")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(!canSave)
            }
        }
        .task {
            auth.clearError()
            await auth.refreshPreferences()
            hydrateFromPreferences()
        }
    }

    private func hydrateFromPreferences() {
        let prefs = auth.currentPreferences
        city = prefs?.trimmedCity
            ?? auth.currentUser?.city
            ?? ""
        radiusKm = Double(
            prefs?.resolvedRadiusKm
                ?? auth.currentUser?.resolvedRadiusKm
                ?? ProfileLocation.defaultRadiusKm
        )
        lookingFor = prefs?.lookingForGenders ?? .everyone
        minAge = Double(prefs?.minAge ?? UserPreferences.defaultMinAge)
        maxAge = Double(prefs?.maxAge ?? UserPreferences.defaultMaxAge)
        approxLatitude = auth.currentUser?.approxLatitude
        approxLongitude = auth.currentUser?.approxLongitude
    }

    private func save() async {
        localError = nil
        guard let userId = auth.currentUser?.id else { return }

        let age = UserPreferences.clampAgeRange(min: Int(minAge), max: Int(maxAge))
        var prefs = auth.currentPreferences ?? UserPreferences.defaults(
            for: auth.currentUser ?? NADAUser(id: userId)
        )
        prefs.city = city
        prefs.radiusKm = ProfileLocation.clampRadiusKm(radiusKm)
        prefs.lookingForGenders = lookingFor
        prefs.minAge = age.min
        prefs.maxAge = age.max
        prefs.buddyTypes = [.openToAll]

        let ok = await auth.updatePreferences(prefs)
        if ok, let approxLatitude, let approxLongitude {
            // Coarse coords on user doc; mirrors prefs again from the just-saved filters.
            let locationOK = await auth.updateLocation(
                city: city,
                radiusKm: prefs.resolvedRadiusKm,
                approxLatitude: approxLatitude,
                approxLongitude: approxLongitude
            )
            if locationOK {
                dismiss()
            } else if auth.errorMessage == nil {
                localError = "Preferences saved, but approximate location couldn't be stored."
            }
            return
        }

        if ok {
            dismiss()
        } else if auth.errorMessage == nil {
            localError = "Couldn't save your preferences. Try again."
        }
    }
}

/// Dual-thumb slider — one track for min and max age.
private struct AgeRangeSlider: View {
    @Binding var minValue: Double
    @Binding var maxValue: Double
    let bounds: ClosedRange<Double>
    var step: Double = 1

    @State private var draggingLower: Bool?

    private let thumbSize: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - thumbSize, 1)
            let lowerX = xPosition(for: minValue, width: width)
            let upperX = xPosition(for: maxValue, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NADATheme.hairline)
                    .frame(height: 4)
                    .padding(.horizontal, thumbSize / 2)

                Capsule()
                    .fill(NADATheme.brand)
                    .frame(width: max(upperX - lowerX, 0), height: 4)
                    .offset(x: lowerX + thumbSize / 2)

                thumb(at: lowerX)
                thumb(at: upperX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let raw = value(for: gesture.location.x - thumbSize / 2, width: width)
                        if draggingLower == nil {
                            draggingLower = abs(raw - minValue) <= abs(raw - maxValue)
                        }
                        if draggingLower == true {
                            minValue = min(raw, maxValue)
                        } else {
                            maxValue = max(raw, minValue)
                        }
                    }
                    .onEnded { _ in
                        draggingLower = nil
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Age range")
            .accessibilityValue("\(Int(minValue)) to \(Int(maxValue))")
        }
    }

    private func thumb(at x: CGFloat) -> some View {
        Circle()
            .fill(NADATheme.card)
            .frame(width: thumbSize, height: thumbSize)
            .overlay {
                Circle()
                    .strokeBorder(NADATheme.brand, lineWidth: 2)
            }
            .shadow(color: NADATheme.ink.opacity(0.08), radius: 2, y: 1)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        return CGFloat((clamped - bounds.lowerBound) / span) * width
    }

    private func value(for x: CGFloat, width: CGFloat) -> Double {
        let ratio = min(max(x / width, 0), 1)
        let raw = bounds.lowerBound + Double(ratio) * (bounds.upperBound - bounds.lowerBound)
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, bounds.lowerBound), bounds.upperBound)
    }
}

/// Icon + title pairing used by every preference row.
private struct PreferenceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NADATheme.brandPressed)
                .frame(width: 26, height: 26)
                .background(NADATheme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            configuration.title
                .font(NADATheme.bodyFont)
                .fontWeight(.semibold)
                .foregroundStyle(NADATheme.ink)
        }
    }
}

/// Single- or multi-select list presented from a preference combo row.
private struct PreferenceOptionPicker<Option: Identifiable & Hashable>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var subtitle: String?
    let options: [Option]
    let label: KeyPath<Option, String>
    @Binding var selection: Set<Option>
    var allowsMultipleSelection = false
    /// Returns the next selection for a tapped option; lets callers enforce rules like an exclusive "Open to all".
    var selectionRule: (Set<Option>, Option) -> Set<Option> = { current, option in
        current.contains(option) ? current : [option]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let subtitle {
                        Text(subtitle)
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.secondaryInk)
                            .padding(.horizontal, 4)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            if index > 0 {
                                Rectangle()
                                    .fill(NADATheme.ink.opacity(0.06))
                                    .frame(height: 1)
                                    .padding(.leading, 18)
                            }
                            optionRow(option)
                        }
                    }
                    .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(NADATheme.ink.opacity(0.06), lineWidth: 1)
                    )
                }
                .padding(20)
            }
            .background(NADATheme.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func optionRow(_ option: Option) -> some View {
        let selected = selection.contains(option)

        return Button {
            selection = selectionRule(selection, option)
            if !allowsMultipleSelection {
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Text(option[keyPath: label])
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.ink)

                Spacer(minLength: 12)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? NADATheme.brand : NADATheme.hairline)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// How friends will see you — Hinge-inspired stack:
/// name → primary photo → first Bit → essentials → interests →
/// photo, photo, Bit, photo, Bit, photo, photo.
struct ProfilePreviewSheet: View {
    @Environment(AuthManager.self) private var auth

    let bits: [Prompt]
    var answers: [PromptAnswer] = []

    @State private var photos: [ProfilePhoto] = []
    @State private var isLoadingPhotos = false
    @State private var catalogInterests: [Interest] = []
    @State private var catalogBits: [Prompt]

    init(bits: [Prompt], answers: [PromptAnswer] = []) {
        self.bits = bits
        self.answers = answers
        _catalogBits = State(initialValue: bits)
    }

    private var promptById: [String: Prompt] {
        Dictionary(uniqueKeysWithValues: catalogBits.map { ($0.id, $0) })
    }

    private var sortedAnswers: [PromptAnswer] {
        answers.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var firstBit: (prompt: String, answer: String)? {
        guard let answer = sortedAnswers.first else { return nil }
        return (
            prompt: promptText(for: answer.promptId),
            answer: answer.answerText
        )
    }

    private var essentialsModel: ProfileEssentialsCard.Model {
        ProfileEssentialsCard.Model(
            age: auth.currentUser?.age,
            gender: ProfileGender.fromStored(auth.currentUser?.gender)?.title,
            city: auth.currentUser?.city,
            jobTitle: auth.currentUser?.trimmedJobTitle,
            university: auth.currentUser?.trimmedUniversity,
            hangoutLookingFor: auth.currentUser?.trimmedHangoutLookingFor,
            openToGroups: nil
        )
    }

    private var previewInterests: [Interest] {
        let byId = Dictionary(uniqueKeysWithValues: catalogInterests.map { ($0.id, $0) })
        return (auth.currentUser?.interestIds ?? []).compactMap { byId[$0] }
    }

    /// After name / primary / first Bit / essentials / interests.
    private var interleavedBlocks: [ProfilePreviewBlock] {
        let remainingPhotos = Array(photos.dropFirst())
        let remainingBits = Array(sortedAnswers.dropFirst())
        return ProfileStackRhythm.tail(photos: remainingPhotos, bits: remainingBits).map { item in
            switch item {
            case .photo(let photo):
                return .photo(photo)
            case .bit(let answer):
                return .bit(
                    prompt: promptText(for: answer.promptId),
                    answer: answer.answerText
                )
            }
        }
    }

    var body: some View {
        ProfileSheetScaffold(title: "Preview") {
            LazyVStack(spacing: 14) {
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
            await loadCatalog()
            await loadInterests()
        }
    }

    @ViewBuilder
    private var profileStack: some View {
        // 1. Name + zodiac
        VStack(alignment: .leading, spacing: 4) {
            Text(auth.currentUser?.displayName ?? "Your name")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
            ProfileZodiacCaption(
                sign: auth.currentUser?.dateOfBirth.map { ZodiacSign.from(dateOfBirth: $0) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // 2. Primary photo
        if let primary = photos.first {
            ProfilePreviewPhotoTile(
                urlString: primary.url,
                thumbnailURLString: primary.thumbnailURL
            )
        } else if let url = auth.currentUser?.photoURL, !url.isEmpty {
            ProfilePreviewPhotoTile(
                urlString: url,
                thumbnailURLString: auth.currentUser?.photoThumbnailURL
            )
        } else {
            ProfilePreviewPhotoTile(urlString: nil)
        }

        // 3. First Bit under the primary photo
        if let firstBit {
            ProfilePreviewBitCard(prompt: firstBit.prompt, answer: firstBit.answer)
        }

        // 4. Essentials (“about”) card
        ProfileEssentialsCard(model: essentialsModel)

        // 5. Interest badges under essentials
        ProfileInterestBadgesView(interests: previewInterests)

        // 6. Remaining: photo, photo, Bit, photo, Bit, photo, photo
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
                    ProfilePreviewPhotoTile(
                        urlString: photo.url,
                        thumbnailURLString: photo.thumbnailURL
                    )
                case .bit(let prompt, let answer):
                    ProfilePreviewBitCard(prompt: prompt, answer: answer)
                }
            }
        }
    }

    private func promptText(for promptId: String) -> String {
        promptById[promptId]?.text ?? ""
    }

    private func loadPhotos() async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        photos = await auth.fetchPhotos()
        // Only the next couple of photos — the rest load as they scroll into view.
        RemoteImageLoader.shared.prefetch(
            urlStrings: photos.dropFirst().prefix(2).map(\.url),
            targetPointSize: 430,
            limit: 2
        )
    }

    private func loadCatalog() async {
        catalogBits = (try? await FirestorePromptService().fetchActivePrompts(locale: "en")) ?? catalogBits
    }

    private func loadInterests() async {
        catalogInterests = (try? await FirestoreInterestService().fetchActiveInterests(locale: "en")) ?? []
    }
}

private enum ProfilePreviewBlock {
    case photo(ProfilePhoto)
    case bit(prompt: String, answer: String)
}

/// Remaining cards after primary photo + first Bit + essentials + interests.
/// Full 6-photo / 3-Bit profile: photo, photo, Bit, photo, Bit, photo, photo.
enum ProfileStackRhythm {
    enum Item<Photo, Bit> {
        case photo(Photo)
        case bit(Bit)
    }

    private enum Slot {
        case photo
        case bit
    }

    private static let tailSlots: [Slot] = [
        .photo, .photo, .bit, .photo, .bit, .photo, .photo
    ]

    static func tail<Photo, Bit>(photos: [Photo], bits: [Bit]) -> [Item<Photo, Bit>] {
        var photoIndex = 0
        var bitIndex = 0
        var items: [Item<Photo, Bit>] = []

        for slot in tailSlots {
            switch slot {
            case .photo:
                guard photoIndex < photos.count else { continue }
                items.append(.photo(photos[photoIndex]))
                photoIndex += 1
            case .bit:
                guard bitIndex < bits.count else { continue }
                items.append(.bit(bits[bitIndex]))
                bitIndex += 1
            }
        }

        while photoIndex < photos.count {
            items.append(.photo(photos[photoIndex]))
            photoIndex += 1
        }
        while bitIndex < bits.count {
            items.append(.bit(bits[bitIndex]))
            bitIndex += 1
        }
        return items
    }
}

/// Full-width square photo tile (Discover / Preview).
struct ProfilePreviewPhotoTile: View {
    let urlString: String?
    /// Small file shown while the full-size decode finishes.
    var thumbnailURLString: String? = nil

    /// Display decode size for Discover / Preview tiles (matches prefetch).
    static let displayPointSize: CGFloat = 430
    var cornerRadius: CGFloat = 22

    /// Full-bleed inside the sheet — one iPad-safe cap keeps this off `UIScreen`.
    private var targetPointSize: CGFloat { Self.displayPointSize }

    var body: some View {
        Group {
            if urlString?.isEmpty == false {
                RemoteImageView(
                    urlString: urlString,
                    thumbnailURLString: thumbnailURLString,
                    targetPointSize: targetPointSize
                )
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

/// Editorial Bit card — prompt is secondary, the answer is the voice.
struct ProfilePreviewBitCard: View {
    let prompt: String
    let answer: String
    var showsChrome: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NADATheme.brandPressed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(answer)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(NADATheme.ink)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(showsChrome ? 20 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if showsChrome {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(NADATheme.card)
            }
        }
        .overlay {
            if showsChrome {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.38), lineWidth: 1)
            }
        }
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Defne")
                    .font(NADATheme.displayFont)
                    .foregroundStyle(NADATheme.ink)
                ProfileZodiacCaption(sign: .leo)
            }
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
    @State private var dateOfBirth: Date?
    @State private var jobTitle = ""
    @State private var university = ""
    @State private var hangoutLookingFor = ""
    @State private var localError: String?

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && gender != nil
            && dateOfBirth != nil
            && !auth.isBusy
    }

    var body: some View {
        ProfileSheetScaffold(title: "Edit profile") {
            VStack(alignment: .leading, spacing: 24) {
                Text("Keep these up to date so hangouts feel personal. NADA is 18+.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)

                ProfileBasicsForm(
                    displayName: $displayName,
                    city: $city,
                    gender: $gender,
                    dateOfBirth: $dateOfBirth,
                    jobTitle: $jobTitle,
                    university: $university,
                    hangoutLookingFor: $hangoutLookingFor,
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
            dateOfBirth = auth.currentUser?.dateOfBirth
            jobTitle = auth.currentUser?.trimmedJobTitle ?? ""
            university = auth.currentUser?.trimmedUniversity ?? ""
            hangoutLookingFor = auth.currentUser?.trimmedHangoutLookingFor ?? ""
        }
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
            dateOfBirth: dateOfBirth,
            jobTitle: jobTitle,
            university: university,
            hangoutLookingFor: hangoutLookingFor,
            updateHangoutEssentials: true
        )
        if ok {
            dismiss()
        } else if auth.errorMessage == nil {
            localError = "Couldn't save your profile. Try again."
        }
    }
}
