import Foundation

enum ProfileGender: String, CaseIterable, Identifiable, Sendable {
    case woman = "woman"
    case man = "man"
    case nonBinary = "nonBinary"
    case preferNotToSay = "preferNotToSay"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .woman: return "Woman"
        case .man: return "Man"
        case .nonBinary: return "Non-binary"
        case .preferNotToSay: return "Prefer not to say"
        }
    }

    static func fromStored(_ value: String?) -> ProfileGender? {
        guard let value else { return nil }
        return ProfileGender(rawValue: value)
    }
}

/// Birthday / 18+ helpers for the basic profile gate.
enum ProfileAge {
    static let minimumAge = 18

    static func age(from dateOfBirth: Date, on reference: Date = Date()) -> Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: reference).year ?? 0
    }

    static func isAtLeastMinimumAge(_ dateOfBirth: Date, on reference: Date = Date()) -> Bool {
        age(from: dateOfBirth, on: reference) >= minimumAge
    }

    /// Youngest allowed birthday (exactly `minimumAge` years ago).
    static func maximumSelectableDate(on reference: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .year, value: -minimumAge, to: reference) ?? reference
    }

    static func minimumSelectableDate(on reference: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .year, value: -120, to: reference) ?? reference
    }
}

extension NADAUser {
    var hasCompletedBasicProfile: Bool {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gender = gender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let dateOfBirth else { return false }
        return !name.isEmpty
            && !city.isEmpty
            && ProfileGender.fromStored(gender) != nil
            && ProfileAge.isAtLeastMinimumAge(dateOfBirth)
    }
}

/// Discover-ready gate stored on `users/{uid}.isProfileComplete` (W2-06).
enum ProfileCompleteness {
    static let minimumPhotos = 1
    static let minimumBitAnswers = PromptAnswer.maxCount

    static func evaluate(
        photoCount: Int,
        answeredBits: Int,
        hasGender: Bool,
        hasCity: Bool
    ) -> Bool {
        photoCount >= minimumPhotos
            && answeredBits >= minimumBitAnswers
            && hasGender
            && hasCity
    }

    static func evaluate(user: NADAUser, photoCount: Int, answeredBits: Int) -> Bool {
        let genderOK = ProfileGender.fromStored(user.gender) != nil
        let cityOK = !(user.city?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return evaluate(
            photoCount: photoCount,
            answeredBits: answeredBits,
            hasGender: genderOK,
            hasCity: cityOK
        )
    }
}
