import CryptoKit
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Owner-only FCM tokens under `users/{uid}/deviceTokens/{tokenId}` (W3-05).
/// Kept off the user doc so Discover readers cannot see push credentials.
@MainActor
final class FirestoreDeviceTokenService {
    static let collectionName = "deviceTokens"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    static func documentId(for fcmToken: String) -> String {
        let digest = SHA256.hash(data: Data(fcmToken.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func upsertToken(userId: String, fcmToken: String) async throws {
        guard let database else { throw AuthError.notConfigured }
        guard !userId.isEmpty, !fcmToken.isEmpty else {
            throw AuthError.unknown("Missing device token.")
        }

        let document = database
            .collection("users")
            .document(userId)
            .collection(Self.collectionName)
            .document(Self.documentId(for: fcmToken))

        try await document.setData(
            [
                "fcmToken": fcmToken,
                "platform": "ios",
                "updatedAt": FieldValue.serverTimestamp()
            ],
            merge: true
        )
    }

    func deleteToken(userId: String, fcmToken: String) async throws {
        guard let database else { throw AuthError.notConfigured }
        guard !userId.isEmpty, !fcmToken.isEmpty else { return }

        try await database
            .collection("users")
            .document(userId)
            .collection(Self.collectionName)
            .document(Self.documentId(for: fcmToken))
            .delete()
    }
}
