import Foundation

/// Mutual like (W4-02). One doc per pair; `unmatchedAt` hides it for both (W4-04).
struct NADAMatch: Identifiable, Equatable, Sendable {
    let id: String
    var userAId: String
    var userBId: String
    var createdAt: Date?
    var unmatchedAt: Date?

    var isActive: Bool { unmatchedAt == nil }

    func otherUserId(viewerId: String) -> String {
        viewerId == userAId ? userBId : userAId
    }

    /// Stable id so A→B and B→A cannot create two matches.
    static func documentId(userId: String, otherUserId: String) -> String {
        [userId, otherUserId].sorted().joined(separator: "_")
    }
}

/// Hydrated row for `fetchMatches` — other person never includes email.
struct MatchListItem: Identifiable, Equatable, Sendable {
    var id: String { match.id }
    let match: NADAMatch
    let otherUser: LikePartySummary
}

struct MatchListPage: Equatable, Sendable {
    let items: [MatchListItem]
    let cursor: String?
    var isEmpty: Bool { items.isEmpty }

    static let empty = MatchListPage(items: [], cursor: nil)
}
