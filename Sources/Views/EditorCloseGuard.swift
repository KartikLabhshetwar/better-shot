import AppKit
import SwiftUI

/// Lets an editor window's close button ask before it throws unsaved edits away, which `NSWindow` only does for itself when a document backs it.
@MainActor
final class EditorCloseGuard {
    static let shared = EditorCloseGuard()

    private var registrations: [ObjectIdentifier: () -> Bool] = [:]

    private init() {}

    func register(_ window: NSWindow, shouldClose: @escaping () -> Bool) {
        registrations[ObjectIdentifier(window)] = shouldClose
    }

    func unregister(_ window: NSWindow) {
        registrations.removeValue(forKey: ObjectIdentifier(window))
    }

    func shouldClose(_ window: NSWindow) -> Bool {
        registrations[ObjectIdentifier(window)]?() ?? true
    }
}

private struct EditorCloseGuardModifier: ViewModifier {
    let window: NSWindow?
    let hasEdits: Bool
    let willClose: (() -> Void)?
    let confirmDiscard: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { register() }
            .onChange(of: window) { _, _ in register() }
            .onChange(of: hasEdits) { _, _ in register() }
            .onDisappear { if let window { EditorCloseGuard.shared.unregister(window) } }
    }

    @MainActor
    private func register() {
        guard let window else { return }
        window.isDocumentEdited = hasEdits
        EditorCloseGuard.shared.register(window) {
            guard hasEdits else {
                willClose?()
                return true
            }
            confirmDiscard()
            return false
        }
    }
}

extension View {
    /// Shows the standard unsaved dot in the close button and diverts a close into `confirmDiscard` while edits are pending. `willClose` runs on the closes that are allowed through, which is the last chance to keep anything the window is about to drop.
    func editorCloseGuard(
        window: NSWindow?,
        hasEdits: Bool,
        willClose: (() -> Void)? = nil,
        confirmDiscard: @escaping () -> Void
    ) -> some View {
        modifier(EditorCloseGuardModifier(
            window: window,
            hasEdits: hasEdits,
            willClose: willClose,
            confirmDiscard: confirmDiscard
        ))
    }
}
