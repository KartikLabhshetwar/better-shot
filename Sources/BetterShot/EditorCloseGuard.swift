//
//  EditorCloseGuard.swift
//  BetterShot
//
//  Closing an editor window with uncommitted edits asks first - Studio and
//  the annotation editor both use this. SwiftUI has no
//  `windowShouldClose` hook, so this installs itself as the window delegate
//  and forwards every other message to the delegate SwiftUI already set -
//  taking over the window outright would break scene teardown.
//

import AppKit

@MainActor
final class EditorCloseGuard: NSObject, NSWindowDelegate {
    enum Decision {
        case save
        case discard
        case delete
        case cancel
    }

    /// Nothing to ask about when this is false.
    var hasUnsavedChanges: () -> Bool = { false }
    /// Only a project that was never saved offers "Delete and close":
    /// discarding a project the user already committed to is unrecoverable,
    /// so that case reverts to the saved state instead.
    var offersDelete: () -> Bool = { false }
    var projectName: () -> String = { "" }
    var onDecision: (Decision, @escaping () -> Void) -> Void = { _, done in done() }

    private weak var attachedWindow: NSWindow?
    private nonisolated(unsafe) weak var previousDelegate: NSWindowDelegate?
    private var isPrompting = false
    private var isCloseApproved = false

    func attach(to window: NSWindow?) {
        guard let window else {
            detach()
            return
        }
        guard window !== attachedWindow else { return }
        detach()
        attachedWindow = window
        previousDelegate = window.delegate
        window.delegate = self
    }

    func detach() {
        if let attachedWindow, attachedWindow.delegate === self {
            attachedWindow.delegate = previousDelegate
        }
        attachedWindow = nil
        previousDelegate = nil
    }

    /// Mirrors the dirty state onto the close button's dot, so the prompt is
    /// never the first hint that something is unsaved.
    func refreshDocumentEdited() {
        attachedWindow?.isDocumentEdited = hasUnsavedChanges()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isCloseApproved { return true }
        guard hasUnsavedChanges() else { return true }
        guard !isPrompting else { return false }

        isPrompting = true
        present(on: sender)
        return false
    }

    private func present(on window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = offersDelete()
            ? "Do you want to save your project before closing or delete it?"
            : "Do you want to save the changes to “\(projectName())”?"
        alert.informativeText = offersDelete()
            ? "This recording has never been saved. Deleting it removes the footage as well."
            : "Your changes since the last save will be lost if you don't save them."

        alert.addButton(withTitle: "Save and Close")
        alert.addButton(withTitle: offersDelete() ? "Delete and Close" : "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        // Escape and ⌘. land on Cancel rather than destroying anything.
        alert.buttons[2].keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isPrompting = false

            let decision: Decision
            switch response {
            case .alertFirstButtonReturn:
                decision = .save
            case .alertSecondButtonReturn:
                decision = self.offersDelete() ? .delete : .discard
            default:
                decision = .cancel
            }

            guard decision != .cancel else { return }

            self.onDecision(decision) { [weak self, weak window] in
                guard let self, let window else { return }
                // Deleting already tore the project down; either way the
                // window is now free to go.
                self.isCloseApproved = true
                window.close()
            }
        }
    }

    // MARK: - Delegate passthrough

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return previousDelegate?.responds(to: aSelector) ?? false
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        previousDelegate
    }
}
