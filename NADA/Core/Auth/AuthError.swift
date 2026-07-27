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
            return "Firebase yapılandırılmamış. GoogleService-Info.plist dosyasını ekleyin."
        case .invalidEmail:
            return "Geçerli bir e-posta adresi girin."
        case .weakPassword:
            return "Şifre en az 6 karakter olmalı."
        case .wrongPassword:
            return "E-posta veya şifre hatalı."
        case .userNotFound:
            return "Bu e-posta ile kayıtlı hesap bulunamadı."
        case .emailAlreadyInUse:
            return "Bu e-posta zaten kullanımda."
        case .appleSignInFailed:
            return "Apple ile giriş başarısız oldu."
        case .cancelled:
            return nil
        case .unknown(let message):
            return message
        }
    }
}
