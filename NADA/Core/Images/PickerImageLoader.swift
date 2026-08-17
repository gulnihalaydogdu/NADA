import PhotosUI
import UIKit

enum PickerImageLoader {
    /// Loads a library asset already downsampled for the crop editor.
    static func load(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return ImageIOCodec.downsample(data: data, maxPixelSize: ImageIOCodec.pickerMaxPixelSize)
    }
}
