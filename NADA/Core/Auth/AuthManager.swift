import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class AuthManager {
    private(set) var currentUser: NADAUser?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// True while a signed-in user's Firestore profile is still being read.
    private(set) var isResolvingProfile = false

    /// False until the initial session has been fully resolved on launch.
    private(set) var isSessionResolved = false

    private let authService: FirebaseAuthService
    private let userService: FirestoreUserService
    private let storageService: FirebaseStorageService
    private let photoService: FirestorePhotoService
    private let promptService: FirestorePromptService
    private var authStateHandle: AuthStateHandle?

    init() {
        self.authService = FirebaseAuthService()
        self.userService = FirestoreUserService()
        self.storageService = FirebaseStorageService()
        self.photoService = FirestorePhotoService(storageService: storageService)
        self.promptService = FirestorePromptService()
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
            }
        }
    }

    /// Updates display name, gender, and city on Firestore. Returns `true` on success.
    @discardableResult
    func updateBasicProfile(displayName: String, gender: ProfileGender, city: String) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedCity.isEmpty else {
            errorMessage = "Name and city are required."
            return false
        }

        var didSucceed = false
        await perform {
            let updated = try await self.userService.updateProfile(
                userId: userId,
                displayName: trimmedName,
                gender: gender.rawValue,
                city: trimmedCity,
                locale: nil
            )
            self.currentUser = updated
            didSucceed = true
        }
        return didSucceed
    }

    /// Marks the soft profile setup shell (Photos → Bits → Preferences) as done.
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
            didSucceed = true
        }
        return didSucceed
    }

    func fetchPhotos() async -> [ProfilePhoto] {
        guard let userId = currentUser?.id else { return [] }
        do {
            return try await photoService.fetchPhotos(
                userId: userId,
                legacyPhotoURL: currentUser?.photoURL
            )
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
        }
        return result
    }

    // MARK: - Bit answers

    func fetchBitAnswers() async -> [PromptAnswer] {
        guard let userId = currentUser?.id else { return [] }
        do {
            return try await promptService.fetchAnswers(userId: userId)
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
        }
        return result
    }

    @discardableResult
    func deleteBitAnswer(promptId: String) async -> [PromptAnswer]? {
        guard let userId = currentUser?.id else { return nil }
        var result: [PromptAnswer]?
        await perform {
            result = try await self.promptService.deleteAnswer(userId: userId, promptId: promptId)
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
        }
        return result
    }

    func signOut() {
        do {
            try authService.signOut()
            currentUser = nil
            errorMessage = nil
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
            isResolvingProfile = false
            return
        }

        // Firebase Auth cannot tell us `friendsIntentCompleted`, so publishing the
        // user before Firestore answers would briefly route to the intent screen.
        isResolvingProfile = true
        defer { isResolvingProfile = false }

        do {
            currentUser = try await userService.ensureUserDocument(for: authUser)
        } catch {
            // Keep auth session; surface Firestore issues without blocking sign-in UI.
            currentUser = authUser
            if isBusy {
                errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            }
        }
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
