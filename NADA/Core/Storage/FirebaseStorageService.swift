import FirebaseCore
import FirebaseStorage
import Foundation
import UIKit

struct StoredPhotoURLs: Sendable {
    var url: String
    var thumbnailURL: String
    /// Written file extensions. Re-uploading a slot with a different codec leaves the
    /// previous objects behind, and they are only identifiable by name.
    var fileExtension: String
    var thumbnailFileExtension: String
}

@MainActor
final class FirebaseStorageService {
    /// `users/{uid}/photos/{photoId}.{ext}`
    static func photoPath(userId: String, photoId: String, fileExtension: String) -> String {
        "users/\(userId)/photos/\(photoId).\(fileExtension)"
    }

    static func thumbnailPath(userId: String, photoId: String, fileExtension: String) -> String {
        "users/\(userId)/photos/\(photoId)_thumb.\(fileExtension)"
    }

    private var storage: Storage? {
        guard FirebaseApp.app() != nil else { return nil }
        return Storage.storage()
    }

    /// Encodes a display + thumbnail pair (WebP when possible) and uploads both.
    /// Encoding runs off the main thread so the crop sheet stays responsive.
    func uploadPhoto(userId: String, photoId: String, image: UIImage) async throws -> StoredPhotoURLs {
        guard let storage else { throw AuthError.notConfigured }

        guard let variants = await ImageProcessing.encodeVariants(image: image) else {
            throw AuthError.unknown("Couldn't prepare the photo for upload.")
        }
        let display = variants.display
        let thumbnail = variants.thumbnail

        // Both objects go up at once; uploading them back to back doubled the round-trips.
        async let displayURL = put(
            data: display.data,
            contentType: display.contentType,
            path: Self.photoPath(userId: userId, photoId: photoId, fileExtension: display.fileExtension),
            storage: storage
        )
        async let thumbURL = put(
            data: thumbnail.data,
            contentType: thumbnail.contentType,
            path: Self.thumbnailPath(userId: userId, photoId: photoId, fileExtension: thumbnail.fileExtension),
            storage: storage
        )

        return StoredPhotoURLs(
            url: try await displayURL,
            thumbnailURL: try await thumbURL,
            fileExtension: display.fileExtension,
            thumbnailFileExtension: thumbnail.fileExtension
        )
    }

    /// Deletes display + thumbnail objects. Missing objects are ignored.
    func deletePhoto(userId: String, photoId: String) async throws {
        guard let storage else { throw AuthError.notConfigured }
        for name in objectNames(photoId: photoId) {
            let reference = storage.reference().child("users/\(userId)/photos/\(name)")
            try await deleteIgnoringMissing(reference)
        }
    }

    /// Drops the objects a re-upload orphaned — the previous codec's files. The freshly
    /// written names are skipped, so this is safe to run after the new URLs are live.
    func deleteSupersededObjects(userId: String, photoId: String, keeping stored: StoredPhotoURLs) async {
        guard let storage else { return }
        let survivors: Set<String> = [
            "\(photoId).\(stored.fileExtension)",
            "\(photoId)_thumb.\(stored.thumbnailFileExtension)"
        ]
        for name in objectNames(photoId: photoId) where !survivors.contains(name) {
            let reference = storage.reference().child("users/\(userId)/photos/\(name)")
            try? await deleteIgnoringMissing(reference)
        }
    }

    /// Every object name a photo slot may occupy across codecs.
    private func objectNames(photoId: String) -> [String] {
        var names = [
            "\(photoId).jpg",
            "\(photoId).webp",
            "\(photoId)_thumb.jpg",
            "\(photoId)_thumb.webp"
        ]
        // The W1 single-photo object only belongs to the migrated primary slot; removing it
        // for any other id would delete a live photo.
        if photoId == "profile" || photoId == "legacy-primary" {
            names.append("profile.jpg")
        }
        return names
    }

    private func put(
        data: Data,
        contentType: String,
        path: String,
        storage: Storage
    ) async throws -> String {
        let reference = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        // New object names are unique per photo id; HTTP caches can keep them.
        metadata.cacheControl = "public, max-age=31536000, immutable"
        _ = try await reference.putDataAsync(data, metadata: metadata)
        let url = try await reference.downloadURL()
        return url.absoluteString
    }

    private func deleteIgnoringMissing(_ reference: StorageReference) async throws {
        do {
            try await reference.delete()
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("does not exist") || message.contains("object not found") {
                return
            }
            let nsError = error as NSError
            if nsError.domain.contains("StorageError") || nsError.domain.contains("FIRStorage") {
                if nsError.code == 404 || nsError.code == -13010 {
                    return
                }
            }
            throw error
        }
    }
}
