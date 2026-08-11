import SwiftUI
import UIKit

/// Decoded-image memory cache + in-flight de-dupe on top of the shared `URLCache`.
///
/// `AsyncImage` re-runs its phase machine (spinner → image) every time a view
/// appears, even on cache hits. `ImageStore` keeps ready-to-render `UIImage`s
/// so warmed photos display synchronously with zero flicker.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        // ~20+ decoded 1200px photos; NSCache evicts under memory pressure.
        memory.totalCostLimit = 128 * 1024 * 1024
    }

    /// Synchronous, thread-safe memory-cache lookup.
    func cached(_ urlString: String?) -> UIImage? {
        guard let urlString else { return nil }
        return memory.object(forKey: urlString as NSString)
    }

    /// Fetches (network or `URLCache`), decodes off-main, stores in memory.
    /// Concurrent callers for the same URL share one download.
    @discardableResult
    func load(_ urlString: String) async -> UIImage? {
        if let hit = cached(urlString) { return hit }
        guard let url = URL(string: urlString) else { return nil }

        lock.lock()
        let task: Task<UIImage?, Never>
        if let existing = inFlight[urlString] {
            task = existing
            lock.unlock()
        } else {
            task = Task.detached(priority: .userInitiated) {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                guard let (data, _) = try? await URLSession.shared.data(for: request),
                      let image = UIImage(data: data) else { return nil }
                // Decode now so the first render pass doesn't hitch.
                return image.preparingForDisplay() ?? image
            }
            inFlight[urlString] = task
            lock.unlock()
        }

        let image = await task.value

        lock.lock()
        inFlight[urlString] = nil
        lock.unlock()

        if let image {
            let pixels = image.size.width * image.size.height * image.scale * image.scale
            memory.setObject(image, forKey: urlString as NSString, cost: Int(pixels * 4))
        }
        return image
    }
}

/// Warms `ImageStore` (and the shared `URLCache`) so upcoming cards render instantly.
enum ImagePrefetcher {
    static func prefetch(urlStrings: [String]) {
        for urlString in urlStrings where !urlString.isEmpty {
            Task(priority: .userInitiated) {
                await ImageStore.shared.load(urlString)
            }
        }
    }
}

/// Drop-in replacement for `AsyncImage` backed by `ImageStore`:
/// cache hits render synchronously (no spinner flash), misses show a placeholder once.
struct CachedRemoteImage<Placeholder: View>: View {
    let urlString: String?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(urlString: String?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.urlString = urlString
        self.placeholder = placeholder
        _image = State(initialValue: ImageStore.shared.cached(urlString))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: urlString) {
            guard let urlString else { return }
            if let hit = ImageStore.shared.cached(urlString) {
                image = hit
                return
            }
            image = nil
            image = await ImageStore.shared.load(urlString)
        }
    }
}
