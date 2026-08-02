import Foundation

struct NADAUser: Identifiable, Equatable, Sendable {
    let id: String
    var displayName: String?
    var email: String?
    var gender: String?
    var city: String?
    var photoURL: String?
    var intent: UserIntent
    var locale: String?
    var createdAt: Date?
    var friendsIntentCompleted: Bool

    enum UserIntent: String, Codable, Sendable {
        case friendsOnly = "friendsOnly"
    }

    init(
        id: String,
        displayName: String? = nil,
        email: String? = nil,
        gender: String? = nil,
        city: String? = nil,
        photoURL: String? = nil,
        intent: UserIntent = .friendsOnly,
        locale: String? = nil,
        createdAt: Date? = nil,
        friendsIntentCompleted: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.gender = gender
        self.city = city
        self.photoURL = photoURL
        self.intent = intent
        self.locale = locale
        self.createdAt = createdAt
        self.friendsIntentCompleted = friendsIntentCompleted
    }
}
