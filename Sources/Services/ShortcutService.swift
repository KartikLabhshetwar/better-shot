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

    typealias Action = ShortcutAction
    typealias Shortcut = ShortcutDefinition

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
        cachedShortcuts = globalShortcutBindingsForTests()
    }

    static func globalShortcutBindingsForTests(loader: ShortcutLoadClosure? = nil) -> [(Action, Shortcut)] {
        let resolveLoader: ShortcutLoadClosure = loader ?? { action in
            ShortcutService.shared.loadShortcut(for: action)
        }
        return ShortcutBindings.resolveBindings(loadShortcut: resolveLoader)
    }

    static func defaultShortcut(for action: Action) -> Shortcut {
        ShortcutBindings.defaultShortcut(for: action)
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
        let key = ShortcutBindings.key(for: action)
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        }
        Self.cacheShortcuts()
    }

    func loadShortcut(for action: Action) -> Shortcut? {
        let key = ShortcutBindings.key(for: action)
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
                let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                Task { @MainActor in
                    if action == .recording {
                        if ScreenRecordingManager.shared.isRecording {
                            return
                        }
                        let started = try? await ScreenRecordingManager.shared.startRecording()
                        if started == true {
                            RecordingStatusBarController.shared.show(on: mouseScreen)
                        }
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
