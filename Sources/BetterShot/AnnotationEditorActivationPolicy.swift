//
//  AnnotationEditorActivationPolicy.swift
//  BetterShot
//

import AppKit

/// Keeps Dock visibility consistent across launch, settings, and every editor.
@MainActor
enum AppActivationPolicy {
    private static var activeWindowCount = 0

    static func applyVisibility() {
        let visibility = AppPreferences.visibility()
        NSApp.setActivationPolicy(visibility.dock ? .regular : .accessory)
        MenuBarPopoverController.shared.setVisible(visibility.menuBar)
    }

    /// Call when a regular window (annotation editor, video editor, settings, etc.) appears.
    /// Pass `hidePreview: true` for editing flows launched from the preview panel.
    static func enter(hidePreview: Bool = false) {
        activeWindowCount += 1
        if hidePreview {
            // The overlay stays on screen but tucks into the peek tab so it
            // doesn't sit on top of the editor. The panel is never ordered out,
            // so there's no show/hide race when the editor closes.
            ScreenshotPreviewStack.shared.collapse()
        }
        applyVisibility()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call when a regular window closes.
    /// Pass `restorePreview: true` for editing flows launched from the preview panel.
    static func leave(restorePreview: Bool = false) {
        activeWindowCount = max(0, activeWindowCount - 1)
        guard activeWindowCount == 0 else { return }

        if restorePreview {
            ScreenshotPreviewStack.shared.expand()
        }

        Task { @MainActor in
            guard activeWindowCount == 0 else { return }
            applyVisibility()
        }
    }
}

/// Legacy alias so existing annotation editor callsites still compile.
typealias AnnotationEditorActivationPolicy = AppActivationPolicy
