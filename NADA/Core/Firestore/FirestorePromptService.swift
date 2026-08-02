import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestorePromptService {
    static let promptsCollection = "prompts"
    /// Stub collection for Week 2 answers API (`promptAnswers/{answerId}`).
    static let promptAnswersCollection = "promptAnswers"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Active catalog bits, ordered by `sortOrder` (English MVP seed).
    /// Filters `locale` in-memory so we avoid a composite index for Week 1.
    func fetchActivePrompts(locale: String = "en") async throws -> [Prompt] {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.promptsCollection)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()

        let prompts = snapshot.documents.compactMap { doc -> Prompt? in
            mapPrompt(id: doc.documentID, data: doc.data())
        }
        .filter { $0.locale == locale }

        return prompts.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func mapPrompt(id: String, data: [String: Any]) -> Prompt? {
        guard let text = data["text"] as? String, !text.isEmpty else { return nil }
        let categoryRaw = data["category"] as? String ?? Prompt.Category.hangout.rawValue
        let category = Prompt.Category(rawValue: categoryRaw) ?? .hangout
        let isActive = data["isActive"] as? Bool ?? false
        let sortOrder = data["sortOrder"] as? Int ?? 0
        let locale = data["locale"] as? String ?? "en"
        return Prompt(
            id: id,
            text: text,
            category: category,
            isActive: isActive,
            sortOrder: sortOrder,
            locale: locale
        )
    }
}
