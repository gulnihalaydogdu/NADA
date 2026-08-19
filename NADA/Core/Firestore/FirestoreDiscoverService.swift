import FirebaseCore
import FirebaseFirestore
import Foundation

/// Builds Discover feed pages from complete nearby profiles (W3-01).
///
/// Queries `isProfileComplete`, filters by viewer prefs (gender / age / city+radius),
/// excludes self + liked / liked-you / skipped / seen / blocked, ranks by distance then recency.
@MainActor
final class FirestoreDiscoverService {
    static let defaultPageSize = 10
    private static let queryBatchSize = 40
    private static let maxQueryBatches = 12

    private let promptService = FirestorePromptService()
    private var promptCacheById: [String: Prompt]?
    private var profileCacheViewerId: String?
    private var profileCache: [String: DiscoverCandidate] = [:]
    private var profileInflight: [String: Task<DiscoverCandidate?, Never>] = [:]

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Fetches the next Discover page for `viewer`.
    /// - Parameters:
    ///   - extraExcludedUserIds: Additional ids to skip (tests / UI already-on-screen).
    ///   - cursor: Opaque token from a previous `DiscoverFeedPage.cursor`.
    ///   - pageSize: Max candidates after filtering.
    func fetchCandidates(
        viewer: NADAUser,
        preferences: UserPreferences,
        extraExcludedUserIds: Set<String> = [],
        cursor: String? = nil,
        pageSize: Int = defaultPageSize,
        excludeSeen: Bool = true
    ) async throws -> DiscoverFeedPage {
        guard let database else { throw AuthError.notConfigured }
        guard pageSize > 0 else {
            return DiscoverFeedPage(candidates: [], cursor: nil)
        }
        guard viewer.isProfileComplete else {
            return DiscoverFeedPage(candidates: [], cursor: nil)
        }

        try? await touchLastActive(userId: viewer.id)

        let promptById = try await activePromptsById()
        let excluded = extraExcludedUserIds.union(
            try await loadExcludedUserIds(viewerId: viewer.id, excludeSeen: excludeSeen)
        )

        var matched: [DiscoverCandidate] = []
        matched.reserveCapacity(pageSize)
        var lastExaminedId: String? = cursor
        var exhausted = false
        var batches = 0

        while matched.count < pageSize, !exhausted, batches < Self.maxQueryBatches {
            batches += 1

            // Equality-only query keeps the default document-id order (no composite index).
            var query: Query = database.collection("users")
                .whereField("isProfileComplete", isEqualTo: true)
                .limit(to: Self.queryBatchSize)

            if let lastExaminedId, !lastExaminedId.isEmpty {
                do {
                    let cursorDoc = try await database.collection("users").document(lastExaminedId).getDocument()
                    if cursorDoc.exists {
                        query = query.start(afterDocument: cursorDoc)
                    }
                } catch {
                    // Can't read the cursor doc — continue from the start of this batch.
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
                if excluded.contains(userId) { continue }
                pending.append((userId, document.data()))
            }

            let assembled = await withTaskGroup(of: DiscoverCandidate?.self) { group in
                for (userId, data) in pending {
                    group.addTask { @MainActor in
                        do {
                            return try await self.assembleCandidate(
                                userId: userId,
                                data: data,
                                viewer: viewer,
                                preferences: preferences,
                                promptById: promptById
                            )
                        } catch {
                            return nil
                        }
                    }
                }
                var results: [DiscoverCandidate] = []
                for await candidate in group {
                    if let candidate { results.append(candidate) }
                }
                return results
            }
            matched.append(contentsOf: assembled)

            if snapshot.documents.count < Self.queryBatchSize {
                exhausted = true
            }
        }

        // Two test accounts: after a card is marked seen, recycle it so Discover isn't empty.
        if matched.isEmpty, cursor == nil, excludeSeen {
            return try await fetchCandidates(
                viewer: viewer,
                preferences: preferences,
                extraExcludedUserIds: extraExcludedUserIds,
                cursor: nil,
                pageSize: pageSize,
                excludeSeen: false
            )
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

        return DiscoverFeedPage(
            candidates: Array(matched.prefix(pageSize)),
            cursor: pageCursor
        )
    }

    /// Full profile for Likes inbox — no Discover gender/age/radius gates.
    /// Someone who liked you should still be viewable even if they wouldn't appear in the feed.
    func fetchProfile(userId: String, viewer: NADAUser) async throws -> DiscoverCandidate? {
        guard !userId.isEmpty, userId != viewer.id else { return nil }

        if profileCacheViewerId != viewer.id {
            profileCache = [:]
            profileInflight = [:]
            profileCacheViewerId = viewer.id
        }
        if let cached = profileCache[userId] {
            return cached
        }
        if let inflight = profileInflight[userId] {
            return await inflight.value
        }

        let task = Task<DiscoverCandidate?, Never> {
            await self.loadProfileUncached(userId: userId, viewer: viewer)
        }
        profileInflight[userId] = task
        let candidate = await task.value
        profileInflight[userId] = nil
        if let candidate {
            profileCache[userId] = candidate
        }
        return candidate
    }

    func evictProfile(userId: String) {
        profileCache[userId] = nil
        profileInflight[userId] = nil
    }

    private func loadProfileUncached(userId: String, viewer: NADAUser) async -> DiscoverCandidate? {
        guard let database else { return nil }
        guard let snapshot = try? await database.collection("users").document(userId).getDocument(),
              snapshot.exists,
              let data = snapshot.data() else { return nil }
        let promptById = (try? await activePromptsById()) ?? [:]
        return try? await assembleCandidate(
            userId: userId,
            data: data,
            viewer: viewer,
            preferences: UserPreferences.defaults(for: viewer),
            promptById: promptById,
            applyDiscoveryFilters: false
        )
    }

    /// Marks a profile as seen so later pages skip it (W3-01 / W3-04).
    func recordSeen(fromUserId: String, toUserId: String) async throws {
        guard let database else { throw AuthError.notConfigured }
        guard fromUserId != toUserId, !toUserId.isEmpty else { return }

        let docId = "\(fromUserId)_\(toUserId)"
        try await database.collection("discoverSeen").document(docId).setData([
            "fromUserId": fromUserId,
            "toUserId": toUserId,
            "seenAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // MARK: - Exclusions

    private func loadExcludedUserIds(viewerId: String, excludeSeen: Bool) async throws -> Set<String> {
        async let liked = fetchToUserIds(collection: "likes", fromUserId: viewerId)
        async let likedMe = fetchIds(
            collection: "likes",
            field: "toUserId",
            equals: viewerId,
            take: "fromUserId"
        )
        async let skipped = fetchToUserIds(collection: "skips", fromUserId: viewerId)
        async let seen = fetchToUserIds(collection: "discoverSeen", fromUserId: viewerId)
        async let blockedByMe = fetchIds(
            collection: "blocks",
            field: "blockerId",
            equals: viewerId,
            take: "blockedId"
        )
        async let blockedMe = fetchIds(
            collection: "blocks",
            field: "blockedId",
            equals: viewerId,
            take: "blockerId"
        )
        var ids = try await liked
            .union(likedMe)
            .union(skipped)
            .union(blockedByMe)
            .union(blockedMe)
        if excludeSeen {
            ids.formUnion(try await seen)
        }
        return ids
    }

    private func fetchToUserIds(collection: String, fromUserId: String) async throws -> Set<String> {
        try await fetchIds(collection: collection, field: "fromUserId", equals: fromUserId, take: "toUserId")
    }

    private func fetchIds(
        collection: String,
        field: String,
        equals value: String,
        take: String
    ) async throws -> Set<String> {
        guard let database else { throw AuthError.notConfigured }
        do {
            let snapshot = try await database.collection(collection)
                .whereField(field, isEqualTo: value)
                .getDocuments()
            return Set(snapshot.documents.compactMap { $0.data()[take] as? String })
        } catch {
            // Collection missing / rules not published yet — don't block the feed.
            return []
        }
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
        promptById: [String: Prompt],
        applyDiscoveryFilters: Bool = true
    ) async throws -> DiscoverCandidate? {
        let displayName = (data["displayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !displayName.isEmpty else { return nil }

        let gender = data["gender"] as? String
        if applyDiscoveryFilters {
            guard matchesLookingFor(preferences.lookingForGenders, gender: gender) else { return nil }
        }

        let dateOfBirth = (data["dateOfBirth"] as? Timestamp)?.dateValue()
        let age = dateOfBirth.map { ProfileAge.age(from: $0) }
        if applyDiscoveryFilters {
            guard let age, age >= preferences.minAge, age <= preferences.maxAge else { return nil }
        }

        let city = (data["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateLat = doubleValue(data["approxLatitude"])
        let candidateLon = doubleValue(data["approxLongitude"])
        let distanceKm = distance(
            viewer: viewer,
            candidateLatitude: candidateLat,
            candidateLongitude: candidateLon
        )

        if applyDiscoveryFilters {
            guard passesLocationFilter(
                preferences: preferences,
                viewer: viewer,
                candidateCity: city,
                distanceKm: distanceKm
            ) else {
                return nil
            }
        }

        async let photosTask = loadPhotos(
            userId: userId,
            legacyPhotoURL: data["photoURL"] as? String,
            legacyThumbnailURL: data["photoThumbnailURL"] as? String
        )
        async let answersTask = promptService.fetchAnswers(userId: userId)

        let photos: [ProfilePhoto]
        do {
            photos = try await photosTask
        } catch {
            photos = legacyPhotos(
                url: data["photoURL"] as? String,
                thumbnailURL: data["photoThumbnailURL"] as? String
            )
        }
        guard applyDiscoveryFilters == false || !photos.isEmpty else { return nil }

        let answers: [PromptAnswer]
        do {
            answers = try await answersTask
        } catch {
            answers = []
        }
        let bits: [DiscoverBit] = answers.compactMap { answer in
            guard let prompt = promptById[answer.promptId] else { return nil }
            return DiscoverBit(
                id: answer.promptId,
                promptText: prompt.text,
                answerText: answer.answerText,
                sortOrder: answer.sortOrder
            )
        }.sorted { $0.sortOrder < $1.sortOrder }

        let lastActiveAt = (data["lastActiveAt"] as? Timestamp)?.dateValue()
            ?? (data["createdAt"] as? Timestamp)?.dateValue()

        return DiscoverCandidate(
            id: userId,
            displayName: displayName,
            age: age,
            gender: gender,
            city: city,
            jobTitle: NADAUser.trimmed(data["jobTitle"] as? String, max: NADAUser.maxJobTitleLength),
            university: NADAUser.trimmed(data["university"] as? String, max: NADAUser.maxUniversityLength),
            hangoutLookingFor: NADAUser.trimmed(
                data["hangoutLookingFor"] as? String,
                max: NADAUser.maxHangoutLookingForLength
            ),
            zodiac: dateOfBirth.map { ZodiacSign.from(dateOfBirth: $0) },
            interestIds: InterestSelection.normalized(data["interestIds"] as? [String] ?? []),
            photos: photos,
            bits: bits,
            distanceKm: distanceKm,
            lastActiveAt: lastActiveAt
        )
    }

    private func loadPhotos(
        userId: String,
        legacyPhotoURL: String?,
        legacyThumbnailURL: String?
    ) async throws -> [ProfilePhoto] {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection("users")
            .document(userId)
            .collection("photos")
            .getDocuments()

        let photos = snapshot.documents
            .compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        if !photos.isEmpty { return photos }
        return legacyPhotos(url: legacyPhotoURL, thumbnailURL: legacyThumbnailURL)
    }

    private func legacyPhotos(url: String?, thumbnailURL: String?) -> [ProfilePhoto] {
        guard let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return [
            ProfilePhoto(
                id: "legacy",
                url: url,
                thumbnailURL: thumbnailURL,
                sortOrder: 0,
                isPrimary: true,
                createdAt: nil
            )
        ]
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
            thumbnailURL: data["thumbnailURL"] as? String,
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
        case .everyone: return true
        case .women: return profileGender == .woman
        case .men: return profileGender == .man
        case .nonBinary: return profileGender == .nonBinary
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

        if !viewerCity.isEmpty, !otherCity.isEmpty, viewerCity == otherCity {
            return true
        }
        if let distanceKm {
            return distanceKm <= Double(preferences.resolvedRadiusKm)
        }
        return false
    }

    /// Folds Turkish İ/I/ı so "Istanbul" / "İstanbul" match.
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

    /// Nearer first; then more recently active; then name.
    private static func rank(_ lhs: DiscoverCandidate, _ rhs: DiscoverCandidate) -> Bool {
        switch (lhs.distanceKm, rhs.distanceKm) {
        case let (l?, r?) where l != r:
            return l < r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        switch (lhs.lastActiveAt, rhs.lastActiveAt) {
        case let (l?, r?) where l != r:
            return l > r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func touchLastActive(userId: String) async throws {
        guard let database else { return }
        try await database.collection("users").document(userId).updateData([
            "lastActiveAt": FieldValue.serverTimestamp()
        ])
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
