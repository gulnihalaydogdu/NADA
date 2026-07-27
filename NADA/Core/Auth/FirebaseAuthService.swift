import Foundation
import FirebaseAuth
import FirebaseCore

@MainActor
final class FirebaseAuthService {
    private var isConfigured: Bool { FirebaseApp.app() != nil }

    init() {
        configureFirebaseIfNeeded()
    }

    func configureFirebaseIfNeeded() {
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return
        }
        FirebaseApp.configure()
    }

    var isReady: Bool { isConfigured }

    func onAuthStateChanged(_ handler: @escaping (NADAUser?) -> Void) -> AuthStateHandle {
        guard isConfigured else {
            handler(nil)
            return ()
        }
        return Auth.auth().addStateDidChangeListener { _, firebaseUser in
            Task { @MainActor in
                handler(Self.mapUser(firebaseUser))
            }
        }
    }

    func signUp(email: String, password: String) async throws {
        try ensureReady()
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        guard password.count >= 6 else { throw AuthError.weakPassword }
        do {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    func signIn(email: String, password: String) async throws {
        try ensureReady()
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws {
        try ensureReady()
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: fullName
        )
        do {
            let result = try await Auth.auth().signIn(with: credential)
            if let fullName, result.user.displayName?.isEmpty != false {
                let displayName = PersonNameComponentsFormatter.localizedString(from: fullName, style: .default, options: [])
                if !displayName.isEmpty {
                    let changeRequest = result.user.createProfileChangeRequest()
                    changeRequest.displayName = displayName
                    try await changeRequest.commitChanges()
                }
            }
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    func signOut() throws {
        try ensureReady()
        try Auth.auth().signOut()
    }

    private func ensureReady() throws {
        guard isConfigured else { throw AuthError.notConfigured }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private func mapFirebaseError(_ error: NSError) -> AuthError {
        guard let code = AuthErrorCode(rawValue: error.code) else {
            return .unknown(error.localizedDescription)
        }
        switch code {
        case .invalidEmail: return .invalidEmail
        case .wrongPassword: return .wrongPassword
        case .userNotFound: return .userNotFound
        case .emailAlreadyInUse: return .emailAlreadyInUse
        case .weakPassword: return .weakPassword
        default: return .unknown(error.localizedDescription)
        }
    }

    private static func mapUser(_ firebaseUser: FirebaseAuth.User?) -> NADAUser? {
        guard let firebaseUser else { return nil }
        return NADAUser(
            id: firebaseUser.uid,
            displayName: firebaseUser.displayName,
            email: firebaseUser.email,
            gender: nil,
            city: nil,
            intent: .friendsOnly,
            locale: Locale.current.identifier,
            createdAt: firebaseUser.metadata.creationDate
        )
    }
}
