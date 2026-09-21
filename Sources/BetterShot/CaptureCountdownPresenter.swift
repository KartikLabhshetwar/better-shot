//
//  CaptureCountdownPresenter.swift
//  BetterShot
//

import AppKit
import SwiftUI

/// Shows a brief centered countdown before a capture is taken, so the user can
/// arrange hover states, menus, etc. Driven by the `captureDelaySeconds`
/// preference. The overlay is fully torn down before the capture fires, so it
/// never appears in the screenshot.
@MainActor
final class CaptureCountdownPresenter {
    static let shared = CaptureCountdownPresenter()

    private var panel: NSPanel?

    private init() {}

    /// Runs the countdown if `seconds` is positive, otherwise returns
    /// immediately. Shared by screenshots (`captureDelaySeconds`) and
    /// recordings (`recordingStartDelaySeconds`) - callers pass whichever
    /// preference applies.
    func runIfNeeded(seconds: Int, displayID: CGDirectDisplayID?) async {
        guard seconds > 0 else { return }
        await run(seconds: seconds, displayID: displayID)
    }

    private func run(seconds: Int, displayID: CGDirectDisplayID?) async {
        let model = CaptureCountdownModel(remaining: seconds)
        present(model: model, displayID: displayID)

        for value in stride(from: seconds, through: 1, by: -1) {
            model.remaining = value
            try? await Task.sleep(for: .seconds(1))
        }

        dismiss()
        // Give the window server a beat to fully remove the overlay before the
        // capture begins.
        try? await Task.sleep(for: .milliseconds(80))
    }

    private func present(model: CaptureCountdownModel, displayID: CGDirectDisplayID?) {
        dismiss()

        let hostingView = NSHostingView(rootView: CaptureCountdownView(model: model))
        let size = NSSize(width: 160, height: 160)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hostingView
        panel.setFrame(NSRect(origin: centeredOrigin(size: size, displayID: displayID), size: size), display: true)
        panel.orderFrontRegardless()

        self.panel = panel
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func centeredOrigin(size: NSSize, displayID: CGDirectDisplayID?) -> CGPoint {
        let screen = screen(for: displayID) ?? NSScreen.main
        guard let frame = screen?.frame else { return .zero }
        return CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
    }

    private func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
    }
}

@MainActor
@Observable
private final class CaptureCountdownModel {
    var remaining: Int

    init(remaining: Int) {
        self.remaining = remaining
    }
}

private struct CaptureCountdownView: View {
    @State var model: CaptureCountdownModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                )

            Text("\(model.remaining)")
                .font(.system(size: 76, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: model.remaining)
        }
        .frame(width: 160, height: 160)
    }
}
