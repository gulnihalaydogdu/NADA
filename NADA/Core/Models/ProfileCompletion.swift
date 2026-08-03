import Foundation

/// Sections listed on the Profile tab. Order matches the design.
enum ProfileSection: String, CaseIterable, Identifiable {
    case photos
    case bits
    case about
    case hangoutEnergy
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: return "Photos"
        case .bits: return "Bits"
        case .about: return "About you"
        case .hangoutEnergy: return "Hangout energy"
        case .location: return "Location & distance"
        }
    }

    var systemImage: String {
        switch self {
        case .photos: return "photo.on.rectangle"
        case .bits: return "bubble.left.and.text.bubble.right"
        case .about: return "person"
        case .hangoutEnergy: return "star"
        case .location: return "mappin.and.ellipse"
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

    init(user: NADAUser?, photoCount: Int? = nil, answeredBits: Int = 0, interestCount: Int = 0) {
        if let photoCount {
            self.photoCount = min(max(photoCount, 0), Self.photoTarget)
        } else {
            self.photoCount = (user?.photoURL?.isEmpty == false) ? 1 : 0
        }
        self.answeredBits = answeredBits
        self.interestCount = interestCount
        self.hasName = user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.hasGender = ProfileGender.fromStored(user?.gender) != nil
        self.hasCity = user?.city?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func progress(for section: ProfileSection) -> Double {
        switch section {
        case .photos:
            return min(Double(photoCount) / Double(Self.photoTarget), 1)
        case .bits:
            return min(Double(answeredBits) / Double(Self.bitTarget), 1)
        case .about:
            let filled = [hasName, hasGender].filter { $0 }.count
            return Double(filled) / 2
        case .hangoutEnergy:
            return interestCount > 0 ? 1 : 0
        case .location:
            return hasCity ? 1 : 0
        }
    }

    /// Average of all section progress, so a section landing in Week 2 keeps the bar honest.
    var percentComplete: Int {
        let total = ProfileSection.allCases.reduce(0.0) { $0 + progress(for: $1) }
        return Int((total / Double(ProfileSection.allCases.count) * 100).rounded())
    }

    func detail(for section: ProfileSection) -> String? {
        switch section {
        case .photos:
            return "\(photoCount) / \(Self.photoTarget)"
        case .bits:
            return "\(answeredBits) / \(Self.bitTarget)"
        case .about:
            return (hasName && hasGender) ? nil : "Add details"
        case .hangoutEnergy:
            return interestCount > 0 ? "\(interestCount)" : "Add"
        case .location:
            return hasCity ? nil : "Add city"
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
            items.append(ProfileSuggestion(section: .hangoutEnergy, title: "Add your hangout interests"))
        }

        if !hasName || !hasGender {
            items.append(ProfileSuggestion(section: .about, title: "Finish the about you basics"))
        }

        if !hasCity {
            items.append(ProfileSuggestion(section: .location, title: "Add your city"))
        }

        return Array(items.prefix(3))
    }
}
