import Foundation

/// Text chat inside a mutual (W5-01). Lives at `matches/{matchId}/messages/{id}`.
struct ChatMessage: Identifiable, Equatable, Sendable {
    static let maxTextLength = 1000
    static let defaultPageSize = 40

    let id: String
    var matchId: String
    var senderId: String
    var body: String
    var createdAt: Date?
    var readAt: Date?

    var isRead: Bool { readAt != nil }

    /// Stable id so a like comment becomes one chat bubble, not a duplicate.
    static func openingMessageId(likeId: String) -> String {
        "opening_\(likeId)"
    }
}

struct ChatMessagePage: Equatable, Sendable {
    let messages: [ChatMessage]
    /// Oldest examined id — pass to load earlier messages.
    let cursor: String?
    var isEmpty: Bool { messages.isEmpty }

    static let empty = ChatMessagePage(messages: [], cursor: nil)
}
