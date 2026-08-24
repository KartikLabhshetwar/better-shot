import AppKit
import SwiftUI

@MainActor
@Observable
final class CountdownModel {
    var currentNumber: Int = 3
    var totalSeconds: Double = 3
    var remainingFraction: Double = 1
    var isPresented = false
}

private struct CountdownView: View {
    let model: CountdownModel

    private let diameter: CGFloat = 152

    var body: some View {
        ZStack {
            Color.black.opacity(model.isPresented ? 0.1 : 0)

            dial
                .scaleEffect(model.isPresented ? 1 : 0.82)
                .opacity(model.isPresented ? 1 : 0)
                .blur(radius: model.isPresented ? 0 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(RecordingMotion.reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.78), value: model.isPresented)
        .onAppear {
            model.isPresented = true
            guard !RecordingMotion.reduceMotion else { return }
            withAnimation(.linear(duration: model.totalSeconds)) { model.remainingFraction = 0 }
        }
    }

    private var dial: some View {
        Text("\(model.currentNumber)")
            .font(.system(size: 68, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .foregroundStyle(Color(nsColor: .labelColor))
            .frame(width: diameter, height: diameter)
            .glassSurface(in: Circle(), depth: .floating)
            .overlay(track)
            .overlay(sweep)
            .accessibilityLabel("Starting in \(model.currentNumber) seconds")
    }

    private var track: some View {
        Circle()
            .inset(by: 5)
            .stroke(Color(nsColor: .labelColor).opacity(0.12), lineWidth: 5)
    }

    private var sweep: some View {
        Circle()
            .inset(by: 5)
            .trim(from: 0, to: model.remainingFraction)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .shadow(color: Color.accentColor.opacity(0.45), radius: 6)
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
        countdownModel.currentNumber = seconds
        countdownModel.totalSeconds = Double(seconds)
        self.model = countdownModel

        createPanel(model: countdownModel, on: screen)
        panel?.orderFront(nil)

        for tick in stride(from: seconds, through: 1, by: -1) {
            withAnimation(RecordingMotion.reduceMotion ? nil : .snappy(duration: 0.3)) {
                countdownModel.currentNumber = tick
            }
            try? await Task.sleep(for: .milliseconds(1000))
        }

        withAnimation(RecordingMotion.reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.9)) {
            countdownModel.isPresented = false
        }
        try? await Task.sleep(for: .milliseconds(RecordingMotion.reduceMotion ? 110 : 220))

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
