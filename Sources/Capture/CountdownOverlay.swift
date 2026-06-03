import AppKit
import SwiftUI

// MARK: - Observable Model

@MainActor
@Observable
final class CountdownModel {
    var currentNumber: Int = 3
    var scale: CGFloat = 1.0
    var opacity: Double = 1.0
}

// MARK: - SwiftUI View

private struct CountdownView: View {
    let model: CountdownModel

    var body: some View {
        ZStack {
            Color.clear

            Text("\(model.currentNumber)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)
                .scaleEffect(model.scale)
                .opacity(model.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

// MARK: - Overlay Controller

@MainActor
final class CountdownOverlay {
    static let shared = CountdownOverlay()

    private var panel: NSPanel?
    private var model: CountdownModel?

    private init() {}

    /// Shows a countdown from `seconds` down to 1, then dismisses the overlay.
    /// Awaits the full countdown before returning so the caller can proceed with capture.
    func showCountdown(seconds: Int) async {
        guard seconds > 0 else { return }

        let countdownModel = CountdownModel()
        self.model = countdownModel

        createPanel(model: countdownModel)
        panel?.orderFront(nil)

        for tick in stride(from: seconds, through: 1, by: -1) {
            // Reset to visible state for this number
            countdownModel.currentNumber = tick
            countdownModel.scale = 1.0
            countdownModel.opacity = 1.0

            // Animate scale-down + fade over 0.8s
            withAnimation(.easeIn(duration: 0.8)) {
                countdownModel.scale = 0.6
                countdownModel.opacity = 0.0
            }

            // Wait the full second before moving to the next tick
            try? await Task.sleep(for: .milliseconds(1000))
        }

        // Brief pause so the last animation has time to complete, then dismiss
        try? await Task.sleep(for: .milliseconds(100))
        dismiss()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    // MARK: - Private

    private func createPanel(model: CountdownModel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame

        let newPanel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        newPanel.hasShadow = false
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.ignoresMouseEvents = true

        let hostingView = NSHostingView(rootView: CountdownView(model: model))
        newPanel.contentView = hostingView

        self.panel = newPanel
    }
}
