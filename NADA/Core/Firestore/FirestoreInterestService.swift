import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreInterestService {
    static let interestsCollection = "interests"

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    /// Active catalog interests, ordered by `sortOrder` (English MVP seed).
    private static var catalogCache: [String: [Interest]] = [:]

    func fetchActiveInterests(locale: String = "en") async throws -> [Interest] {
        if let cached = Self.catalogCache[locale], !cached.isEmpty {
            return cached
        }
        guard let database else { throw AuthError.notConfigured }

        let snapshot = try await database.collection(Self.interestsCollection).getDocuments()

        let interests = snapshot.documents
            .compactMap { doc -> Interest? in
                mapInterest(id: doc.documentID, data: doc.data())
            }
            .filter { $0.isActive && $0.locale == locale }
            .sorted { $0.sortOrder < $1.sortOrder }

        Self.catalogCache[locale] = interests
        return interests
    }

    private func mapInterest(id: String, data: [String: Any]) -> Interest? {
        guard let label = data["label"] as? String, !label.isEmpty else { return nil }

        let categoryRaw = data["category"] as? String ?? Interest.Category.lifestyle.rawValue
        let category = Interest.Category(rawValue: categoryRaw) ?? .lifestyle
        let locale = data["locale"] as? String ?? "en"

        return Interest(
            id: id,
            label: label,
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
