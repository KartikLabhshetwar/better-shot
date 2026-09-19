import Foundation

enum CapturePresentationMode: String, CaseIterable, Identifiable {
    case normal
    case notch

    var id: String { rawValue }
    var title: String { self == .normal ? "Normal Mode" : "Notch Mode" }
}
