import Foundation

/// Other person on an incoming like. Never includes email.
struct LikePartySummary: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
    let photoURL: String?
    let photoThumbnailURL: String?
}

/// What was liked: whole profile, a Bit, or a photo.
struct LikeTargetPreview: Equatable, Sendable {
    let type: DiscoverLike.TargetType
    let targetId: String
    var promptText: String?
    var answerText: String?
    var photoURL: String?
    var photoThumbnailURL: String?
}

/// One hydrated like for the inbox APIs (W4-01).
struct InboxLike: Identifiable, Equatable, Sendable {
    var id: String { like.id }
    let like: DiscoverLike
    let otherUser: LikePartySummary
    let target: LikeTargetPreview
}

/// Page of incoming or sent likes plus an opaque cursor.
struct LikeInboxPage: Equatable, Sendable {
    let items: [InboxLike]
    let cursor: String?
    var isEmpty: Bool { items.isEmpty }

    static let empty = LikeInboxPage(items: [], cursor: nil)
}

enum LikeInboxDirection: String, Sendable, Hashable, CaseIterable, Identifiable {
    case incoming
    case sent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incoming: return "Clicks you"
        case .sent: return "Sent"
        }
    }
}
