import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestorePromptService {
    static let promptsCollection = "prompts"
    static let promptAnswersCollection = "promptAnswers"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    // MARK: - Catalog

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

    // MARK: - Answers

    static func answerDocumentId(userId: String, promptId: String) -> String {
        "\(userId)_\(promptId)"
    }

    func fetchAnswers(userId: String) async throws -> [PromptAnswer] {
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.promptAnswersCollection)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        return snapshot.documents
            .compactMap { mapAnswer(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Creates or updates an answer. Enforces max count, text length, and one answer per prompt.
    @discardableResult
    func upsertAnswer(
        userId: String,
        promptId: String,
        answerText: String,
        sortOrder: Int? = nil
    ) async throws -> PromptAnswer {
        guard let database else { throw AuthError.notConfigured }

        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.unknown("Write a short answer first.")
        }
        guard trimmed.count <= PromptAnswer.maxTextLength else {
            throw AuthError.unknown("Keep answers under \(PromptAnswer.maxTextLength) characters.")
        }
        guard !promptId.isEmpty else {
            throw AuthError.unknown("Pick a Bit first.")
        }

        let existing = try await fetchAnswers(userId: userId)
        let docId = Self.answerDocumentId(userId: userId, promptId: promptId)
        let alreadyHasThisPrompt = existing.contains { $0.promptId == promptId }

        if !alreadyHasThisPrompt, existing.count >= PromptAnswer.maxCount {
            throw AuthError.unknown("You can answer up to \(PromptAnswer.maxCount) Bits.")
        }

        let order = sortOrder
            ?? existing.first(where: { $0.promptId == promptId })?.sortOrder
            ?? existing.count

        let payload: [String: Any] = [
            "userId": userId,
            "promptId": promptId,
            "answerText": trimmed,
            "sortOrder": order
        ]

        try await database.collection(Self.promptAnswersCollection)
            .document(docId)
            .setData(payload, merge: true)

        return PromptAnswer(
            id: docId,
            userId: userId,
            promptId: promptId,
            answerText: trimmed,
            sortOrder: order
        )
    }

    func deleteAnswer(userId: String, promptId: String) async throws -> [PromptAnswer] {
        guard let database else { throw AuthError.notConfigured }

        let docId = Self.answerDocumentId(userId: userId, promptId: promptId)
        try await database.collection(Self.promptAnswersCollection).document(docId).delete()

        var remaining = try await fetchAnswers(userId: userId)
        // Re-pack sortOrder 0…n-1
        let batch = database.batch()
        for index in remaining.indices {
            remaining[index].sortOrder = index
            batch.updateData(
                ["sortOrder": index],
                forDocument: database.collection(Self.promptAnswersCollection).document(remaining[index].id)
            )
        }
        if !remaining.isEmpty {
            try await batch.commit()
        }
        return remaining
    }

    /// Reorders answers. `orderedPromptIds` must match the user's current answer set.
    func reorderAnswers(userId: String, orderedPromptIds: [String]) async throws -> [PromptAnswer] {
        guard let database else { throw AuthError.notConfigured }

        let existing = try await fetchAnswers(userId: userId)
        let byPrompt = Dictionary(uniqueKeysWithValues: existing.map { ($0.promptId, $0) })

        guard orderedPromptIds.count == byPrompt.count,
              Set(orderedPromptIds) == Set(byPrompt.keys) else {
            throw AuthError.unknown("Couldn't reorder Bits.")
        }

        let batch = database.batch()
        var updated: [PromptAnswer] = []
        for (index, promptId) in orderedPromptIds.enumerated() {
            guard var answer = byPrompt[promptId] else { continue }
            answer.sortOrder = index
            batch.updateData(
                ["sortOrder": index],
                forDocument: database.collection(Self.promptAnswersCollection).document(answer.id)
            )
            updated.append(answer)
        }
        try await batch.commit()
        return updated.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Moves an answer to a different catalog prompt (new doc id), keeping sort order.
    @discardableResult
    func changeAnswerPrompt(
        userId: String,
        fromPromptId: String,
        toPromptId: String,
        answerText: String
    ) async throws -> PromptAnswer {
        guard fromPromptId != toPromptId else {
            return try await upsertAnswer(
                userId: userId,
                promptId: toPromptId,
                answerText: answerText
            )
        }

        let existing = try await fetchAnswers(userId: userId)
        guard let current = existing.first(where: { $0.promptId == fromPromptId }) else {
            throw AuthError.unknown("Bit answer not found.")
        }
        if existing.contains(where: { $0.promptId == toPromptId }) {
            throw AuthError.unknown("You already answered that Bit.")
        }

        let saved = try await upsertAnswer(
            userId: userId,
            promptId: toPromptId,
            answerText: answerText,
            sortOrder: current.sortOrder
        )

        guard let database else { throw AuthError.notConfigured }
        let oldDocId = Self.answerDocumentId(userId: userId, promptId: fromPromptId)
        try await database.collection(Self.promptAnswersCollection).document(oldDocId).delete()

        return saved
    }

    // MARK: - Mapping

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

    private func mapAnswer(id: String, data: [String: Any]) -> PromptAnswer? {
        guard let userId = data["userId"] as? String, !userId.isEmpty,
              let promptId = data["promptId"] as? String, !promptId.isEmpty,
              let answerText = data["answerText"] as? String else { return nil }

        return PromptAnswer(
            id: id,
            userId: userId,
            promptId: promptId,
            answerText: answerText,
            sortOrder: intValue(data["sortOrder"]) ?? 0
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
