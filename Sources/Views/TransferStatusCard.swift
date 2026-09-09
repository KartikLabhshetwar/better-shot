import AppKit
import SwiftUI

enum TransferStatus: Equatable {
    case working(stage: TransferStage, progress: Double?)
    case linkReady(url: URL)
    case exported(url: URL)
    case failed(headline: String, message: String, canRetry: Bool)
}

struct TransferStage: Equatable {
    let label: String
    let icon: String

    static let rendering = TransferStage(label: "Rendering", icon: "film.stack")
    static let uploading = TransferStage(label: "Uploading", icon: "icloud.and.arrow.up")
    static let exporting = TransferStage(label: "Exporting", icon: "arrow.down.circle")
}

struct TransferStatusCard: View {
    let status: TransferStatus
    var onCancel: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var didCopy = false
    @State private var copyReset: Task<Void, Never>?
    @State private var isHovering = false

    var body: some View {
        Group {
            switch status {
            case .working(let stage, let progress):
                workingRow(stage: stage, progress: progress.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil })
            case .linkReady(let url):
                linkReadyRows(url: url)
            case .exported(let url):
                exportedRow(url: url)
            case .failed(let headline, let message, let canRetry):
                failedRow(headline: headline, message: message, canRetry: canRetry)
            }
        }
        .id(caseKey)
        .transition(.opacity)
        .padding(12)
        .frame(width: 340, height: 88)
        .studioGlass(cornerRadius: 12)
        .animation(RecordingMotion.reduceMotion ? nil : .easeOut(duration: 0.15), value: caseKey)
        .onHover { isHovering = $0 }
        .onChange(of: caseKey) { didCopy = false }
        .task(id: "\(caseKey)-\(isHovering)") {
            guard let delay = autoDismissDelay, !isHovering else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        .onDisappear { copyReset?.cancel() }
    }

    private var caseKey: String {
        switch status {
        case .working: "working"
        case .linkReady: "linkReady"
        case .exported: "exported"
        case .failed: "failed"
        }
    }

    private var autoDismissDelay: Duration? {
        switch status {
        case .linkReady: .seconds(12)
        case .exported: .seconds(6)
        default: nil
        }
    }

    // MARK: Rows

    private func workingRow(stage: TransferStage, progress: Double?) -> some View {
        HStack(spacing: 10) {
            iconTile(systemName: stage.icon, tint: EditorChrome.accent)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    ZStack(alignment: .leading) {
                        Text(stage.label)
                            .font(.system(size: 13, weight: .semibold))
                            .id(stage.label)
                            .transition(.opacity)
                    }
                    .animation(RecordingMotion.reduceMotion ? nil : .easeOut(duration: 0.15), value: stage)

                    Spacer(minLength: 8)

                    if let progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                TransferProgressBar(progress: progress)
            }

            circleButton(help: "Cancel", action: onCancel)
        }
    }

    private func linkReadyRows(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                iconTile(systemName: "checkmark.circle", tint: EditorChrome.accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Link ready")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Copied to your clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                circleButton(help: "Dismiss", action: onDismiss)
            }

            HStack(spacing: 8) {
                Text(url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(GlassPalette.edge, lineWidth: 0.5)
                    )

                quietButton("Open") {
                    NSWorkspace.shared.open(url)
                    onDismiss()
                }

                prominentButton(
                    didCopy ? "Copied" : "Copy",
                    icon: didCopy ? "checkmark" : "doc.on.doc"
                ) {
                    copy(url)
                }
            }
        }
    }

    private func exportedRow(url: URL) -> some View {
        HStack(spacing: 10) {
            iconTile(systemName: "checkmark.circle", tint: EditorChrome.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Export complete")
                    .font(.system(size: 13, weight: .semibold))
                Text(url.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            quietButton("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                onDismiss()
            }
            .help("Show in Finder")

            circleButton(help: "Dismiss", action: onDismiss)
        }
    }

    private func failedRow(headline: String, message: String, canRetry: Bool) -> some View {
        HStack(spacing: 10) {
            iconTile(systemName: "exclamationmark.triangle.fill", tint: .orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(message)
            }

            Spacer(minLength: 8)

            if canRetry {
                prominentButton("Retry", icon: "arrow.clockwise", action: onRetry)
            }

            circleButton(help: "Dismiss", action: onDismiss)
        }
    }

    // MARK: Pieces

    private func iconTile(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName).font(.system(size: 22, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    private func circleButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(TransferPressStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(height: 26)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(TransferPressStyle())
    }

    private func prominentButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(height: 26)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
            )
        }
        .buttonStyle(TransferPressStyle())
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        didCopy = true
        copyReset?.cancel()
        copyReset = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}

private struct TransferProgressBar: View {
    let progress: Double?

    var body: some View {
        ProgressView(value: progress, total: 1)
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(EditorChrome.accent)
            .accessibilityLabel("Transfer progress")
            .transaction { $0.animation = nil }
    }
}

private struct TransferPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(RecordingMotion.reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Hosts the existing card outside the editor, at the shared screen-toast position.
struct TransferToast: NSViewRepresentable {
    let status: TransferStatus?
    var onCancel: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void = {}

    func makeNSView(context: Context) -> TransferToastAnchorView {
        TransferToastAnchorView(frame: .zero)
    }

    func updateNSView(_ view: TransferToastAnchorView, context: Context) {
        view.update(card: status.map {
            TransferStatusCard(status: $0, onCancel: onCancel, onRetry: onRetry, onDismiss: onDismiss)
        })
    }

    static func dismantleNSView(_ view: TransferToastAnchorView, coordinator: ()) {
        view.update(card: nil)
        NotificationCenter.default.removeObserver(view)
    }
}

@MainActor
final class TransferToastAnchorView: NSView {
    private var card: TransferStatusCard?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TransferStatusCard>?

    func update(card: TransferStatusCard?) {
        self.card = card
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            for name in [NSWindow.didChangeScreenNotification, NSWindow.didEnterFullScreenNotification,
                         NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: window)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(ownerClosed),
                name: NSWindow.willCloseNotification, object: window)
        }
        refresh()
    }

    @objc private func ownerClosed() {
        update(card: nil)
    }

    @objc private func refresh() {
        guard let card, let window, window.isVisible, let screen = window.screen else {
            panel?.orderOut(nil)
            panel?.contentView = nil
            hostingView = nil
            panel = nil
            return
        }
        if let hostingView {
            hostingView.rootView = card
        } else {
            let hostingView = NSHostingView(rootView: card)
            self.hostingView = hostingView
            panel = ToastWindow.makePanel(hostingView: hostingView)
            panel?.identifier = NSUserInterfaceItemIdentifier("BetterShot.TransferToast")
            panel?.title = "Export and sharing status"
        }
        guard let panel else { return }
        panel.appearance = window.appearance
        panel.setFrameOrigin(ToastWindow.origin(for: panel.frame.size, in: screen.visibleFrame))
        // Progress updates must not raise windows or steal keyboard focus.
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
