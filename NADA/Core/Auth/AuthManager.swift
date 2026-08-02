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
    private var authStateHandle: AuthStateHandle?

    init() {
        self.authService = FirebaseAuthService()
        self.userService = FirestoreUserService()
        self.storageService = FirebaseStorageService()
    }

    var hasCompletedFriendsIntent: Bool {
        currentUser?.friendsIntentCompleted == true
    }

    var hasCompletedBasicProfile: Bool {
        currentUser?.hasCompletedBasicProfile == true
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

    /// Uploads a profile photo to Storage and stores `photoURL` on the user doc.
    @discardableResult
    func uploadProfilePhoto(_ image: UIImage) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        var didSucceed = false
        await perform {
            let url = try await self.storageService.uploadProfilePhoto(userId: userId, image: image)
            let updated = try await self.userService.updateProfile(
                userId: userId,
                displayName: nil,
                gender: nil,
                city: nil,
                locale: nil,
                photoURL: url
            )
            self.currentUser = updated
            didSucceed = true
        }
        return didSucceed
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
