import Foundation
import UIKit

/// Downloads, downsamples, and caches remote photos.
/// In-flight requests are coalesced; decode happens off the main thread.
/// A request is cancelled once every view waiting on it goes away — unless a
/// prefetch still needs the same decode (Discover next-card warming).
@MainActor
final class RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let cache = RemoteImageCache.shared
    private let session: URLSession
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var waiters: [String: Int] = [:]
    private var prefetchHolds: [String: Int] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 80 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    /// Cached image without touching the network — lets a view paint on its first frame.
    func cachedImage(urlString: String?, targetPointSize: CGFloat) -> UIImage? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return cache.memoryImage(
            urlString: urlString,
            maxPixelSize: pixelSize(for: targetPointSize)
        )
    }

    func image(urlString: String?, targetPointSize: CGFloat) async -> UIImage? {
        await image(urlString: urlString, targetPointSize: targetPointSize, isPrefetch: false)
    }

    /// Warms images in **priority order**: the first URL is awaited so it wins
    /// connections and decode slots; the rest start in parallel after that.
    func prefetchOrdered(_ items: [(urlString: String, targetPointSize: CGFloat)]) {
        let filtered = items.filter { !$0.urlString.isEmpty }
        guard !filtered.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let first = filtered[0]
            _ = await self.image(
                urlString: first.urlString,
                targetPointSize: first.targetPointSize,
                isPrefetch: true
            )
            guard filtered.count > 1 else { return }
            await withTaskGroup(of: Void.self) { group in
                for item in filtered.dropFirst() {
                    group.addTask { @MainActor in
                        _ = await self.image(
                            urlString: item.urlString,
                            targetPointSize: item.targetPointSize,
                            isPrefetch: true
                        )
                    }
                }
            }
        }
    }

    /// Warms nearby photos in parallel so the next Discover card can paint immediately.
    func prefetch(urlStrings: [String], targetPointSize: CGFloat, limit: Int = 3) {
        let prefix = Array(urlStrings.prefix(limit).filter { !$0.isEmpty })
        guard !prefix.isEmpty else { return }
        prefetchOrdered(prefix.map { (urlString: $0, targetPointSize: targetPointSize) })
    }

    func invalidate(urlString: String?) {
        guard let urlString, !urlString.isEmpty else { return }
        cache.remove(urlString: urlString)
    }

    func invalidateAll() {
        cache.removeAll()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
        waiters.removeAll()
        prefetchHolds.removeAll()
    }

    private func image(
        urlString: String?,
        targetPointSize: CGFloat,
        isPrefetch: Bool
    ) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString), !urlString.isEmpty else {
            return nil
        }

        let maxPixelSize = pixelSize(for: targetPointSize)
        if let cached = cache.memoryImage(urlString: urlString, maxPixelSize: maxPixelSize) {
            return cached
        }

        let key = "\(urlString)#\(Int(maxPixelSize.rounded()))"
        let task = inflight[key] ?? makeTask(
            key: key,
            url: url,
            urlString: urlString,
            maxPixelSize: maxPixelSize
        )

        if isPrefetch {
            prefetchHolds[key, default: 0] += 1
            let image = await task.value
            releasePrefetch(key: key)
            return image
        }

        waiters[key, default: 0] += 1
        let ticket = WaiterTicket()

        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor [weak self] in
                guard ticket.claim() else { return }
                self?.dropWaiter(key: key, cancelWhenLast: true)
            }
        }

        if ticket.claim() {
            dropWaiter(key: key, cancelWhenLast: false)
        }
        return image
    }

    private func pixelSize(for targetPointSize: CGFloat) -> CGFloat {
        let scale = max(UITraitCollection.current.displayScale, 1)
        return min(max(targetPointSize * scale, 1), ImageIOCodec.displayMaxPixelSize)
    }

    private func makeTask(
        key: String,
        url: URL,
        urlString: String,
        maxPixelSize: CGFloat
    ) -> Task<UIImage?, Never> {
        let task = Task<UIImage?, Never> { [weak self] in
            let image = await self?.load(url: url, urlString: urlString, maxPixelSize: maxPixelSize)
            await MainActor.run {
                self?.finishInflight(key: key)
            }
            return image
        }
        inflight[key] = task
        return task
    }

    private func finishInflight(key: String) {
        if (waiters[key] ?? 0) == 0, (prefetchHolds[key] ?? 0) == 0 {
            inflight[key] = nil
        }
    }

    /// Cancels the download when the last interested view disappears — never
    /// while a Discover prefetch still holds the same key.
    private func dropWaiter(key: String, cancelWhenLast: Bool) {
        guard let count = waiters[key] else { return }
        let remaining = count - 1
        guard remaining <= 0 else {
            waiters[key] = remaining
            return
        }

        waiters[key] = nil
        let held = prefetchHolds[key] ?? 0
        if cancelWhenLast, held == 0 {
            inflight[key]?.cancel()
            inflight[key] = nil
        } else if held == 0 {
            inflight[key] = nil
        }
    }

    private func releasePrefetch(key: String) {
        guard let count = prefetchHolds[key] else { return }
        let remaining = count - 1
        if remaining <= 0 {
            prefetchHolds[key] = nil
            if (waiters[key] ?? 0) == 0 {
                inflight[key] = nil
            }
        } else {
            prefetchHolds[key] = remaining
        }
    }

    private func load(url: URL, urlString: String, maxPixelSize: CGFloat) async -> UIImage? {
        if let diskURL = cache.diskFileURL(for: urlString),
           let image = await ImageProcessing.decodeFile(at: diskURL, maxPixelSize: maxPixelSize) {
            cache.storeMemory(image, urlString: urlString, maxPixelSize: maxPixelSize)
            return image
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await session.data(for: request)
            guard !data.isEmpty, !Task.isCancelled else { return nil }
            cache.storeDisk(data, urlString: urlString)
            guard let image = await ImageProcessing.decode(data: data, maxPixelSize: maxPixelSize) else {
                return nil
            }
            cache.storeMemory(image, urlString: urlString, maxPixelSize: maxPixelSize)
            return image
        } catch {
            return nil
        }
    }
}

/// Makes sure one waiter is only released once, whether it finished or was cancelled.
private final class WaiterTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}
