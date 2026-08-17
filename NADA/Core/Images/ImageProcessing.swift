import Foundation
import UIKit

/// Hops ImageIO decode / encode off the main thread and caps how many run at once,
/// so scrolling never waits on a decode and several tiles can't spike memory together.
enum ImageProcessing {
    private static let queue = DispatchQueue(
        label: "nada.image-processing",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private static let limiter = ImageWorkLimiter(limit: 3)

    static func decode(data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        await limiter.run {
            await perform { ImageIOCodec.downsample(data: data, maxPixelSize: maxPixelSize) }
        }
    }

    static func decodeFile(at url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        await limiter.run {
            await perform {
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
                return ImageIOCodec.downsample(data: data, maxPixelSize: maxPixelSize)
            }
        }
    }

    /// Display + thumbnail variants for one upload.
    static func encodeVariants(
        image: UIImage
    ) async -> (display: ImageIOCodec.EncodedImage, thumbnail: ImageIOCodec.EncodedImage)? {
        let box = UncheckedBox(image)
        return await limiter.run {
            await perform {
                guard let display = ImageIOCodec.encode(
                    box.value,
                    maxPixelSize: ImageIOCodec.displayMaxPixelSize,
                    quality: ImageIOCodec.displayQuality
                ) else { return nil }

                let thumbnail = ImageIOCodec.encode(
                    box.value,
                    maxPixelSize: ImageIOCodec.thumbnailMaxPixelSize,
                    quality: ImageIOCodec.thumbnailQuality
                ) ?? display

                return (display, thumbnail)
            }
        }
    }

    static func downsampleForEditor(data: Data) async -> UIImage? {
        await decode(data: data, maxPixelSize: ImageIOCodec.pickerMaxPixelSize)
    }

    /// Off-main bitmap rendering (crop export).
    static func render(_ work: @escaping @Sendable () -> UIImage?) async -> UIImage? {
        await limiter.run {
            await perform(work)
        }
    }

    private static func perform<T>(_ work: @escaping () -> T?) async -> T? {
        let workBox = UncheckedBox(work)
        let result: UncheckedBox<T?> = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: UncheckedBox(workBox.value()))
            }
        }
        return result.value
    }
}

/// UIImage / CGImage are safe for our read-only cross-queue use; this quiets Sendable checks.
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

/// Async gate — waits without blocking a thread, unlike DispatchSemaphore.
private actor ImageWorkLimiter {
    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func run<T>(_ work: () async -> T?) async -> T? {
        await acquire()
        defer { release() }
        return await work()
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        // Resumed by `release`, which hands its slot over instead of freeing it.
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    private func release() {
        guard !waiting.isEmpty else {
            active -= 1
            return
        }
        waiting.removeFirst().resume()
    }
}
