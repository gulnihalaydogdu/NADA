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

    func setProfileWizardCompleted(userId: String) async throws -> NADAUser {
        try await patchUser(
            userId: userId,
            fields: ["profileWizardCompleted": true]
        )
    }

    func setProfileComplete(userId: String, isComplete: Bool) async throws -> NADAUser {
        try await patchUser(
            userId: userId,
            fields: ["isProfileComplete": isComplete]
        )
    }

    func updateProfile(
        userId: String,
        displayName: String?,
        gender: String?,
        city: String?,
        locale: String?,
        photoURL: String? = nil,
        dateOfBirth: Date? = nil
    ) async throws -> NADAUser {
        var fields: [String: Any] = [:]
        if let displayName { fields["displayName"] = displayName }
        if let gender { fields["gender"] = gender }
        if let city { fields["city"] = city }
        if let locale { fields["locale"] = locale }
        if let photoURL { fields["photoURL"] = photoURL }
        if let dateOfBirth { fields["dateOfBirth"] = Timestamp(date: dateOfBirth) }
        return try await patchUser(userId: userId, fields: fields)
    }

    func updateLocation(
        userId: String,
        city: String,
        radiusKm: Int,
        approxLatitude: Double? = nil,
        approxLongitude: Double? = nil
    ) async throws -> NADAUser {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else {
            throw AuthError.unknown("City is required.")
        }

        var fields: [String: Any] = [
            "city": trimmedCity,
            "radiusKm": ProfileLocation.clampRadiusKm(radiusKm)
        ]

        if let approxLatitude, let approxLongitude {
            fields["approxLatitude"] = ProfileLocation.coarsenCoordinate(approxLatitude)
            fields["approxLongitude"] = ProfileLocation.coarsenCoordinate(approxLongitude)
        }

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
            "profileWizardCompleted": false,
            "isProfileComplete": false,
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

        var dateOfBirth = fallback.dateOfBirth
        if let timestamp = data["dateOfBirth"] as? Timestamp {
            dateOfBirth = timestamp.dateValue()
        }

        return NADAUser(
            id: id,
            displayName: data["displayName"] as? String ?? fallback.displayName,
            email: data["email"] as? String ?? fallback.email,
            gender: data["gender"] as? String,
            city: data["city"] as? String,
            dateOfBirth: dateOfBirth,
            radiusKm: intValue(data["radiusKm"]) ?? fallback.radiusKm,
            approxLatitude: doubleValue(data["approxLatitude"]) ?? fallback.approxLatitude,
            approxLongitude: doubleValue(data["approxLongitude"]) ?? fallback.approxLongitude,
            photoURL: data["photoURL"] as? String ?? fallback.photoURL,
            photoThumbnailURL: data["photoThumbnailURL"] as? String ?? fallback.photoThumbnailURL,
            intent: intent,
            locale: data["locale"] as? String ?? fallback.locale,
            createdAt: createdAt,
            friendsIntentCompleted: data["friendsIntentCompleted"] as? Bool ?? false,
            profileWizardCompleted: data["profileWizardCompleted"] as? Bool ?? false,
            isProfileComplete: data["isProfileComplete"] as? Bool ?? false
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

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let number as NSNumber: return number.doubleValue
        case let int as Int: return Double(int)
        default: return nil
        }
    }
}
