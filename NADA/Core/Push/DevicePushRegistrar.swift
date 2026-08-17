import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

/// Requests notification permission, registers for APNs, and stores the FCM token (W3-09).
@MainActor
final class DevicePushRegistrar {
    static let shared = DevicePushRegistrar()

    private let tokens = FirestoreDeviceTokenService()
    private var userId: String?
    private var fcmToken: String?
    private var lastUploadedToken: String?

    private init() {}

    func setSignedInUser(_ userId: String?) {
        self.userId = userId
        lastUploadedToken = nil
        Task { await upsertIfPossible() }
    }

    /// System permission + APNs registration. Safe to call on every Main tab appear.
    func requestPermissionAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .denied:
            return
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            guard granted else { return }
        default:
            break
        }

        UIApplication.shared.registerForRemoteNotifications()

        if let token = try? await Messaging.messaging().token() {
            await handleFCMToken(token)
        }
    }

    func handleFCMToken(_ token: String?) async {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return }

        if let previous = fcmToken, previous != trimmed, let userId {
            try? await tokens.deleteToken(userId: userId, fcmToken: previous)
        }

        fcmToken = trimmed
        await upsertIfPossible()
    }

    /// Deletes this device’s token while the session is still authenticated.
    func clearForSignOut() async {
        if let userId, let fcmToken {
            try? await tokens.deleteToken(userId: userId, fcmToken: fcmToken)
        }
        userId = nil
        lastUploadedToken = nil
    }

    func forgetUser() {
        userId = nil
        lastUploadedToken = nil
    }

    private func upsertIfPossible() async {
        guard let userId, let fcmToken else { return }
        guard lastUploadedToken != fcmToken else { return }
        do {
            try await tokens.upsertToken(userId: userId, fcmToken: fcmToken)
            lastUploadedToken = fcmToken
        } catch {
            // Missing capability / unpublished rules / simulator — don't block the app.
        }
    }
}
