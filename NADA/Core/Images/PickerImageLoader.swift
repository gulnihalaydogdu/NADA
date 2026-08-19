import PhotosUI
import SwiftUI
import UIKit

enum PickerImageLoader {
    /// Still photos only. Videos and Live Photos stay out of the picker grid.
    static let stillPhotosFilter: PHPickerFilter = .all(of: [
        .images,
        .not(.videos),
        .not(.livePhotos),
        .not(.slomoVideos),
        .not(.timelapseVideos),
        .not(.cinematicVideos),
        .not(.screenRecordings)
    ])

    /// Loads a library asset already downsampled for the crop editor, decoding off the main thread.
    static func load(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await ImageProcessing.downsampleForEditor(data: data)
    }
}

extension View {
    /// Hides Albums / Collections so the Videos album never appears in the picker chrome.
    func nadaStillPhotosPickerChrome() -> some View {
        photosPickerDisabledCapabilities(.collectionNavigation)
    }
}
 
