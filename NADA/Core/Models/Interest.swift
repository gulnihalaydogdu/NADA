import Foundation

/// Catalog hangout/hobby tag (`interests/{id}`). User-facing copy: **Interests**.
struct Interest: Identifiable, Equatable, Sendable {
    let id: String
    var label: String
    var category: Category
    var isActive: Bool
    var sortOrder: Int
    var locale: String

    enum Category: String, Codable, Sendable, CaseIterable, Identifiable {
        case lifestyle
        case tvMovies = "tvMovies"
        case music
        case games
        case foodDrink = "foodDrink"
        case sportsOutdoors = "sportsOutdoors"
        case creative
        case goingOut = "goingOut"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lifestyle: return "Lifestyle"
            case .tvMovies: return "TV & Movies"
            case .music: return "Music"
            case .games: return "Games"
            case .foodDrink: return "Food & Drink"
            case .sportsOutdoors: return "Sports & Outdoors"
            case .creative: return "Creative"
            case .goingOut: return "Going Out"
            }
        }
    }
}

/// Selected catalog ids on `users/{uid}.interestIds`.
enum InterestSelection {
    static let maxCount = 8

    static func normalized(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where !id.isEmpty {
            if seen.insert(id).inserted {
                result.append(id)
                if result.count == maxCount { break }
            }
        }
        return result
    }

    static func toggling(_ id: String, in current: [String]) -> [String] {
        if let index = current.firstIndex(of: id) {
            var next = current
            next.remove(at: index)
            return next
        }
        guard current.count < maxCount else { return current }
        return current + [id]
    }
}
