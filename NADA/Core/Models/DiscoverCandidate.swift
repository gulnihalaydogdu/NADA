import Foundation

/// One Discover card — assembled from user + photos + bits (W3-01).
/// Never carries email or full birthday; age is derived only.
struct DiscoverCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let age: Int?
    let gender: String?
    let city: String?
    var jobTitle: String?
    var university: String?
    var hangoutLookingFor: String?
    /// Derived from birthday month/day only — full date of birth is never on the candidate.
    var zodiac: ZodiacSign?
    var interestIds: [String]
    /// Ordered photos (primary first). May be a single primary URL when subcollection is empty.
    let photos: [ProfilePhoto]
    let bits: [DiscoverBit]
    /// Approximate distance from the viewer in km. Nil when either side lacks coarse coords.
    let distanceKm: Double?
    /// Recency for ranking (`lastActiveAt`, else `createdAt`).
    let lastActiveAt: Date?

    var primaryPhotoURL: String? {
        photos.first(where: \.isPrimary)?.previewURL ?? photos.first?.previewURL
    }
}

/// A Bit shown on a Discover card (prompt text + answer).
struct DiscoverBit: Identifiable, Equatable, Sendable {
    let id: String
    let promptText: String
    let answerText: String
    let sortOrder: Int
}

/// One page of Discover candidates plus an opaque cursor for the next fetch.
struct DiscoverFeedPage: Equatable, Sendable {
    let candidates: [DiscoverCandidate]
    /// Pass back into the next `fetchCandidates` call. Nil when there is no further page.
    let cursor: String?
    var isEmpty: Bool { candidates.isEmpty }
}
