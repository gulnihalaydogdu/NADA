import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreChatService {
    static let collectionName = "messages"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    func sendMessage(
        matchId: String,
        senderId: String,
        body: String,
        messageId: String? = nil
    ) async throws -> ChatMessage {
        guard let database else { throw AuthError.notConfigured }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.unknown("Write a message first.")
        }
        guard trimmed.count <= ChatMessage.maxTextLength else {
            throw AuthError.unknown("Keep messages under \(ChatMessage.maxTextLength) characters.")
        }

        let messages = database.collection(FirestoreMatchService.collectionName)
            .document(matchId)
            .collection(Self.collectionName)
        let document = (messageId?.isEmpty == false)
            ? messages.document(messageId!)
            : messages.document()

        let existing = try await document.getDocument()
        if existing.exists, let mapped = Self.mapMessage(matchId: matchId, document: existing) {
            return mapped
        }

        let payload: [String: Any] = [
            "senderId": senderId,
            "body": trimmed,
            "createdAt": FieldValue.serverTimestamp()
        ]
        do {
            try await document.setData(payload)
        } catch {
            let raced = try await document.getDocument()
            if raced.exists, let mapped = Self.mapMessage(matchId: matchId, document: raced) {
                return mapped
            }
            throw error
        }
        return ChatMessage(
            id: document.documentID,
            matchId: matchId,
            senderId: senderId,
            body: trimmed,
            createdAt: Date(),
            readAt: nil
        )
    }

    func fetchMessages(
        matchId: String,
        cursor: String? = nil,
        pageSize: Int = ChatMessage.defaultPageSize
    ) async throws -> ChatMessagePage {
        guard let database else { throw AuthError.notConfigured }
        guard !matchId.isEmpty else { return .empty }

        let collection = database.collection(FirestoreMatchService.collectionName)
            .document(matchId)
            .collection(Self.collectionName)

        var query: Query = collection
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        if let cursor, !cursor.isEmpty {
            let cursorDoc = try await collection.document(cursor).getDocument()
            if cursorDoc.exists {
                query = query.start(afterDocument: cursorDoc)
            }
        }

        let snapshot = try await query.getDocuments()
        let messages = snapshot.documents.compactMap { Self.mapMessage(matchId: matchId, document: $0) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        let cursorOut = snapshot.documents.count < pageSize
            ? nil
            : snapshot.documents.last?.documentID
        return ChatMessagePage(messages: messages, cursor: cursorOut)
    }

    /// Live newest page. Caller must invoke the returned stop handler.
    func listenMessages(
        matchId: String,
        pageSize: Int = ChatMessage.defaultPageSize,
        onChange: @escaping @MainActor ([ChatMessage]) -> Void
    ) -> (() -> Void)? {
        guard let database, !matchId.isEmpty else { return nil }
        let registration = database.collection(FirestoreMatchService.collectionName)
            .document(matchId)
            .collection(Self.collectionName)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let messages = snapshot.documents.compactMap { document in
                    Self.mapMessage(matchId: matchId, document: document)
                }
                .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                Task { @MainActor in
                    onChange(messages)
                }
            }
        return { registration.remove() }
    }

    /// Stamps `readAt` on unread messages the viewer did not send.
    func markRead(
        matchId: String,
        viewerId: String,
        messages: [ChatMessage]
    ) async throws {
        guard let database else { throw AuthError.notConfigured }
        let unread = messages.filter { $0.senderId != viewerId && $0.readAt == nil }
        guard !unread.isEmpty else { return }

        let collection = database.collection(FirestoreMatchService.collectionName)
            .document(matchId)
            .collection(Self.collectionName)
        let batch = database.batch()
        for message in unread {
            batch.updateData(
                ["readAt": FieldValue.serverTimestamp()],
                forDocument: collection.document(message.id)
            )
        }
        try await batch.commit()
    }

    private nonisolated static func mapMessage(
        matchId: String,
        document: DocumentSnapshot
    ) -> ChatMessage? {
        guard let data = document.data(with: .estimate) else { return nil }
        return ChatMessage(
            id: document.documentID,
            matchId: matchId,
            senderId: data["senderId"] as? String ?? "",
            body: data["body"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            readAt: (data["readAt"] as? Timestamp)?.dateValue()
        )
    }
}
