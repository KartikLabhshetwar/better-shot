import Carbon
import AppKit
import CoreGraphics

@MainActor
final class ShortcutService {
    static let shared = ShortcutService()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
        static let defaultRepeatRegion = Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey | controlKey), enabled: true)
    }

    enum Action: UInt32, CaseIterable {
        case region = 1
        case fullscreen = 2
        case ocr = 4
        case colorPicker = 5
        case repeatRegion = 7
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
        print("BetterShot: Event tap registered successfully — keyboard shortcuts active")
    }

    func unregisterAll() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
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

        // Convert CGEventFlags to Carbon modifier mask for comparison
        var carbonMods: UInt32 = 0
        if flags.contains(.maskCommand) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { carbonMods |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.maskControl) { carbonMods |= UInt32(controlKey) }

        let service = ShortcutService.shared

        let shortcuts: [(Action, Shortcut)] = [
            (.region, service.loadShortcut(for: .region) ?? .defaultRegion),
            (.fullscreen, service.loadShortcut(for: .fullscreen) ?? .defaultFullscreen),
            (.ocr, service.loadShortcut(for: .ocr) ?? .defaultOCR),
            (.colorPicker, service.loadShortcut(for: .colorPicker) ?? .defaultColorPicker),
            (.repeatRegion, service.loadShortcut(for: .repeatRegion) ?? .defaultRepeatRegion),
        ]

        for (action, shortcut) in shortcuts {
            guard shortcut.enabled else { continue }
            if keyCode == shortcut.keyCode && carbonMods == shortcut.modifiers {
                Task { @MainActor in
                    await CaptureOrchestrator.shared.performCapture(action)
                }
                // Return nil to consume the event — prevents macOS screenshot tool from firing
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
