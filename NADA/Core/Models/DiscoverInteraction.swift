import Foundation

/// Outgoing like on a profile, Bit, or photo (W3-02).
struct DiscoverLike: Identifiable, Equatable, Sendable {
    static let maxCommentLength = 200

    enum TargetType: String, Codable, Sendable, CaseIterable {
        case profile
        case prompt
        case photo
    }

    let id: String
    var fromUserId: String
    var toUserId: String
    var targetType: TargetType
    var targetId: String
    var comment: String?
    var createdAt: Date?

    static func documentId(
        fromUserId: String,
        toUserId: String,
        targetType: TargetType,
        targetId: String
    ) -> String {
        "\(fromUserId)_\(toUserId)_\(targetType.rawValue)_\(targetId)"
    }
}

/// Skip of another user’s profile in Discover (W3-03).
struct DiscoverSkip: Identifiable, Equatable, Sendable {
    let id: String
    var fromUserId: String
    var toUserId: String
    var createdAt: Date?

    static func documentId(fromUserId: String, toUserId: String) -> String {
        "\(fromUserId)_\(toUserId)"
    }
}
