//
//  PreviewWindowPlacement.swift
//  BetterShot
//
//  Created by Codex on 30/04/26.
//

import AppKit
import CoreGraphics

@MainActor
final class PreviewWindowPlacement {
    static let shared = PreviewWindowPlacement()

    private weak var previewWindow: NSWindow?
    private var targetDisplayID: CGDirectDisplayID?

    private init() {}

    func attach(window: NSWindow?) {
        guard let window else { return }

        previewWindow = window
        configurePreviewWindow(window)
        applyPlacement()
        showAboveActiveSpace()
    }

    func setTargetDisplayID(_ displayID: CGDirectDisplayID?) {
        targetDisplayID = displayID ?? ActiveDisplayResolver.activeDisplayID()
        applyPlacement()
    }

    func applyPlacement() {
        guard let previewWindow,
              let screen = targetScreen() else {
            return
        }

        let targetFrame = screen.visibleFrame.integral
        guard targetFrame.width > 0, targetFrame.height > 0 else { return }

        if previewWindow.frame != targetFrame {
            previewWindow.setFrame(targetFrame, display: previewWindow.isVisible)
        }
    }

    func showAboveActiveSpace() {
        guard let previewWindow else { return }

        configurePreviewWindow(previewWindow)
        applyPlacement()
        previewWindow.orderFrontRegardless()
    }

    func showAboveActiveSpaceAfterOpening() {
        showAboveActiveSpace()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            showAboveActiveSpace()
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            showAboveActiveSpace()
        }
    }

    private func targetScreen() -> NSScreen? {
        ActiveDisplayResolver.screen(for: targetDisplayID)
            ?? ActiveDisplayResolver.activeScreen()
    }

    private func configurePreviewWindow(_ window: NSWindow) {
        window.level = .screenSaver
        window.collectionBehavior.formUnion([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ])
    }
}
