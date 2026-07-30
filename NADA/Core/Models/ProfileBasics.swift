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

extension NADAUser {
    var hasCompletedBasicProfile: Bool {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gender = gender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty && !city.isEmpty && ProfileGender.fromStored(gender) != nil
    }
}
