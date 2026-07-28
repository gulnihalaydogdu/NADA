import Foundation
import Observation

@Observable
@MainActor
final class AuthManager {
    private(set) var currentUser: NADAUser?
    private(set) var isBootstrapped = false
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

    /// Call once at launch — configures Firebase and restores session without blocking first frame.
    func bootstrap() {
        guard !isBootstrapped else { return }
        authService.configureFirebaseIfNeeded()
        currentUser = authService.cachedUser
        listenForAuthChanges()
        isBootstrapped = true
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
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
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
