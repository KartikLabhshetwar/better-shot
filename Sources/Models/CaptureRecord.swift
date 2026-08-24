import CoreGraphics
import Foundation

/// Represents a captured screenshot or recording in the history.
struct CaptureRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var filename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: CaptureKind
    var hasAnnotations: Bool
    var beautifiedPath: String?
    /// Absolute path when the file lives outside Application Support and is only referenced.
    var sourcePath: String?

    init(
        filename: String,
        pixelWidth: Int,
        pixelHeight: Int,
        kind: CaptureKind = .screenshot,
        hasAnnotations: Bool = false,
        beautifiedPath: String? = nil,
        sourcePath: String? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.filename = filename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kind = kind
        self.hasAnnotations = hasAnnotations
        self.beautifiedPath = beautifiedPath
        self.sourcePath = sourcePath
    }

    var isManaged: Bool { sourcePath == nil }
}

enum CaptureKind: String, Codable {
    case screenshot
    case recording
}

/// Background configuration for the beautifier.
struct BeautifierConfig: Codable, Equatable {
    var style: BackgroundStyle = .none
    var padding: CGFloat = 0.08
    var cornerRadius: CGFloat = 0.018
    var shadowStrength: CGFloat = 0.36
    var alignment: ImageAlignment = .center
    var aspectRatio: CanvasAspectRatio = .auto

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
    }
}
