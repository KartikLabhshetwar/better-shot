//
//  TeleprompterComposerPresenter.swift
//  BetterShot
//
//  The small script window opened from the pre-record bar's teleprompter
//  button: paste or type the script, switch the prompter on, and pick how
//  many lines the notch shows at once. Values persist in preferences so a
//  script survives between recordings.
//

import AppKit
import SwiftUI

@MainActor
final class TeleprompterComposerPresenter {
    static let shared = TeleprompterComposerPresenter()

    private var panel: NSPanel?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = TeleprompterComposerPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hostingView = TeleprompterComposerHostingView(rootView: TeleprompterComposerView())
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)

        self.panel = panel
        return panel
    }

    /// Sits just above the pre-record bar when it's on screen; otherwise
    /// falls back to the bar's usual bottom-center spot.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        if let barFrame = RecordingPickerPresenter.shared.barFrame {
            panel.setFrameOrigin(CGPoint(
                x: barFrame.midX - size.width / 2,
                y: barFrame.maxY + 12
            ))
            return
        }

        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
        let screen = ActiveDisplayResolver.screen(for: displayID) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrameOrigin(CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 126
        ))
    }
}

private final class TeleprompterComposerPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        TeleprompterComposerPresenter.shared.hide()
    }
}

private final class TeleprompterComposerHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }
}

// MARK: - View

private struct TeleprompterComposerView: View {
    @AppStorage(BetterShotPreferences.recordingTeleprompterEnabledKey) private var isEnabled = false
    @AppStorage(BetterShotPreferences.recordingTeleprompterScriptKey) private var script = ""
    @AppStorage(BetterShotPreferences.recordingTeleprompterLineCountKey) private var lineCount = 3

    var body: some View {
        VStack(spacing: 10) {
            header
            editor
            footer
        }
        .padding(12)
        .frame(width: 360)
        .background(Color(white: 0.14).opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .onChange(of: isEnabled) { _, enabled in
            if enabled {
                TeleprompterController.shared.preflightAssets()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Teleprompter")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Toggle("Show while recording", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(.green)
                .help(isEnabled
                    ? "Teleprompter will appear in the notch while recording"
                    : "Turn on to show the script in the notch while recording")
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $script)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(6)

            if script.isEmpty {
                Text("Type or paste your script…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 6)
                    .padding(.leading, 11)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 150)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Lines shown")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            ForEach(BetterShotPreferences.teleprompterLineCountRange, id: \.self) { count in
                Button {
                    lineCount = count
                } label: {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(lineCount == count ? .white : .white.opacity(0.45))
                        .frame(width: 28, height: 24)
                        .background(lineCount == count ? Color.white.opacity(0.22) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Show \(count) lines in the notch")
            }
        }
    }
}
