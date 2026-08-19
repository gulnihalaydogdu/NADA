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

/// Western tropical sign from month + day only — never needs the birth year.
enum ZodiacSign: String, Equatable, Sendable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces

    var title: String {
        switch self {
        case .aries: return "Aries"
        case .taurus: return "Taurus"
        case .gemini: return "Gemini"
        case .cancer: return "Cancer"
        case .leo: return "Leo"
        case .virgo: return "Virgo"
        case .libra: return "Libra"
        case .scorpio: return "Scorpio"
        case .sagittarius: return "Sagittarius"
        case .capricorn: return "Capricorn"
        case .aquarius: return "Aquarius"
        case .pisces: return "Pisces"
        }
    }

    var glyph: String {
        switch self {
        case .aries: return "♈︎"
        case .taurus: return "♉︎"
        case .gemini: return "♊︎"
        case .cancer: return "♋︎"
        case .leo: return "♌︎"
        case .virgo: return "♍︎"
        case .libra: return "♎︎"
        case .scorpio: return "♏︎"
        case .sagittarius: return "♐︎"
        case .capricorn: return "♑︎"
        case .aquarius: return "♒︎"
        case .pisces: return "♓︎"
        }
    }

    static func from(dateOfBirth: Date, calendar: Calendar = .current) -> ZodiacSign {
        let parts = calendar.dateComponents([.month, .day], from: dateOfBirth)
        let stamp = (parts.month ?? 1) * 100 + (parts.day ?? 1)
        switch stamp {
        case 120...218: return .aquarius
        case 219...320: return .pisces
        case 321...419: return .aries
        case 420...520: return .taurus
        case 521...620: return .gemini
        case 621...722: return .cancer
        case 723...822: return .leo
        case 823...922: return .virgo
        case 923...1022: return .libra
        case 1023...1121: return .scorpio
        case 1122...1221: return .sagittarius
        default: return .capricorn
        }
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
