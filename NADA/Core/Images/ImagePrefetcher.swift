import Foundation

/// Warms `URLCache` so `AsyncImage` / subsequent loads hit memory/disk sooner.
enum ImagePrefetcher {
    static func prefetch(urlStrings: [String]) {
        let urls = urlStrings.compactMap { URL(string: $0) }
        guard !urls.isEmpty else { return }
        for url in urls {
            Task.detached(priority: .utility) {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }
}
