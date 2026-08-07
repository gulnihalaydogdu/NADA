import Foundation

struct NADAUser: Identifiable, Equatable, Sendable {
    let id: String
    var displayName: String?
    var email: String?
    var gender: String?
    var city: String?
    /// Full birthday — used for 18+ gate; Preview shows derived age only.
    var dateOfBirth: Date?
    /// Discover radius in km (5…80). Nil → UI default until first location save.
    var radiusKm: Int?
    /// Coarse approximate coordinates (city-level). Nil until user uses location.
    var approxLatitude: Double?
    var approxLongitude: Double?
    var photoURL: String?
    var intent: UserIntent
    var locale: String?
    var createdAt: Date?
    var friendsIntentCompleted: Bool
    /// Soft profile setup shell (Photos → Bits → Preferences). Skip allowed.
    var profileWizardCompleted: Bool
    /// Discover gate (W2-06): photos≥1, bits≥3, gender, city.
    var isProfileComplete: Bool

    enum UserIntent: String, Codable, Sendable {
        case friendsOnly = "friendsOnly"
    }

    init(
        id: String,
        displayName: String? = nil,
        email: String? = nil,
        gender: String? = nil,
        city: String? = nil,
        dateOfBirth: Date? = nil,
        radiusKm: Int? = nil,
        approxLatitude: Double? = nil,
        approxLongitude: Double? = nil,
        photoURL: String? = nil,
        intent: UserIntent = .friendsOnly,
        locale: String? = nil,
        createdAt: Date? = nil,
        friendsIntentCompleted: Bool = false,
        profileWizardCompleted: Bool = false,
        isProfileComplete: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.gender = gender
        self.city = city
        self.dateOfBirth = dateOfBirth
        self.radiusKm = radiusKm
        self.approxLatitude = approxLatitude
        self.approxLongitude = approxLongitude
        self.photoURL = photoURL
        self.intent = intent
        self.locale = locale
        self.createdAt = createdAt
        self.friendsIntentCompleted = friendsIntentCompleted
        self.profileWizardCompleted = profileWizardCompleted
        self.isProfileComplete = isProfileComplete
    }

    /// Whole years since birthday (nil if DOB missing).
    var age: Int? {
        guard let dateOfBirth else { return nil }
        return ProfileAge.age(from: dateOfBirth)
    }

    var resolvedRadiusKm: Int {
        ProfileLocation.clampRadiusKm(radiusKm ?? ProfileLocation.defaultRadiusKm)
    }
}
