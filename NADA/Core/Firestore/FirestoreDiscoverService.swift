import FirebaseCore
import FirebaseFirestore
import Foundation

/// Builds Discover feed pages from complete nearby profiles (W3-01).
///
/// Queries `isProfileComplete`, filters by viewer prefs (gender / age / city+radius),
/// excludes self + `excludedUserIds` (liked / skipped; blocks later), ranks by distance.
/// Photos + Bits are hydrated per candidate.
@MainActor
final class FirestoreDiscoverService {
    static let defaultPageSize = 10
    /// How many complete-profile docs to pull from Firestore before client-side filters.
    private static let queryBatchSize = 40

    private let promptService = FirestorePromptService()
    private let preferencesService = FirestorePreferencesService()

    /// Bits catalog rarely changes — fetch once per app session instead of per page.
    private var promptCacheById: [String: Prompt]?

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Caps how many Firestore batches one call may scan while filling a page.
    private static let maxQueryBatches = 12

    /// Fetches the next Discover page for `viewer` using their discovery preferences.
    /// - Parameters:
    ///   - excludedUserIds: Already liked / skipped ids (blocks via same hook later).
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

        let promptById = try await activePromptsById()

        var matched: [DiscoverCandidate] = []
        matched.reserveCapacity(pageSize)
        var lastExaminedId: String? = cursor
        var exhausted = false
        var batches = 0

        // Keep scanning batches until the page is full — city/gender filters are client-side,
        // so the first 40 complete users worldwide may not include same-city matches.
        while matched.count < pageSize, !exhausted, batches < Self.maxQueryBatches {
            batches += 1

            var query: Query = database.collection("users")
                .whereField("isProfileComplete", isEqualTo: true)
                .order(by: FieldPath.documentID())
                .limit(to: Self.queryBatchSize)

            if let lastExaminedId, !lastExaminedId.isEmpty {
                let cursorDoc = try await database.collection("users").document(lastExaminedId).getDocument()
                if cursorDoc.exists {
                    query = query.start(afterDocument: cursorDoc)
                }
            }

            let snapshot = try await query.getDocuments()
            if snapshot.documents.isEmpty {
                exhausted = true
                break
            }

            var pending: [(userId: String, data: [String: Any])] = []
            for document in snapshot.documents {
                lastExaminedId = document.documentID

                let userId = document.documentID
                if userId == viewer.id { continue }
                if excludedUserIds.contains(userId) { continue }
                pending.append((userId, document.data()))
            }

            // Hydrate the whole batch concurrently — per-candidate photos/Bits/prefs reads
            // dominate page latency when done one at a time.
            let assembled = try await withThrowingTaskGroup(
                of: DiscoverCandidate?.self
            ) { group in
                for (userId, data) in pending {
                    group.addTask { @MainActor in
                        try await self.assembleCandidate(
                            userId: userId,
                            data: data,
                            viewer: viewer,
                            preferences: preferences,
                            promptById: promptById
                        )
                    }
                }
                var results: [DiscoverCandidate] = []
                for try await candidate in group {
                    if let candidate { results.append(candidate) }
                }
                return results
            }
            matched.append(contentsOf: assembled)

            if snapshot.documents.count < Self.queryBatchSize {
                exhausted = true
            }
        }

        matched.sort(by: Self.rank)

        let pageCursor: String?
        if lastExaminedId == nil || lastExaminedId == cursor {
            pageCursor = exhausted ? nil : lastExaminedId
        } else if exhausted, matched.count < pageSize {
            pageCursor = nil
        } else {
            pageCursor = lastExaminedId
        }

        return DiscoverFeedPage(candidates: matched, cursor: pageCursor)
    }

    // MARK: - Assemble + filter

    private func activePromptsById() async throws -> [String: Prompt] {
        if let promptCacheById { return promptCacheById }
        let prompts = try await promptService.fetchActivePrompts()
        let byId = Dictionary(uniqueKeysWithValues: prompts.map { ($0.id, $0) })
        promptCacheById = byId
        return byId
    }

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

        // The three per-candidate reads are independent — run them concurrently.
        async let photosTask = loadPhotos(
            userId: userId,
            legacyPhotoURL: data["photoURL"] as? String
        )
        async let answersTask = promptService.fetchAnswers(userId: userId)
        async let prefsTask = preferencesService.fetchPreferences(userId: userId)

        let photos = try await photosTask
        guard !photos.isEmpty else { return nil }

        let answers = try await answersTask
        let bits: [DiscoverBit] = answers.compactMap { answer in
            guard let prompt = promptById[answer.promptId] else { return nil }
            return DiscoverBit(
                id: answer.promptId,
                promptText: prompt.text,
                answerText: answer.answerText,
                sortOrder: answer.sortOrder
            )
        }.sorted { $0.sortOrder < $1.sortOrder }

        // Display-only on the card — never filter the feed by hangout type.
        let prefs = try? await prefsTask
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
        let viewerCity = Self.normalizedCity(preferences.trimmedCity ?? viewer.city)
        let otherCity = Self.normalizedCity(candidateCity)

        // Same city always matches — don't let coarse GPS / radius hide neighbors.
        if !viewerCity.isEmpty, !otherCity.isEmpty, viewerCity == otherCity {
            return true
        }

        // Different (or missing) city labels: allow if within discover radius.
        if let distanceKm {
            return distanceKm <= Double(preferences.resolvedRadiusKm)
        }

        return false
    }

    /// Folds Turkish İ/I/ı and trims so "Istanbul" / "İstanbul" / " istanbul " match.
    static func normalizedCity(_ raw: String?) -> String {
        guard let raw else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let turkish = Locale(identifier: "tr_TR")
        return trimmed
            .lowercased(with: turkish)
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
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
