//
//  PreviewWindowCaptureExclusion.swift
//  BetterShot
//
//  Created by Codex on 27/04/26.
//

import AppKit
import SwiftUI

@MainActor
final class PreviewWindowCaptureExclusion {
    static let shared = PreviewWindowCaptureExclusion()

    /// Whether BetterShot's UI should be available to screenshot and screen
    /// recording APIs. Opt-in via Settings only.
    static var includesAppWindowsInCaptures: Bool {
        BetterShotPreferences.includeAppWindowsInCaptures
    }

    private let registeredWindows = NSHashTable<NSWindow>.weakObjects()

    private init() {}

    /// Registers any BetterShot-owned window whose capture visibility should
    /// follow the production preference.
    func register(window: NSWindow?) {
        guard let window else { return }

        registeredWindows.add(window)
        applyCaptureVisibility(to: window)
    }

    /// Applies a changed Settings value immediately to windows that already
    /// exist, rather than waiting for them to be recreated.
    func refreshRegisteredWindows() {
        for window in registeredWindows.allObjects {
            applyCaptureVisibility(to: window)
        }
    }

    /// Applies capture visibility to the overlay panel and wires it into the
    /// placement manager.
    ///
    /// The overlay no longer hides itself for editors or Quick Look - it stays
    /// mounted and collapses into the peek tab instead (see
    /// `ScreenshotPreviewStack.collapse()`), and the passthrough hosting view
    /// keeps it from intercepting clicks meant for the windows beneath it.
    func attach(window: NSWindow?) {
        guard let window else { return }

        register(window: window)
        PreviewWindowPlacement.shared.attach(window: window)
    }

    private func applyCaptureVisibility(to window: NSWindow) {
        window.sharingType = Self.includesAppWindowsInCaptures ? .readOnly : .none
    }
}

struct PreviewWindowCaptureExclusionView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateWindow(for: view)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindow(for: nsView)
    }
    
    private func updateWindow(for view: NSView) {
        DispatchQueue.main.async {
            PreviewWindowCaptureExclusion.shared.attach(window: view.window)
        }
    }
}
