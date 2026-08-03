import Foundation

/// Catalog question (API/internal name). User-facing copy: **Bits**.
struct Prompt: Identifiable, Equatable, Sendable {
    let id: String
    var text: String
    var category: Category
    var isActive: Bool
    var sortOrder: Int
    var locale: String

    enum Category: String, Codable, Sendable, CaseIterable, Identifiable {
        case hangout
        case hobby
        case gamesMemes = "gamesMemes"
        case newInTown = "newInTown"
        case energy

        var id: String { rawValue }

        /// Friend-coded labels — no dating language.
        var title: String {
            switch self {
            case .hangout: return "Hangouts"
            case .hobby: return "Hobbies"
            case .gamesMemes: return "Games & memes"
            case .newInTown: return "New in town"
            case .energy: return "Energy"
            }
        }
    }
}

/// A user's answer to one catalog Bit (`promptAnswers/{userId}_{promptId}`).
struct PromptAnswer: Identifiable, Equatable, Sendable {
    static let maxCount = 3
    static let maxTextLength = 150

    let id: String
    var userId: String
    var promptId: String
    var answerText: String
    var sortOrder: Int
}
