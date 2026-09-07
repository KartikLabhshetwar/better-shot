import Foundation

nonisolated enum CaptureURLAction: String, CaseIterable {
    case region = "capture/region"
    case fullscreen = "capture/fullscreen"
    case window = "capture/window"
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
