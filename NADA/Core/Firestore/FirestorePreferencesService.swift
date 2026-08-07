import FirebaseCore
import FirebaseFirestore
import Foundation

/// Owns `preferences/{userId}` — discovery prefs 1–1 with User (W2-05).
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
    func updatePreferences(
        userId: String,
        city: String,
        radiusKm: Int,
        showMe: UserPreferences.ShowMe = .everyone
    ) async throws -> UserPreferences {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.unknown("City is required.")
        }

        let prefs = UserPreferences(
            userId: userId,
            city: trimmed,
            radiusKm: radiusKm,
            intent: .friendsOnly,
            showMe: showMe
        )
        return try await writePreferences(prefs, merge: true)
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
                showMe: existing.showMe
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
            "showMe": prefs.showMe.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let city = prefs.trimmedCity {
            payload["city"] = city
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

        let showMeRaw = data["showMe"] as? String
        let showMe = UserPreferences.ShowMe(rawValue: showMeRaw ?? "") ?? .everyone

        var updatedAt: Date?
        if let timestamp = data["updatedAt"] as? Timestamp {
            updatedAt = timestamp.dateValue()
        }

        let radius = intValue(data["radiusKm"]) ?? ProfileLocation.defaultRadiusKm

        return UserPreferences(
            userId: userId,
            city: data["city"] as? String,
            radiusKm: radius,
            intent: intent,
            showMe: showMe,
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
