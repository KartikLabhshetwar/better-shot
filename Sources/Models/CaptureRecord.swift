import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Represents a captured screenshot or recording in the history.
struct CaptureRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    /// Where the file is stored; may carry a storage number (`Name-2.png`).
    var filename: String
    /// The name the capture was given when it was taken. Nil for records from
    /// builds that only stored a filename.
    var name: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: CaptureKind
    var hasAnnotations: Bool
    var beautifiedPath: String?
    /// Absolute path when the file lives outside Application Support and is only referenced.
    var sourcePath: String?
    /// Public link from the last successful cloud share, if any.
    var shareURL: String?

    init(
        filename: String,
        name: String? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        kind: CaptureKind = .screenshot,
        hasAnnotations: Bool = false,
        beautifiedPath: String? = nil,
        sourcePath: String? = nil,
        shareURL: String? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.filename = filename
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kind = kind
        self.hasAnnotations = hasAnnotations
        self.beautifiedPath = beautifiedPath
        self.sourcePath = sourcePath
        self.shareURL = shareURL
    }

    var isManaged: Bool { sourcePath == nil }

    /// What the capture is called in the library, Copy, Save, and Share.
    var displayName: String { name ?? filename }
}

enum CaptureKind: String, Codable {
    case screenshot
    case recording

    nonisolated static func resolved(for url: URL, fallback: Self = .screenshot) -> Self {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        return type?.conforms(to: .movie) == true ? .recording : fallback
    }
}

/// Background configuration for the beautifier.
struct BeautifierConfig: Codable, Equatable {
    var style: BackgroundStyle = .none
    var padding: CGFloat = 0.08
    var cornerRadius: CGFloat = 0.018
    var shadowStrength: CGFloat = 0.36
    var alignment: ImageAlignment = .center
    var aspectRatio: CanvasAspectRatio = .auto
    var grade = ColorGrade.neutral

    static let `default` = BeautifierConfig()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(BackgroundStyle.self, forKey: .style) ?? .none
        padding = try container.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 0.08
        cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0.018
        shadowStrength = try container.decodeIfPresent(CGFloat.self, forKey: .shadowStrength) ?? 0.36
        alignment = try container.decodeIfPresent(ImageAlignment.self, forKey: .alignment) ?? .center
        aspectRatio = try container.decodeIfPresent(CanvasAspectRatio.self, forKey: .aspectRatio) ?? .auto
        grade = try container.decodeIfPresent(ColorGrade.self, forKey: .grade) ?? .neutral
    }
}
