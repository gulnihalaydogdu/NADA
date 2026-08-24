import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreMatchService {
    static let collectionName = "matches"
    static let defaultPageSize = 20
    private static let documentIdChunk = 10

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Creates `matches/{minUid_maxUid}` if missing. Same pair always maps to one doc.
    /// Does not clear `unmatchedAt` — rematch is Week 5.
    @discardableResult
    func ensureMatch(userId: String, otherUserId: String) async throws -> NADAMatch {
        guard let database else { throw AuthError.notConfigured }
        guard userId != otherUserId, !otherUserId.isEmpty else {
            throw AuthError.unknown("A match needs two people.")
        }

        let ids = [userId, otherUserId].sorted()
        let userAId = ids[0]
        let userBId = ids[1]
        let docId = NADAMatch.documentId(userId: userId, otherUserId: otherUserId)
        let document = database.collection(Self.collectionName).document(docId)

        let payload: [String: Any] = [
            "userAId": userAId,
            "userBId": userBId,
            "userIds": [userAId, userBId],
            "createdAt": FieldValue.serverTimestamp()
        ]

        // Create first. A get on a missing `matches` doc is denied (rules need
        // `resource.data.userIds`), so read-before-write never reaches setData.
        do {
            try await document.setData(payload)
            return NADAMatch(
                id: docId,
                userAId: userAId,
                userBId: userBId,
                createdAt: Date(),
                unmatchedAt: nil
            )
        } catch {
            let existing = try await document.getDocument()
            if existing.exists, let data = existing.data() {
                return mapMatch(id: docId, data: data)
            }
            throw error
        }
    }

    /// Hides the match for both people (W4-04). Idempotent if already unmatched.
    @discardableResult
    func unmatch(viewerId: String, matchId: String) async throws -> NADAMatch {
        guard let database else { throw AuthError.notConfigured }
        guard !viewerId.isEmpty, !matchId.isEmpty else {
            throw AuthError.unknown("Couldn't find that mutual.")
        }

        let document = database.collection(Self.collectionName).document(matchId)
        let snapshot = try await document.getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            throw AuthError.unknown("Couldn't find that mutual.")
        }

        var match = mapMatch(id: matchId, data: data)
        let userIds = data["userIds"] as? [String] ?? [match.userAId, match.userBId]
        guard userIds.contains(viewerId) else {
            throw AuthError.unknown("You can only remove your own mutuals.")
        }
        if match.unmatchedAt != nil {
            return match
        }

        do {
            try await document.updateData([
                "unmatchedAt": FieldValue.serverTimestamp()
            ])
        } catch {
            let raced = try await document.getDocument()
            if raced.exists, let racedData = raced.data() {
                let racedMatch = mapMatch(id: matchId, data: racedData)
                if racedMatch.unmatchedAt != nil {
                    return racedMatch
                }
            }
            throw error
        }

        let updated = try await document.getDocument()
        if let updatedData = updated.data() {
            return mapMatch(id: matchId, data: updatedData)
        }
        match.unmatchedAt = Date()
        return match
    }

    /// Creates any missing matches for people who already liked each other (pre-W4-02 likes).
    func ensureMatches(viewerId: String, otherIds: Set<String>) async throws {
        let blocked = await blockedPairIds(viewerId: viewerId, otherIds: otherIds)
        for otherId in otherIds where otherId != viewerId && !blocked.contains(otherId) {
            _ = try await ensureMatch(userId: viewerId, otherUserId: otherId)
        }
    }

    func fetchMatches(
        viewerId: String,
        cursor: String? = nil,
        pageSize: Int = 20
    ) async throws -> MatchListPage {
        guard let database else { throw AuthError.notConfigured }
        guard !viewerId.isEmpty else { return .empty }

        var query: Query = database.collection(Self.collectionName)
            .whereField("userIds", arrayContains: viewerId)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        if let cursor, !cursor.isEmpty {
            let cursorDoc = try await database.collection(Self.collectionName)
                .document(cursor)
                .getDocument()
            if cursorDoc.exists {
                query = query.start(afterDocument: cursorDoc)
            }
        }

        let snapshot = try await query.getDocuments()
        if snapshot.documents.isEmpty {
            return .empty
        }

        var matches: [NADAMatch] = []
        var lastExaminedId: String?
        for document in snapshot.documents {
            lastExaminedId = document.documentID
            let match = mapMatch(id: document.documentID, data: document.data())
            guard match.isActive else { continue }
            matches.append(match)
        }

        let otherIds = Set(matches.map { $0.otherUserId(viewerId: viewerId) })
        let blocked = await blockedPairIds(viewerId: viewerId, otherIds: otherIds)
        matches.removeAll { blocked.contains($0.otherUserId(viewerId: viewerId)) }
        let parties = await loadParties(userIds: Array(otherIds.subtracting(blocked)))
        let items = matches.compactMap { match -> MatchListItem? in
            let otherId = match.otherUserId(viewerId: viewerId)
            guard let other = parties[otherId] else { return nil }
            return MatchListItem(match: match, otherUser: other)
        }

        let cursorOut = snapshot.documents.count < pageSize ? nil : lastExaminedId
        return MatchListPage(items: items, cursor: cursorOut)
    }

    private func loadParties(userIds: [String]) async -> [String: LikePartySummary] {
        guard let database else { return [:] }
        let unique = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }

        var result: [String: LikePartySummary] = [:]
        var index = 0
        while index < unique.count {
            let end = min(index + Self.documentIdChunk, unique.count)
            let chunk = Array(unique[index..<end])
            index = end
            guard let snapshot = try? await database.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments() else { continue }
            for document in snapshot.documents {
                let data = document.data()
                let name = (data["displayName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { continue }
                result[document.documentID] = LikePartySummary(
                    id: document.documentID,
                    displayName: name,
                    photoURL: data["photoURL"] as? String,
                    photoThumbnailURL: data["photoThumbnailURL"] as? String
                )
            }
        }
        return result
    }

    func isBlockedPair(userId: String, otherUserId: String) async -> Bool {
        let blocked = await blockedPairIds(viewerId: userId, otherIds: [otherUserId])
        return blocked.contains(otherUserId)
    }

    private func blockedPairIds(viewerId: String, otherIds: Set<String>) async -> Set<String> {
        guard let database, !otherIds.isEmpty else { return [] }
        var blocked: Set<String> = []
        for otherId in otherIds {
            let mine = "\(viewerId)_\(otherId)"
            let theirs = "\(otherId)_\(viewerId)"
            if let snap = try? await database.collection("blocks").document(mine).getDocument(),
               snap.exists {
                blocked.insert(otherId)
                continue
            }
            if let snap = try? await database.collection("blocks").document(theirs).getDocument(),
               snap.exists {
                blocked.insert(otherId)
            }
        }
        return blocked
    }

    private func mapMatch(id: String, data: [String: Any]) -> NADAMatch {
        NADAMatch(
            id: id,
            userAId: data["userAId"] as? String ?? "",
            userBId: data["userBId"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            unmatchedAt: (data["unmatchedAt"] as? Timestamp)?.dateValue()
        )
    }
}
