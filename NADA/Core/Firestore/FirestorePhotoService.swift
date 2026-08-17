import FirebaseCore
import FirebaseFirestore
import Foundation
import UIKit

@MainActor
final class FirestorePhotoService {
    static let maxPhotos = ProfilePhoto.maxCount

    private let storageService: FirebaseStorageService

    init(storageService: FirebaseStorageService? = nil) {
        self.storageService = storageService ?? FirebaseStorageService()
    }

    private var database: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    private func photosCollection(userId: String) throws -> CollectionReference {
        guard let database else { throw AuthError.notConfigured }
        return database.collection("users").document(userId).collection("photos")
    }

    /// Ordered photos for the user. Lazily migrates a lone `photoURL` into the subcollection.
    func fetchPhotos(userId: String, legacyPhotoURL: String?) async throws -> [ProfilePhoto] {
        let collection = try photosCollection(userId: userId)
        let snapshot = try await collection.getDocuments()
        var photos = snapshot.documents.compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        if photos.isEmpty,
           let legacyPhotoURL,
           !legacyPhotoURL.isEmpty {
            let migrated = try await migrateLegacyPhotoURL(
                userId: userId,
                url: legacyPhotoURL,
                collection: collection
            )
            photos = [migrated]
        }

        return photos
    }

    /// Adds a photo (max 6). Optional `at` inserts into that slot (0-based); others shift right.
    /// Slot 0 is always primary and syncs `users/{uid}.photoURL`.
    @discardableResult
    func addPhoto(userId: String, image: UIImage, at insertAt: Int? = nil) async throws -> ProfilePhoto {
        let collection = try photosCollection(userId: userId)
        let snapshot = try await collection.getDocuments()
        let existing = snapshot.documents.compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard existing.count < Self.maxPhotos else {
            throw AuthError.unknown("You can add up to \(Self.maxPhotos) photos.")
        }

        let photoId = UUID().uuidString.lowercased()
        let sortOrder: Int
        if let insertAt {
            sortOrder = min(max(0, insertAt), existing.count)
        } else {
            sortOrder = existing.count
        }
        let makePrimary = sortOrder == 0
        let stored = try await storageService.uploadPhoto(userId: userId, photoId: photoId, image: image)

        let batch = try requireDatabase().batch()

        // Shift photos at / after the insert slot to the right.
        for photo in existing where photo.sortOrder >= sortOrder {
            batch.updateData(
                [
                    "sortOrder": photo.sortOrder + 1,
                    "isPrimary": false
                ],
                forDocument: collection.document(photo.id)
            )
        }

        if makePrimary {
            for photo in existing where photo.isPrimary {
                batch.updateData(["isPrimary": false], forDocument: collection.document(photo.id))
            }
        }

        let payload: [String: Any] = [
            "url": stored.url,
            "thumbnailURL": stored.thumbnailURL,
            "sortOrder": sortOrder,
            "isPrimary": makePrimary,
            "createdAt": FieldValue.serverTimestamp()
        ]
        batch.setData(payload, forDocument: collection.document(photoId))
        try await batch.commit()

        if makePrimary {
            try await syncUserPhotoURL(
                userId: userId,
                url: stored.url,
                thumbnailURL: stored.thumbnailURL
            )
        }

        return ProfilePhoto(
            id: photoId,
            url: stored.url,
            thumbnailURL: stored.thumbnailURL,
            sortOrder: sortOrder,
            isPrimary: makePrimary,
            createdAt: Date()
        )
    }

