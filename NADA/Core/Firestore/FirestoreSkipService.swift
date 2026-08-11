import FirebaseCore
import FirebaseFirestore
import Foundation

/// Owns `skips/{id}` — Discover skips + undo (W3-03).
@MainActor
final class FirestoreSkipService {
    static let collectionName = "skips"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Records a skip. Re-skipping the same user refreshes `createdAt`.
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

    /// Removes a skip so the profile can resurface in Discover (undo).
    func deleteSkip(fromUserId: String, toUserId: String) async throws {
        guard let database else { throw AuthError.notConfigured }
        let docId = DiscoverSkip.documentId(fromUserId: fromUserId, toUserId: toUserId)
        try await database.collection(Self.collectionName).document(docId).delete()
    }

    /// Deletes the most recently created skip for this viewer (if any) and returns its `toUserId`.
    func undoLastSkip(fromUserId: String) async throws -> String? {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.collectionName)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first,
              let toUserId = doc.data()["toUserId"] as? String else {
            return nil
        }
        try await doc.reference.delete()
        return toUserId
    }

    func fetchSkippedUserIds(fromUserId: String) async throws -> Set<String> {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.collectionName)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["toUserId"] as? String })
    }
}
