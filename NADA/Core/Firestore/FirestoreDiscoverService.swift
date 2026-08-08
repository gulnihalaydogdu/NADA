import FirebaseCore
import FirebaseFirestore
import Foundation

/// Builds Discover feed pages from complete nearby profiles (W3-01).
///
/// First pass: query `isProfileComplete`, filter by viewer prefs (gender / age / city+radius),
/// exclude self + interaction ids, rank by distance then recency. Photos + Bits are hydrated
/// per candidate. Like / skip / block exclusion is injected via `excludedUserIds` until W3-02–04.
@MainActor
final class FirestoreDiscoverService {
    static let defaultPageSize = 10
    /// How many complete-profile docs to pull from Firestore before client-side filters.
    private static let queryBatchSize = 40

    private let promptService = FirestorePromptService()
    private let preferencesService = FirestorePreferencesService()

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Fetches the next Discover page for `viewer` using their discovery preferences.
    /// - Parameters:
    ///   - excludedUserIds: Already liked / skipped / blocked ids (empty until those APIs land).
    ///   - cursor: Opaque token from a previous `DiscoverFeedPage.cursor`.
    ///   - pageSize: Max candidates to return after filtering.
    func fetchCandidates(
        viewer: NADAUser,
        preferences: UserPreferences,
        excludedUserIds: Set<String> = [],
        cursor: String? = nil,
        pageSize: Int = defaultPageSize
    ) async throws -> DiscoverFeedPage {
        guard let database else { throw AuthError.notConfigured }
        guard pageSize > 0 else {
            return DiscoverFeedPage(candidates: [], cursor: nil)
        }

        var query: Query = database.collection("users")
            .whereField("isProfileComplete", isEqualTo: true)
            .order(by: FieldPath.documentID())
            .limit(to: Self.queryBatchSize)

        if let cursor, !cursor.isEmpty {
            let cursorDoc = try await database.collection("users").document(cursor).getDocument()
            if cursorDoc.exists {
                query = query.start(afterDocument: cursorDoc)
            }
        }

        let snapshot = try await query.getDocuments()

        let promptById = Dictionary(
            uniqueKeysWithValues: (try await promptService.fetchActivePrompts()).map { ($0.id, $0) }
        )

        var matched: [DiscoverCandidate] = []
        matched.reserveCapacity(pageSize)
        var lastExaminedId: String?

        for document in snapshot.documents {
            if matched.count >= pageSize { break }
            lastExaminedId = document.documentID

            let userId = document.documentID
            if userId == viewer.id { continue }
            if excludedUserIds.contains(userId) { continue }

            let data = document.data()
            guard let candidate = try await assembleCandidate(
                userId: userId,
                data: data,
                viewer: viewer,
                preferences: preferences,
                promptById: promptById
            ) else {
                continue
            }
            matched.append(candidate)
        }

        matched.sort(by: Self.rank)

        let exhausted = snapshot.documents.count < Self.queryBatchSize
        let pageCursor: String?
        if lastExaminedId == nil {
            pageCursor = nil
        } else if matched.count >= pageSize {
            // Stopped early — resume after the last examined doc.
            pageCursor = lastExaminedId
        } else if exhausted {
            pageCursor = nil
        } else {
            // Batch full but few matches — keep scanning.
            pageCursor = lastExaminedId
        }

        return DiscoverFeedPage(candidates: matched, cursor: pageCursor)
    }

    // MARK: - Assemble + filter

