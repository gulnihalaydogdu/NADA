import Foundation

struct NADAUser: Identifiable, Equatable, Sendable {
    let id: String
    var displayName: String?
    var email: String?
    var gender: String?
    var city: String?
    var intent: UserIntent
    var locale: String?
    var createdAt: Date?

    enum UserIntent: String, Codable, Sendable {
        case friendsOnly = "friendsOnly"
    }
}
