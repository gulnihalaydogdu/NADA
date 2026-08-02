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
    /// Loads the collection and filters in memory so Console type mismatches
    /// (`isActive` as string, `sortOrder` as Int64) still work.
    func fetchActivePrompts(locale: String = "en") async throws -> [Prompt] {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.promptsCollection).getDocuments()

        return snapshot.documents
            .compactMap { doc -> Prompt? in
                mapPrompt(id: doc.documentID, data: doc.data())
            }
            .filter { $0.isActive && $0.locale == locale }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func mapPrompt(id: String, data: [String: Any]) -> Prompt? {
        guard let text = data["text"] as? String, !text.isEmpty else { return nil }

        let categoryRaw = data["category"] as? String ?? Prompt.Category.hangout.rawValue
        let category = Prompt.Category(rawValue: categoryRaw) ?? .hangout
        let locale = data["locale"] as? String ?? "en"

        return Prompt(
            id: id,
            text: text,
            category: category,
            isActive: boolValue(data["isActive"]) ?? false,
            sortOrder: intValue(data["sortOrder"]) ?? 0,
            locale: locale
        )
    }

    private func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}
