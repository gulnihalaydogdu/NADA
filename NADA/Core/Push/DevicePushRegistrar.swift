import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

/// Requests notification permission, registers for APNs, and stores the FCM token (W3-09).
@MainActor
final class DevicePushRegistrar {
    static let shared = DevicePushRegistrar()

    private static let promptShownCountKey = "nada.pushPrompt.shownCount"
    private static let promptFinishedKey = "nada.pushPrompt.finished"
    private static let maxInAppPrompts = 2

    private let tokens = FirestoreDeviceTokenService()
    private var userId: String?
    private var fcmToken: String?
    private var lastUploadedToken: String?
    private var didEvaluatePromptThisSession = false

    private init() {}

    func setSignedInUser(_ userId: String?) {
        self.userId = userId
        lastUploadedToken = nil
        Task { await upsertIfPossible() }
    }

    /// Silent: register only if iOS already allowed notifications. Never shows a system dialog.
    func registerIfAlreadyAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        await registerForRemoteNotifications()
    }

    /// User tapped Turn on — this is the only path that may show the iOS permission alert.
    func enableAfterUserConsent() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .denied:
            Self.markPromptFinished()
            return
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            Self.markPromptFinished()
            guard granted else { return }
        default:
            Self.markPromptFinished()
        }

        await registerForRemoteNotifications()
    }

    /// Once per launch, after splash: whether to show NADA’s Enable / Skip card.
    /// At most twice per install. Skip is remembered; we never nag after that.
    func shouldShowInAppPrompt() async -> Bool {
        guard !didEvaluatePromptThisSession else { return false }
        didEvaluatePromptThisSession = true

        await registerIfAlreadyAuthorized()

        guard !Self.isPromptFinished else { return false }
        guard Self.promptShownCount < Self.maxInAppPrompts else {
            Self.markPromptFinished()
            return false
        }

        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .notDetermined:
            Self.incrementPromptShownCount()
            return true
        case .denied:
            Self.markPromptFinished()
            return false
        default:
            return false
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
        PushRouter.shared.clear()
    }

    func forgetUser() {
        userId = nil
        lastUploadedToken = nil
        PushRouter.shared.clear()
    }

    private func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
        if let token = try? await Messaging.messaging().token() {
            await handleFCMToken(token)
        }
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

    private static var promptShownCount: Int {
        UserDefaults.standard.integer(forKey: promptShownCountKey)
    }

    private static var isPromptFinished: Bool {
        UserDefaults.standard.bool(forKey: promptFinishedKey)
    }

    private static func incrementPromptShownCount() {
        UserDefaults.standard.set(promptShownCount + 1, forKey: promptShownCountKey)
    }

    private static func markPromptFinished() {
        UserDefaults.standard.set(true, forKey: promptFinishedKey)
    }
}
