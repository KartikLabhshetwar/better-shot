import UniformTypeIdentifiers

extension UTType {
    static let webp = UTType(importedAs: "org.webmproject.webp")
}

enum ExportFormat: String, CaseIterable {
    case png, jpeg, webp

    var utType: String {
        switch self {
        case .png: return UTType.png.identifier
        case .jpeg: return UTType.jpeg.identifier
        case .webp: return UTType.webp.identifier
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .webp: return "webp"
        }
    }

    var supportsLossyCompressionQuality: Bool {
        switch self {
        case .png: return false
        case .jpeg, .webp: return true
        }
    }
}
