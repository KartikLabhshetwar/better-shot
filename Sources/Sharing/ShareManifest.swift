import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Sidecar document the web share page fetches to describe an uploaded capture.
struct ShareManifest: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let id: String
    let kind: String
    let title: String?
    let media: String
    let poster: String?
    let mimeType: String?
    let width: Int?
    let height: Int?
    let durationSeconds: Double?
    let byteSize: Int?
    let createdAt: String?
    let appVersion: String?
}

/// Builds the manifest plus poster frame that accompany a shared file.
enum ShareBundle {
    static let posterFilename = "poster.jpg"
    static let manifestFilename = "meta.json"

    struct Contents: Sendable {
        let manifest: ShareManifest
        let mediaFilename: String
        let mediaMimeType: String
        let posterData: Data?
    }

    nonisolated static func slug(for itemID: UUID) -> String {
        withUnsafeBytes(of: itemID.uuid) { Data($0) }
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func make(id: String, fileURL: URL, title: String?) async -> Contents {
        let mediaFilename = sanitizedFilename(fileURL.lastPathComponent)
        let mimeType = mimeType(for: fileURL)
        let isVideo = mimeType.hasPrefix("video/")
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let byteSize = attributes?[.size] as? Int

        let probe = isVideo ? await probeVideo(fileURL) : probeImage(fileURL)

        let manifest = ShareManifest(
            version: ShareManifest.currentVersion,
            id: id,
            kind: isVideo ? "video" : "image",
            title: title,
            media: mediaFilename,
            poster: probe.poster == nil ? nil : posterFilename,
            mimeType: mimeType,
            width: probe.width,
            height: probe.height,
            durationSeconds: probe.duration,
            byteSize: byteSize,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )

        return Contents(
            manifest: manifest,
            mediaFilename: mediaFilename,
            mediaMimeType: mimeType,
            posterData: probe.poster
        )
    }

    private struct Probe {
        var width: Int?
        var height: Int?
        var duration: Double?
        var poster: Data?
    }

    private nonisolated static func probeVideo(_ url: URL) async -> Probe {
        var probe = Probe()
        let asset = AVURLAsset(url: url)

        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return probe }

        if let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            let oriented = naturalSize.applying(transform)
            probe.width = Int(abs(oriented.width).rounded())
            probe.height = Int(abs(oriented.height).rounded())
        }

        let duration = (try? await asset.load(.duration).seconds) ?? 0
        if duration.isFinite, duration > 0 { probe.duration = duration }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let seconds = duration > 0 ? min(1.0, duration / 2) : 0
        if let (image, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
            probe.poster = jpegData(from: image)
        }

        return probe
    }

    private nonisolated static func probeImage(_ url: URL) -> Probe {
        var probe = Probe()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return probe }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            probe.width = properties[kCGImagePropertyPixelWidth] as? Int
            probe.height = properties[kCGImagePropertyPixelHeight] as? Int
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
            probe.poster = jpegData(from: thumbnail)
        }

        return probe
    }

    private nonisolated static func jpegData(from image: CGImage) -> Data? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }

    private nonisolated static let filenameAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"
    )

    nonisolated static func sanitizedFilename(_ name: String) -> String {
        let cleaned = String(name.unicodeScalars.map { filenameAllowedCharacters.contains($0) ? Character($0) : "-" })
        return cleaned.isEmpty ? "capture" : cleaned
    }

    nonisolated static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

extension ShareBundle {
    static let pageBaseURL = "https://bettershot.site"

    nonisolated static func objectPrefix(id: String) -> String { "s/\(id)/" }

    /// Tolerates a pasted trailing slash. Returns nil for anything that is not https.
    nonisolated private static func normalizedOrigin(_ publicBaseURL: String) -> String? {
        let origin = publicBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard origin.lowercased().hasPrefix("https://") else { return nil }
        return origin
    }

    /// Why a pasted Public Bucket URL cannot be used, and what to tell the user.
    enum PublicBaseURLProblem: Equatable {
        case empty
        case notHTTPS
        case invalidHost
        case hasQueryOrFragment

        nonisolated var message: String {
            switch self {
            case .empty:
                return "Add the public address of your bucket, like https://share.example.com."
            case .notHTTPS:
                return "The address has to start with https:// - a public bucket is served over HTTPS."
            case .invalidHost:
                return "That is not a complete address. Use the domain your bucket is served from, like https://share.example.com."
            case .hasQueryOrFragment:
                return "Remove everything after the address - a share link is built by adding to it."
            }
        }
    }

    /// Returns nil when the address is usable. A path is allowed: a bucket can be bound under a subfolder.
    nonisolated static func validatePublicBaseURL(_ publicBaseURL: String) -> PublicBaseURLProblem? {
        let trimmed = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        // Before normalizedOrigin, which trims a bare "https://" down to "https:" and would blame the scheme.
        guard trimmed.lowercased().hasPrefix("https://") else { return .notHTTPS }
        guard let components = URLComponents(string: trimmed) else { return .invalidHost }
        guard components.query == nil, components.fragment == nil else { return .hasQueryOrFragment }
        guard let host = components.host, isHostname(host) else { return .invalidHost }
        guard normalizedOrigin(trimmed) != nil else { return .invalidHost }
        return nil
    }

    /// A public bucket is always on a dotted domain, so a single label is a typo.
    nonisolated private static func isHostname(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty
                && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// Drops "/" so a filename cannot open a new path segment.
    private nonisolated static let pathSegmentAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/"))

    /// Links straight at the uploaded object instead of the viewer page.
    nonisolated static func directURL(id: String, filename: String, publicBaseURL: String) -> URL? {
        guard !filename.isEmpty, let origin = normalizedOrigin(publicBaseURL) else { return nil }
        guard let segment = filename.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) else { return nil }
        return URL(string: "\(origin)/\(objectPrefix(id: id))\(segment)")
    }

    nonisolated static func pageURL(id: String, publicBaseURL: String) -> URL? {
        guard let origin = normalizedOrigin(publicBaseURL) else { return nil }

        let encodedOrigin = Data(origin.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return URL(string: "\(pageBaseURL)/s/\(id)?b=\(encodedOrigin)")
    }
}
