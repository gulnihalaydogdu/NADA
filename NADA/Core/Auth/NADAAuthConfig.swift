import Foundation

enum NADAAuthConfig {
    /// Sign in with Apple requires a **paid** Apple Developer Program account.
    /// Personal (free) teams cannot use the capability — Xcode will fail provisioning.
    /// Set to `true` after enrolling: add `com.apple.developer.applesignin` to NADA.entitlements
    /// and enable Apple in Firebase Authentication.
    static let isAppleSignInEnabled = false
}
