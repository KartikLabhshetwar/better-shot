//
//  AnnotationEditorActivationPolicy.swift
//  BetterShot
//

import AppKit

/// Manages the app's activation policy so that regular windows (annotation
/// editor, settings) show the Dock icon and appear in Cmd-Tab.  Uses
/// reference counting so the policy stays `.regular` until *all* windows leave.
@MainActor
enum AppActivationPolicy {
    private static var activeWindowCount = 0

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
        NSApp.setActivationPolicy(.regular)
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
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Legacy alias so existing annotation editor callsites still compile.
typealias AnnotationEditorActivationPolicy = AppActivationPolicy
