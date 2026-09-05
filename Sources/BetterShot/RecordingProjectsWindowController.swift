//
//  RecordingProjectsWindowController.swift
//  BetterShot
//
//  Hosts the Projects browser. AppKit-owned for the same reason Settings is:
//  it opens from the menu bar extra, which has no scene of its own to open a
//  SwiftUI window from.
//

import AppKit
import SwiftUI

@MainActor
final class RecordingProjectsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: RecordingProjectsWindowController?
    private var didEnterActivationPolicy = false

    static func show() {
        RecordingProjectStore.shared.reload()

        if shared == nil {
            shared = RecordingProjectsWindowController()
        }

        shared?.showWindow(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 1100, height: 720)),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .miniaturizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        guard let window else { return }

        window.title = "Media Gallery"
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.animationBehavior = .none
        window.isMovableByWindowBackground = false
        window.setFrameAutosaveName("RecordingProjectsWindow")
        window.minSize = NSSize(width: 900, height: 580)
        window.center()
        window.delegate = self

        window.contentViewController = NSHostingController(rootView: MediaGalleryView())
        PreviewWindowCaptureExclusion.shared.register(window: window)
    }

    override func showWindow(_ sender: Any?) {
        guard let window else { return }

        if !didEnterActivationPolicy {
            AppActivationPolicy.enter()
            didEnterActivationPolicy = true
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        let shouldAnimate = !window.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.alphaValue = shouldAnimate ? 0 : 1

        super.showWindow(sender)

        guard shouldAnimate else { return }
        window.displayIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }
    }

    func windowWillClose(_ notification: Notification) {
        if didEnterActivationPolicy {
            AppActivationPolicy.leave()
            didEnterActivationPolicy = false
        }
        Self.shared = nil
    }
}
