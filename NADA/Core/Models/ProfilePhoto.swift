import Foundation

/// One ordered profile photo under `users/{uid}/photos/{id}`.
struct ProfilePhoto: Identifiable, Equatable, Sendable {
    static let maxCount = 6

    let id: String
    var url: String
    var sortOrder: Int
    var isPrimary: Bool
    var createdAt: Date?
}
