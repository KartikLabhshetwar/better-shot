import Carbon
import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class ShortcutService {
    static let shared = ShortcutService()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private static let shortcutLock = NSLock()
    private static var _cachedShortcuts: [(Action, Shortcut)] = []
    private static var cachedShortcuts: [(Action, Shortcut)] {
        get { shortcutLock.withLock { _cachedShortcuts } }
        set { shortcutLock.withLock { _cachedShortcuts = newValue } }
    }

    var isRegistered: Bool { eventTap != nil }

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var revision = 0
    private var recorderCount = 0
    var isRecordingShortcut: Bool { recorderCount > 0 }

    func beginRecordingShortcut() {
        recorderCount += 1
        unregisterAll()
    }

    func endRecordingShortcut() {
        recorderCount = max(0, recorderCount - 1)
        if recorderCount == 0 { registerAll() }
    }
    @ObservationIgnored private let windowScopes = NSMapTable<NSWindow, NSNumber>.weakToStrongObjects()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateCaptureShortcuts(defaults: defaults)
    }

    func registerScope(_ scope: Scope, for window: NSWindow) {
        windowScopes.setObject(NSNumber(value: scope.rawValue), forKey: window)
    }

    func scope(for window: NSWindow) -> Scope? {
        windowScopes.object(forKey: window).flatMap { Scope(rawValue: $0.intValue) }
    }

    // MARK: - Shortcut Definition

    struct Shortcut: Codable, Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var enabled: Bool

        static let defaultRegion = Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultFullscreen = Shortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultOCR = Shortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultColorPicker = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultRecordingOptions = Shortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultRecording = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
    }

    // MARK: - Registration (CGEvent tap — intercepts system shortcuts)

    func registerAll() {
        unregisterAll()

        guard !isRecordingShortcut, ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        guard Self.hasAccessibilityPermission else {
            print("BetterShot: No accessibility permission, skipping event tap registration")
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: ShortcutService.eventTapCallback,
            userInfo: nil
        ) else {
            print("BetterShot: Failed to create event tap — app may need a restart after granting Accessibility permission")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        Self.cacheShortcuts()
        print("BetterShot: Event tap registered successfully — keyboard shortcuts active")
    }

    private static func cacheShortcuts() {
        let service = ShortcutService.shared
        cachedShortcuts = Action.allCases.filter { $0.scope == .global }.compactMap { action in
            guard let shortcut = service.effectiveShortcut(for: action),
                  shortcut.modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { return nil }
            return (action, shortcut)
        }
    }

    func unregisterAll() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Persistence

    func saveShortcut(_ shortcut: Shortcut, for action: Action) {
        let key = "bs_hotkey_\(action.rawValue)"
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        }
        revision &+= 1
        if self === Self.shared { Self.cacheShortcuts() }
    }

    func loadShortcut(for action: Action) -> Shortcut? {
        let key = "bs_hotkey_\(action.rawValue)"
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    /// Move only the old defaults; preserve custom combinations and disabled shortcuts.
    static func migrateCaptureShortcuts(defaults: UserDefaults = .standard) {
        let migrationKey = "bs_captureShortcuts050Restored"
        guard !defaults.bool(forKey: migrationKey) else { return }
        for (action, oldKey, replacement) in [
            (Action.region, UInt32(kVK_ANSI_2), Shortcut.defaultRegion),
            (Action.recording, UInt32(kVK_ANSI_5), Shortcut.defaultRecording)
        ] {
            let key = "bs_hotkey_\(action.rawValue)"
            guard let data = defaults.data(forKey: key),
                  var saved = try? JSONDecoder().decode(Shortcut.self, from: data),
                  saved.keyCode == oldKey, saved.modifiers == replacement.modifiers else { continue }
            saved.keyCode = replacement.keyCode
            if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key) }
        }
        defaults.set(true, forKey: migrationKey)
    }

    // MARK: - Accessibility Permission

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    nonisolated static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Event Tap Callback

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Re-enable the tap if macOS disables it
            Task { @MainActor in
                if let tap = ShortcutService.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        var carbonMods: UInt32 = 0
        if flags.contains(.maskCommand) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { carbonMods |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.maskControl) { carbonMods |= UInt32(controlKey) }

        // The tap runs on the main run loop. Editor bindings take precedence
        // over global captures (e.g. Copy Image and Pick Color both used ⌘⇧C).
        let passesToEditor = MainActor.assumeIsolated {
            let service = ShortcutService.shared
            if service.isRecordingShortcut { return true }
            guard NSApp.isActive, let window = NSApp.keyWindow else { return false }
            if window.attachedSheet != nil || window.sheetParent != nil { return true }
            guard let scope = service.scope(for: window) else { return false }
            return service.action(keyCode: keyCode, modifiers: carbonMods, scope: scope) != nil
        }
        if passesToEditor { return Unmanaged.passUnretained(event) }

        for (action, shortcut) in cachedShortcuts {
            if keyCode == shortcut.keyCode && carbonMods == shortcut.modifiers {
                // Holding a shortcut must not queue repeated captures or confirmations.
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    Task { @MainActor in await ShortcutService.shared.performGlobal(action) }
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

extension ShortcutService.Shortcut {
    /// Modifiers in the order macOS renders them: control, option, shift, command.
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    /// Spelled out for VoiceOver, which reads the symbol glyphs as nothing.
    var accessibilityDescription: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    static func keyName(for code: UInt32) -> String {
        let map: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F",
            0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
            0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
            0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
            0x1C: "8", 0x19: "9", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I",
            0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K",
            0x2C: "/", 0x2D: "N", 0x2E: "M",
            0x18: "=", 0x1B: "−", 0x27: "'", 0x29: ";", 0x2A: "\\",
            0x2B: ",", 0x2F: ".", 0x32: "`", 0x31: "Space",
            0x24: "Return", 0x30: "Tab", 0x33: "Delete", 0x35: "Escape",
            0x75: "Forward Delete", 0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
            0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        return map[code] ?? "Key \(code)"
    }
}

extension ShortcutService {
    func help(_ title: String, for action: Action?) -> String {
        let _ = revision
        guard let action, let shortcut = effectiveShortcut(for: action) else { return title }
        return "\(title) (\(shortcut.displayString))"
    }

    func effectiveShortcut(for action: Action) -> Shortcut? {
        guard let shortcut = loadShortcut(for: action) ?? action.defaultShortcut, shortcut.enabled else { return nil }
        return shortcut
    }

    func resetShortcut(for action: Action) {
        defaults.removeObject(forKey: "bs_hotkey_\(action.rawValue)")
        revision &+= 1
        if self === Self.shared { Self.cacheShortcuts() }
    }

    func restoreDefaults() {
        Action.allCases.forEach { resetShortcut(for: $0) }
    }

    func action(keyCode: UInt32, modifiers: UInt32, scope: Scope) -> Action? {
        let candidates = Action.allCases.filter { $0.scope == scope }
        if let exact = candidates.first(where: {
            guard let shortcut = effectiveShortcut(for: $0) else { return false }
            return shortcut.keyCode == keyCode && shortcut.modifiers == modifiers
        }) { return exact }
        // Preserve the old alternate Delete and ⌘+ spellings only while their
        // original binding remains in use; a custom binding replaces them too.
        for action in candidates {
            guard let shortcut = effectiveShortcut(for: action), shortcut == action.defaultShortcut else { continue }
            if (action == .imageDelete || action == .videoDelete), keyCode == UInt32(kVK_ForwardDelete), modifiers == 0 { return action }
            if (action == .imageZoomIn || action == .videoZoomIn), keyCode == UInt32(kVK_ANSI_Equal), modifiers == UInt32(cmdKey | shiftKey) { return action }
        }
        return nil
    }

    func validationError(for shortcut: Shortcut, action: Action) -> String? {
        guard shortcut.enabled else { return nil }
        if shortcut.keyCode == UInt32(kVK_Escape) || shortcut.keyCode == UInt32(kVK_Tab)
            || shortcut.keyCode == UInt32(kVK_Return) {
            return "Tab, Return, and Escape are reserved for navigation and dialogs."
        }
        if action.scope == .global && shortcut.modifiers & UInt32(cmdKey | controlKey | optionKey) == 0 {
            return "Global shortcuts need Command, Control, or Option."
        }
        let reserved: [UInt32] = [UInt32(kVK_ANSI_Q), UInt32(kVK_ANSI_W), UInt32(kVK_ANSI_H), UInt32(kVK_ANSI_M), UInt32(kVK_ANSI_Comma)]
        if shortcut.modifiers == UInt32(cmdKey), reserved.contains(shortcut.keyCode) {
            return "This shortcut is reserved for standard macOS window and app commands."
        }
        if let conflict = Action.allCases.first(where: {
            guard $0 != action, $0.scope == action.scope, let other = effectiveShortcut(for: $0) else { return false }
            return other.keyCode == shortcut.keyCode && other.modifiers == shortcut.modifiers
        }) {
            return "Already assigned to \(conflict.title). Clear or change that shortcut first."
        }
        return nil
    }
}

extension ShortcutService.Shortcut {
    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }
}
