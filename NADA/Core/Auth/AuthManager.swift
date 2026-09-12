import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class AuthManager {
    private(set) var currentUser: NADAUser?
    /// Discovery prefs (`preferences/{uid}`). Nil until profile hydrate finishes.
    private(set) var currentPreferences: UserPreferences?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Unique people with a pending incoming like (tab badge). 0 hides the badge.
    private(set) var incomingLikerCount = 0

    /// True while a signed-in user's Firestore profile is still being read.
    private(set) var isResolvingProfile = false

    /// False until the initial session has been fully resolved on launch.
    private(set) var isSessionResolved = false

    /// Splash stays up until this is true. Non-Discover landings flip it immediately;
    /// Discover waits until the first card's primary photo is in cache (or a timeout).
    private(set) var isDiscoverLaunchReady = false

    private var discoverWarmTask: Task<Void, Never>?
    private var didFinishDiscoverWarm = false
    private var didWarmLikeInbox = false

    /// In-memory Discover deck for this signed-in session. Survives tab switches;
    /// cleared on logout / process death. Skip and click still advance the card.
    private(set) var discoverSessionQueue: [DiscoverCandidate] = []
    private(set) var discoverSessionCursor: String?
    private(set) var discoverSessionSkipped: [DiscoverCandidate] = []
    private(set) var discoverSessionLoaded = false

    /// Wizard Back on the first step returns here without clearing saved basics.
    var isRevisitingBasicProfile = false

    private let authService: FirebaseAuthService
    private let userService: FirestoreUserService
    private let preferencesService: FirestorePreferencesService
    private let storageService: FirebaseStorageService
    private let photoService: FirestorePhotoService
    private let promptService: FirestorePromptService
    private let discoverService: FirestoreDiscoverService
    private let likeService: FirestoreLikeService
    private let skipService: FirestoreSkipService
    private let matchService: FirestoreMatchService
    private let chatService: FirestoreChatService
    private var authStateHandle: AuthStateHandle?

    private var cachedPhotos: [ProfilePhoto] = []
    private var cachedPhotosUserId: String?
    private var didLoadPhotos = false
    private var cachedAnswers: [PromptAnswer] = []
    private var cachedAnswersUserId: String?
    private var didLoadAnswers = false

    init() {
        self.authService = FirebaseAuthService()
        self.userService = FirestoreUserService()
        self.preferencesService = FirestorePreferencesService()
        self.storageService = FirebaseStorageService()
        self.photoService = FirestorePhotoService(storageService: storageService)
        self.promptService = FirestorePromptService()
        self.discoverService = FirestoreDiscoverService()
        self.likeService = FirestoreLikeService()
        self.skipService = FirestoreSkipService()
        self.matchService = FirestoreMatchService()
        self.chatService = FirestoreChatService()
    }

    var hasCompletedFriendsIntent: Bool {
        currentUser?.friendsIntentCompleted == true
    }

    var hasCompletedBasicProfile: Bool {
        currentUser?.hasCompletedBasicProfile == true
    }

    var hasCompletedProfileWizard: Bool {
        currentUser?.profileWizardCompleted == true
    }

    /// Discover-ready gate (W2-06). Week 3 filters Discover on this flag.
    var isProfileComplete: Bool {
        currentUser?.isProfileComplete == true
    }

    /// Attaches auth listener and hydrates cached session.
    func bootstrap() {
        guard authStateHandle == nil else { return }

        authService.configureFirebaseIfNeeded()

        Task {
            if let cached = authService.cachedUser {
                await handleAuthUser(cached)
            }

            startDiscoverWarmIfNeeded()
            listenForAuthChanges()
            isSessionResolved = true
            await prepareDiscoverLaunch()
        }
    }

    var isAuthenticated: Bool { currentUser != nil }
    var isFirebaseReady: Bool { authService.isReady }

    /// Covers both the network call and the profile read that follows it.
    var isBusy: Bool { isLoading || isResolvingProfile }

    func signInWithEmail(email: String, password: String) async {
        await perform {
            try await self.authService.signIn(email: email, password: password)
        }
    }

    func signUpWithEmail(email: String, password: String) async {
        await perform {
            try await self.authService.signUp(email: email, password: password)
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async {
        await perform {
            try await self.authService.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
        }
    }

    func completeFriendsIntent() async {
        guard let userId = currentUser?.id else { return }
        await perform {
            let updated = try await self.userService.setFriendsIntentCompleted(userId: userId, isCompleted: true)
            self.currentUser = updated
        }
    }

    /// Returns to the friends-intent screen from Basics without signing out.
    func reopenFriendsIntent() async {
        guard let userId = currentUser?.id else { return }
        isRevisitingBasicProfile = false
        await perform {
            let updated = try await self.userService.setFriendsIntentCompleted(userId: userId, isCompleted: false)
            self.currentUser = updated
        }
    }

    /// Writes the name (required) plus any gender / city / birthday already chosen.
    /// Empty optional fields are left unchanged so Skip can leave them for later.
    @discardableResult
    func completeBasicProfileOnboarding(
        displayName: String,
        gender: ProfileGender?,
        city: String,
        dateOfBirth: Date?
    ) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return false
        }

        if let dateOfBirth, !ProfileAge.isAtLeastMinimumAge(dateOfBirth) {
            errorMessage = "You must be \(ProfileAge.minimumAge) or older to use NADA."
            return false
        }

        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityToSave = trimmedCity.isEmpty ? nil : trimmedCity

        var didSucceed = false
        await perform {
            let updated = try await self.userService.updateProfile(
                userId: userId,
                displayName: trimmedName,
                gender: gender?.rawValue,
                city: cityToSave,
                locale: nil,
                dateOfBirth: dateOfBirth,
                markBasicProfileSetupCompleted: true
            )
            self.currentUser = updated
            if let cityToSave {
                self.currentPreferences = try await self.preferencesService.syncCity(
                    userId: userId,
                    city: cityToSave,
                    seedFrom: updated
                )
            }
            try await self.syncProfileCompleteness()
            self.isRevisitingBasicProfile = false
            didSucceed = true
        }
        return didSucceed
    }

    /// Job / university / hangout looking-for on the Discover card. Does not require city or gender.
    @discardableResult
    func updateHangoutEssentials(
        jobTitle: String,
        university: String,
        hangoutLookingFor: String
    ) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        var didSucceed = false
        await perform {
            let updated = try await self.userService.updateProfile(
                userId: userId,
                displayName: nil,
                gender: nil,
                city: nil,
                locale: nil,
                jobTitle: jobTitle,
                university: university,
                hangoutLookingFor: hangoutLookingFor,
                updateHangoutEssentials: true
            )
            self.currentUser = updated
            didSucceed = true
        }
        return didSucceed
    }

    func refreshCurrentUser() async {
        guard let userId = currentUser?.id else { return }
        await perform {
            if let profile = try await self.userService.fetchUser(id: userId) {
                self.currentUser = profile
                do {
                    self.currentPreferences = try await self.preferencesService.ensurePreferences(for: profile)
                } catch {
                    self.currentPreferences = nil
                    // Don't fail the whole refresh — Profile still works without prefs hydrate.
                    self.errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
                }
                try await self.syncProfileCompleteness()
            }
        }
    }

    /// Updates display name, gender, city, and birthday on Firestore. Enforces 18+.
    /// Pass `updateHangoutEssentials` from About you / Edit so job, university, and
    /// hangout looking-for persist (empty values clear the fields). Returns `true` on success.
    @discardableResult
    func updateBasicProfile(
        displayName: String,
        gender: ProfileGender,
        city: String,
        dateOfBirth: Date,
        jobTitle: String? = nil,
        university: String? = nil,
        hangoutLookingFor: String? = nil,
        updateHangoutEssentials: Bool = false
    ) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedCity.isEmpty else {
            errorMessage = "Name and city are required."
            return false
        }

        guard ProfileAge.isAtLeastMinimumAge(dateOfBirth) else {
            errorMessage = "You must be \(ProfileAge.minimumAge) or older to use NADA."
            return false
        }

        var didSucceed = false
        await perform {
            let updated = try await self.userService.updateProfile(
                userId: userId,
                displayName: trimmedName,
                gender: gender.rawValue,
                city: trimmedCity,
                locale: nil,
                dateOfBirth: dateOfBirth,
                jobTitle: jobTitle,
                university: university,
                hangoutLookingFor: hangoutLookingFor,
                updateHangoutEssentials: updateHangoutEssentials
            )
            self.currentUser = updated
            self.currentPreferences = try await self.preferencesService.syncCity(
                userId: userId,
                city: trimmedCity,
                seedFrom: updated
            )
            try await self.syncProfileCompleteness()
            if !updateHangoutEssentials {
                self.isRevisitingBasicProfile = false
            }
            didSucceed = true
        }
        return didSucceed
    }

    /// Updates city, discover radius, and optional coarse coordinates.
    /// Mirrors discovery fields onto `preferences/{uid}` (W2-05).
    @discardableResult
    func updateLocation(
        city: String,
        radiusKm: Int,
        approxLatitude: Double? = nil,
        approxLongitude: Double? = nil
    ) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else {
            errorMessage = "City is required."
            return false
        }

        var didSucceed = false
        await perform {
            let updated = try await self.userService.updateLocation(
                userId: userId,
                city: trimmedCity,
                radiusKm: radiusKm,
                approxLatitude: approxLatitude,
                approxLongitude: approxLongitude
            )
            let prefs = try await self.preferencesService.updatePreferences(
                userId: userId,
                city: trimmedCity,
                radiusKm: radiusKm,
                base: self.currentPreferences
            )
            self.currentUser = updated
            self.currentPreferences = prefs
            try await self.syncProfileCompleteness()
            didSucceed = true
        }
        return didSucceed
    }

    /// Reads/writes discovery preferences entity (W2-05 / W2-11). Also mirrors city + radius onto the user doc.
    @discardableResult
    func updatePreferences(_ prefs: UserPreferences) async -> Bool {
        guard currentUser?.id == prefs.userId else { return false }
        guard prefs.trimmedCity != nil else {
            errorMessage = "City is required."
            return false
        }

        var didSucceed = false
        await perform {
            let saved = try await self.preferencesService.updatePreferences(prefs)
            let updated = try await self.userService.updateLocation(
                userId: prefs.userId,
                city: saved.trimmedCity ?? "",
                radiusKm: saved.resolvedRadiusKm
            )
            self.currentPreferences = saved
            self.currentUser = updated
            try await self.syncProfileCompleteness()
            didSucceed = true
        }
        return didSucceed
    }

    /// Convenience for wizard / simple city+radius saves — preserves discovery filters.
    @discardableResult
    func updatePreferences(
        city: String,
        radiusKm: Int
    ) async -> Bool {
        guard let userId = currentUser?.id else { return false }
        var prefs = currentPreferences ?? UserPreferences.defaults(for: currentUser ?? NADAUser(id: userId))
        prefs.city = city
        prefs.radiusKm = radiusKm
        return await updatePreferences(prefs)
    }

    /// Replaces the user's interest badge ids (max 8). Empty is allowed.
    @discardableResult
    func updateInterestIds(_ interestIds: [String]) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        var didSucceed = false
        await perform {
            let updated = try await self.userService.updateInterestIds(
                userId: userId,
                interestIds: interestIds
            )
            self.currentUser = updated
            didSucceed = true
        }
        return didSucceed
    }

    /// Next Discover page for the signed-in viewer (W3-01). Empty if the profile is incomplete.
    func fetchDiscoverFeed(
        extraExcludedUserIds: Set<String> = [],
        cursor: String? = nil,
        ignoreSession: Bool = false
    ) async -> DiscoverFeedPage {
        if cursor == nil, extraExcludedUserIds.isEmpty, !ignoreSession {
            if let discoverWarmTask {
                await discoverWarmTask.value
            }
            if discoverSessionLoaded {
                return DiscoverFeedPage(
                    candidates: discoverSessionQueue,
                    cursor: discoverSessionCursor
                )
            }
        }

        return await fetchDiscoverFeedFromNetwork(
            extraExcludedUserIds: extraExcludedUserIds,
            cursor: cursor
        )
    }

    func rememberDiscoverSession(
        queue: [DiscoverCandidate],
        cursor: String?,
        skipped: [DiscoverCandidate]
    ) {
        discoverSessionQueue = queue
        discoverSessionCursor = cursor
        discoverSessionSkipped = skipped
        discoverSessionLoaded = true
    }

    func clearDiscoverSession() {
        discoverSessionQueue = []
        discoverSessionCursor = nil
        discoverSessionSkipped = []
        discoverSessionLoaded = false
    }

    private static let discoverLaunchTimeoutSeconds: TimeInterval = 6

    private func startDiscoverWarmIfNeeded() {
        guard landsOnDiscoverAtLaunch, discoverWarmTask == nil else { return }
        isDiscoverLaunchReady = false
        didFinishDiscoverWarm = false
        discoverWarmTask = Task { await self.loadDiscoverWarm() }
    }

    /// Holds the NADA splash until the first Discover photo is cached (or we time out).
    private func prepareDiscoverLaunch() async {
        guard landsOnDiscoverAtLaunch else {
            isDiscoverLaunchReady = true
            return
        }

        startDiscoverWarmIfNeeded()

        let deadline = Date().addingTimeInterval(Self.discoverLaunchTimeoutSeconds)
        while !didFinishDiscoverWarm, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        isDiscoverLaunchReady = true
    }

    private var landsOnDiscoverAtLaunch: Bool {
        isAuthenticated
            && hasCompletedFriendsIntent
            && hasCompletedProfileWizard
            && isProfileComplete
            && !isRevisitingBasicProfile
    }

    private func loadDiscoverWarm() async {
        defer { didFinishDiscoverWarm = true }
        let viewerId = currentUser?.id
        let page = await fetchDiscoverFeedFromNetwork(
            extraExcludedUserIds: [],
            cursor: nil
        )
        guard !Task.isCancelled, viewerId != nil, viewerId == currentUser?.id else { return }
        rememberDiscoverSession(queue: page.candidates, cursor: page.cursor, skipped: [])
        guard let photo = page.candidates.first?.photos.first else { return }

        let size = ProfilePreviewPhotoTile.displayPointSize
        _ = await RemoteImageLoader.shared.image(
            urlString: photo.url,
            targetPointSize: size
        )
        if let next = page.candidates.dropFirst().first?.photos.first {
            Task {
                _ = await RemoteImageLoader.shared.image(
                    urlString: next.url,
                    targetPointSize: size
                )
            }
        }
    }

    private func fetchDiscoverFeedFromNetwork(
        extraExcludedUserIds: Set<String>,
        cursor: String?
    ) async -> DiscoverFeedPage {
        guard let user = currentUser else {
            return DiscoverFeedPage(candidates: [], cursor: nil)
        }
        let prefs = currentPreferences ?? UserPreferences.defaults(for: user)
        do {
            return try await discoverService.fetchCandidates(
                viewer: user,
                preferences: prefs,
                extraExcludedUserIds: extraExcludedUserIds,
                cursor: cursor
            )
        } catch {
            errorMessage = Self.discoverFeedErrorMessage(error)
            return DiscoverFeedPage(candidates: [], cursor: nil)
        }
    }

    func recordDiscoverSeen(userId: String) async {
        guard let viewerId = currentUser?.id else { return }
        try? await discoverService.recordSeen(fromUserId: viewerId, toUserId: userId)
    }

    @discardableResult
    func likeDiscoverTarget(
        toUserId: String,
        targetType: DiscoverLike.TargetType,
        targetId: String,
        comment: String? = nil
    ) async -> DiscoverLikeOutcome? {
        guard let fromUserId = currentUser?.id else { return nil }
        var like: DiscoverLike?
        await perform {
            like = try await self.likeService.createLike(
                fromUserId: fromUserId,
                toUserId: toUserId,
                targetType: targetType,
                targetId: targetId,
                comment: comment
            )
        }
        guard let like else { return nil }

        var match: NADAMatch?
        do {
            match = try await ensureMatchIfMutual(fromUserId: fromUserId, toUserId: toUserId)
        } catch {
            // Like already landed. Cloud Function / repairMutualMatches can create the doc.
        }
        if match == nil,
           like.comment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            match = try? await matchService.fetchMatch(
                matchId: NADAMatch.documentId(userId: fromUserId, otherUserId: toUserId),
                viewerId: fromUserId
            )
        }
        if let match, match.isActive {
            await seedOpeningChatMessage(like: like, matchId: match.id)
        }
        await likeService.refreshIncomingLikerCount()
        dropCachedInboxUser(toUserId)
        return DiscoverLikeOutcome(like: like, match: match)
    }

    /// Active matches for the signed-in user, newest first (W4-02). UI is W4-07.
    func fetchMatches(cursor: String? = nil) async throws -> MatchListPage {
        guard let userId = currentUser?.id else { return .empty }
        return try await matchService.fetchMatches(viewerId: userId, cursor: cursor)
    }

    func fetchMatchListItem(matchId: String) async -> MatchListItem? {
        guard let userId = currentUser?.id, !matchId.isEmpty else { return nil }
        return try? await matchService.fetchMatchItem(matchId: matchId, viewerId: userId)
    }

    private func ensureMatchIfMutual(fromUserId: String, toUserId: String) async throws -> NADAMatch? {
        if await matchService.isBlockedPair(userId: fromUserId, otherUserId: toUserId) {
            return nil
        }
        let theyLikedBack = try await likeService.hasLike(fromUserId: toUserId, toUserId: fromUserId)
        guard theyLikedBack else { return nil }
        let match = try await matchService.ensureMatch(userId: fromUserId, otherUserId: toUserId)
        return match.isActive ? match : nil
    }

    /// Hides a mutual for both people (W4-04). Chat hide lands with Week 5.
    @discardableResult
    func unmatch(matchId: String) async -> Bool {
        guard let userId = currentUser?.id else { return false }
        var ok = false
        await perform {
            _ = try await self.matchService.unmatch(viewerId: userId, matchId: matchId)
            ok = true
        }
        return ok
    }

    func sendChatMessage(matchId: String, body: String) async -> ChatMessage? {
        guard let userId = currentUser?.id else { return nil }
        var sent: ChatMessage?
        await perform {
            let match = try await self.matchService.fetchMatch(matchId: matchId, viewerId: userId)
            guard match.isActive else {
                throw AuthError.unknown("This chat is closed.")
            }
            sent = try await self.chatService.sendMessage(
                matchId: matchId,
                senderId: userId,
                body: body
            )
        }
        return sent
    }

    /// Copies this person's like comments into a thread that has no regular messages yet.
    func seedOpeningChatMessages(matchId: String, otherUserId: String) async {
        guard let userId = currentUser?.id else { return }
        let existing = (try? await chatService.fetchMessages(matchId: matchId))?.messages ?? []
        let hasRegularChat = existing.contains { !$0.id.hasPrefix("opening_") }
        guard !hasRegularChat else { return }
        let likes = (try? await likeService.fetchLikes(fromUserId: userId, toUserId: otherUserId)) ?? []
        for like in likes {
            await seedOpeningChatMessage(like: like, matchId: matchId)
        }
    }

    private func seedOpeningChatMessage(like: DiscoverLike, matchId: String) async {
        let body = like.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !body.isEmpty else { return }
        _ = try? await chatService.sendMessage(
            matchId: matchId,
            senderId: like.fromUserId,
            body: String(body.prefix(ChatMessage.maxTextLength)),
            messageId: ChatMessage.openingMessageId(likeId: like.id)
        )
    }

    func fetchChatMessages(matchId: String, cursor: String? = nil) async throws -> ChatMessagePage {
        guard currentUser?.id != nil else { return .empty }
        return try await chatService.fetchMessages(matchId: matchId, cursor: cursor)
    }

    func listenChatMessages(
        matchId: String,
        onChange: @escaping @MainActor ([ChatMessage]) -> Void
    ) -> (() -> Void)? {
        return chatService.listenMessages(matchId: matchId, onChange: onChange)
    }

    func markChatRead(matchId: String, messages: [ChatMessage]) async {
        guard let userId = currentUser?.id else { return }
        try? await chatService.markRead(matchId: matchId, viewerId: userId, messages: messages)
    }

    static func chatErrorMessage(_ error: Error) -> String {
        if let authError = error as? AuthError, let text = authError.errorDescription {
            return text
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("permission") || text.contains("missing or insufficient") {
            return "Can't open chat yet. Publish firebase/firestore.rules (the matches/messages block) in Firebase Console."
        }
        return error.localizedDescription
    }

    /// Fills in matches for pairs that liked each other before W4-02 shipped.
    func repairMutualMatches() async {
        guard let userId = currentUser?.id else { return }
        do {
            async let outgoing = likeService.fetchLikedUserIds(fromUserId: userId)
            async let incoming = likeService.fetchIncomingFromUserIds(toUserId: userId)
            let mutual = try await outgoing.intersection(incoming)
            guard !mutual.isEmpty else { return }
            try await matchService.ensureMatches(viewerId: userId, otherIds: mutual)
        } catch {
            // Index / rules not published yet — like still works; match list stays empty.
        }
    }

    func fetchIncomingLikes(cursor: String? = nil) async -> LikeInboxPage {
        await fetchLikeInbox(direction: .incoming, cursor: cursor)
    }

    func cachedLikeInbox(direction: LikeInboxDirection) -> LikeInboxPage? {
        guard let userId = currentUser?.id else { return nil }
        return likeService.cachedInbox(direction: direction, viewerId: userId)
    }

    /// First page + first avatars, started at sign-in so Likes is warm before the tab opens.
    func warmLikeInbox() async {
        guard currentUser != nil, !didWarmLikeInbox else { return }
        didWarmLikeInbox = true
        let page = await fetchIncomingLikes()
        let thumbSize = RemoteImageView.thumbnailPointSize
        var ordered: [(urlString: String, targetPointSize: CGFloat)] = []
        for item in page.items.prefix(3) {
            if let url = item.otherUser.photoThumbnailURL ?? item.otherUser.photoURL {
                ordered.append((url, thumbSize))
            }
        }
        RemoteImageLoader.shared.prefetchOrdered(ordered)
        if let firstId = page.items.first?.otherUser.id {
            Task { _ = await fetchInboxProfile(userId: firstId) }
        }
        await repairMutualMatches()
    }

    func fetchInboxProfile(userId: String) async -> DiscoverCandidate? {
        guard let viewer = currentUser else { return nil }
        do {
            return try await discoverService.fetchProfile(userId: userId, viewer: viewer)
        } catch {
            return nil
        }
    }

    private func dropCachedInboxUser(_ userId: String) {
        guard let viewerId = currentUser?.id else { return }
        likeService.dropCachedInboxUser(userId: userId, viewerId: viewerId)
        candidateProfileHintRemoved(userId)
    }

    private func candidateProfileHintRemoved(_ userId: String) {
        discoverService.evictProfile(userId: userId)
    }

    private func fetchLikeInbox(direction: LikeInboxDirection, cursor: String?) async -> LikeInboxPage {
        guard let userId = currentUser?.id else { return .empty }
        let photos = cachedPhotosUserId == userId ? cachedPhotos : []
        let answers = cachedAnswersUserId == userId ? cachedAnswers : []
        do {
            let page = try await likeService.fetchInbox(
                direction: direction,
                viewerId: userId,
                cursor: cursor,
                viewerPhotos: photos,
                viewerAnswers: answers
            )
            if errorMessage?.contains("Can't read clicks") == true
                || errorMessage?.contains("Can't load clicks") == true {
                errorMessage = nil
            }
            return page
        } catch {
            errorMessage = Self.likesInboxErrorMessage(error)
            return .empty
        }
    }

    @discardableResult
    func skipDiscoverUser(_ toUserId: String) async -> DiscoverSkip? {
        guard let fromUserId = currentUser?.id else { return nil }
        var result: DiscoverSkip?
        await perform {
            result = try await self.skipService.createSkip(fromUserId: fromUserId, toUserId: toUserId)
        }
        await likeService.refreshIncomingLikerCount()
        dropCachedInboxUser(toUserId)
        return result
    }

    func undoDiscoverSkip(toUserId: String) async -> Bool {
        guard let fromUserId = currentUser?.id else { return false }
        var didSucceed = false
        await perform {
            try await self.skipService.deleteSkip(fromUserId: fromUserId, toUserId: toUserId)
            didSucceed = true
        }
        await likeService.refreshIncomingLikerCount()
        return didSucceed
    }

    func refreshPreferences() async {
        guard let user = currentUser else { return }
        do {
            currentPreferences = try await preferencesService.ensurePreferences(for: user)
        } catch {
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Marks the soft profile setup shell (Photos → Bits → Interests → Preferences) as done.
    @discardableResult
    func completeProfileWizard() async -> Bool {
        guard let userId = currentUser?.id else { return false }

        var didSucceed = false
        await perform {
            let updated = try await self.userService.setProfileWizardCompleted(userId: userId)
            self.currentUser = updated
            self.isRevisitingBasicProfile = false
            didSucceed = true
        }
        return didSucceed
    }

    /// Adds or replaces the primary profile photo (avatar / wizard compatibility).
    @discardableResult
    func uploadProfilePhoto(_ image: UIImage) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        var didSucceed = false
        await perform {
            let list = try await self.photoService.upsertPrimaryPhoto(
                userId: userId,
                image: image,
                legacyPhotoURL: self.currentUser?.photoURL
            )
            self.applyPhotoMutation(list, userId: userId)
            try await self.syncProfileCompleteness(photoCount: list.count)
            didSucceed = true
        }
        return didSucceed
    }

    func fetchPhotos(force: Bool = false) async -> [ProfilePhoto] {
        guard let userId = currentUser?.id else { return [] }
        if !force, didLoadPhotos, cachedPhotosUserId == userId {
            return cachedPhotos
        }
        do {
            let list = try await photoService.fetchPhotos(
                userId: userId,
                legacyPhotoURL: currentUser?.photoURL
            )
            rememberPhotos(list, userId: userId)
            return list
        } catch {
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            return []
        }
    }

    @discardableResult
    func addPhotos(_ images: [UIImage], startingAt index: Int? = nil) async -> [ProfilePhoto]? {
        guard let userId = currentUser?.id, !images.isEmpty else { return nil }
        var result: [ProfilePhoto]?
        await perform {
            let list = try await self.photoService.addPhotos(
                userId: userId,
                images: images,
                startingAt: index
            )
            self.applyPhotoMutation(list, userId: userId)
            try await self.syncProfileCompleteness(photoCount: list.count)
            result = list
        }
        return result
    }

    @discardableResult
    func replacePhoto(id: String, image: UIImage) async -> [ProfilePhoto]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [ProfilePhoto]?
        await perform {
            let list = try await self.photoService.replacePhoto(
                userId: userId,
                photoId: id,
                image: image
            )
            self.applyPhotoMutation(list, userId: userId)
            try await self.syncProfileCompleteness(photoCount: list.count)
            result = list
        }
        return result
    }

    @discardableResult
    func deletePhoto(id: String) async -> [ProfilePhoto]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [ProfilePhoto]?
        await perform {
            let list = try await self.photoService.deletePhoto(userId: userId, photoId: id)
            self.applyPhotoMutation(list, userId: userId)
            try await self.syncProfileCompleteness(photoCount: list.count)
            result = list
        }
        return result
    }

    @discardableResult
    func reorderPhotos(orderedIds: [String]) async -> [ProfilePhoto]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [ProfilePhoto]?
        await perform {
            let list = try await self.photoService.reorder(userId: userId, orderedIds: orderedIds)
            self.applyPhotoMutation(list, userId: userId)
            result = list
        }
        return result
    }

    // MARK: - Bit answers

    func fetchBitAnswers(force: Bool = false) async -> [PromptAnswer] {
        guard let userId = currentUser?.id else { return [] }
        if !force, didLoadAnswers, cachedAnswersUserId == userId {
            return cachedAnswers
        }
        do {
            let list = try await promptService.fetchAnswers(userId: userId)
            rememberAnswers(list, userId: userId)
            return list
        } catch {
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            return []
        }
    }

    @discardableResult
    func saveBitAnswer(promptId: String, answerText: String, sortOrder: Int? = nil) async -> PromptAnswer? {
        guard let userId = currentUser?.id else { return nil }
        var result: PromptAnswer?
        await perform {
            result = try await self.promptService.upsertAnswer(
                userId: userId,
                promptId: promptId,
                answerText: answerText,
                sortOrder: sortOrder
            )
            let answers = try await self.promptService.fetchAnswers(userId: userId)
            self.rememberAnswers(answers, userId: userId)
            try await self.syncProfileCompleteness(answeredBits: answers.count)
        }
        return result
    }

    @discardableResult
    func deleteBitAnswer(promptId: String) async -> [PromptAnswer]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [PromptAnswer]?
        await perform {
            result = try await self.promptService.deleteAnswer(userId: userId, promptId: promptId)
            if let result {
                self.rememberAnswers(result, userId: userId)
            }
            try await self.syncProfileCompleteness(answeredBits: result?.count)
        }
        return result
    }

    @discardableResult
    func reorderBitAnswers(orderedPromptIds: [String]) async -> [PromptAnswer]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [PromptAnswer]?
        await perform {
            result = try await self.promptService.reorderAnswers(
                userId: userId,
                orderedPromptIds: orderedPromptIds
            )
            if let result {
                self.rememberAnswers(result, userId: userId)
            }
        }
        return result
    }

    @discardableResult
    func changeBitAnswerPrompt(
        fromPromptId: String,
        toPromptId: String,
        answerText: String
    ) async -> PromptAnswer? {
        guard let userId = currentUser?.id else { return nil }
        var result: PromptAnswer?
        await perform {
            result = try await self.promptService.changeAnswerPrompt(
                userId: userId,
                fromPromptId: fromPromptId,
                toPromptId: toPromptId,
                answerText: answerText
            )
            let answers = try await self.promptService.fetchAnswers(userId: userId)
            self.rememberAnswers(answers, userId: userId)
        }
        return result
    }

    func signOut() {
        Task {
            await DevicePushRegistrar.shared.clearForSignOut()
            do {
                try authService.signOut()
                currentUser = nil
                currentPreferences = nil
                errorMessage = nil
                isRevisitingBasicProfile = false
                isDiscoverLaunchReady = true
                clearSessionCaches()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// After splash: silently register if already allowed, otherwise maybe show Enable / Skip.
    func shouldOfferPushPrompt() async -> Bool {
        guard currentUser != nil else { return false }
        return await DevicePushRegistrar.shared.shouldShowInAppPrompt()
    }

    /// User tapped Turn on in the in-app card — may show the iOS permission alert once.
    func enablePushFromPrompt() async {
        guard currentUser != nil else { return }
        await DevicePushRegistrar.shared.enableAfterUserConsent()
    }

    func clearError() {
        errorMessage = nil
    }

    func presentError(_ message: String) {
        errorMessage = message
    }

    private func listenForAuthChanges() {
        authStateHandle = authService.onAuthStateChanged { [weak self] user in
            Task { @MainActor in
                await self?.handleAuthUser(user)
            }
        }
    }

    private func handleAuthUser(_ authUser: NADAUser?) async {
        guard let authUser else {
            currentUser = nil
            currentPreferences = nil
            isResolvingProfile = false
            isRevisitingBasicProfile = false
            isDiscoverLaunchReady = true
            DevicePushRegistrar.shared.forgetUser()
            clearSessionCaches()
            return
        }

        if currentUser?.id != authUser.id {
            clearDiscoverSession()
        }

        // Firebase Auth cannot tell us onboarding flags — wait for Firestore before routing.
        isResolvingProfile = true
        defer { isResolvingProfile = false }

        do {
            let profile = try await userService.ensureUserDocument(for: authUser)
            currentUser = profile
            DevicePushRegistrar.shared.setSignedInUser(profile.id)
            startIncomingLikerBadge(userId: profile.id)
            Task { await self.warmLikeInbox() }
        } catch {
            // Keep auth session; surface Firestore issues without blocking sign-in UI.
            currentUser = authUser
            currentPreferences = nil
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            return
        }

        // Preferences must not wipe a valid user profile if rules aren't published yet.
        // Completeness (photos + bits) runs in parallel with prefs hydrate.
        guard let profile = currentUser else { return }
        async let prefsLoad = loadPreferencesResult(for: profile)
        do {
            try await syncProfileCompleteness()
        } catch {
            if errorMessage == nil {
                errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            }
        }
        switch await prefsLoad {
        case .success(let prefs):
            currentPreferences = prefs
        case .failure(let error):
            currentPreferences = nil
            if errorMessage == nil {
                errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Recomputes `users/{uid}.isProfileComplete` from live photos + bits + gender/city.
    private func syncProfileCompleteness(
        photoCount: Int? = nil,
        answeredBits: Int? = nil
    ) async throws {
        guard let user = currentUser else { return }

        let photos: Int
        let bits: Int

        let needsPhotos = photoCount == nil && !(didLoadPhotos && cachedPhotosUserId == user.id)
        let needsAnswers = answeredBits == nil && !(didLoadAnswers && cachedAnswersUserId == user.id)

        if needsPhotos && needsAnswers {
            async let photoList = photoService.fetchPhotos(
                userId: user.id,
                legacyPhotoURL: user.photoURL
            )
            async let answerList = promptService.fetchAnswers(userId: user.id)
            let list = try await photoList
            let answers = try await answerList
            rememberPhotos(list, userId: user.id)
            rememberAnswers(answers, userId: user.id)
            photos = resolvedPhotoCount(list, user: user)
            bits = answers.count
        } else {
            if let photoCount {
                photos = photoCount
            } else if didLoadPhotos, cachedPhotosUserId == user.id {
                photos = resolvedPhotoCount(cachedPhotos, user: user)
            } else {
                let list = try await photoService.fetchPhotos(
                    userId: user.id,
                    legacyPhotoURL: user.photoURL
                )
                rememberPhotos(list, userId: user.id)
                photos = resolvedPhotoCount(list, user: user)
            }

            if let answeredBits {
                bits = answeredBits
            } else if didLoadAnswers, cachedAnswersUserId == user.id {
                bits = cachedAnswers.count
            } else {
                let answers = try await promptService.fetchAnswers(userId: user.id)
                rememberAnswers(answers, userId: user.id)
                bits = answers.count
            }
        }

        let complete = ProfileCompleteness.evaluate(
            user: user,
            photoCount: photos,
            answeredBits: bits
        )
        guard user.isProfileComplete != complete else { return }
        currentUser = try await userService.setProfileComplete(
            userId: user.id,
            isComplete: complete
        )
    }

    private func loadPreferencesResult(for profile: NADAUser) async -> Result<UserPreferences, Error> {
        do {
            return .success(try await preferencesService.ensurePreferences(for: profile))
        } catch {
            return .failure(error)
        }
    }

    private func resolvedPhotoCount(_ list: [ProfilePhoto], user: NADAUser) -> Int {
        if list.isEmpty, let url = user.photoURL, !url.isEmpty { return 1 }
        return list.count
    }

    private static func discoverFeedErrorMessage(_ error: Error) -> String {
        if let authError = error as? AuthError, let text = authError.errorDescription {
            return text
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("permission") || text.contains("missing or insufficient") {
            return "Can't read nearby profiles yet. Publish firebase/firestore.rules in Firebase Console so complete profiles are readable."
        }
        return error.localizedDescription
    }

    private static func likesInboxErrorMessage(_ error: Error) -> String {
        if let authError = error as? AuthError, let text = authError.errorDescription {
            return text
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("requires an index") || text.contains("failed-precondition") {
            return "Can't load clicks yet. Create the Firestore composite index for likes (toUserId/fromUserId + createdAt) from firebase/firestore.indexes.json."
        }
        if text.contains("permission") || text.contains("missing or insufficient") {
            return "Can't read clicks yet. Publish firebase/firestore.rules so you can list clicks sent to or from you."
        }
        return error.localizedDescription
    }

    static func matchesListErrorMessage(_ error: Error) -> String {
        if let authError = error as? AuthError, let text = authError.errorDescription {
            return text
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("requires an index") || text.contains("failed-precondition") {
            return "Can't load mutuals yet. Create the Firestore index for matches (userIds + createdAt) from firebase/firestore.indexes.json."
        }
        if text.contains("permission") || text.contains("missing or insufficient") {
            return "Can't update mutuals yet. Publish firebase/firestore.rules (the matches block, including unmatch) in Firebase Console."
        }
        return error.localizedDescription
    }

    private func rememberPhotos(_ list: [ProfilePhoto], userId: String) {
        cachedPhotos = list
        cachedPhotosUserId = userId
        didLoadPhotos = true
    }

    /// Mirrors a finished photo mutation onto local state. The service has already written the
    /// denormalized `photoURL` / `photoThumbnailURL`, so re-reading the profile and the photo
    /// subcollection would only buy us back what we already know.
    private func applyPhotoMutation(_ list: [ProfilePhoto], userId: String) {
        rememberPhotos(list, userId: userId)
        guard var user = currentUser, user.id == userId else { return }
        let primary = list.first(where: \.isPrimary) ?? list.first
        user.photoURL = primary?.url
        user.photoThumbnailURL = primary?.thumbnailURL
        currentUser = user
    }

    private func rememberAnswers(_ list: [PromptAnswer], userId: String) {
        cachedAnswers = list
        cachedAnswersUserId = userId
        didLoadAnswers = true
    }

    private func startIncomingLikerBadge(userId: String) {
        likeService.startIncomingLikerCountListener(viewerId: userId) { [weak self] count in
            self?.incomingLikerCount = count
        }
    }

    private func clearSessionCaches() {
        likeService.stopIncomingLikerCountListener()
        likeService.resetCaches()
        incomingLikerCount = 0
        didWarmLikeInbox = false
        cachedPhotos = []
        cachedPhotosUserId = nil
        didLoadPhotos = false
        cachedAnswers = []
        cachedAnswersUserId = nil
        didLoadAnswers = false
        discoverWarmTask?.cancel()
        discoverWarmTask = nil
        clearDiscoverSession()
        RemoteImageLoader.shared.invalidateAll()
    }

    private func perform(_ action: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await action()
        } catch AuthError.cancelled {
            // User dismissed Apple sheet — no message
        } catch {
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
        }
    }
}

typealias AuthStateHandle = Any
