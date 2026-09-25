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

    var canShare: Bool {
        R2CredentialStore.shared.canShare
    }

    /// Progress keyed by item ID; only the network leg reports, the local
    /// compress finishes before a fraction would be worth drawing.
    var uploadProgress: [UUID: Double] {
        R2Uploader.shared.uploadProgress
    }

    /// `name` is the capture's name without an extension; the uploaded file,
    /// and so the share page's download, carries it.
    func upload(
        itemID: UUID,
        fileURL: URL,
        named name: String,
        title: String? = nil
    ) async throws -> CloudUploadResult {
        try Task.checkCancellation()
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterShotShare-\(itemID.uuidString)")
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let uploadFile = await Self.prepareUpload(of: fileURL, named: name, into: stagingDir)

        try Task.checkCancellation()
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

    /// The file to upload, named `name`: a compressed copy when that is
    /// smaller, otherwise a clone of the original, in `directory`. The
    /// uploaded file's name is what the share page offers for download.
    nonisolated static func prepareUpload(of fileURL: URL, named name: String, into directory: URL) async -> URL {
        let mimeType = ShareBundle.mimeType(for: fileURL)
        let prepared: URL
        if mimeType.hasPrefix("video/") {
            prepared = await compressedVideo(at: fileURL, named: name, into: directory)
        } else if mimeType.hasPrefix("image/") {
            prepared = await Task.detached { compressedImage(at: fileURL, named: name, into: directory) }.value
        } else {
            prepared = fileURL
        }
        guard prepared.deletingPathExtension().lastPathComponent != name else { return prepared }
        let renamed = directory.appendingPathComponent(name).appendingPathExtension(prepared.pathExtension)
        do {
            try FileManager.default.copyItem(at: prepared, to: renamed)
            return renamed
        } catch {
            return prepared
        }
    }

    /// Downscales and re-encodes the render before a single byte is uploaded;
    /// the original file always wins when it is already the smaller one.
    nonisolated private static func compressedImage(at url: URL, named name: String, into directory: URL) -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return url
        }

        guard let compressed = try? ShareImageCompressor.write(
            image,
            named: name,
            keepingAlpha: hasTransparency(image),
            into: directory
        ) else {
            return url
        }

        return ShareImageCompressor.smaller(compressed, orOriginal: url)
    }

    /// Screen masters are enormous; a 1080p H.264 pass is what a share page
    /// actually plays. The cloud copy is always an MP4: when the re-encode
    /// fails or does not get smaller, a passthrough remux still rewraps a
    /// QuickTime master so the share page never serves a `.mov`.
    nonisolated static func compressedVideo(at url: URL, named name: String? = nil, into directory: URL) async -> URL {
        let asset = AVURLAsset(url: url)
        let output = directory
            .appendingPathComponent(name ?? url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("mp4")

        if let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080
        ) {
            session.shouldOptimizeForNetworkUse = true
            do {
                try await session.export(to: output, as: .mp4)
                if ShareImageCompressor.smaller(output, orOriginal: url) == output {
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
