import Foundation
import Observation

@Observable
@MainActor
final class AuthManager {
    private(set) var currentUser: NADAUser?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let authService: FirebaseAuthService
    private let userService: FirestoreUserService
    private var authStateHandle: AuthStateHandle?

    init() {
        self.authService = FirebaseAuthService()
        self.userService = FirestoreUserService()
    }

    init(authService: FirebaseAuthService, userService: FirestoreUserService) {
        self.authService = authService
        self.userService = userService
    }

    var hasCompletedFriendsIntent: Bool {
        currentUser?.friendsIntentCompleted == true
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
        }
    }

    var isAuthenticated: Bool { currentUser != nil }
    var isFirebaseReady: Bool { authService.isReady }

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
            return
        }

        currentUser = authUser

        do {
            currentUser = try await userService.ensureUserDocument(for: authUser)
        } catch {
            // Keep auth session; surface Firestore issues without blocking sign-in UI.
            currentUser = authUser
            if isLoading {
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
