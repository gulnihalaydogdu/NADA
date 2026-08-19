import Foundation

/// Discovery preferences — 1–1 with User (`preferences/{userId}`, W2-05 / W2-11).
struct UserPreferences: Identifiable, Equatable, Sendable {
    /// Same as Auth uid / `users/{uid}` id.
    let userId: String
    var city: String?
    var radiusKm: Int
    /// Always friends-only for MVP (not shown in Preferences UI).
    var intent: NADAUser.UserIntent
    /// Whose profiles to surface in Discover.
    var lookingForGenders: LookingForGender
    var minAge: Int
    var maxAge: Int
    /// Like-push opt-out (W4-03). Missing in Firestore means true.
    var notifyOnLikes: Bool
    var updatedAt: Date?

    var id: String { userId }

    enum LookingForGender: String, CaseIterable, Identifiable, Codable, Sendable {
        case women
        case men
        case nonBinary
        case everyone

        var id: String { rawValue }

        var title: String {
            switch self {
            case .women: return "Women"
            case .men: return "Men"
            case .nonBinary: return "Non-binary"
            case .everyone: return "Everyone"
            }
        }
    }

    static let absoluteMinAge = 18
    static let absoluteMaxAge = 99
    static let defaultMinAge = 18
    static let defaultMaxAge = 45

    init(
        userId: String,
        city: String? = nil,
        radiusKm: Int = ProfileLocation.defaultRadiusKm,
        intent: NADAUser.UserIntent = .friendsOnly,
        lookingForGenders: LookingForGender = .everyone,
        minAge: Int = defaultMinAge,
        maxAge: Int = defaultMaxAge,
        notifyOnLikes: Bool = true,
        updatedAt: Date? = nil
    ) {
        self.userId = userId
        self.city = city
        self.radiusKm = ProfileLocation.clampRadiusKm(radiusKm)
        self.intent = intent
        self.lookingForGenders = lookingForGenders
        let clamped = Self.clampAgeRange(min: minAge, max: maxAge)
        self.minAge = clamped.min
        self.maxAge = clamped.max
        self.notifyOnLikes = notifyOnLikes
        self.updatedAt = updatedAt
    }

    /// Defaults for a new preferences doc, seeded from an existing user profile when present.
    static func defaults(for user: NADAUser) -> UserPreferences {
        UserPreferences(
            userId: user.id,
            city: user.city,
            radiusKm: user.radiusKm ?? ProfileLocation.defaultRadiusKm
        )
    }

    var resolvedRadiusKm: Int {
        ProfileLocation.clampRadiusKm(radiusKm)
    }

    var trimmedCity: String? {
        guard let city else { return nil }
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func clampAgeRange(min: Int, max: Int) -> (min: Int, max: Int) {
        var lo = Swift.min(Swift.max(min, absoluteMinAge), absoluteMaxAge)
        var hi = Swift.min(Swift.max(max, absoluteMinAge), absoluteMaxAge)
        if lo > hi { swap(&lo, &hi) }
        return (lo, hi)
    }
}
