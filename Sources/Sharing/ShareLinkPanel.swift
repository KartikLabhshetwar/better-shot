import AppKit
import SwiftUI

/// Shows a finished share link instead of only announcing that it was copied: the URL stays on screen, selectable, until it is dismissed.
@MainActor
final class ShareLinkPanel {
    static let shared = ShareLinkPanel()

    private var panel: NSPanel?

    private init() {}

    func present(url: URL, title: String) {
        close()

        let panel = ShareLinkWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 460, height: 240)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(
            rootView: ShareLinkCard(url: url, title: title) { [weak self] in self?.close() }
        )
        hosting.setFrameSize(hosting.fittingSize)
        panel.setContentSize(hosting.fittingSize)
        panel.contentView = hosting

        position(panel, over: NSApp.keyWindow ?? NSApp.mainWindow)

        AppActivationPolicy.enter()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        AppActivationPolicy.leave()
    }

    /// The link belongs to the window the share started from, so it arrives there instead of at the top of whichever screen is main.
    private func position(_ panel: NSPanel, over anchorWindow: NSWindow?) {
        let screen = anchorWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        let anchor = anchorWindow?.frame ?? visible
        let size = panel.frame.size
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(anchor.maxY - size.height - 8, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Borderless panels refuse key focus by default, which would leave the link unselectable and escape dead.
private final class ShareLinkWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private enum ShareLinkMotion {
    static var enter: Animation {
        RecordingMotion.reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.42, bounce: 0)
    }

    static var exit: Animation {
        RecordingMotion.reduceMotion ? .easeIn(duration: 0.12) : .spring(duration: 0.26, bounce: 0)
    }

    static var swap: Animation {
        RecordingMotion.reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0)
    }
}

private struct ShareLinkCard: View {
    let url: URL
    let title: String
    let onClose: () -> Void

    @State private var isPresented = false
    @State private var didCopy = false
    @State private var copyReset: Task<Void, Never>?

    private var reduceMotion: Bool { RecordingMotion.reduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            linkField
            actions
        }
        .padding(18)
        .frame(width: 424, alignment: .leading)
        .glassSurface(cornerRadius: 20, depth: .floating)
        .padding(18)
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (isPresented ? 1 : 0.94), anchor: .top)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : -12))
        .blur(radius: reduceMotion ? 0 : (isPresented ? 0 : 14))
        .onAppear { withAnimation(ShareLinkMotion.enter) { isPresented = true } }
        .onEscapeKey { dismiss(); return true }
        .onDisappear { copyReset?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor.gradient))

            VStack(alignment: .leading, spacing: 1) {
                Text("Link Ready")
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(ShareLinkPressStyle(scale: 0.88))
            .accessibilityLabel("Dismiss")
        }
    }

    private var linkField: some View {
        Text(url.absoluteString)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(GlassPalette.edge, lineWidth: 0.5)
            )
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.open(url)
                dismiss()
            } label: {
                Text("Open")
                    .font(.system(size: 12, weight: .medium))
                    .frame(height: 28)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(ShareLinkPressStyle(scale: 0.97))

            Spacer(minLength: 0)

            Button(action: copy) {
                HStack(spacing: 6) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(didCopy ? "Copied" : "Copy Link")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(height: 28)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(didCopy ? Color.green.gradient : Color.accentColor.gradient)
                )
            }
            .buttonStyle(ShareLinkPressStyle(scale: 0.97))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        withAnimation(ShareLinkMotion.swap) { didCopy = true }
        copyReset?.cancel()
        copyReset = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(ShareLinkMotion.swap) { didCopy = false }
        }
    }

    private func dismiss() {
        withAnimation(ShareLinkMotion.exit) { isPresented = false }
        Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            onClose()
        }
    }
}

/// Presses answer on pointer-down and settle critically damped, so the card feels attached to the cursor.
private struct ShareLinkPressStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(RecordingMotion.reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(RecordingMotion.pressRelease, value: configuration.isPressed)
    }
}