    /// Crops first, then one write: upload all images, then a single Firestore batch.
    @discardableResult
    func addPhotos(
        userId: String,
        images: [UIImage],
        startingAt insertAt: Int? = nil
    ) async throws -> [ProfilePhoto] {
        guard !images.isEmpty else {
            return try await fetchPhotos(userId: userId, legacyPhotoURL: nil)
        }
        if images.count == 1 {
            return [
                try await addPhoto(userId: userId, image: images[0], at: insertAt)
            ]
        }

        let collection = try photosCollection(userId: userId)
        let snapshot = try await collection.getDocuments()
        let existing = snapshot.documents
            .compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard existing.count + images.count <= Self.maxPhotos else {
            throw AuthError.unknown("You can add up to \(Self.maxPhotos) photos.")
        }

        let firstSort: Int
        if let insertAt {
            firstSort = min(max(0, insertAt), existing.count)
        } else {
            firstSort = existing.count
        }

        struct Placement {
            let id: String
            let sortOrder: Int
            let image: UIImage
        }

        let placements: [Placement] = images.enumerated().map { index, image in
            Placement(
                id: UUID().uuidString.lowercased(),
                sortOrder: index == 0 ? firstSort : existing.count + index,
                image: image
            )
        }

        var urlsByIndex: [Int: StoredPhotoURLs] = [:]
        try await withThrowingTaskGroup(of: (Int, StoredPhotoURLs).self) { group in
            for (index, placement) in placements.enumerated() {
                group.addTask { @MainActor in
                    let urls = try await self.storageService.uploadPhoto(
                        userId: userId,
                        photoId: placement.id,
                        image: placement.image
                    )
                    return (index, urls)
                }
            }
            for try await (index, urls) in group {
                urlsByIndex[index] = urls
            }
        }

        let batch = try requireDatabase().batch()
        if firstSort < existing.count {
            for photo in existing where photo.sortOrder >= firstSort {
                batch.updateData(
                    [
                        "sortOrder": photo.sortOrder + 1,
                        "isPrimary": false
                    ],
                    forDocument: collection.document(photo.id)
                )
            }
        }

        if placements.contains(where: { $0.sortOrder == 0 }) {
            for photo in existing where photo.isPrimary {
                batch.updateData(["isPrimary": false], forDocument: collection.document(photo.id))
            }
        }

        for (index, placement) in placements.enumerated() {
            guard let urls = urlsByIndex[index] else { continue }
            batch.setData(
                [
                    "url": urls.url,
                    "thumbnailURL": urls.thumbnailURL,
                    "sortOrder": placement.sortOrder,
                    "isPrimary": placement.sortOrder == 0,
                    "createdAt": FieldValue.serverTimestamp()
                ],
                forDocument: collection.document(placement.id)
            )
        }
        try await batch.commit()

        if let primaryIndex = placements.firstIndex(where: { $0.sortOrder == 0 }),
           let urls = urlsByIndex[primaryIndex] {
            try await syncUserPhotoURL(
                userId: userId,
                url: urls.url,
                thumbnailURL: urls.thumbnailURL
            )
        }

        return try await fetchPhotos(userId: userId, legacyPhotoURL: nil)
    }

    /// Replaces the primary photo image, or adds one if none exist.
    @discardableResult
    func upsertPrimaryPhoto(
        userId: String,
        image: UIImage,
        legacyPhotoURL: String? = nil
    ) async throws -> ProfilePhoto {
        let photos = try await fetchPhotos(userId: userId, legacyPhotoURL: legacyPhotoURL)
        if let primary = photos.first(where: \.isPrimary) ?? photos.first {
            RemoteImageLoader.shared.invalidate(urlString: primary.url)
            RemoteImageLoader.shared.invalidate(urlString: primary.thumbnailURL)
            try await storageService.deletePhoto(userId: userId, photoId: primary.id)
            let stored = try await storageService.uploadPhoto(
                userId: userId,
                photoId: primary.id,
                image: image
            )
            let collection = try photosCollection(userId: userId)
            try await collection.document(primary.id).updateData([
                "url": stored.url,
                "thumbnailURL": stored.thumbnailURL,
                "isPrimary": true
            ])
            // Ensure only one primary.
            for photo in photos where photo.id != primary.id && photo.isPrimary {
                try await collection.document(photo.id).updateData(["isPrimary": false])
            }
            try await syncUserPhotoURL(
                userId: userId,
                url: stored.url,
                thumbnailURL: stored.thumbnailURL
            )
            return ProfilePhoto(
                id: primary.id,
                url: stored.url,
                thumbnailURL: stored.thumbnailURL,
                sortOrder: primary.sortOrder,
                isPrimary: true,
                createdAt: primary.createdAt
            )
        }
        return try await addPhoto(userId: userId, image: image)
    }

    func deletePhoto(userId: String, photoId: String) async throws -> [ProfilePhoto] {
        let collection = try photosCollection(userId: userId)
        let snapshot = try await collection.getDocuments()
        var photos = snapshot.documents.compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let target = photos.first(where: { $0.id == photoId }) else {
            throw AuthError.unknown("Photo not found.")
        }

        RemoteImageLoader.shared.invalidate(urlString: target.url)
        RemoteImageLoader.shared.invalidate(urlString: target.thumbnailURL)
        try await storageService.deletePhoto(userId: userId, photoId: photoId)
        try await collection.document(photoId).delete()
        photos.removeAll { $0.id == photoId }

        // Re-pack sortOrder 0…n-1 and promote primary if needed.
        if !photos.isEmpty || target.isPrimary {
            let batch = try requireDatabase().batch()
            for (index, photo) in photos.enumerated() {
                batch.updateData(["sortOrder": index], forDocument: collection.document(photo.id))
                photos[index].sortOrder = index
            }

            if target.isPrimary {
                if var next = photos.first {
                    next.isPrimary = true
                    photos[0] = next
                    batch.updateData(["isPrimary": true], forDocument: collection.document(next.id))
                    try await batch.commit()
                    try await syncUserPhotoURL(userId: userId, url: next.url, thumbnailURL: next.thumbnailURL)
                } else {
                    try await syncUserPhotoURL(userId: userId, url: nil, thumbnailURL: nil)
                }
            } else {
                try await batch.commit()
            }
        }

        return photos
    }

