import PhotosUI
import UIKit

enum PickerImageLoader {
    /// Loads a library asset already downsampled for the crop editor, decoding off the main thread.
    static func load(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await ImageProcessing.downsampleForEditor(data: data)
    }
}
