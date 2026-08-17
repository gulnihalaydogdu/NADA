import CryptoKit
import Foundation
import UIKit

/// Bounded memory + disk cache for remote photos.
/// Memory holds decoded bitmaps (cost = pixel count). Disk holds original bytes.
final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let diskQueue = DispatchQueue(label: "nada.remote-image.disk", qos: .utility)
    private let folder: URL
    private let maxDiskBytes: UInt64 = 80 * 1024 * 1024
    private let lock = NSLock()
    private var memoryKeysByURL: [String: Set<String>] = [:]

    private init() {
        memory.totalCostLimit = 40 * 1024 * 1024
        memory.countLimit = 80

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = caches.appendingPathComponent("nada-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func memoryImage(urlString: String, maxPixelSize: CGFloat) -> UIImage? {
        memory.object(forKey: memoryKey(urlString, maxPixelSize: maxPixelSize) as NSString)
    }

    func storeMemory(_ image: UIImage, urlString: String, maxPixelSize: CGFloat) {
        let key = memoryKey(urlString, maxPixelSize: maxPixelSize)
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale)
        lock.lock()
        memoryKeysByURL[urlString, default: []].insert(key)
        lock.unlock()
        memory.setObject(image, forKey: key as NSString, cost: max(cost, 1))
    }

    func diskData(urlString: String) -> Data? {
        let url = diskURL(for: urlString)
        return try? Data(contentsOf: url)
    }

    func storeDisk(_ data: Data, urlString: String) {
        let url = diskURL(for: urlString)
        diskQueue.async { [maxDiskBytes, folder] in
            try? data.write(to: url, options: .atomic)
            Self.trimDiskIfNeeded(folder: folder, maxBytes: maxDiskBytes)
        }
    }

    func remove(urlString: String) {
        lock.lock()
        let keys = memoryKeysByURL.removeValue(forKey: urlString) ?? []
        lock.unlock()
        for key in keys {
            memory.removeObject(forKey: key as NSString)
        }
        let url = diskURL(for: urlString)
        diskQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func removeAll() {
        lock.lock()
        memoryKeysByURL.removeAll()
        lock.unlock()
        memory.removeAllObjects()
        let folder = self.folder
        diskQueue.async {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    private func memoryKey(_ urlString: String, maxPixelSize: CGFloat) -> String {
        "\(urlString)#\(Int(maxPixelSize.rounded()))"
    }

    private func diskURL(for urlString: String) -> URL {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(name)
    }

    private static func trimDiskIfNeeded(folder: URL, maxBytes: UInt64) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, date: Date, size: UInt64)] = []
        var total: UInt64 = 0
        for file in files {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = UInt64(values?.fileSize ?? 0)
            total += size
            entries.append((file, values?.contentModificationDate ?? .distantPast, size))
        }
        guard total > maxBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
            if total <= maxBytes { break }
        }
    }
}
