import Carbon
import AppKit

/// Manages global keyboard shortcuts via Carbon API.
@MainActor
final class ShortcutService {
    static let shared = ShortcutService()

    private var hotkeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    private init() {}

    // MARK: - Shortcut Definition

    struct Shortcut: Codable, Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var enabled: Bool

        static let defaultRegion = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
        static let defaultFullscreen = Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey), enabled: false)
        static let defaultWindow = Shortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey), enabled: false)
        static let defaultOCR = Shortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | shiftKey), enabled: false)
    }

    enum Action: UInt32, CaseIterable {
        case region = 1
        case fullscreen = 2
        case window = 3
        case ocr = 4
    }

    // MARK: - Registration

    func registerAll() {
        unregisterAll()

        let shortcuts: [(Action, Shortcut)] = [
            (.region, loadShortcut(for: .region) ?? .defaultRegion),
            (.fullscreen, loadShortcut(for: .fullscreen) ?? .defaultFullscreen),
            (.window, loadShortcut(for: .window) ?? .defaultWindow),
            (.ocr, loadShortcut(for: .ocr) ?? .defaultOCR),
        ]

        installHandler()

        for (action, shortcut) in shortcuts {
            guard shortcut.enabled else { continue }
            register(action: action, shortcut: shortcut)
        }
    }

    func unregisterAll() {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
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

    // MARK: - Private

    private func register(action: Action, shortcut: Shortcut) {
        let signature = OSType(0x4253_4854) // "BSHT"
        var hotkeyID = EventHotKeyID(signature: signature, id: action.rawValue)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref {
            hotkeyRefs.append(ref)
        }
    }

    private func installHandler() {
        guard handlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            guard status == noErr else { return status }

            Task { @MainActor in
                guard let action = Action(rawValue: hotkeyID.id) else { return }
                await CaptureOrchestrator.shared.performCapture(action)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            nil,
            &handlerRef
        )
    }
}
