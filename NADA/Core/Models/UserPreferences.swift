import Foundation

/// Discovery preferences — 1–1 with User (`preferences/{userId}`, W2-05).
struct UserPreferences: Identifiable, Equatable, Sendable {
    /// Same as Auth uid / `users/{uid}` id.
    let userId: String
    var city: String?
    var radiusKm: Int
    var intent: NADAUser.UserIntent
    /// Who to show in Discover (Week 3). Default everyone for MVP.
    var showMe: ShowMe
    var updatedAt: Date?

    var id: String { userId }

    enum ShowMe: String, Codable, Sendable {
        case everyone = "everyone"
    }

    init(
        userId: String,
        city: String? = nil,
        radiusKm: Int = ProfileLocation.defaultRadiusKm,
        intent: NADAUser.UserIntent = .friendsOnly,
        showMe: ShowMe = .everyone,
        updatedAt: Date? = nil
    ) {
        self.userId = userId
        self.city = city
        self.radiusKm = ProfileLocation.clampRadiusKm(radiusKm)
        self.intent = intent
        self.showMe = showMe
        self.updatedAt = updatedAt
    }

    /// Defaults for a new preferences doc, seeded from an existing user profile when present.
    static func defaults(for user: NADAUser) -> UserPreferences {
        UserPreferences(
            userId: user.id,
            city: user.city,
            radiusKm: user.radiusKm ?? ProfileLocation.defaultRadiusKm,
            intent: .friendsOnly,
            showMe: .everyone
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
}
