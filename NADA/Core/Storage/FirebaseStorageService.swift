import FirebaseCore
import FirebaseStorage
import Foundation
import UIKit

@MainActor
final class FirebaseStorageService {
    /// `users/{uid}/photos/profile.jpg`
    static func profilePhotoPath(userId: String) -> String {
        "users/\(userId)/photos/profile.jpg"
    }

    private var storage: Storage? {
        guard FirebaseApp.app() != nil else { return nil }
        return Storage.storage()
    }

    /// Compresses and uploads a profile JPEG; returns a download URL string.
    func uploadProfilePhoto(userId: String, image: UIImage) async throws -> String {
        guard let storage else { throw AuthError.notConfigured }
        guard let data = Self.jpegData(from: image) else {
            throw AuthError.unknown("Couldn't prepare the photo for upload.")
        }

        let reference = storage.reference().child(Self.profilePhotoPath(userId: userId))
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await reference.putDataAsync(data, metadata: metadata)
        let url = try await reference.downloadURL()
        return url.absoluteString
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
