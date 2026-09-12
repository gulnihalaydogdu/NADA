import Foundation

/// Sections listed on the Profile tab. Order matches the design.
enum ProfileSection: String, CaseIterable, Identifiable {
    case photos
    case bits
    case interests
    case about
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: return "Photos"
        case .bits: return "Bits"
        case .interests: return "Interests"
        case .about: return "About you"
        case .location: return "Discover preferences"
        }
    }

    var systemImage: String {
        switch self {
        case .photos: return "photo"
        case .bits: return "text.bubble"
        case .interests: return "sparkle"
        case .about: return "person.crop.circle"
        case .location: return "location"
        }
    }
}

struct ProfileSuggestion: Identifiable {
    let section: ProfileSection
    let title: String
    let note: String

    var id: String { section.id }
}

/// Drives the completion meter, section rows, and "make it feel like you" nudges.
struct ProfileCompletion {
    static let photoTarget = ProfilePhoto.maxCount
    static let bitTarget = PromptAnswer.maxCount

    let photoCount: Int
    let answeredBits: Int
    let interestCount: Int
    let hasName: Bool
    let hasGender: Bool
    let hasCity: Bool
    let hasBirthday: Bool
    let hasJobTitle: Bool
    let hasUniversity: Bool
    let hasHangoutLookingFor: Bool
    let userRadiusKm: Int?

    /// Photos, Bits, About basics, and city — Discover-ready. These own 90% of the meter.
    private static let meterSections: [ProfileSection] = [.photos, .bits, .about, .location]
    private static let coreWeight = 0.90
    private static let extrasWeight = 0.10

    init(user: NADAUser?, photoCount: Int? = nil, answeredBits: Int = 0) {
        if let photoCount {
            self.photoCount = min(max(photoCount, 0), Self.photoTarget)
        } else {
            self.photoCount = (user?.photoURL?.isEmpty == false) ? 1 : 0
        }
        self.answeredBits = answeredBits
        self.interestCount = min(user?.interestIds.count ?? 0, InterestSelection.maxCount)
        self.hasName = user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.hasGender = ProfileGender.fromStored(user?.gender) != nil
        self.hasCity = user?.city?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.hasBirthday = user?.dateOfBirth.map { ProfileAge.isAtLeastMinimumAge($0) } == true
        self.hasJobTitle = user?.trimmedJobTitle != nil
        self.hasUniversity = user?.trimmedUniversity != nil
        self.hasHangoutLookingFor = user?.trimmedHangoutLookingFor != nil
        self.userRadiusKm = user?.radiusKm.map { ProfileLocation.clampRadiusKm($0) }
    }

    func progress(for section: ProfileSection) -> Double {
        switch section {
        case .photos:
            return min(Double(photoCount) / Double(Self.photoTarget), 1)
        case .bits:
            return min(Double(answeredBits) / Double(Self.bitTarget), 1)
        case .interests:
            return min(Double(interestCount) / Double(InterestSelection.maxCount), 1)
        case .about:
            let filled = [hasName, hasGender, hasBirthday].filter { $0 }.count
            return Double(filled) / 3
        case .location:
            // City is required; radius defaults until first save but counts once city exists.
            return hasCity ? 1 : 0
        }
    }

    private var hasHangoutEssentials: Bool {
        hasJobTitle || hasUniversity || hasHangoutLookingFor
    }

    /// Job / uni / looking-for fill half of the optional 10%; interests fill the other half.
    private var extrasProgress: Double {
        let filled = [hasJobTitle, hasUniversity, hasHangoutLookingFor].filter { $0 }.count
        let essentials = Double(filled) / 3.0
        let interests = progress(for: .interests)
        return (essentials + interests) / 2.0
    }

    /// Core sections are 90%. Optional extras (Discover-card fields + interests) are 10%,
    /// so skipping them never looks like an incomplete profile for Discover.
    var percentComplete: Int {
        let core = Self.meterSections.reduce(0.0) { $0 + progress(for: $1) }
            / Double(Self.meterSections.count)
        let total = core * Self.coreWeight + extrasProgress * Self.extrasWeight
        return Int((total * 100).rounded())
    }

    func detail(for section: ProfileSection) -> String? {
        switch section {
        case .photos:
            return "\(photoCount) / \(Self.photoTarget)"
        case .bits:
            return "\(answeredBits) / \(Self.bitTarget)"
        case .interests:
            return "\(interestCount) / \(InterestSelection.maxCount)"
        case .about:
            return (hasName && hasGender && hasBirthday) ? nil : "Add details"
        case .location:
            guard hasCity else { return "Add city" }
            let radius = userRadiusKm ?? ProfileLocation.defaultRadiusKm
            return "\(radius) km"
        }
    }

    /// At most three nudges, ordered by what moves the meter first.
    var suggestions: [ProfileSuggestion] {
        var items: [ProfileSuggestion] = []

        if photoCount == 0 {
            items.append(
                ProfileSuggestion(
                    section: .photos,
                    title: "Add your first photo",
                    note: "A clear photo makes it easier to say hi."
                )
            )
        } else if photoCount < Self.photoTarget {
            items.append(
                ProfileSuggestion(
                    section: .photos,
                    title: "Add another photo",
                    note: "A couple more shots give people a better sense of you."
                )
            )
        }

        if answeredBits == 0 {
            items.append(
                ProfileSuggestion(
                    section: .bits,
                    title: "Answer your first Bit",
                    note: "A short answer people can click — hangout energy, not a bio."
                )
            )
        } else if answeredBits < Self.bitTarget {
            items.append(
                ProfileSuggestion(
                    section: .bits,
                    title: "Answer one more Bit",
                    note: "One more makes your card feel lived-in."
                )
            )
        }

        if interestCount == 0 {
            items.append(
                ProfileSuggestion(
                    section: .interests,
                    title: "Add interest badges",
                    note: "A few interests help the right people find you."
                )
            )
        }

        if !hasName || !hasGender || !hasBirthday {
            items.append(
                ProfileSuggestion(
                    section: .about,
                    title: "Finish the about you basics",
                    note: "Name, gender, and birthday keep Discover accurate."
                )
            )
        } else if !hasHangoutEssentials {
            items.append(
                ProfileSuggestion(
                    section: .about,
                    title: "Add job, school, or hangout looking-for",
                    note: "Small details that make hangouts easier to picture."
                )
            )
        }

        if !hasCity {
            items.append(
                ProfileSuggestion(
                    section: .location,
                    title: "Add your city",
                    note: "City is how we show people nearby."
                )
            )
        }

        return Array(items.prefix(3))
    }
}
