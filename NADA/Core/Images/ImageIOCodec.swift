import ImageIO
import UniformTypeIdentifiers
import UIKit

/// ImageIO helpers — downsample at decode and encode WebP/JPEG without pulling a third-party SDK.
enum ImageIOCodec {
    /// Longest edge for library imports before the crop editor (enough for a 1200px export).
    static let pickerMaxPixelSize: CGFloat = 2048
    /// Stored display photo (Preview / Discover).
    static let displayMaxPixelSize: CGFloat = 1200
    /// Avatar + photo-grid tiles.
    static let thumbnailMaxPixelSize: CGFloat = 360

    static let displayQuality: CGFloat = 0.82
    static let thumbnailQuality: CGFloat = 0.72

    struct EncodedImage: Sendable {
        var data: Data
        var contentType: String
        var fileExtension: String
    }

    /// Decode only the pixels needed for `maxPixelSize` (device pixels). Avoids full-resolution bitmaps.
    static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let capped = max(maxPixelSize, 1)
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(capped.rounded(.up))
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func downsample(image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        if longest <= maxPixelSize, image.imageOrientation == .up {
            return image
        }
        if let data = image.jpegData(compressionQuality: 0.95),
           let downsampled = downsample(data: data, maxPixelSize: maxPixelSize) {
            return downsampled
        }
        return image
    }

    /// Prefer WebP when ImageIO can encode it; JPEG otherwise.
    static func encode(
        _ image: UIImage,
        maxPixelSize: CGFloat,
        quality: CGFloat
    ) -> EncodedImage? {
        let prepared = downsample(image: image, maxPixelSize: maxPixelSize)
        guard let cgImage = prepared.cgImage else { return nil }

        let webp = encode(cgImage, type: .webP, quality: quality)
        let jpeg = encode(cgImage, type: .jpeg, quality: quality)

        if let webp, !webp.isEmpty, jpeg == nil || webp.count <= jpeg!.count {
            return EncodedImage(data: webp, contentType: "image/webp", fileExtension: "webp")
        }
        if let jpeg, !jpeg.isEmpty {
            return EncodedImage(data: jpeg, contentType: "image/jpeg", fileExtension: "jpg")
        }
        return nil
    }

    private static func encode(_ image: CGImage, type: UTType, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
