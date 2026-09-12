import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreLikeService {
    static let collectionName = "likes"
    static let defaultPageSize = 12
    private static let documentIdChunk = 10

    private let promptService = FirestorePromptService()

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    @discardableResult
    func createLike(
        fromUserId: String,
        toUserId: String,
        targetType: DiscoverLike.TargetType,
        targetId: String,
        comment: String? = nil
    ) async throws -> DiscoverLike {
        guard let database else { throw AuthError.notConfigured }
        guard fromUserId != toUserId else {
            throw AuthError.unknown("You can't click your own profile.")
        }
        guard !toUserId.isEmpty, !targetId.isEmpty else {
            throw AuthError.unknown("Missing click target.")
        }

        let trimmedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedComment, trimmedComment.count > DiscoverLike.maxCommentLength {
            throw AuthError.unknown(
                "Keep comments under \(DiscoverLike.maxCommentLength) characters."
            )
        }
        let commentValue = (trimmedComment?.isEmpty == false) ? trimmedComment : nil

        let docId = DiscoverLike.documentId(
            fromUserId: fromUserId,
            toUserId: toUserId,
            targetType: targetType,
            targetId: targetId
        )
        let document = database.collection(Self.collectionName).document(docId)
        let existing = try await document.getDocument()
        if existing.exists, let data = existing.data() {
            return mapLike(id: docId, data: data)
        }

        var clean: [String: Any] = [
            "fromUserId": fromUserId,
            "toUserId": toUserId,
            "targetType": targetType.rawValue,
            "targetId": targetId,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let commentValue {
            clean["comment"] = commentValue
        }

        try await document.setData(clean)

        return DiscoverLike(
            id: docId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            targetType: targetType,
            targetId: targetId,
            comment: commentValue,
            createdAt: Date()
        )
    }

    func fetchLikes(fromUserId: String, toUserId: String) async throws -> [DiscoverLike] {
        guard let database else { throw AuthError.notConfigured }
        guard !fromUserId.isEmpty, !toUserId.isEmpty else { return [] }
        let snapshot = try await database.collection(Self.collectionName)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .whereField("toUserId", isEqualTo: toUserId)
            .getDocuments()
        return snapshot.documents
            .map { mapLike(id: $0.documentID, data: $0.data()) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// True if `fromUserId` has liked `toUserId` on any target (profile / Bit / photo).
    func hasLike(fromUserId: String, toUserId: String) async throws -> Bool {
        guard let database else { throw AuthError.notConfigured }
        guard !fromUserId.isEmpty, !toUserId.isEmpty else { return false }
        let snapshot = try await database.collection(Self.collectionName)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .whereField("toUserId", isEqualTo: toUserId)
            .limit(to: 1)
            .getDocuments()
        return !snapshot.documents.isEmpty
    }

    func fetchIncomingFromUserIds(toUserId: String) async throws -> Set<String> {
        guard let database else { throw AuthError.notConfigured }
        let snapshot = try await database.collection(Self.collectionName)
            .whereField("toUserId", isEqualTo: toUserId)
            .getDocuments()
        return Set(snapshot.documents.compactMap { $0.data()["fromUserId"] as? String })
    }

    func blockedUserIds(for viewerId: String) async -> Set<String> {
        await loadBlockedUserIds(viewerId: viewerId)
    }

    func fetchLikedUserIds(fromUserId: String) async throws -> Set<String> {
        guard let database else { throw AuthError.notConfigured }
        let snapshot = try await database.collection(Self.collectionName)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .getDocuments()
        return Set(snapshot.documents.compactMap { $0.data()["toUserId"] as? String })
    }

    /// Incoming (`toUserId`) or sent (`fromUserId`) likes, newest first, blocks excluded.
    func fetchInbox(
        direction: LikeInboxDirection,
        viewerId: String,
        cursor: String? = nil,
        pageSize: Int = 12,
        viewerPhotos: [ProfilePhoto] = [],
        viewerAnswers: [PromptAnswer] = []
    ) async throws -> LikeInboxPage {
        guard let database else { throw AuthError.notConfigured }
        guard !viewerId.isEmpty else { return .empty }

        viewerPhotoById = Dictionary(viewerPhotos.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        viewerAnswerByPromptId = Dictionary(viewerAnswers.map { ($0.promptId, $0) }, uniquingKeysWith: { _, last in last })
        inboxViewerId = viewerId

        async let excludedLoad = loadInboxExclusions(viewerId: viewerId, direction: direction)

        var query: Query = database.collection(Self.collectionName)
            .whereField(direction == .incoming ? "toUserId" : "fromUserId", isEqualTo: viewerId)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        if let cursor, !cursor.isEmpty {
            let cursorDoc = try await database.collection(Self.collectionName)
                .document(cursor)
                .getDocument()
            if cursorDoc.exists {
                query = query.start(afterDocument: cursorDoc)
            }
        }

        let snapshot = try await query.getDocuments()
        let excluded = await excludedLoad

        if snapshot.documents.isEmpty {
            let page = LikeInboxPage(items: [], cursor: nil)
            if cursor == nil { storeInbox(page, direction: direction, viewerId: viewerId) }
            return page
        }

        var pending: [(like: DiscoverLike, otherId: String)] = []
        var lastExaminedId: String?
        for document in snapshot.documents {
            lastExaminedId = document.documentID
            let like = mapLike(id: document.documentID, data: document.data())
            let otherId = direction == .incoming ? like.fromUserId : like.toUserId
            guard otherId != viewerId, !excluded.contains(otherId) else { continue }
            pending.append((like, otherId))
        }

        let items = await hydrateAll(pending)
        let cursorOut = snapshot.documents.count < pageSize ? nil : lastExaminedId
        let page = LikeInboxPage(items: items, cursor: cursorOut)
        if cursor == nil { storeInbox(page, direction: direction, viewerId: viewerId) }
        return page
    }

    func cachedInbox(direction: LikeInboxDirection, viewerId: String) -> LikeInboxPage? {
        pageCache[InboxCacheKey(viewerId: viewerId, direction: direction)]
    }

    func dropCachedInboxUser(userId: String, viewerId: String) {
        for direction in LikeInboxDirection.allCases {
            let key = InboxCacheKey(viewerId: viewerId, direction: direction)
            guard let page = pageCache[key] else { continue }
            let items = page.items.filter { $0.otherUser.id != userId }
            pageCache[key] = LikeInboxPage(items: items, cursor: page.cursor)
        }
        excludedCache?.insert(userId)
    }

    func resetCaches() {
        pageCache = [:]
        partyCache = [:]
        viewerPhotoById = [:]
        viewerAnswerByPromptId = [:]
        excludedCache = nil
        inboxViewerId = nil
    }

    private struct InboxCacheKey: Hashable {
        let viewerId: String
        let direction: LikeInboxDirection
    }

    private var pageCache: [InboxCacheKey: LikeInboxPage] = [:]
    private var partyCache: [String: LikePartySummary] = [:]
    private var viewerPhotoById: [String: ProfilePhoto] = [:]
    private var viewerAnswerByPromptId: [String: PromptAnswer] = [:]
    private var inboxViewerId: String?
    private var excludedCache: Set<String>?

    private func storeInbox(_ page: LikeInboxPage, direction: LikeInboxDirection, viewerId: String) {
        pageCache[InboxCacheKey(viewerId: viewerId, direction: direction)] = page
    }

    private func loadInboxExclusions(viewerId: String, direction: LikeInboxDirection) async -> Set<String> {
        var excluded = await loadBlockedUserIds(viewerId: viewerId)
        if direction == .incoming {
            excluded.formUnion(await loadHandledUserIds(viewerId: viewerId))
        } else {
            excluded.formUnion(await fetchIncomingIdsForExclusions(viewerId: viewerId))
        }
        excludedCache = excluded
        return excluded
    }

    private func fetchIncomingIdsForExclusions(viewerId: String) async -> Set<String> {
        (try? await fetchIncomingFromUserIds(toUserId: viewerId)) ?? []
    }

    private func hydrateAll(
        _ pending: [(like: DiscoverLike, otherId: String)]
    ) async -> [InboxLike] {
        guard !pending.isEmpty else { return [] }
        await loadParties(userIds: Array(Set(pending.map(\.otherId))))
        return await withTaskGroup(of: (Int, InboxLike?).self) { group in
            for (index, pair) in pending.enumerated() {
                group.addTask { @MainActor in
                    (index, await self.hydrate(like: pair.like, otherUserId: pair.otherId))
                }
            }
            var slots: [InboxLike?] = Array(repeating: nil, count: pending.count)
            for await (index, item) in group {
                slots[index] = item
            }
            return slots.compactMap { $0 }
        }
    }

    private func hydrate(like: DiscoverLike, otherUserId: String) async -> InboxLike? {
        let otherUser: LikePartySummary?
        if let cached = partyCache[otherUserId] {
            otherUser = cached
        } else {
            otherUser = await loadParty(userId: otherUserId)
        }
        guard let otherUser else { return nil }
        let target = await loadTarget(like: like)
        return InboxLike(like: like, otherUser: otherUser, target: target)
    }

    private func loadParties(userIds: [String]) async {
        let missing = userIds.filter { partyCache[$0] == nil }
        guard !missing.isEmpty else { return }
        let docs = await fetchDocuments(collection: "users", ids: missing)
        for (id, data) in docs {
            let name = (data["displayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            partyCache[id] = LikePartySummary(
                id: id,
                displayName: name,
                photoURL: data["photoURL"] as? String,
                photoThumbnailURL: data["photoThumbnailURL"] as? String
            )
        }
    }

    private func fetchDocuments(collection: String, ids: [String]) async -> [String: [String: Any]] {
        guard let database, !ids.isEmpty else { return [:] }
        var result: [String: [String: Any]] = [:]
        var index = 0
        while index < ids.count {
            let end = min(index + Self.documentIdChunk, ids.count)
            let chunk = Array(ids[index..<end])
            index = end
            guard let snapshot = try? await database.collection(collection)
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments() else { continue }
            for document in snapshot.documents {
                result[document.documentID] = document.data()
            }
        }
        return result
    }

    private func loadParty(userId: String) async -> LikePartySummary? {
        if let cached = partyCache[userId] { return cached }
        await loadParties(userIds: [userId])
        return partyCache[userId]
    }

    private func loadTarget(like: DiscoverLike) async -> LikeTargetPreview {
        var preview = LikeTargetPreview(type: like.targetType, targetId: like.targetId)
        if like.toUserId == inboxViewerId {
            if applyLocalTarget(&preview, like: like) { return preview }
        }

        switch like.targetType {
        case .profile:
            break
        case .photo:
            if let photo = await loadPhoto(ownerId: like.toUserId, photoId: like.targetId) {
                preview.photoURL = photo.url
                preview.photoThumbnailURL = photo.thumbnailURL
            }
        case .prompt:
            if let bit = await loadBit(ownerId: like.toUserId, promptId: like.targetId) {
                preview.promptText = bit.promptText
                preview.answerText = bit.answerText
            }
        }
        return preview
    }

    private func applyLocalTarget(_ preview: inout LikeTargetPreview, like: DiscoverLike) -> Bool {
        switch like.targetType {
        case .profile:
            return true
        case .photo:
            guard let photo = viewerPhotoById[like.targetId] else { return false }
            preview.photoURL = photo.url
            preview.photoThumbnailURL = photo.thumbnailURL
            return true
        case .prompt:
            guard let answer = viewerAnswerByPromptId[like.targetId] else { return false }
            preview.answerText = answer.answerText
            preview.promptText = promptService.cachedActivePrompts().first(where: { $0.id == like.targetId })?.text
            return preview.promptText != nil || !(preview.answerText ?? "").isEmpty
        }
    }

    private func loadPhoto(ownerId: String, photoId: String) async -> (url: String, thumbnailURL: String?)? {
        guard let database, !photoId.isEmpty else { return nil }
        guard let snapshot = try? await database
            .collection("users")
            .document(ownerId)
            .collection("photos")
            .document(photoId)
            .getDocument(),
              snapshot.exists,
              let data = snapshot.data(),
              let url = data["url"] as? String,
              !url.isEmpty else { return nil }
        return (url, data["thumbnailURL"] as? String)
    }

    private func loadBit(ownerId: String, promptId: String) async -> (promptText: String, answerText: String)? {
        guard let database, !promptId.isEmpty else { return nil }
        let answerId = FirestorePromptService.answerDocumentId(userId: ownerId, promptId: promptId)
        let answerSnap = try? await database.collection("promptAnswers").document(answerId).getDocument()
        let answerText = (answerSnap?.data()?["answerText"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let prompts = (try? await promptService.fetchActivePrompts()) ?? []
        let promptText = prompts.first(where: { $0.id == promptId })?.text

        guard let promptText, let answerText, !answerText.isEmpty else {
            if let promptText { return (promptText, answerText ?? "") }
            return nil
        }
        return (promptText, answerText)
    }

    /// Incoming likes the viewer already answered — liked back or passed on.
    private func loadHandledUserIds(viewerId: String) async -> Set<String> {
        async let liked = fetchOutgoingIds(collection: Self.collectionName, viewerId: viewerId)
        async let skipped = fetchOutgoingIds(collection: "skips", viewerId: viewerId)
        let likedIds = await liked
        let skippedIds = await skipped
        return likedIds.union(skippedIds)
    }

    private func fetchOutgoingIds(collection: String, viewerId: String) async -> Set<String> {
        guard let database else { return [] }
        do {
            let snapshot = try await database.collection(collection)
                .whereField("fromUserId", isEqualTo: viewerId)
                .getDocuments()
            return Set(snapshot.documents.compactMap { $0.data()["toUserId"] as? String })
        } catch {
            return []
        }
    }

    private func loadBlockedUserIds(viewerId: String) async -> Set<String> {
        async let blockedByMe = fetchBlockIds(field: "blockerId", equals: viewerId, take: "blockedId")
        async let blockedMe = fetchBlockIds(field: "blockedId", equals: viewerId, take: "blockerId")
        let blockedByMeIds = await blockedByMe
        let blockedMeIds = await blockedMe
        return blockedByMeIds.union(blockedMeIds)
    }

    private func fetchBlockIds(field: String, equals value: String, take: String) async -> Set<String> {
        guard let database else { return [] }
        do {
            let snapshot = try await database.collection("blocks")
                .whereField(field, isEqualTo: value)
                .getDocuments()
            return Set(snapshot.documents.compactMap { $0.data()[take] as? String })
        } catch {
            return []
        }
    }

    // MARK: - Incoming liker badge

    private var incomingCountListener: ListenerRegistration?
    private var incomingCountViewerId: String?
    private var lastIncomingFromIds: Set<String> = []
    private var incomingCountHandler: ((Int) -> Void)?

    /// Live unique people who liked the viewer and haven't been liked back or passed.
    func startIncomingLikerCountListener(
        viewerId: String,
        onChange: @escaping (Int) -> Void
    ) {
        if incomingCountViewerId == viewerId, incomingCountListener != nil {
            incomingCountHandler = onChange
            Task { await publishIncomingLikerCount() }
            return
        }

        stopIncomingLikerCountListener()
        incomingCountViewerId = viewerId
        incomingCountHandler = onChange
        lastIncomingFromIds = []
        onChange(0)

        guard let database, !viewerId.isEmpty else { return }

        incomingCountListener = database.collection(Self.collectionName)
            .whereField("toUserId", isEqualTo: viewerId)
            .addSnapshotListener { [weak self] snapshot, _ in
                let ids = Set(
                    (snapshot?.documents ?? []).compactMap { document in
                        document.data()["fromUserId"] as? String
                    }
                    .filter { !$0.isEmpty }
                )
                Task { @MainActor in
                    guard let self, self.incomingCountViewerId == viewerId else { return }
                    self.lastIncomingFromIds = ids
                    await self.publishIncomingLikerCount()
                }
            }
    }

    func stopIncomingLikerCountListener() {
        incomingCountListener?.remove()
        incomingCountListener = nil
        incomingCountViewerId = nil
        incomingCountHandler = nil
        lastIncomingFromIds = []
    }

    /// Recompute after like-back / pass — incoming docs don't change, exclusions do.
    func refreshIncomingLikerCount() async {
        excludedCache = nil
        await publishIncomingLikerCount()
    }

    private func publishIncomingLikerCount() async {
        guard let viewerId = incomingCountViewerId else { return }
        if excludedCache == nil {
            var excluded = await loadBlockedUserIds(viewerId: viewerId)
            excluded.formUnion(await loadHandledUserIds(viewerId: viewerId))
            excludedCache = excluded
        }
        let excluded = (excludedCache ?? []).union([viewerId])
        incomingCountHandler?(lastIncomingFromIds.subtracting(excluded).count)
    }

    private func mapLike(id: String, data: [String: Any]) -> DiscoverLike {
        let typeRaw = data["targetType"] as? String ?? DiscoverLike.TargetType.profile.rawValue
        return DiscoverLike(
            id: id,
            fromUserId: data["fromUserId"] as? String ?? "",
            toUserId: data["toUserId"] as? String ?? "",
            targetType: DiscoverLike.TargetType(rawValue: typeRaw) ?? .profile,
            targetId: data["targetId"] as? String ?? "",
            comment: data["comment"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }
}
