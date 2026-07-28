import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreUserService {
    private static let usersCollection = "users"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Creates `users/{uid}` on first sign-in, otherwise returns the stored profile.
    func ensureUserDocument(for authUser: NADAUser) async throws -> NADAUser {
        guard let database else { throw AuthError.notConfigured }

        let document = database.collection(Self.usersCollection).document(authUser.id)
        let snapshot = try await document.getDocument()

        if snapshot.exists, let data = snapshot.data() {
            return mapUser(id: authUser.id, data: data, fallback: authUser)
        }

        var payload = newUserPayload(from: authUser)
        try await document.setData(payload)

        if payload["createdAt"] == nil {
            payload["createdAt"] = Timestamp(date: Date())
        }
        return mapUser(id: authUser.id, data: payload, fallback: authUser)
    }

    func fetchUser(id: String) async throws -> NADAUser? {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.usersCollection).document(id).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }

        let fallback = NADAUser(id: id)
        return mapUser(id: id, data: data, fallback: fallback)
    }

    func setFriendsIntentCompleted(userId: String) async throws -> NADAUser {
        try await patchUser(
            userId: userId,
            fields: [
                "friendsIntentCompleted": true,
                "intent": NADAUser.UserIntent.friendsOnly.rawValue
            ]
        )
    }

    func updateProfile(
        userId: String,
        displayName: String?,
        gender: String?,
        city: String?,
        locale: String?
    ) async throws -> NADAUser {
        var fields: [String: Any] = [:]
        if let displayName { fields["displayName"] = displayName }
        if let gender { fields["gender"] = gender }
        if let city { fields["city"] = city }
        if let locale { fields["locale"] = locale }
        return try await patchUser(userId: userId, fields: fields)
    }

    private func patchUser(userId: String, fields: [String: Any]) async throws -> NADAUser {
        guard let database else { throw AuthError.notConfigured }
        guard !fields.isEmpty else {
            guard let existing = try await fetchUser(id: userId) else {
                throw AuthError.unknown("User profile not found.")
            }
            return existing
        }

        let document = database.collection(Self.usersCollection).document(userId)
        try await document.updateData(fields)

        let snapshot = try await document.getDocument()
        guard let data = snapshot.data() else {
            throw AuthError.unknown("User profile not found.")
        }

        return mapUser(id: userId, data: data, fallback: NADAUser(id: userId))
    }

    private func newUserPayload(from user: NADAUser) -> [String: Any] {
        var data: [String: Any] = [
            "intent": NADAUser.UserIntent.friendsOnly.rawValue,
            "friendsIntentCompleted": false,
            "locale": user.locale ?? Locale.current.identifier,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let displayName = user.displayName, !displayName.isEmpty {
            data["displayName"] = displayName
        }
        if let email = user.email, !email.isEmpty {
            data["email"] = email
        }
        return data
    }

    private func mapUser(id: String, data: [String: Any], fallback: NADAUser) -> NADAUser {
        let intentRaw = data["intent"] as? String
        let intent = NADAUser.UserIntent(rawValue: intentRaw ?? "") ?? .friendsOnly

        var createdAt = fallback.createdAt
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        }

        return NADAUser(
            id: id,
            displayName: data["displayName"] as? String ?? fallback.displayName,
            email: data["email"] as? String ?? fallback.email,
            gender: data["gender"] as? String,
            city: data["city"] as? String,
            intent: intent,
            locale: data["locale"] as? String ?? fallback.locale,
            createdAt: createdAt,
            friendsIntentCompleted: data["friendsIntentCompleted"] as? Bool ?? false
        )
    }
}
