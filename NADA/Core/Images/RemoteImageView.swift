import SwiftUI

/// Cached, downsampled remote image. Replaces `AsyncImage` so we never decode a 1200px
/// photo into a 120pt tile, and so revisits hit memory/disk instead of the network.
///
/// Memory-cache hits paint on the **first frame** (no blank flash after Like/Skip).
/// When `thumbnailURLString` is set, the small file shows while the display decode finishes.
struct RemoteImageView: View {
    let urlString: String?
    var thumbnailURLString: String? = nil
    var targetPointSize: CGFloat
    var contentMode: ContentMode = .fill
    var showsProgress: Bool = false

    @State private var image: UIImage?
    /// Guards against a recycled cell briefly showing the previous photo.
    @State private var loadedKey: String?

    /// Points that decode the stored 360px thumbnail 1:1 on a 3x screen.
    static let thumbnailPointSize: CGFloat = 120

    var body: some View {
        let shown = displayedImage
        ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String {
        "\(urlString ?? "")|\(thumbnailURLString ?? "")|\(Int(targetPointSize.rounded()))"
    }

    /// Prefer in-state pixels for the current key; otherwise paint from memory cache
    /// so a remounted Discover tile is not empty for a frame.
    private var displayedImage: UIImage? {
        if loadedKey == taskKey {
            return image
        }
        return cachedPreview
    }

    private var cachedPreview: UIImage? {
        let loader = RemoteImageLoader.shared
        if let full = loader.cachedImage(urlString: urlString, targetPointSize: targetPointSize) {
            return full
        }
        if let thumbnailURLString, thumbnailURLString != urlString {
            return loader.cachedImage(
                urlString: thumbnailURLString,
                targetPointSize: Self.thumbnailPointSize
            )
        }
        return nil
    }

    @ViewBuilder
    private var placeholder: some View {
        NADATheme.brandSoft
            .overlay {
                if showsProgress, urlString?.isEmpty == false {
                    ProgressView()
                        .tint(NADATheme.brandPressed)
                }
            }
    }

    private func load() async {
        let key = taskKey
        let loader = RemoteImageLoader.shared

        if let ready = loader.cachedImage(urlString: urlString, targetPointSize: targetPointSize) {
            show(ready, for: key)
            return
        }

        var showedPreview = false
        if let thumbnailURLString, thumbnailURLString != urlString,
           let cachedThumb = loader.cachedImage(
            urlString: thumbnailURLString,
            targetPointSize: Self.thumbnailPointSize
           ) {
            show(cachedThumb, for: key)
            showedPreview = true
        }

        if !showedPreview, loadedKey != key {
            image = nil
        }

        if !showedPreview, let thumbnailURLString, thumbnailURLString != urlString {
            if let thumb = await loader.image(
                urlString: thumbnailURLString,
                targetPointSize: Self.thumbnailPointSize
            ) {
                guard !Task.isCancelled else { return }
                show(thumb, for: key)
            }
        }

        guard let full = await loader.image(
            urlString: urlString,
            targetPointSize: targetPointSize
        ) else { return }
        guard !Task.isCancelled else { return }
        show(full, for: key)
    }

    private func show(_ loaded: UIImage, for key: String) {
        image = loaded
        loadedKey = key
    }
}
