import Foundation

struct NADAUser: Identifiable, Equatable, Sendable {
    static let maxJobTitleLength = 60
    static let maxUniversityLength = 80
    static let maxHangoutLookingForLength = 120

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
    /// Small primary photo for avatars / grids. Falls back to `photoURL` when missing.
    var photoThumbnailURL: String?
    /// Friend-coded role on the Discover card, e.g. Student, Designer.
    var jobTitle: String?
    /// Last / current school name.
    var university: String?
    /// Short hangout-intent line, e.g. “Looking for a travel-buddy from Istanbul”.
    var hangoutLookingFor: String?
    var intent: UserIntent
    var locale: String?
    var createdAt: Date?
    var friendsIntentCompleted: Bool
    /// Finished the post-signup name / gender / age / city steps (Skip allowed after name).
    var basicProfileSetupCompleted: Bool
    /// Soft profile setup shell (Photos → Bits → Discover card → Interests → Preferences). Skip allowed.
    var profileWizardCompleted: Bool
    /// Discover gate (W2-06): photos≥1, bits≥3, gender, city.
    var isProfileComplete: Bool
    /// Catalog interest ids (max 8). Used for Discover overlap (`array-contains-any`).
    var interestIds: [String]

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
        photoThumbnailURL: String? = nil,
        jobTitle: String? = nil,
        university: String? = nil,
        hangoutLookingFor: String? = nil,
        intent: UserIntent = .friendsOnly,
        locale: String? = nil,
        createdAt: Date? = nil,
        friendsIntentCompleted: Bool = false,
        basicProfileSetupCompleted: Bool = false,
        profileWizardCompleted: Bool = false,
        isProfileComplete: Bool = false,
        interestIds: [String] = []
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
        self.photoThumbnailURL = photoThumbnailURL
        self.jobTitle = jobTitle
        self.university = university
        self.hangoutLookingFor = hangoutLookingFor
        self.intent = intent
        self.locale = locale
        self.createdAt = createdAt
        self.friendsIntentCompleted = friendsIntentCompleted
        self.basicProfileSetupCompleted = basicProfileSetupCompleted
        self.profileWizardCompleted = profileWizardCompleted
        self.isProfileComplete = isProfileComplete
        self.interestIds = InterestSelection.normalized(interestIds)
    }

    /// Whole years since birthday (nil if DOB missing).
    var age: Int? {
        guard let dateOfBirth else { return nil }
        return ProfileAge.age(from: dateOfBirth)
    }

    var resolvedRadiusKm: Int {
        ProfileLocation.clampRadiusKm(radiusKm ?? ProfileLocation.defaultRadiusKm)
    }

    var avatarURL: String? { photoThumbnailURL ?? photoURL }

    var trimmedJobTitle: String? {
        Self.trimmed(jobTitle, max: Self.maxJobTitleLength)
    }

    var trimmedUniversity: String? {
        Self.trimmed(university, max: Self.maxUniversityLength)
    }

    var trimmedHangoutLookingFor: String? {
        Self.trimmed(hangoutLookingFor, max: Self.maxHangoutLookingForLength)
    }

    static func trimmed(_ value: String?, max: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(max))
    }
}
