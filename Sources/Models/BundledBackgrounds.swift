import AppKit

/// Catalog of bundled background images shipped with the app.
enum BundledBackgrounds {

    struct ImageAsset: Identifiable, Equatable {
        let id: String
        let filename: String
        let category: Category

        var image: NSImage? {
            guard let url else { return nil }
            return NSImage(contentsOf: url)
        }

        var url: URL? {
            guard let resourceURL = Bundle.main.resourceURL else { return nil }
            let fileURL = resourceURL.appendingPathComponent(category.subdirectory).appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return fileURL
        }
    }

    enum Category: String, CaseIterable {
        case wallpapers
        case gradients
        case mac

        var subdirectory: String {
            "Backgrounds/\(rawValue)"
        }

        var displayName: String {
            switch self {
            case .wallpapers: return "Wallpapers"
            case .gradients: return "Gradients"
            case .mac: return "macOS"
            }
        }
    }

    // MARK: - Wallpapers

    static let wallpapers: [ImageAsset] = [
        ImageAsset(id: "wall-1", filename: "asset-13.jpg", category: .wallpapers),
        ImageAsset(id: "wall-2", filename: "asset-18.jpg", category: .wallpapers),
        ImageAsset(id: "wall-3", filename: "asset-19.jpg", category: .wallpapers),
        ImageAsset(id: "wall-4", filename: "asset-24.avif", category: .wallpapers),
        ImageAsset(id: "wall-5", filename: "asset-25.jpg", category: .wallpapers),
        ImageAsset(id: "wall-6", filename: "asset-26.jpeg", category: .wallpapers),
        ImageAsset(id: "wall-7", filename: "asset-27.jpeg", category: .wallpapers),
        ImageAsset(id: "wall-8", filename: "asset-28.jpeg", category: .wallpapers),
        ImageAsset(id: "wall-9", filename: "asset-29.jpeg", category: .wallpapers),
        ImageAsset(id: "wall-10", filename: "asset-30.jpeg", category: .wallpapers),
    ]

    // MARK: - Mesh Gradients

    static let gradients: [ImageAsset] = (1...17).map { i in
        ImageAsset(id: "mesh-\(i)", filename: "mesh\(i).webp", category: .gradients)
    }

    // MARK: - macOS Assets

    static let macAssets: [ImageAsset] = [
        ImageAsset(id: "mac-3", filename: "mac-asset-3.jpg", category: .mac),
        ImageAsset(id: "mac-5", filename: "mac-asset-5.jpg", category: .mac),
        ImageAsset(id: "mac-6", filename: "mac-asset-6.jpeg", category: .mac),
        ImageAsset(id: "mac-7", filename: "mac-asset-7.png", category: .mac),
        ImageAsset(id: "mac-8", filename: "mac-asset-8.jpg", category: .mac),
        ImageAsset(id: "mac-9", filename: "mac-asset-9.jpg", category: .mac),
        ImageAsset(id: "mac-10", filename: "mac-asset-10.jpg", category: .mac),
    ]

    // MARK: - All

    static let all: [ImageAsset] = wallpapers + gradients + macAssets

    static func asset(byID id: String) -> ImageAsset? {
        all.first { $0.id == id }
    }
}
