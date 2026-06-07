import AppKit

enum BundledBackgrounds {

    struct ImageAsset: Identifiable, Equatable {
        let id: String
        let filename: String

        var image: NSImage? {
            ImageCache.shared.image(for: self)
        }

        var url: URL? {
            guard let resourceURL = Bundle.main.resourceURL else { return nil }
            let fileURL = resourceURL
                .appendingPathComponent("Backgrounds/mac")
                .appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return fileURL
        }
    }

    final class ImageCache: @unchecked Sendable {
        static let shared = ImageCache()
        private let lock = NSLock()
        private var cache: [String: NSImage] = [:]

        func image(for asset: ImageAsset) -> NSImage? {
            lock.lock()
            if let cached = cache[asset.id] { lock.unlock(); return cached }
            lock.unlock()
            guard let url = asset.url, let img = NSImage(contentsOf: url) else { return nil }
            lock.lock()
            cache[asset.id] = img
            lock.unlock()
            return img
        }
    }

    static let macAssets: [ImageAsset] = [
        ImageAsset(id: "mac-3", filename: "mac-asset-3.jpg"),
        ImageAsset(id: "mac-5", filename: "mac-asset-5.jpg"),
        ImageAsset(id: "mac-6", filename: "mac-asset-6.jpeg"),
        ImageAsset(id: "mac-7", filename: "mac-asset-7.png"),
        ImageAsset(id: "mac-8", filename: "mac-asset-8.jpg"),
        ImageAsset(id: "mac-9", filename: "mac-asset-9.jpg"),
        ImageAsset(id: "mac-10", filename: "mac-asset-10.jpg"),
    ]

    static func asset(byID id: String) -> ImageAsset? {
        macAssets.first { $0.id == id }
    }
}