    private func assembleCandidate(
        userId: String,
        data: [String: Any],
        viewer: NADAUser,
        preferences: UserPreferences,
        promptById: [String: Prompt]
    ) async throws -> DiscoverCandidate? {
        let displayName = (data["displayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !displayName.isEmpty else { return nil }

        let gender = data["gender"] as? String
        guard matchesLookingFor(preferences.lookingForGenders, gender: gender) else { return nil }

        let dateOfBirth = (data["dateOfBirth"] as? Timestamp)?.dateValue()
        let age = dateOfBirth.map { ProfileAge.age(from: $0) }
        if let age {
            guard age >= preferences.minAge, age <= preferences.maxAge else { return nil }
        } else {
            // Incomplete age — keep out of age-gated feed.
            return nil
        }

        let city = (data["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateLat = doubleValue(data["approxLatitude"])
        let candidateLon = doubleValue(data["approxLongitude"])
        let distanceKm = distance(
            viewer: viewer,
            candidateLatitude: candidateLat,
            candidateLongitude: candidateLon
        )

        guard passesLocationFilter(
            preferences: preferences,
            viewer: viewer,
            candidateCity: city,
            distanceKm: distanceKm
        ) else {
            return nil
        }

        let photos = try await loadPhotos(
            userId: userId,
            legacyPhotoURL: data["photoURL"] as? String
        )
        guard !photos.isEmpty else { return nil }

        let answers = try await promptService.fetchAnswers(userId: userId)
        let bits: [DiscoverBit] = answers.compactMap { answer in
            guard let prompt = promptById[answer.promptId] else { return nil }
            return DiscoverBit(
                id: answer.promptId,
                promptText: prompt.text,
                answerText: answer.answerText,
                sortOrder: answer.sortOrder
            )
        }.sorted { $0.sortOrder < $1.sortOrder }

        let prefs = try? await preferencesService.fetchPreferences(userId: userId)
        let buddyTypes = prefs?.buddyTypes ?? [.openToAll]

        return DiscoverCandidate(
            id: userId,
            displayName: displayName,
            age: age,
            gender: gender,
            city: city,
            photos: photos,
            bits: bits,
            buddyTypes: buddyTypes,
            distanceKm: distanceKm
        )
    }

    /// Read-only photo load — never migrates another user's legacy `photoURL`.
    private func loadPhotos(userId: String, legacyPhotoURL: String?) async throws -> [ProfilePhoto] {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection("users")
            .document(userId)
            .collection("photos")
            .getDocuments()

        let photos = snapshot.documents
            .compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        if !photos.isEmpty { return photos }

        if let legacyPhotoURL,
           !legacyPhotoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [
                ProfilePhoto(
                    id: "legacy",
                    url: legacyPhotoURL,
                    sortOrder: 0,
                    isPrimary: true,
                    createdAt: nil
                )
            ]
        }
        return []
    }

    private func mapPhoto(id: String, data: [String: Any]) -> ProfilePhoto? {
        guard let url = data["url"] as? String, !url.isEmpty else { return nil }
        let sortOrder: Int
        switch data["sortOrder"] {
        case let int as Int: sortOrder = int
        case let number as NSNumber: sortOrder = number.intValue
        default: sortOrder = 0
        }
        return ProfilePhoto(
            id: id,
            url: url,
            sortOrder: sortOrder,
            isPrimary: data["isPrimary"] as? Bool ?? false,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private func matchesLookingFor(
        _ lookingFor: UserPreferences.LookingForGender,
        gender: String?
    ) -> Bool {
        guard let profileGender = ProfileGender.fromStored(gender) else { return false }
        switch lookingFor {
        case .everyone:
            return true
        case .women:
            return profileGender == .woman
        case .men:
            return profileGender == .man
        case .nonBinary:
            return profileGender == .nonBinary
        }
    }

    private func distance(
        viewer: NADAUser,
        candidateLatitude: Double?,
        candidateLongitude: Double?
    ) -> Double? {
        guard let fromLat = viewer.approxLatitude,
              let fromLon = viewer.approxLongitude,
              let toLat = candidateLatitude,
              let toLon = candidateLongitude else {
            return nil
        }
        return ProfileLocation.distanceKm(
            fromLatitude: fromLat,
            fromLongitude: fromLon,
            toLatitude: toLat,
            toLongitude: toLon
        )
    }

    private func passesLocationFilter(
        preferences: UserPreferences,
        viewer: NADAUser,
        candidateCity: String?,
        distanceKm: Double?
    ) -> Bool {
        if let distanceKm {
            return distanceKm <= Double(preferences.resolvedRadiusKm)
        }

        // No coarse coords — fall back to case-insensitive city match.
        let viewerCity = (preferences.trimmedCity ?? viewer.city)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let otherCity = candidateCity?.lowercased() ?? ""
        guard !viewerCity.isEmpty, !otherCity.isEmpty else { return false }
        return viewerCity == otherCity
    }

    private static func rank(_ lhs: DiscoverCandidate, _ rhs: DiscoverCandidate) -> Bool {
        switch (lhs.distanceKm, rhs.distanceKm) {
        case let (l?, r?):
            if l != r { return l < r }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let number as NSNumber: return number.doubleValue
        case let int as Int: return Double(int)
        default: return nil
        }
    }
}
