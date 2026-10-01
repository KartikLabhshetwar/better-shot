import AppKit
import Carbon

@main @MainActor
enum ShortcutRecorderFieldCheck {
    static func main() throws {
        _ = NSApplication.shared
        let field = ShortcutRecorderField(frame: NSRect(x: 0, y: 0, width: 124, height: 28))
        var recorded: [(UInt32, NSEvent.ModifierFlags)] = []
        var cleared = 0
        var transitions: [Bool] = []
        field.shortcutDescription = "Command Shift 4"
        field.shortcutLabel = "⌘⇧4"
        field.onRecord = { recorded.append(($0, $1)) }
        field.onClear = {
            cleared += 1
            field.shortcutDescription = "Unassigned"
            field.shortcutLabel = nil
        }
        field.onRecordingChanged = { transitions.append($0) }
        let cell = field.cell as! NSSearchFieldCell
        precondition(field.isBezeled && field.focusRingType == .exterior)
        precondition(cell.searchButtonCell == nil && cell.cancelButtonCell != nil)
        precondition(field.stringValue == "⌘⇧4")

        field.beginRecording()
        precondition(field.handle(event(.flagsChanged, kVK_Command, [.command, .shift])))
        precondition(field.stringValue == "⇧⌘", "Held modifiers must appear in macOS order")
        precondition(recorded.isEmpty)
        precondition(field.handle(event(.keyDown, kVK_ANSI_A, [.command, .shift])))
        precondition(recorded.count == 1 && recorded[0].0 == UInt32(kVK_ANSI_A)
                     && recorded[0].1 == [.command, .shift])
        precondition(!field.isRecording && field.stringValue == "⌘⇧4")

        field.beginRecording()
        precondition(field.handle(event(.keyDown, kVK_Escape)))
        precondition(!field.isRecording && recorded.count == 1 && cleared == 0)
        precondition(field.stringValue == "⌘⇧4", "Cancelling must preserve the old binding")

        field.beginRecording()
        precondition(field.handle(event(.keyDown, kVK_Delete)))
        precondition(cleared == 1 && !field.isRecording && field.stringValue.isEmpty)
        field.beginRecording()
        precondition(field.handle(event(.keyDown, kVK_Delete, [.command])))
        precondition(recorded.count == 2 && recorded[1].0 == UInt32(kVK_Delete)
                     && recorded[1].1 == .command, "Modified Delete must remain bindable")

        field.shortcutLabel = "⌘S"
        precondition(NSApplication.shared.sendAction(cell.cancelButtonCell!.action!,
            to: cell.cancelButtonCell!.target, from: field))
        precondition(cleared == 2 && field.stringValue.isEmpty)

        field.beginRecording()
        precondition(field.handle(event(.keyDown, kVK_ANSI_B, [], repeat: true)))
        precondition(field.isRecording && recorded.count == 2, "Repeat must not commit")
        field.cancelRecording()
        field.cancelRecording()
        precondition(transitions.count % 2 == 0 && transitions.enumerated().allSatisfy { $0.element == ($0.offset % 2 == 0) },
                     "Recording suspension must be balanced on every exit")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = field
        precondition(window.makeFirstResponder(field))
        precondition(field.isRecording, "Keyboard focus must start recording")
        precondition(window.makeFirstResponder(nil))
        precondition(!field.isRecording, "Focus loss must cancel recording")
        field.beginRecording()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        precondition(!field.isRecording, "Leaving the window must restore normal shortcuts")
        field.stopObserving()
        window.close()
        field.frame = NSRect(x: 0, y: 0, width: 124, height: 28)
        let output = URL(fileURLWithPath: ".build/shortcut-recorder-checks", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            field.appearance = NSAppearance(named: name)
            let scheme = name == .aqua ? "light" : "dark"
            field.shortcutLabel = "⌃⌥⇧⌘F20"
            try snapshot(field, to: output.appendingPathComponent("shortcut-\(scheme).png"))
            field.beginRecording()
            _ = field.handle(event(.flagsChanged, kVK_Command, [.control, .option, .shift, .command]))
            try snapshot(field, to: output.appendingPathComponent("modifiers-\(scheme).png"))
            field.cancelRecording()
        }
        print("native bezel/clear, modifier echo, commit, Escape, Delete, repeat, balanced lifecycle, and focus/window cancellation")
    }

    private static func event(_ type: NSEvent.EventType, _ code: Int,
                              _ flags: NSEvent.ModifierFlags = [], repeat repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: repeating, keyCode: UInt16(code))!
    }

    private static func snapshot(_ field: ShortcutRecorderField, to url: URL) throws {
        guard let bitmap = field.bitmapImageRepForCachingDisplay(in: field.bounds) else {
            preconditionFailure("Could not allocate the recorder snapshot")
        }
        field.cacheDisplay(in: field.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
