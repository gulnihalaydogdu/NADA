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

    /// Resolved once — `CGImageDestination` only writes WebP on OS versions that ship the encoder.
    private static let supportsWebPEncoding: Bool = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(UTType.webP.identifier)
    }()

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

    /// Redraws straight into the target bitmap. Going through JPEG bytes would cost a
    /// full-size encode plus decode for what is only a resize.
    static func downsample(image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > 0 else { return image }
        if longest <= maxPixelSize, image.imageOrientation == .up {
            return image
        }

        let ratio = min(maxPixelSize / longest, 1)
        let target = CGSize(
            width: max((pixelWidth * ratio).rounded(), 1),
            height: max((pixelHeight * ratio).rounded(), 1)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Prefer WebP when ImageIO can encode it; JPEG otherwise.
    static func encode(
        _ image: UIImage,
        maxPixelSize: CGFloat,
        quality: CGFloat
    ) -> EncodedImage? {
        encodePrepared(downsample(image: image, maxPixelSize: maxPixelSize), quality: quality)
    }

    /// Encodes an image that is already at its final pixel size.
    /// Only one codec runs — trying both and keeping the smaller doubled upload latency.
    static func encodePrepared(_ image: UIImage, quality: CGFloat) -> EncodedImage? {
        guard let cgImage = image.cgImage else { return nil }

        if supportsWebPEncoding,
           let webp = encode(cgImage, type: .webP, quality: quality),
           !webp.isEmpty {
            return EncodedImage(data: webp, contentType: "image/webp", fileExtension: "webp")
        }
        guard let jpeg = encode(cgImage, type: .jpeg, quality: quality), !jpeg.isEmpty else {
            return nil
        }
        return EncodedImage(data: jpeg, contentType: "image/jpeg", fileExtension: "jpg")
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
