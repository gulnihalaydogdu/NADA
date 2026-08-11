import FirebaseCore
import FirebaseFirestore
import Foundation

/// Owns `likes/{id}` — outgoing Discover likes (W3-02).
@MainActor
final class FirestoreLikeService {
    static let collectionName = "likes"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Creates a like. Duplicate (same from/to/target) is a no-op that returns the existing doc.
    @discardableResult
    func createLike(
        fromUserId: String,
        toUserId: String,
        targetType: DiscoverLike.TargetType,
        targetId: String,
        comment: String? = nil
    ) async throws -> DiscoverLike {
        guard let database else { throw AuthError.notConfigured }
        guard fromUserId != toUserId else {
            throw AuthError.unknown("You can't like your own profile.")
        }
        guard !toUserId.isEmpty, !targetId.isEmpty else {
            throw AuthError.unknown("Missing like target.")
        }

        let trimmedComment = comment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedComment, trimmedComment.count > DiscoverLike.maxCommentLength {
            throw AuthError.unknown(
                "Keep comments under \(DiscoverLike.maxCommentLength) characters."
            )
        }
        let commentValue = (trimmedComment?.isEmpty == false) ? trimmedComment : nil

        let docId = DiscoverLike.documentId(
            fromUserId: fromUserId,
            toUserId: toUserId,
            targetType: targetType,
            targetId: targetId
        )
        let document = database.collection(Self.collectionName).document(docId)
        let existing = try await document.getDocument()
        if existing.exists, let data = existing.data() {
            return mapLike(id: docId, data: data)
        }

        var clean: [String: Any] = [
            "fromUserId": fromUserId,
            "toUserId": toUserId,
            "targetType": targetType.rawValue,
            "targetId": targetId,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let commentValue {
            clean["comment"] = commentValue
        }

        try await document.setData(clean)

        return DiscoverLike(
            id: docId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            targetType: targetType,
            targetId: targetId,
            comment: commentValue,
            createdAt: Date()
        )
    }

    /// All user ids this viewer has already liked (any target) — excluded from Discover.
    func fetchLikedUserIds(fromUserId: String) async throws -> Set<String> {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.collectionName)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .getDocuments()

        return Set(snapshot.documents.compactMap { $0.data()["toUserId"] as? String })
    }

    private func mapLike(id: String, data: [String: Any]) -> DiscoverLike {
        let typeRaw = data["targetType"] as? String ?? DiscoverLike.TargetType.profile.rawValue
        return DiscoverLike(
            id: id,
            fromUserId: data["fromUserId"] as? String ?? "",
            toUserId: data["toUserId"] as? String ?? "",
            targetType: DiscoverLike.TargetType(rawValue: typeRaw) ?? .profile,
            targetId: data["targetId"] as? String ?? "",
            comment: data["comment"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }
}
