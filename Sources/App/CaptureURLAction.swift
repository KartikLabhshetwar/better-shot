import Foundation
import UniformTypeIdentifiers

nonisolated enum CaptureURLAction: String, CaseIterable {
    case region = "capture/region"
    case fullscreen = "capture/fullscreen"
    case window = "capture/window"
    case scrollCapture = "capture/scroll"
    case recording = "record"
    case ocr
    case colorPicker = "color-picker"
    case settings

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "bettershot",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              let host = components.host else { return nil }
        self.init(rawValue: host.lowercased() + components.path)
    }
}

/// Finder's Open With delivers files through the same callback as `bettershot://` links.
nonisolated enum OpenedImageFile {
    static func isEditable(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
