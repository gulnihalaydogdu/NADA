import Foundation

enum AuthError: LocalizedError, Equatable {
    case notConfigured
    case invalidEmail
    case weakPassword
    case wrongPassword
    case userNotFound
    case emailAlreadyInUse
    case appleSignInFailed
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase is not configured. Add GoogleService-Info.plist."
        case .invalidEmail:
            return "Enter a valid email address."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .wrongPassword:
            return "Incorrect email or password."
        case .userNotFound:
            return "No account found with this email."
        case .emailAlreadyInUse:
            return "This email is already in use."
        case .appleSignInFailed:
            return "Sign in with Apple failed."
        case .cancelled:
            return nil
        case .unknown(let message):
            return message
        }
    }
}
