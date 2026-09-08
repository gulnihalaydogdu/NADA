import Foundation

/// Where a like / match / chat push should land (W4-08 / W5-02 / W5-07).
enum PushRoute: Equatable {
    case likes
    case matches
    case chat(matchId: String)

    static func fromNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> PushRoute? {
        switch normalizedType(in: userInfo) {
        case "like", "click":
            return .likes
        case "match":
            return .matches
        case "message", "chat":
            if let matchId = matchId(in: userInfo), !matchId.isEmpty {
                return .chat(matchId: matchId)
            }
            return .matches
        default:
            return nil
        }
    }

    private static func normalizedType(in userInfo: [AnyHashable: Any]) -> String? {
        if let type = stringValue(userInfo["type"]) ?? stringValue(userInfo["gcm.notification.type"]) {
            return type.lowercased()
        }
        if let nested = userInfo["data"] as? [AnyHashable: Any] {
            return stringValue(nested["type"])?.lowercased()
        }
        return nil
    }

    private static func matchId(in userInfo: [AnyHashable: Any]) -> String? {
        if let matchId = stringValue(userInfo["matchId"]) {
            return matchId
        }
        if let nested = userInfo["data"] as? [AnyHashable: Any] {
            return stringValue(nested["matchId"])
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// Match id for a chat push; Mutuals consumes this after the tab switch.
    private(set) var chatMatchId: String?

    private init() {}

    func handle(_ route: PushRoute) {
        pending = route
        if case .chat(let matchId) = route {
            chatMatchId = matchId
        }
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

    func consumeChatMatchId() -> String? {
        let matchId = chatMatchId
        chatMatchId = nil
        return matchId
    }

    func clear() {
        pending = nil
        chatMatchId = nil
    }
}
