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
        case .photos: return "photo.on.rectangle"
        case .bits: return "bubble.left.and.text.bubble.right"
        case .interests: return "sparkles"
        case .about: return "person"
        case .location: return "slider.horizontal.3"
        }
    }
}

struct ProfileSuggestion: Identifiable {
    let section: ProfileSection
    let title: String

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
    let hasHangoutEssentials: Bool
    let userRadiusKm: Int?

    /// Completeness still uses the four required sections so the meter can hit 100% without badges.
    private static let meterSections: [ProfileSection] = [.photos, .bits, .about, .location]

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
        self.hasHangoutEssentials = user?.hasHangoutEssentials == true
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

    /// Average of the required sections. Interests are optional and do not cap the meter.
    var percentComplete: Int {
        let total = Self.meterSections.reduce(0.0) { $0 + progress(for: $1) }
        return Int((total / Double(Self.meterSections.count) * 100).rounded())
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
            items.append(ProfileSuggestion(section: .photos, title: "Add your first photo"))
        } else if photoCount < Self.photoTarget {
            items.append(ProfileSuggestion(section: .photos, title: "Add another photo"))
        }

        if answeredBits == 0 {
            items.append(ProfileSuggestion(section: .bits, title: "Answer your first Bit"))
        } else if answeredBits < Self.bitTarget {
            items.append(ProfileSuggestion(section: .bits, title: "Answer one more Bit"))
        }

        if interestCount == 0 {
            items.append(ProfileSuggestion(section: .interests, title: "Add interest badges"))
        }

        if !hasName || !hasGender || !hasBirthday {
            items.append(ProfileSuggestion(section: .about, title: "Finish the about you basics"))
        } else if !hasHangoutEssentials {
            items.append(
                ProfileSuggestion(
                    section: .about,
                    title: "Add job, school, or hangout looking-for"
                )
            )
        }

        if !hasCity {
            items.append(ProfileSuggestion(section: .location, title: "Add your city"))
        }

        return Array(items.prefix(3))
    }
}
