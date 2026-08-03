import FirebaseCore
import FirebaseStorage
import Foundation
import UIKit

@MainActor
final class FirebaseStorageService {
    /// `users/{uid}/photos/{photoId}.jpg`
    static func photoPath(userId: String, photoId: String) -> String {
        "users/\(userId)/photos/\(photoId).jpg"
    }

    /// Legacy W1 single-photo path.
    static func profilePhotoPath(userId: String) -> String {
        "users/\(userId)/photos/profile.jpg"
    }

    private var storage: Storage? {
        guard FirebaseApp.app() != nil else { return nil }
        return Storage.storage()
    }

    /// Compresses and uploads a JPEG for the given photo id; returns a download URL string.
    func uploadPhoto(userId: String, photoId: String, image: UIImage) async throws -> String {
        guard let storage else { throw AuthError.notConfigured }
        guard let data = Self.jpegData(from: image) else {
            throw AuthError.unknown("Couldn't prepare the photo for upload.")
        }

        let reference = storage.reference().child(Self.photoPath(userId: userId, photoId: photoId))
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await reference.putDataAsync(data, metadata: metadata)
        let url = try await reference.downloadURL()
        return url.absoluteString
    }

    /// Deletes a photo object. Missing objects are ignored.
    func deletePhoto(userId: String, photoId: String) async throws {
        guard let storage else { throw AuthError.notConfigured }
        let reference = storage.reference().child(Self.photoPath(userId: userId, photoId: photoId))
        do {
            try await reference.delete()
        } catch {
            // Legacy or already-deleted objects should not block Firestore cleanup.
            let message = error.localizedDescription.lowercased()
            if message.contains("does not exist") || message.contains("object not found") {
                return
            }
            let nsError = error as NSError
            if nsError.domain.contains("StorageError") || nsError.domain.contains("FIRStorage") {
                // objectNotFound == 404-style codes vary by SDK version
                if nsError.code == 404 || nsError.code == -13010 {
                    return
                }
            }
            throw error
        }
    }

    /// W1 compatibility: uploads as primary-style `profile.jpg`.
    func uploadProfilePhoto(userId: String, image: UIImage) async throws -> String {
        try await uploadPhoto(userId: userId, photoId: "profile", image: image)
    }

    private static func jpegData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1200
        let size = image.size
        let longest = max(size.width, size.height)
        let scaled: UIImage
        if longest > maxDimension {
            let scale = maxDimension / longest
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaled = image
        }
        return scaled.jpegData(compressionQuality: 0.82)
    }
}
