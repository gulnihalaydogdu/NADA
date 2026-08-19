import FirebaseCore
import FirebaseFirestore
import Foundation

/// Owns `preferences/{userId}` — discovery prefs 1–1 with User (W2-05 / W2-11).
@MainActor
final class FirestorePreferencesService {
    private static let collectionName = "preferences"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Returns existing prefs, or creates defaults (seeded from `user` when provided).
    func ensurePreferences(for user: NADAUser) async throws -> UserPreferences {
        if let existing = try await fetchPreferences(userId: user.id) {
            return existing
        }

        let created = UserPreferences.defaults(for: user)
        return try await writePreferences(created, merge: false)
    }

    func fetchPreferences(userId: String) async throws -> UserPreferences? {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.collectionName).document(userId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return mapPreferences(userId: userId, data: data)
    }

    /// Upserts discovery prefs. Always forces `intent = friendsOnly` for MVP.
    @discardableResult
    func updatePreferences(_ prefs: UserPreferences) async throws -> UserPreferences {
        guard prefs.trimmedCity != nil else {
            throw AuthError.unknown("City is required.")
        }
        return try await writePreferences(prefs, merge: true)
    }

    /// Convenience for location / city-only syncs — preserves discovery filters.
    @discardableResult
    func updatePreferences(
        userId: String,
        city: String,
        radiusKm: Int,
        base: UserPreferences?
    ) async throws -> UserPreferences {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.unknown("City is required.")
        }

        var next = base ?? UserPreferences(userId: userId)
        next.city = trimmed
        next.radiusKm = radiusKm
        return try await updatePreferences(next)
    }

    /// Syncs city onto an existing prefs doc (or creates defaults) after basics save.
    @discardableResult
    func syncCity(userId: String, city: String, seedFrom user: NADAUser?) async throws -> UserPreferences {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.unknown("City is required.")
        }

        if let existing = try await fetchPreferences(userId: userId) {
            return try await updatePreferences(
                userId: userId,
                city: trimmed,
                radiusKm: existing.resolvedRadiusKm,
                base: existing
            )
        }

        var seeded = UserPreferences.defaults(for: user ?? NADAUser(id: userId))
        seeded.city = trimmed
        return try await writePreferences(seeded, merge: false)
    }

    // MARK: - Private

    private func writePreferences(_ prefs: UserPreferences, merge: Bool) async throws -> UserPreferences {
        guard let database else { throw AuthError.notConfigured }

        var payload: [String: Any] = [
            "userId": prefs.userId,
            "radiusKm": prefs.resolvedRadiusKm,
            "intent": NADAUser.UserIntent.friendsOnly.rawValue,
            "lookingForGenders": prefs.lookingForGenders.rawValue,
            "minAge": prefs.minAge,
            "maxAge": prefs.maxAge,
            "buddyTypes": prefs.buddyTypes.map(\.rawValue),
            "notifyOnLikes": prefs.notifyOnLikes,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let city = prefs.trimmedCity {
            payload["city"] = city
        }

        // Drop legacy single-value showMe when rewriting.
        if merge {
            payload["showMe"] = FieldValue.delete()
        }

        let document = database.collection(Self.collectionName).document(prefs.userId)
        try await document.setData(payload, merge: merge)

        let snapshot = try await document.getDocument()
        guard let data = snapshot.data() else {
            throw AuthError.unknown("Preferences not found.")
        }
        return mapPreferences(userId: prefs.userId, data: data)
    }

    private func mapPreferences(userId: String, data: [String: Any]) -> UserPreferences {
        let intentRaw = data["intent"] as? String
        let intent = NADAUser.UserIntent(rawValue: intentRaw ?? "") ?? .friendsOnly

        let lookingFor: UserPreferences.LookingForGender
        if let raw = data["lookingForGenders"] as? String,
           let value = UserPreferences.LookingForGender(rawValue: raw) {
            lookingFor = value
        } else if let legacy = data["showMe"] as? String, legacy == "everyone" {
            lookingFor = .everyone
        } else {
            lookingFor = .everyone
        }

        var updatedAt: Date?
        if let timestamp = data["updatedAt"] as? Timestamp {
            updatedAt = timestamp.dateValue()
        }

        let radius = intValue(data["radiusKm"]) ?? ProfileLocation.defaultRadiusKm
        let minAge = intValue(data["minAge"]) ?? UserPreferences.defaultMinAge
        let maxAge = intValue(data["maxAge"]) ?? UserPreferences.defaultMaxAge

        let buddyRaw = data["buddyTypes"] as? [String] ?? []
        let buddyTypes = buddyRaw.compactMap { UserPreferences.BuddyType(rawValue: $0) }

        return UserPreferences(
            userId: userId,
            city: data["city"] as? String,
            radiusKm: radius,
            intent: intent,
            lookingForGenders: lookingFor,
            minAge: minAge,
            maxAge: maxAge,
            buddyTypes: buddyTypes.isEmpty ? [.openToAll] : buddyTypes,
            notifyOnLikes: data["notifyOnLikes"] as? Bool ?? true,
            updatedAt: updatedAt
        )
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let number as NSNumber: return number.intValue
        case let double as Double: return Int(double.rounded())
        default: return nil
        }
    }
}
