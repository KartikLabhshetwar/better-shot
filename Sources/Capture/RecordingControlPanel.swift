import AppKit
import SwiftUI

@MainActor
@Observable
final class RecordingControlPanel {
    static let shared = RecordingControlPanel()

    private var panel: NSPanel?

    private init() {}

    func show() {
        if panel == nil { createPanel() }
        positionPanel()
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 56),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none

        let hostingView = NSHostingView(rootView: RecordingControlView())
        panel.contentView = hostingView

        self.panel = panel
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.minY + 48
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Control Pill SwiftUI View

struct RecordingControlView: View {
    private let recorder = ScreenRecorder.shared
    @State private var dotPulse = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: indicator + timer
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 1, green: 0.23, blue: 0.19))
                    .frame(width: 8, height: 8)
                    .opacity(recorder.state == .paused ? 0.35 : (dotPulse ? 1.0 : 0.6))
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dotPulse)

                Text(recorder.formattedTime)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: 50, alignment: .leading)
            }
            .padding(.leading, 16)

            Spacer(minLength: 8)

            // Separator
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: 22)

            Spacer(minLength: 8)

            // Right: action buttons
            HStack(spacing: 2) {
                controlButton(
                    icon: recorder.state == .paused ? "play.fill" : "pause.fill",
                    color: .white.opacity(0.85)
                ) {
                    if recorder.state == .paused { recorder.resume() }
                    else { recorder.pause() }
                }

                controlButton(icon: "stop.fill", color: Color(red: 1, green: 0.23, blue: 0.19)) {
                    recorder.stop()
                    RecordingControlPanel.shared.hide()
                }

                controlButton(icon: "trash", color: .white.opacity(0.45)) {
                    recorder.discard()
                    RecordingControlPanel.shared.hide()
                }
            }
            .padding(.trailing, 10)
        }
        .frame(height: 40)
        .background(
            Capsule()
                .fill(Color(white: 0.10).opacity(0.92))
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .preferredColorScheme(.dark)
        .onAppear { dotPulse = true }
    }

    private func controlButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .background(
                    Circle()
                        .fill(.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}
