import AppKit
import SwiftUI

/// Window-scoped dispatch shared by editor controls. Text entry and sheets keep
/// native key handling; recording a binding never executes the action being set.
struct EditorShortcutHandler: NSViewRepresentable {
    let scope: ShortcutService.Scope
    var intercept: ((NSEvent) -> Bool)? = nil
    let perform: (ShortcutService.Action) -> Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> EditorShortcutHandlerView {
        let view = EditorShortcutHandlerView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: EditorShortcutHandlerView, context: Context) {
        view.scope = scope
        view.intercept = intercept
        view.perform = perform
        view.isEnabled = isEnabled
        if let window = view.window { ShortcutService.shared.registerScope(scope, for: window) }
    }
}

final class EditorShortcutHandlerView: NSView {
    var service = ShortcutService.shared
    var scope: ShortcutService.Scope = .image
    var intercept: ((NSEvent) -> Bool)?
    var perform: ((ShortcutService.Action) -> Bool)?
    var isEnabled = true
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard let window else { return }
        ShortcutService.shared.registerScope(scope, for: window)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard isEnabled, let window, window.isKeyWindow,
              window.attachedSheet == nil, !service.isRecordingShortcut else { return false }
        let modifiers = ShortcutService.Shortcut.modifiers(from: event.modifierFlags)
        let action = service.action(keyCode: UInt32(event.keyCode), modifiers: modifiers, scope: scope)
        if window.firstResponder is NSTextView {
            guard (action == .imageSave || action == .videoSave), event.modifierFlags.contains(.command) else { return false }
        }
        if intercept?(event) == true { return true }
        guard let action else { return false }
        if event.isARepeat { return true }
        return perform?(action) ?? false
    }
}
