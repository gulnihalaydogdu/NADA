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
    /// Returns the full ordered list, rebuilt from the writes we just made.
    @discardableResult
    func addPhoto(userId: String, image: UIImage, at insertAt: Int? = nil) async throws -> [ProfilePhoto] {
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

        var updated = existing
        for index in updated.indices where updated[index].sortOrder >= sortOrder {
            updated[index].sortOrder += 1
            updated[index].isPrimary = false
        }
        updated.append(
            ProfilePhoto(
                id: photoId,
                url: stored.url,
                thumbnailURL: stored.thumbnailURL,
                sortOrder: sortOrder,
                isPrimary: makePrimary,
                createdAt: Date()
            )
        )
        return updated.sorted { $0.sortOrder < $1.sortOrder }
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
            return try await addPhoto(userId: userId, image: images[0], at: insertAt)
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

        var updated = existing
        if firstSort < existing.count {
            for index in updated.indices where updated[index].sortOrder >= firstSort {
                updated[index].sortOrder += 1
                updated[index].isPrimary = false
            }
        }
        if placements.contains(where: { $0.sortOrder == 0 }) {
            for index in updated.indices {
                updated[index].isPrimary = false
            }
        }
        for (index, placement) in placements.enumerated() {
            guard let urls = urlsByIndex[index] else { continue }
            updated.append(
                ProfilePhoto(
                    id: placement.id,
                    url: urls.url,
                    thumbnailURL: urls.thumbnailURL,
                    sortOrder: placement.sortOrder,
                    isPrimary: placement.sortOrder == 0,
                    createdAt: Date()
                )
            )
        }
        return updated.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Replaces the primary photo image, or adds one if none exist.
    @discardableResult
    func upsertPrimaryPhoto(
        userId: String,
        image: UIImage,
        legacyPhotoURL: String? = nil
    ) async throws -> [ProfilePhoto] {
        var photos = try await fetchPhotos(userId: userId, legacyPhotoURL: legacyPhotoURL)
        guard let primaryIndex = photos.firstIndex(where: \.isPrimary) ?? photos.indices.first else {
            return try await addPhoto(userId: userId, image: image)
        }
        let primary = photos[primaryIndex]

        let stored = try await storageService.uploadPhoto(
            userId: userId,
            photoId: primary.id,
            image: image
        )
        RemoteImageLoader.shared.invalidate(urlString: primary.url)
        RemoteImageLoader.shared.invalidate(urlString: primary.thumbnailURL)

        let collection = try photosCollection(userId: userId)
        let batch = try requireDatabase().batch()
        batch.updateData(
            [
                "url": stored.url,
                "thumbnailURL": stored.thumbnailURL,
                "isPrimary": true
            ],
            forDocument: collection.document(primary.id)
        )
        // Ensure only one primary.
        for photo in photos where photo.id != primary.id && photo.isPrimary {
            batch.updateData(["isPrimary": false], forDocument: collection.document(photo.id))
        }
        try await batch.commit()

        try await syncUserPhotoURL(
            userId: userId,
            url: stored.url,
            thumbnailURL: stored.thumbnailURL
        )
        cleanUpSupersededObjects(userId: userId, photoId: primary.id, keeping: stored)

        for index in photos.indices {
            photos[index].isPrimary = index == primaryIndex
        }
        photos[primaryIndex].url = stored.url
        photos[primaryIndex].thumbnailURL = stored.thumbnailURL
        return photos
    }

    /// Replaces the image for an existing slot without changing order or primary.
    @discardableResult
    func replacePhoto(userId: String, photoId: String, image: UIImage) async throws -> [ProfilePhoto] {
        let collection = try photosCollection(userId: userId)
        let snapshot = try await collection.getDocuments()
        var photos = snapshot.documents.compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let targetIndex = photos.firstIndex(where: { $0.id == photoId }) else {
            throw AuthError.unknown("Photo not found.")
        }
        let target = photos[targetIndex]

        // Upload first — the new object overwrites the old one under the same name, so the
        // user never waits on delete round-trips before their photo starts going up.
        let stored = try await storageService.uploadPhoto(
            userId: userId,
            photoId: photoId,
            image: image
        )
        RemoteImageLoader.shared.invalidate(urlString: target.url)
        RemoteImageLoader.shared.invalidate(urlString: target.thumbnailURL)

        try await collection.document(photoId).updateData([
            "url": stored.url,
            "thumbnailURL": stored.thumbnailURL
        ])

        if target.isPrimary {
            try await syncUserPhotoURL(
                userId: userId,
                url: stored.url,
                thumbnailURL: stored.thumbnailURL
            )
        }
        cleanUpSupersededObjects(userId: userId, photoId: photoId, keeping: stored)

        photos[targetIndex].url = stored.url
        photos[targetIndex].thumbnailURL = stored.thumbnailURL
        return photos
    }

    func deletePhoto(userId: String, photoId: String) async throws -> [ProfilePhoto] {
        let collection = try photosCollection(userId: userId)
        let snapshot = try await collection.getDocuments()
        var photos = snapshot.documents.compactMap { mapPhoto(id: $0.documentID, data: $0.data()) }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let target = photos.first(where: { $0.id == photoId }) else {
            throw AuthError.unknown("Photo not found.")
        }

        photos.removeAll { $0.id == photoId }

        // Removal, re-packed sortOrder 0…n-1, and the promoted primary ride in one commit.
        let batch = try requireDatabase().batch()
        batch.deleteDocument(collection.document(photoId))
        for (index, photo) in photos.enumerated() {
            batch.updateData(["sortOrder": index], forDocument: collection.document(photo.id))
            photos[index].sortOrder = index
        }
        if target.isPrimary, !photos.isEmpty {
            photos[0].isPrimary = true
            batch.updateData(["isPrimary": true], forDocument: collection.document(photos[0].id))
        }
        try await batch.commit()

        if target.isPrimary {
            try await syncUserPhotoURL(
                userId: userId,
                url: photos.first?.url,
                thumbnailURL: photos.first?.thumbnailURL
            )
        }

        RemoteImageLoader.shared.invalidate(urlString: target.url)
        RemoteImageLoader.shared.invalidate(urlString: target.thumbnailURL)
        // Storage objects are unreferenced now; reclaiming them shouldn't hold up the grid.
        Task { [storageService] in
            try? await storageService.deletePhoto(userId: userId, photoId: photoId)
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

    /// A re-upload only orphans the previous codec's files. Nothing points at them anymore,
    /// so they are reclaimed off the critical path.
    private func cleanUpSupersededObjects(
        userId: String,
        photoId: String,
        keeping stored: StoredPhotoURLs
    ) {
        Task { [storageService] in
            await storageService.deleteSupersededObjects(
                userId: userId,
                photoId: photoId,
                keeping: stored
            )
        }
    }

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
