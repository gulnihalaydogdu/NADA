import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreSkipService {
    static let collectionName = "skips"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    @discardableResult
    func createSkip(fromUserId: String, toUserId: String) async throws -> DiscoverSkip {
        guard let database else { throw AuthError.notConfigured }
        guard fromUserId != toUserId else {
            throw AuthError.unknown("You can't skip yourself.")
        }
        guard !toUserId.isEmpty else {
            throw AuthError.unknown("Missing skip target.")
        }

        let docId = DiscoverSkip.documentId(fromUserId: fromUserId, toUserId: toUserId)
        let payload: [String: Any] = [
            "fromUserId": fromUserId,
            "toUserId": toUserId,
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await database.collection(Self.collectionName).document(docId).setData(payload)

        return DiscoverSkip(
            id: docId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            createdAt: Date()
        )
    }

    func deleteSkip(fromUserId: String, toUserId: String) async throws {
        guard let database else { throw AuthError.notConfigured }
        let docId = DiscoverSkip.documentId(fromUserId: fromUserId, toUserId: toUserId)
        try await database.collection(Self.collectionName).document(docId).delete()
    }

    func fetchSkippedUserIds(fromUserId: String) async throws -> Set<String> {
        guard let database else { throw AuthError.notConfigured }
        let snapshot = try await database.collection(Self.collectionName)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .getDocuments()
        return Set(snapshot.documents.compactMap { $0.data()["toUserId"] as? String })
    }
}
