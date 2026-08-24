import AppKit
import SwiftUI

@MainActor
@Observable
final class CountdownModel {
    var currentNumber: Int = 3
    var scale: CGFloat = 1.0
    var opacity: Double = 1.0
}

private struct CountdownView: View {
    let model: CountdownModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)

            Text("\(model.currentNumber)")
                .font(.system(size: 76, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 156, height: 156)
                .glassSurface(in: Circle(), material: .hudWindow, depth: .floating)
                .scaleEffect(model.scale)
                .opacity(model.opacity)
                .accessibilityLabel("Capturing in \(model.currentNumber) seconds")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

@MainActor
final class CountdownOverlay {
    static let shared = CountdownOverlay()

    private var panel: NSPanel?
    private var model: CountdownModel?

    private init() {}

    /// Counts down from `seconds` to 1 on `screen`, returning once the overlay is gone.
    func showCountdown(seconds: Int, on screen: NSScreen? = nil) async {
        guard seconds > 0 else { return }

        dismiss()

        let countdownModel = CountdownModel()
        self.model = countdownModel

        createPanel(model: countdownModel, on: screen)
        panel?.orderFront(nil)

        let fade = RecordingMotion.reduceMotion
            ? Animation.easeOut(duration: 0.2).delay(0.6)
            : Animation.easeIn(duration: 0.75)

        for tick in stride(from: seconds, through: 1, by: -1) {
            countdownModel.currentNumber = tick
            countdownModel.scale = 1.0
            countdownModel.opacity = 1.0

            withAnimation(fade) {
                countdownModel.scale = RecordingMotion.reduceMotion ? 1.0 : 0.72
                countdownModel.opacity = 0.0
            }

            try? await Task.sleep(for: .milliseconds(1000))
        }

        dismiss()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    private func createPanel(model: CountdownModel, on preferred: NSScreen?) {
        let mouseLocation = NSEvent.mouseLocation
        let target = preferred
            ?? NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = target else { return }

        let newPanel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.ignoresMouseEvents = true

        newPanel.contentView = NSHostingView(rootView: CountdownView(model: model))

        self.panel = newPanel
    }
}
