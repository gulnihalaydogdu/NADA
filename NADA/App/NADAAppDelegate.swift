import FirebaseMessaging
import UIKit
import UserNotifications

/// APNs + FCM glue (W3-05 / W3-09) and tap routing to Clicks / Mutuals (W4-08).
final class NADAAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        NADATheme.applyTabBadgeAppearance()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simulator and Personal Team builds have no APNs — registration is optional.
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            await DevicePushRegistrar.shared.handleFCMToken(fcmToken)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let tappedBanner = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let route = tappedBanner
            ? PushRoute.fromNotificationUserInfo(response.notification.request.content.userInfo)
            : nil
        Task { @MainActor in
            if let route {
                PushRouter.shared.handle(route)
            }
            completionHandler()
        }
    }
}
