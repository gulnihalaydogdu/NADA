import Foundation

/// Catalog question (API/internal name). User-facing copy: **Bits**.
struct Prompt: Identifiable, Equatable, Sendable {
    let id: String
    var text: String
    var category: Category
    var isActive: Bool
    var sortOrder: Int
    var locale: String

    enum Category: String, Codable, Sendable, CaseIterable {
        case hangout
        case hobby
        case gamesMemes = "gamesMemes"
        case newInTown = "newInTown"
        case energy
    }
}

/// Stub for Week 2 write path — collection exists in rules/docs only for now.
struct PromptAnswer: Identifiable, Equatable, Sendable {
    let id: String
    var userId: String
    var promptId: String
    var answerText: String
    var sortOrder: Int
}
