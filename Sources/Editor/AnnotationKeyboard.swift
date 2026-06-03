import AppKit
import SwiftUI

struct AnnotationKeyCommandHandler: NSViewRepresentable {
    let onDelete: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSelectAll: () -> Void
    let onSelectTool: (AnnotationTool) -> Void

    func makeNSView(context: Context) -> AnnotationKeyCommandHandlerView {
        let view = AnnotationKeyCommandHandlerView()
        view.onDelete = onDelete
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onSelectAll = onSelectAll
        view.onSelectTool = onSelectTool
        return view
    }

    func updateNSView(_ nsView: AnnotationKeyCommandHandlerView, context: Context) {
        nsView.onDelete = onDelete
        nsView.onUndo = onUndo
        nsView.onRedo = onRedo
        nsView.onSelectAll = onSelectAll
        nsView.onSelectTool = onSelectTool
    }
}

final class AnnotationKeyCommandHandlerView: NSView {
    var onDelete: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onSelectAll: (() -> Void)?
    var onSelectTool: ((AnnotationTool) -> Void)?

    nonisolated(unsafe) private var localKeyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLocalKeyMonitor()
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    private func updateLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else {
                return event
            }

            if Self.isEditingText(in: self.window) {
                return event
            }

            if Self.isPlainDelete(event) {
                self.onDelete?()
                return nil
            }

            if Self.isUndo(event) {
                self.onUndo?()
                return nil
            }

            if Self.isRedo(event) {
                self.onRedo?()
                return nil
            }

            if Self.isSelectAll(event) {
                self.onSelectAll?()
                return nil
            }

            if let tool = Self.toolShortcut(for: event) {
                self.onSelectTool?(tool)
                return nil
            }

            return event
        }
    }

    private static func isPlainDelete(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            && (event.keyCode == 51 || event.keyCode == 117)
    }

    private static func isEditingText(in window: NSWindow?) -> Bool {
        window?.firstResponder is NSTextView
    }

    private static func isUndo(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "z"
    }

    private static func isRedo(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "z"
    }

    private static func isSelectAll(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    private static func toolShortcut(for event: NSEvent) -> AnnotationTool? {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let character = event.charactersIgnoringModifiers?.lowercased(),
              character.count == 1 else {
            return nil
        }

        switch character {
        case "v": return .select
        case "r": return .rectangle
        case "f": return .filledRectangle
        case "o": return .ellipse
        case "l": return .line
        case "a": return .arrow
        case "d": return .freehand
        case "n": return .numberedCircle
        case "p": return .pixelate
        case "b": return .blur
        case "g": return .spotlight
        case "t": return .text
        case "h": return .select
        default: return nil
        }
    }
}
