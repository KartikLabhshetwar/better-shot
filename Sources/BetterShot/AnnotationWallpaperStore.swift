//
//  AnnotationWallpaperStore.swift
//  BetterShot
//

import Foundation
import Observation

@MainActor
@Observable
final class AnnotationWallpaperStore {
    static let shared = AnnotationWallpaperStore()

    nonisolated private static let recentWallpaperPathsKey = "annotationBackground.recentWallpaperPaths"
    nonisolated private static let maxRecentWallpaperCount = 24
    nonisolated private static let supportedImageExtensions: Set<String> = [
        "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ]

    private(set) var recentWallpapers: [AnnotationCustomWallpaper] = []

    private init() {
        Task { await reload() }
    }

    /// Refreshes the recent wallpaper list. The filesystem checks run off
    /// the main actor; only the resulting state assignment happens on-main.
    func reload() async {
        let recent = await Task.detached(priority: .userInitiated) {
            Self.loadRecentWallpaperURLs()
        }.value

        recentWallpapers = recent.map { AnnotationCustomWallpaper(url: $0) }
    }

    func isAvailable(_ wallpaper: AnnotationCustomWallpaper) -> Bool {
        Self.isSupportedImageFile(wallpaper.url)
    }

    func addRecentWallpaper(_ url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        let standardizedURL = URL(fileURLWithPath: standardizedPath)
        guard Self.isSupportedImageFile(standardizedURL) else { return }

        var paths = UserDefaults.standard.stringArray(forKey: Self.recentWallpaperPathsKey) ?? []
        guard !paths.contains(standardizedPath) else { return }
        paths.insert(standardizedPath, at: 0)

        let filteredPaths = paths
            .filter { path in
                let url = URL(fileURLWithPath: path)
                return Self.isSupportedImageFile(url)
            }
            .prefix(Self.maxRecentWallpaperCount)
        let recentPaths = Array(filteredPaths)

        UserDefaults.standard.set(recentPaths, forKey: Self.recentWallpaperPathsKey)
        recentWallpapers = recentPaths.map { AnnotationCustomWallpaper(url: URL(fileURLWithPath: $0)) }
        Task { await reload() }
    }

    // MARK: - Off-main filesystem work

    nonisolated private static func loadRecentWallpaperURLs() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: recentWallpaperPathsKey) ?? []
        let availablePaths = paths.filter { path in
            let url = URL(fileURLWithPath: path)
            return isSupportedImageFile(url)
        }

        if availablePaths != paths {
            UserDefaults.standard.set(availablePaths, forKey: recentWallpaperPathsKey)
        }

        return availablePaths.map { URL(fileURLWithPath: $0) }
    }

    nonisolated private static func isSupportedImageFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard !url.lastPathComponent.hasPrefix("._") else { return false }
        guard !url.pathComponents.contains("__MACOSX") else { return false }
        return supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

}

extension BundledBackgrounds {
    /// The bundled macOS wallpapers as pickable editor wallpapers, so the
    /// image editor, the Studio, and Settings all offer the same set.
    static var macWallpapers: [AnnotationCustomWallpaper] {
        macAssets.compactMap { asset in
            asset.url.map { AnnotationCustomWallpaper(url: $0) }
        }
    }
}
