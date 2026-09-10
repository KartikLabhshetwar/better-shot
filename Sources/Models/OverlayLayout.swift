import Foundation

// The six positions are shared by the capture card and its settings editor.
enum OverlayToolSlot: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, centerLeft, centerRight, bottomLeft, bottomRight

    var id: String { rawValue }
    var isCenter: Bool { self == .centerLeft || self == .centerRight }
    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .centerLeft: "Center left"
        case .centerRight: "Center right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

enum OverlayTool: String, CaseIterable, Identifiable, Sendable {
    case pin, dismiss, copy, save, edit, share

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pin: "Pin"
        case .dismiss: "Dismiss"
        case .copy: "Copy"
        case .save: "Save"
        case .edit: "Edit"
        case .share: "Cloud Share"
        }
    }
    var symbol: String {
        switch self {
        case .pin: "pin.circle.fill"
        case .dismiss: "xmark.circle.fill"
        case .copy: "doc.on.doc"
        case .save: "square.and.arrow.down"
        case .edit: "pencil.circle.fill"
        case .share: "icloud.and.arrow.up"
        }
    }
}

enum OverlayLayoutPreset: String, CaseIterable, Identifiable, Sendable {
    case standard, sharing, minimal, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Standard"
        case .sharing: "Sharing"
        case .minimal: "Minimal"
        case .custom: "Custom"
        }
    }
    var layout: OverlayToolLayout? {
        switch self {
        case .standard: .standard
        case .sharing: .sharing
        case .minimal: .minimal
        case .custom: nil
        }
    }
}

struct OverlayToolLayout: Equatable, Sendable {
    private(set) var assignments: [OverlayToolSlot: OverlayTool]

    static let standard = Self([.topLeft: .pin, .topRight: .dismiss,
        .centerLeft: .copy, .centerRight: .save, .bottomLeft: .edit, .bottomRight: .share])
    static let sharing = Self([.topLeft: .pin, .topRight: .dismiss,
        .centerLeft: .copy, .centerRight: .share, .bottomLeft: .edit, .bottomRight: .save])
    static let minimal = Self([.topRight: .dismiss, .centerLeft: .copy, .centerRight: .save])

    private init(_ assignments: [OverlayToolSlot: OverlayTool]) {
        self.assignments = assignments
    }

    init(data: Data?) {
        guard let data, let stored = try? JSONDecoder().decode([String: String].self, from: data) else {
            self = .standard
            return
        }
        assignments = [:]
        for slot in OverlayToolSlot.allCases {
            if let raw = stored[slot.rawValue], let tool = OverlayTool(rawValue: raw),
               !assignments.values.contains(tool) {
                assignments[slot] = tool
            }
        }
        // Corrupt or future preferences must never leave the card without a close action.
        if !assignments.values.contains(.dismiss) { assignments[.topRight] = .dismiss }
    }

    var data: Data {
        let stored = Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.rawValue, $0.value.rawValue) })
        return (try? JSONEncoder().encode(stored)) ?? Data()
    }

    var preset: OverlayLayoutPreset {
        OverlayLayoutPreset.allCases.first { $0.layout == self } ?? .custom
    }

    mutating func assign(_ tool: OverlayTool?, to slot: OverlayToolSlot) {
        let previous = assignments[slot]
        guard tool != previous, tool != nil || previous != .dismiss else { return }
        if let tool, let occupied = assignments.first(where: { $0.value == tool })?.key {
            assignments[occupied] = previous
        } else if previous == .dismiss,
                  let empty = OverlayToolSlot.allCases.first(where: { $0 != slot && assignments[$0] == nil }) {
            assignments[empty] = .dismiss
        }
        assignments[slot] = tool
    }
}
