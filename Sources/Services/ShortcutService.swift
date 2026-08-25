import Carbon
import AppKit
import CoreGraphics

@MainActor
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

    private init() {}

    // MARK: - Shortcut Definition

    struct Shortcut: Codable, Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var enabled: Bool

        static let defaultRegion = Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultFullscreen = Shortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultOCR = Shortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultColorPicker = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultRecording = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
    }

    enum Action: UInt32, CaseIterable {
        case region = 1
        case fullscreen = 2
        case window = 3
        case ocr = 4
        case colorPicker = 5
        case recording = 6
    }

    // MARK: - Registration (CGEvent tap — intercepts system shortcuts)

    func registerAll() {
        unregisterAll()

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
        cachedShortcuts = [
            (.region, service.loadShortcut(for: .region) ?? .defaultRegion),
            (.fullscreen, service.loadShortcut(for: .fullscreen) ?? .defaultFullscreen),
            (.ocr, service.loadShortcut(for: .ocr) ?? .defaultOCR),
            (.colorPicker, service.loadShortcut(for: .colorPicker) ?? .defaultColorPicker),
            (.recording, service.loadShortcut(for: .recording) ?? .defaultRecording),
        ]
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
            UserDefaults.standard.set(data, forKey: key)
        }
        Self.cacheShortcuts()
    }

    func loadShortcut(for action: Action) -> Shortcut? {
        let key = "bs_hotkey_\(action.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
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

        for (action, shortcut) in cachedShortcuts {
            guard shortcut.enabled else { continue }
            if keyCode == shortcut.keyCode && carbonMods == shortcut.modifiers {
                let pointerLocation = event.location
                Task { @MainActor in
                    let mouseScreen = ActiveDisplayResolver.screen(containingQuartzPoint: pointerLocation)
                    if action == .recording {
                        guard !ScreenRecordingManager.shared.isRecording else { return }
                        RecordingBarPresenter.shared.togglePicker(on: mouseScreen)
                    } else {
                        await CaptureOrchestrator.shared.performCapture(action, on: mouseScreen)
                    }
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

extension ShortcutService.Action {
    var defaultShortcut: ShortcutService.Shortcut? {
        switch self {
        case .region: .defaultRegion
        case .fullscreen: .defaultFullscreen
        case .ocr: .defaultOCR
        case .colorPicker: .defaultColorPicker
        case .recording: .defaultRecording
        case .window: nil
        }
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
        ]
        return map[code] ?? "?"
    }
}

extension ShortcutService {
    func effectiveShortcut(for action: Action) -> Shortcut? {
        guard let shortcut = loadShortcut(for: action) ?? action.defaultShortcut, shortcut.enabled else { return nil }
        return shortcut
    }

    func restoreDefaults() {
        for action in Action.allCases {
            guard let fallback = action.defaultShortcut else { continue }
            saveShortcut(fallback, for: action)
        }
        registerAll()
    }
}
