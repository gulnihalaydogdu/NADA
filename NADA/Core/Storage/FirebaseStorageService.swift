import FirebaseCore
import FirebaseStorage
import Foundation
import UIKit

struct StoredPhotoURLs: Sendable {
    var url: String
    var thumbnailURL: String
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

    /// Legacy W1 single-photo path.
    static func profilePhotoPath(userId: String) -> String {
        "users/\(userId)/photos/profile.jpg"
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

        let displayURL = try await put(
            data: display.data,
            contentType: display.contentType,
            path: Self.photoPath(userId: userId, photoId: photoId, fileExtension: display.fileExtension),
            storage: storage
        )
        let thumbURL = try await put(
            data: thumbnail.data,
            contentType: thumbnail.contentType,
            path: Self.thumbnailPath(userId: userId, photoId: photoId, fileExtension: thumbnail.fileExtension),
            storage: storage
        )

        return StoredPhotoURLs(url: displayURL, thumbnailURL: thumbURL)
    }

    /// Deletes display + thumbnail objects. Missing objects are ignored.
    func deletePhoto(userId: String, photoId: String) async throws {
        guard let storage else { throw AuthError.notConfigured }
        let names = [
            "\(photoId).jpg",
            "\(photoId).webp",
            "\(photoId)_thumb.jpg",
            "\(photoId)_thumb.webp",
            "profile.jpg"
        ]
        for name in names {
            let reference = storage.reference().child("users/\(userId)/photos/\(name)")
            try await deleteIgnoringMissing(reference)
        }
    }

    /// W1 compatibility: uploads as primary-style `profile.jpg`.
    func uploadProfilePhoto(userId: String, image: UIImage) async throws -> StoredPhotoURLs {
        try await uploadPhoto(userId: userId, photoId: "profile", image: image)
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
