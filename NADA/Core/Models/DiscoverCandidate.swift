import Foundation

/// One Discover card — assembled from user + photos + bits + prefs (W3-01).
/// Never carries email or full birthday; age is derived only.
struct DiscoverCandidate: Identifiable, Equatable, Sendable {
    /// Same as Auth uid / `users/{uid}`.
    let id: String
    let displayName: String
    let age: Int?
    let gender: String?
    let city: String?
    /// Ordered photos (primary first). May be a single primary URL when subcollection is empty.
    let photos: [ProfilePhoto]
    let bits: [DiscoverBit]
    let buddyTypes: [UserPreferences.BuddyType]
    /// Approximate distance from the viewer in km. Nil when either side lacks coarse coords.
    let distanceKm: Double?

    var primaryPhotoURL: String? {
        photos.first(where: \.isPrimary)?.url ?? photos.first?.url
    }
}

/// A Bit shown on a Discover card (prompt text + answer).
struct DiscoverBit: Identifiable, Equatable, Sendable {
    /// Prompt catalog id.
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
