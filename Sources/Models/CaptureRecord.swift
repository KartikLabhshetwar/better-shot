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

    init(
        filename: String,
        pixelWidth: Int,
        pixelHeight: Int,
        kind: CaptureKind = .screenshot,
        hasAnnotations: Bool = false
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.filename = filename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kind = kind
        self.hasAnnotations = hasAnnotations
    }
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
}
