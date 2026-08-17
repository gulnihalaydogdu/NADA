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

    /// True while a signed-in user's Firestore profile is still being read.
    private(set) var isResolvingProfile = false

    /// False until the initial session has been fully resolved on launch.
    private(set) var isSessionResolved = false

    private let authService: FirebaseAuthService
    private let userService: FirestoreUserService
    private let preferencesService: FirestorePreferencesService
    private let storageService: FirebaseStorageService
    private let photoService: FirestorePhotoService
    private let promptService: FirestorePromptService
    private let discoverService: FirestoreDiscoverService
    private let likeService: FirestoreLikeService
    private let skipService: FirestoreSkipService
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

            listenForAuthChanges()
            isSessionResolved = true
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
            let updated = try await self.userService.setFriendsIntentCompleted(userId: userId)
            self.currentUser = updated
        }
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
        cursor: String? = nil
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
    ) async -> DiscoverLike? {
        guard let fromUserId = currentUser?.id else { return nil }
        var result: DiscoverLike?
        await perform {
            result = try await self.likeService.createLike(
                fromUserId: fromUserId,
                toUserId: toUserId,
                targetType: targetType,
                targetId: targetId,
                comment: comment
            )
        }
        return result
    }

    @discardableResult
    func skipDiscoverUser(_ toUserId: String) async -> DiscoverSkip? {
        guard let fromUserId = currentUser?.id else { return nil }
        var result: DiscoverSkip?
        await perform {
            result = try await self.skipService.createSkip(fromUserId: fromUserId, toUserId: toUserId)
        }
        return result
    }

    func undoDiscoverSkip(toUserId: String) async -> Bool {
        guard let fromUserId = currentUser?.id else { return false }
        var didSucceed = false
        await perform {
            try await self.skipService.deleteSkip(fromUserId: fromUserId, toUserId: toUserId)
            didSucceed = true
        }
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
            _ = try await self.photoService.upsertPrimaryPhoto(
                userId: userId,
                image: image,
                legacyPhotoURL: self.currentUser?.photoURL
            )
            if let profile = try await self.userService.fetchUser(id: userId) {
                self.currentUser = profile
            }
            let list = try await self.photoService.fetchPhotos(
                userId: userId,
                legacyPhotoURL: self.currentUser?.photoURL
            )
            self.rememberPhotos(list, userId: userId)
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
    func addPhoto(_ image: UIImage, at index: Int? = nil) async -> ProfilePhoto? {
        guard let userId = currentUser?.id else { return nil }
        var result: ProfilePhoto?
        await perform {
            result = try await self.photoService.addPhoto(userId: userId, image: image, at: index)
            if let profile = try await self.userService.fetchUser(id: userId) {
                self.currentUser = profile
            }
            let list = try await self.photoService.fetchPhotos(
                userId: userId,
                legacyPhotoURL: self.currentUser?.photoURL
            )
            self.rememberPhotos(list, userId: userId)
            try await self.syncProfileCompleteness(photoCount: list.count)
        }
        return result
    }

    @discardableResult
    func deletePhoto(id: String) async -> [ProfilePhoto]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [ProfilePhoto]?
        await perform {
            result = try await self.photoService.deletePhoto(userId: userId, photoId: id)
            if let profile = try await self.userService.fetchUser(id: userId) {
                self.currentUser = profile
            }
            if let result {
                self.rememberPhotos(result, userId: userId)
            }
            try await self.syncProfileCompleteness(photoCount: result?.count)
        }
        return result
    }

    @discardableResult
    func setPrimaryPhoto(id: String) async -> [ProfilePhoto]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [ProfilePhoto]?
        await perform {
            result = try await self.photoService.setPrimary(userId: userId, photoId: id)
            if let profile = try await self.userService.fetchUser(id: userId) {
                self.currentUser = profile
            }
            if let result {
                self.rememberPhotos(result, userId: userId)
            }
        }
        return result
    }

    @discardableResult
    func reorderPhotos(orderedIds: [String]) async -> [ProfilePhoto]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [ProfilePhoto]?
        await perform {
            result = try await self.photoService.reorder(userId: userId, orderedIds: orderedIds)
            // Reorder may change primary → refresh denormalized photoURL on the profile.
            if let profile = try await self.userService.fetchUser(id: userId) {
                self.currentUser = profile
            }
            if let result {
                self.rememberPhotos(result, userId: userId)
            }
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
        do {
            try authService.signOut()
            currentUser = nil
            currentPreferences = nil
            errorMessage = nil
            clearSessionCaches()
        } catch {
            errorMessage = error.localizedDescription
        }
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
            clearSessionCaches()
            return
        }

        // Firebase Auth cannot tell us onboarding flags — wait for Firestore before routing.
        isResolvingProfile = true
        defer { isResolvingProfile = false }

        do {
            let profile = try await userService.ensureUserDocument(for: authUser)
            currentUser = profile
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

    private func rememberPhotos(_ list: [ProfilePhoto], userId: String) {
        cachedPhotos = list
        cachedPhotosUserId = userId
        didLoadPhotos = true
    }

    private func rememberAnswers(_ list: [PromptAnswer], userId: String) {
        cachedAnswers = list
        cachedAnswersUserId = userId
        didLoadAnswers = true
    }

    private func clearSessionCaches() {
        cachedPhotos = []
        cachedPhotosUserId = nil
        didLoadPhotos = false
        cachedAnswers = []
        cachedAnswersUserId = nil
        didLoadAnswers = false
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
