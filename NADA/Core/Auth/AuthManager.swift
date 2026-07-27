import Foundation
import Observation

@Observable
@MainActor
final class AuthManager {
    private(set) var currentUser: NADAUser?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var hasCompletedFriendsIntent: Bool {
        get { UserDefaults.standard.bool(forKey: Self.friendsIntentKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.friendsIntentKey) }
    }

    private static let friendsIntentKey = "nada.friendsIntentCompleted"
    private let authService: FirebaseAuthService
    private var authStateHandle: AuthStateHandle?

    init(authService: FirebaseAuthService = FirebaseAuthService()) {
        self.authService = authService
        listenForAuthChanges()
    }

    var isAuthenticated: Bool { currentUser != nil }

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

    func signOut() {
        do {
            try authService.signOut()
            currentUser = nil
            hasCompletedFriendsIntent = false
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
                self?.currentUser = user
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
