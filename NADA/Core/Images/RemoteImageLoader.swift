import Foundation
import UIKit

/// Downloads, downsamples, and caches remote photos. In-flight requests are coalesced.
@MainActor
final class RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let cache = RemoteImageCache.shared
    private let session: URLSession
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 80 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }

    func image(urlString: String?, targetPointSize: CGFloat) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString), !urlString.isEmpty else {
            return nil
        }

        let scale = UITraitCollection.current.displayScale
        let maxPixelSize = min(
            max(targetPointSize * max(scale, 1), 1),
            ImageIOCodec.displayMaxPixelSize
        )
        let key = "\(urlString)#\(Int(maxPixelSize.rounded()))"

        if let cached = cache.memoryImage(urlString: urlString, maxPixelSize: maxPixelSize) {
            return cached
        }

        if let existing = inflight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [weak self] in
            await self?.load(url: url, urlString: urlString, maxPixelSize: maxPixelSize)
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        return image
    }

    func prefetch(urlStrings: [String], targetPointSize: CGFloat) {
        let prefix = Array(urlStrings.prefix(3))
        Task { [weak self] in
            for urlString in prefix {
                _ = await self?.image(urlString: urlString, targetPointSize: targetPointSize)
            }
        }
    }

    func invalidate(urlString: String?) {
        guard let urlString, !urlString.isEmpty else { return }
        cache.remove(urlString: urlString)
    }

    func invalidateAll() {
        cache.removeAll()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
    }

    private func load(url: URL, urlString: String, maxPixelSize: CGFloat) async -> UIImage? {
        if let disk = cache.diskData(urlString: urlString),
           let image = ImageIOCodec.downsample(data: disk, maxPixelSize: maxPixelSize) {
            cache.storeMemory(image, urlString: urlString, maxPixelSize: maxPixelSize)
            return image
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await session.data(for: request)
            guard !data.isEmpty else { return nil }
            cache.storeDisk(data, urlString: urlString)
            guard let image = ImageIOCodec.downsample(data: data, maxPixelSize: maxPixelSize) else {
                return nil
            }
            cache.storeMemory(image, urlString: urlString, maxPixelSize: maxPixelSize)
            return image
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }
}
