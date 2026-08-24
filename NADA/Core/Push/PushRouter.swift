import Foundation

/// Where a like / match push should land (W4-08). Chat threads are Week 5.
enum PushRoute: Equatable {
    case likes
    case matches

    static func fromNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> PushRoute? {
        switch normalizedType(in: userInfo) {
        case "like", "click":
            return .likes
        case "match":
            return .matches
        default:
            return nil
        }
    }

    private static func normalizedType(in userInfo: [AnyHashable: Any]) -> String? {
        if let type = stringValue(userInfo["type"]) ?? stringValue(userInfo["gcm.notification.type"]) {
            return type
        }
        if let nested = userInfo["data"] as? [AnyHashable: Any] {
            return stringValue(nested["type"])
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}

/// Holds a tap until MainTabView can switch Clicks / Mutuals (cold start, splash, setup).
@MainActor
@Observable
final class PushRouter {
    static let shared = PushRouter()

    private(set) var pending: PushRoute?

    private init() {}

    func handle(_ route: PushRoute) {
        pending = route
    }

    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        guard let route = PushRoute.fromNotificationUserInfo(userInfo) else { return }
        handle(route)
    }

    func consumeIfPresent() -> PushRoute? {
        let route = pending
        pending = nil
        return route
    }

    func clear() {
        pending = nil
    }
}