    func setPrimary(userId: String, photoId: String) async throws -> [ProfilePhoto] {
        let collection = try photosCollection(userId: userId)
        let snapshot = try await collection.getDocuments()
        var photos = snapshot.documents.compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let targetIndex = photos.firstIndex(where: { $0.id == photoId }) else {
            throw AuthError.unknown("Photo not found.")
        }

        let batch = try requireDatabase().batch()
        for index in photos.indices {
            let isPrimary = index == targetIndex
            photos[index].isPrimary = isPrimary
            batch.updateData(
                ["isPrimary": isPrimary],
                forDocument: collection.document(photos[index].id)
            )
        }
        try await batch.commit()
        try await syncUserPhotoURL(
            userId: userId,
            url: photos[targetIndex].url,
            thumbnailURL: photos[targetIndex].thumbnailURL
        )
        return photos
    }

    /// Reorders photos. Index 0 is always primary and mirrored to `users/{uid}.photoURL`.
    func reorder(userId: String, orderedIds: [String]) async throws -> [ProfilePhoto] {
        let collection = try photosCollection(userId: userId)
        let snapshot = try await collection.getDocuments()
        let byId = Dictionary(
            uniqueKeysWithValues: snapshot.documents.compactMap { doc -> (String, ProfilePhoto)? in
                guard let photo = mapPhoto(id: doc.documentID, data: doc.data()) else { return nil }
                return (photo.id, photo)
            }
        )

        guard orderedIds.count == byId.count,
              Set(orderedIds) == Set(byId.keys) else {
            throw AuthError.unknown("Couldn't reorder photos.")
        }

        let batch = try requireDatabase().batch()
        var updated: [ProfilePhoto] = []
        for (index, id) in orderedIds.enumerated() {
            guard var photo = byId[id] else { continue }
            photo.sortOrder = index
            photo.isPrimary = index == 0
            batch.updateData(
                [
                    "sortOrder": index,
                    "isPrimary": index == 0
                ],
                forDocument: collection.document(id)
            )
            updated.append(photo)
        }
        try await batch.commit()

        let sorted = updated.sorted { $0.sortOrder < $1.sortOrder }
        if let primary = sorted.first {
            try await syncUserPhotoURL(
                userId: userId,
                url: primary.url,
                thumbnailURL: primary.thumbnailURL
            )
        }
        return sorted
    }

    // MARK: - Private

    private func migrateLegacyPhotoURL(
        userId: String,
        url: String,
        collection: CollectionReference
    ) async throws -> ProfilePhoto {
        let photoId = "legacy-primary"
        let payload: [String: Any] = [
            "url": url,
            "sortOrder": 0,
            "isPrimary": true,
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await collection.document(photoId).setData(payload)
        try await syncUserPhotoURL(userId: userId, url: url, thumbnailURL: nil)
        return ProfilePhoto(
            id: photoId,
            url: url,
            thumbnailURL: nil,
            sortOrder: 0,
            isPrimary: true,
            createdAt: Date()
        )
    }

    private func syncUserPhotoURL(userId: String, url: String?, thumbnailURL: String?) async throws {
        let database = try requireDatabase()
        let document = database.collection("users").document(userId)
        var fields: [String: Any] = [:]
        if let url {
            fields["photoURL"] = url
        } else {
            fields["photoURL"] = FieldValue.delete()
        }
        if let thumbnailURL {
            fields["photoThumbnailURL"] = thumbnailURL
        } else {
            fields["photoThumbnailURL"] = FieldValue.delete()
        }
        try await document.updateData(fields)
    }

    private func requireDatabase() throws -> Firestore {
        guard let database else { throw AuthError.notConfigured }
        return database
    }

    private func mapPhoto(id: String, data: [String: Any]) -> ProfilePhoto? {
        guard let url = data["url"] as? String, !url.isEmpty else { return nil }
        let sortOrder: Int
        if let int = data["sortOrder"] as? Int {
            sortOrder = int
        } else if let number = data["sortOrder"] as? NSNumber {
            sortOrder = number.intValue
        } else {
            sortOrder = 0
        }
        let isPrimary = (data["isPrimary"] as? Bool)
            ?? (data["isPrimary"] as? NSNumber)?.boolValue
            ?? false
        var createdAt: Date?
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        }
        return ProfilePhoto(
            id: id,
            url: url,
            thumbnailURL: data["thumbnailURL"] as? String,
            sortOrder: sortOrder,
            isPrimary: isPrimary,
            createdAt: createdAt
        )
    }
}
