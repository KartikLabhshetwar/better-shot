//
//  CloudUploader.swift
//  BetterShot
//
//  Compresses a capture locally, then publishes it through the R2 share
//  pipeline. Keeps the editors' original call-site API so the studio and
//  annotation editor never learn about the transport underneath.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CloudUploadResult: Sendable {
    let id: String
    let url: String
    let filename: String
    let size: Int
}

@MainActor
@Observable
final class CloudUploader {
    static let shared = CloudUploader()

    private init() {}

    var isConfigured: Bool {
        R2CredentialStore.shared.isConfigured
    }

    /// Progress keyed by item ID; only the network leg reports, the local
    /// compress finishes before a fraction would be worth drawing.
    var uploadProgress: [UUID: Double] {
        R2Uploader.shared.uploadProgress
    }

    func upload(
        itemID: UUID,
        fileURL: URL,
        title: String? = nil
    ) async throws -> CloudUploadResult {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterShotShare-\(itemID.uuidString)")
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let mimeType = ShareBundle.mimeType(for: fileURL)
        let uploadFile: URL
        if mimeType.hasPrefix("video/") {
            uploadFile = await Self.compressedVideo(at: fileURL, into: stagingDir)
        } else if mimeType.hasPrefix("image/") {
            uploadFile = await Task.detached {
                Self.compressedImage(at: fileURL, into: stagingDir)
            }.value
        } else {
            uploadFile = fileURL
        }

        let pageURL = try await R2Uploader.shared.uploadShare(
            itemID: itemID,
            fileURL: uploadFile,
            title: title
        )

        return CloudUploadResult(
            id: ShareBundle.slug(for: itemID),
            url: pageURL.absoluteString,
            filename: uploadFile.lastPathComponent,
            size: Self.fileSize(of: uploadFile)
        )
    }

    func cancelUpload(for itemID: UUID) {
        R2Uploader.shared.cancel(itemID: itemID)
    }

    // MARK: - Local compression

    /// Downscales and re-encodes the render before a single byte is uploaded;
    /// the original file always wins when it is already the smaller one.
    nonisolated private static func compressedImage(at url: URL, into directory: URL) -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return url
        }

        let name = url.deletingPathExtension().lastPathComponent
        guard let compressed = try? ShareImageCompressor.write(
            image,
            named: name,
            keepingAlpha: hasTransparency(image),
            into: directory
        ) else {
            return url
        }

        return ShareImageCompressor.byteCount(compressed) < ShareImageCompressor.byteCount(url)
            ? compressed : url
    }

    /// Screen masters are enormous; a 1080p H.264 pass is what a share page
    /// actually plays. The cloud copy is always an MP4: when the re-encode
    /// fails or does not get smaller, a passthrough remux still rewraps a
    /// QuickTime master so the share page never serves a `.mov`.
    nonisolated private static func compressedVideo(at url: URL, into directory: URL) async -> URL {
        let asset = AVURLAsset(url: url)
        let output = directory
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("mp4")

        if let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080
        ) {
            session.shouldOptimizeForNetworkUse = true
            do {
                try await session.export(to: output, as: .mp4)
                if ShareImageCompressor.byteCount(output) < ShareImageCompressor.byteCount(url) {
                    return output
                }
            } catch {}
        }

        if VideoExportContainer(fileExtension: url.pathExtension) == .mp4 {
            return url
        }

        try? FileManager.default.removeItem(at: output)
        do {
            try await VideoContainerRemuxer.remux(from: url, to: output, as: .mp4)
            return output
        } catch {
            return url
        }
    }

    /// The render pipeline always attaches an alpha channel, so only a real
    /// scan can tell a transparent shot from an opaque one.
    nonisolated private static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }

        let probe = ShareImageCompressor.downscaled(image) ?? image
        let width = probe.width
        let height = probe.height
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(probe, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return true }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }

    nonisolated private static func fileSize(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
    }
}
