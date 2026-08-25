//
//  FailureAlert.swift
//  BetterShot
//
//  One place for "the thing you asked for didn't happen." Background work
//  that fails where no card, badge, or inline message can carry the news
//  used to print to the console, which meant the user clicked a button and
//  simply never found out why nothing arrived.
//

import AppKit

@MainActor
enum FailureAlert {
    /// Cancellation is the user's own doing and never worth an alert.
    static func present(message: String, error: Error, detail: String? = nil) {
        guard !(error is CancellationError) else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = [detail, error.localizedDescription]
            .compactMap { $0 }
            .joined(separator: " ")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
