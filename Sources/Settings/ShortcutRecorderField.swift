import AppKit
import Carbon

@MainActor
final class ShortcutRecorderField: NSSearchField {
    var onRecord: ((UInt32, NSEvent.ModifierFlags) -> Void)?
    var onClear: (() -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var shortcutLabel: String? {
        didSet {
            if !isRecording {
                showShortcut()
            }
        }
    }
    var shortcutDescription = "Unassigned"
    private(set) var isRecording = false
    nonisolated(unsafe) private var eventMonitor: Any?
    nonisolated(unsafe) private var windowObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }

    private func configure() {
        isEditable = false
        isSelectable = false
        alignment = .center
        font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        controlSize = .small
        focusRingType = .exterior
        placeholderString = "Record Shortcut"
        if let cell = cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.cancelButtonCell?.target = self
            cell.cancelButtonCell?.action = #selector(clearShortcut)
            cell.cancelButtonCell?.setAccessibilityLabel("Clear shortcut")
        }
        setAccessibilityHelp("Press to record a shortcut. Escape cancels; Delete clears the shortcut.")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        beginRecording()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        needsDisplay = true
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        if let window {
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelRecording() }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !stringValue.isEmpty, let cell = cell as? NSSearchFieldCell,
           cell.cancelButtonRect(forBounds: bounds).contains(point) {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        beginRecording()
        return true
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        onRecordingChanged?(true)
        showModifiers(NSEvent.modifierFlags)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]) { [weak self] event in
            guard let self else { return event }
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
                if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.cancelRecording()
                }
                return event
            }
            guard self.window?.isKeyWindow == true, self.window?.firstResponder === self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        showShortcut()
        onRecordingChanged?(false)
    }

    func stopObserving() {
        cancelRecording()
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
        windowObserver = nil
    }

    func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.type == .flagsChanged {
            showModifiers(event.modifierFlags)
            return true
        }
        guard event.type == .keyDown else { return false }
        guard !event.isARepeat else { return true }
        let keyCode = UInt32(event.keyCode)
        if keyCode == UInt32(kVK_Escape) {
            cancelRecording()
            return true
        }
        if keyCode == UInt32(kVK_Tab) {
            cancelRecording()
            if event.modifierFlags.contains(.shift) {
                window?.selectPreviousKeyView(self)
            } else {
                window?.selectNextKeyView(self)
            }
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty, keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            clearShortcut()
        } else {
            onRecord?(keyCode, modifiers)
            cancelRecording()
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !handle(event) {
            if event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
                beginRecording()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        _ = handle(event)
    }

    @objc private func clearShortcut() {
        onClear?()
        cancelRecording()
        showShortcut()
    }

    private func showShortcut() {
        stringValue = shortcutLabel ?? ""
        setAccessibilityValue(shortcutDescription)
    }

    private func showModifiers(_ flags: NSEvent.ModifierFlags) {
        let active = [(NSEvent.ModifierFlags.control, "⌃", "Control"), (.option, "⌥", "Option"),
            (.shift, "⇧", "Shift"), (.command, "⌘", "Command")].filter { flags.contains($0.0) }
        stringValue = active.isEmpty ? "Press Shortcut" : active.map(\.1).joined()
        setAccessibilityValue(active.isEmpty ? "Press Shortcut" : active.map(\.2).joined(separator: " "))
    }

}
