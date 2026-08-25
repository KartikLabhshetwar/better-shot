//
//  VideoCompressionModels.swift
//  BetterShot
//

import Foundation

enum VideoCompressionQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }

    var crf: Int {
        switch self {
        case .high:
            20
        case .medium:
            26
        case .low:
            32
        }
    }

    var audioBitrate: String {
        switch self {
        case .high:
            "192k"
        case .medium:
            "128k"
        case .low:
            "96k"
        }
    }
}

enum VideoCompressionSpeed: String, CaseIterable, Identifiable, Codable, Sendable {
    case ultrafast = "Ultrafast"
    case fast = "Fast"
    case medium = "Medium"
    case slow = "Slow"

    var id: String { rawValue }

    var ffmpegPreset: String {
        rawValue.lowercased()
    }
}

enum VideoCompressionCodec: String, CaseIterable, Identifiable, Codable, Sendable {
    case h264 = "H.264"
    case hevc = "HEVC"

    var id: String { rawValue }

    var encoder: String {
        switch self {
        case .h264:
            "libx264"
        case .hevc:
            "libx265"
        }
    }
}

enum VideoCompressionResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case original = "Original"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }

    var scaleFilter: String? {
        switch self {
        case .original:
            nil
        case .p1080:
            "-2:1080"
        case .p720:
            "-2:720"
        case .p480:
            "-2:480"
        }
    }
}

/// Delivery container for exported recordings. The encoded video and audio
/// are identical either way - only the wrapper differs.
enum VideoExportContainer: String, CaseIterable, Identifiable, Codable, Sendable {
    /// What capture already writes, so exporting one is a copy-on-write
    /// clone with no rewrite at all.
    case mov = "MOV"
    /// Plays everywhere - Slack, Discord, browsers, Windows - which is why
    /// it is the default even though a QuickTime master costs a container
    /// rewrite on the way out.
    case mp4 = "MP4"

    static let `default` = VideoExportContainer.mp4

    var id: String { rawValue }

    var fileExtension: String { rawValue.lowercased() }

    init?(fileExtension: String) {
        guard let match = Self.allCases.first(where: {
            $0.fileExtension == fileExtension.lowercased()
        }) else { return nil }
        self = match
    }
}

struct VideoCompressionSettings: Codable, Equatable, Sendable {
    var quality: VideoCompressionQuality = .medium
    var speed: VideoCompressionSpeed = .fast
    var codec: VideoCompressionCodec = .h264
    var resolution: VideoCompressionResolution = .original
    var removeAudio = false
    /// Optional so projects saved before the format picker keep decoding.
    /// A synthesized `Codable` decoder ignores property defaults and throws
    /// on a missing key, and `loadEditDocument` swallows that with `try?` -
    /// a non-optional field here would silently discard the whole project.
    var container: VideoExportContainer?

    var effectiveContainer: VideoExportContainer { container ?? .default }
}

struct VideoCompressionResult: Sendable {
    let outputURL: URL
    let inputSize: Int64
    let outputSize: Int64

    var reduction: Double? {
        guard inputSize > 0 else { return nil }
        return 1 - Double(outputSize) / Double(inputSize)
    }
}
