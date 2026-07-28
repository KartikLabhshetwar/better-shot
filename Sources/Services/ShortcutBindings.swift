import Carbon
import Foundation

typealias ShortcutLoadClosure = (ShortcutAction) -> ShortcutDefinition?

struct ShortcutDefinition: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var enabled: Bool

    static let defaultRegion = ShortcutDefinition(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
    static let defaultFullscreen = ShortcutDefinition(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
    static let defaultOCR = ShortcutDefinition(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
    static let defaultColorPicker = ShortcutDefinition(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
    static let defaultRecording = ShortcutDefinition(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
    static let defaultWindow = ShortcutDefinition(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
}

enum ShortcutAction: UInt32, CaseIterable {
    case region = 1
    case fullscreen = 2
    case window = 3
    case ocr = 4
    case colorPicker = 5
    case recording = 6
}

enum ShortcutBindings {
    static func key(for action: ShortcutAction) -> String {
        "bs_hotkey_\(action.rawValue)"
    }

    static func defaultShortcut(for action: ShortcutAction) -> ShortcutDefinition {
        switch action {
        case .region: return .defaultRegion
        case .fullscreen: return .defaultFullscreen
        case .window: return .defaultWindow
        case .ocr: return .defaultOCR
        case .colorPicker: return .defaultColorPicker
        case .recording: return .defaultRecording
        }
    }

    static func resolveBindings(loadShortcut: ShortcutLoadClosure) -> [(ShortcutAction, ShortcutDefinition)] {
        ShortcutAction.allCases.map { action in
            (action, loadShortcut(action) ?? defaultShortcut(for: action))
        }
    }
}
