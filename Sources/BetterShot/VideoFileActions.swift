//
//  VideoFileActions.swift
//  BetterShot
//
//  Created by Codex on 01/05/26.
//

import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum VideoPreviewImageLoader {
    static func thumbnail(at url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        let cgImage = await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
                continuation.resume(returning: image)
            }
        }

        guard let cgImage else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    static func placeholderImage() -> NSImage {
        let size = CGSize(width: 520, height: 390)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        if let symbol = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil) {
            symbol.size = CGSize(width: 96, height: 96)
            symbol.draw(
                in: CGRect(
                    x: (size.width - 96) / 2,
                    y: (size.height - 96) / 2,
                    width: 96,
                    height: 96
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.85
            )
        }

        image.unlockFocus()
        return image
    }
}

extension VideoExportContainer {
    var contentType: UTType {
        switch self {
        case .mov: .quickTimeMovie
        case .mp4: .mpeg4Movie
        }
    }

    var fileType: AVFileType {
        switch self {
        case .mov: .mov
        case .mp4: .mp4
        }
    }

    /// Faststart is an MP4/streaming convention. Asking for it costs the
    /// writer an extra reorganisation pass, so it is not requested for
    /// containers that gain nothing from it.
    var supportsFastStart: Bool { self == .mp4 }
}

enum VideoFileActions {
    /// Recordings are delivered as MP4 by default so they play everywhere;
    /// `save` remuxes QuickTime masters on the way out. Studio's export
    /// options override this per project.
    static var exportFileExtension: String { VideoExportContainer.default.fileExtension }
    static var exportContentType: UTType { VideoExportContainer.default.contentType }

    static func copyToClipboard(from url: URL) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([url as NSURL]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    @discardableResult
    static func saveToDefaultLocation(from url: URL, suggestedFileName: String? = nil) async throws -> URL {
        let destinationDirectory = BetterShotPreferences.exportDirectory
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        let destinationURL = uniqueDestinationURL(
            for: suggestedFileName ?? exportFileName(for: url),
            in: destinationDirectory
        )
        try await save(from: url, to: destinationURL)
        return destinationURL
    }

    /// Copies when the source already matches the destination container, and
    /// otherwise rewrites it. A file extension is a claim about the bytes, so
    /// renaming a QuickTime master to `.mp4` would produce a file some players
    /// reject - the remux is what makes the rename honest. Matching containers
    /// take the copy path, which on APFS is a clone rather than a byte copy.
    static func save(from sourceURL: URL, to destinationURL: URL) async throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        guard let target = remuxTarget(from: sourceURL, to: destinationURL) else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        try await VideoContainerRemuxer.remux(from: sourceURL, to: destinationURL, as: target)
    }

    /// The container to rewrite into, or nil when a plain copy is correct.
    /// Only recognised video containers are converted; audio-only exports and
    /// anything unfamiliar are copied untouched.
    private static func remuxTarget(from sourceURL: URL, to destinationURL: URL) -> VideoExportContainer? {
        guard let destination = VideoExportContainer(fileExtension: destinationURL.pathExtension),
              let source = VideoExportContainer(fileExtension: sourceURL.pathExtension),
              source != destination else {
            return nil
        }
        return destination
    }

    static func exportFileName(
        for sourceURL: URL,
        container: VideoExportContainer = .default
    ) -> String {
        sourceURL
            .deletingPathExtension()
            .appendingPathExtension(container.fileExtension)
            .lastPathComponent
    }

    static func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let originalURL = directory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return originalURL
        }

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension

        for index in 1...10_000 {
            let numberedName = "\(baseName) \(index)"
            let candidateURL = directory
                .appendingPathComponent(numberedName)
                .appendingPathExtension(pathExtension)

            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory
            .appendingPathComponent("\(baseName) \(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}

/// Rewrites a movie into a different container without re-encoding. The
/// passthrough preset copies the existing H.264/HEVC and AAC samples, so this
/// is an I/O-bound copy rather than a second transcode and the result is
/// bit-for-bit the same picture.
nonisolated enum VideoContainerRemuxer {
    enum RemuxError: LocalizedError {
        case unsupported(VideoExportContainer)

        var errorDescription: String? {
            switch self {
            case let .unsupported(container):
                "This recording could not be converted to \(container.rawValue)."
            }
        }
    }

    static func remux(
        from sourceURL: URL,
        to destinationURL: URL,
        as container: VideoExportContainer
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        // Passthrough only. Re-encoding to satisfy a container change would
        // cost a generation of quality that the user never asked for, so an
        // unconvertible source fails loudly instead of degrading in silence.
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough),
              session.supportedFileTypes.contains(container.fileType) else {
            throw RemuxError.unsupported(container)
        }
        session.shouldOptimizeForNetworkUse = container.supportsFastStart
        try await session.export(to: destinationURL, as: container.fileType)
    }
}
