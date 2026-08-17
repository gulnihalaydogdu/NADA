import SwiftUI

/// Cached, downsampled remote image. Replaces `AsyncImage` so we never decode a 1200px
/// photo into a 120pt tile, and so revisits hit memory/disk instead of the network.
struct RemoteImageView: View {
    let urlString: String?
    var targetPointSize: CGFloat
    var contentMode: ContentMode = .fill
    var showsProgress: Bool = true

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: urlString) {
            image = await RemoteImageLoader.shared.image(
                urlString: urlString,
                targetPointSize: targetPointSize
            )
        }
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
}
