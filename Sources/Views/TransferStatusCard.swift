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
                workingRow(stage: stage, progress: progress)
            case .linkReady(let url):
                linkReadyRows(url: url)
            case .exported(let url):
                exportedRow(url: url)
            case .failed(let headline, let message, let canRetry):
                failedRow(headline: headline, message: message, canRetry: canRetry)
            }
        }
        .id(caseKey)
        .transition(contentSwap)
        .padding(14)
        .frame(width: 400)
        .glassSurface(cornerRadius: 18, depth: .raised)
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

    private var contentSwap: AnyTransition {
        RecordingMotion.reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }

    private var stageSwap: AnyTransition {
        RecordingMotion.reduceMotion
            ? .opacity
            : AnyTransition(.push(from: .top)).combined(with: .opacity)
    }

    // MARK: Rows

    private func workingRow(stage: TransferStage, progress: Double?) -> some View {
        HStack(spacing: 12) {
            iconTile(systemName: stage.icon, tint: .accentColor)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    ZStack(alignment: .leading) {
                        Text(stage.label)
                            .font(.system(size: 13, weight: .semibold))
                            .id(stage.label)
                            .transition(stageSwap)
                    }
                    .animation(RecordingMotion.showHideSpring, value: stage)

                    Spacer(minLength: 8)

                    if let progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: progress))
                            .animation(.spring(duration: 0.35, bounce: 0), value: progress)
                    }
                }

                TransferProgressBar(progress: progress)
            }

            circleButton(help: "Cancel", action: onCancel)
        }
    }

    private func linkReadyRows(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                iconTile(systemName: "checkmark", tint: .green)

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
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
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
                    icon: didCopy ? "checkmark" : "doc.on.doc",
                    tint: didCopy ? .green : .accentColor
                ) {
                    copy(url)
                }
            }
        }
    }

    private func exportedRow(url: URL) -> some View {
        HStack(spacing: 12) {
            iconTile(systemName: "checkmark", tint: .green)

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
        HStack(spacing: 12) {
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
                prominentButton("Retry", icon: "arrow.clockwise", tint: .accentColor, action: onRetry)
            }

            circleButton(help: "Dismiss", action: onDismiss)
        }
    }

    // MARK: Pieces

    private func iconTile(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                    .fill(tint.gradient)
            )
            .contentTransition(.symbolEffect(.replace))
            .animation(RecordingMotion.showHideSpring, value: systemName)
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
        .buttonStyle(TransferPressStyle(scale: 0.88))
        .help(help)
        .accessibilityLabel(help)
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(height: 30)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(TransferPressStyle(scale: 0.97))
    }

    private func prominentButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(height: 30)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.gradient)
            )
        }
        .buttonStyle(TransferPressStyle(scale: 0.97))
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        withAnimation(RecordingMotion.pressRelease) { didCopy = true }
        copyReset?.cancel()
        copyReset = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(RecordingMotion.pressRelease) { didCopy = false }
        }
    }
}

private struct TransferProgressBar: View {
    let progress: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))

                if let progress {
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: max(6, proxy.size.width * min(max(progress, 0), 1)))
                } else if RecordingMotion.reduceMotion {
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: proxy.size.width * 0.35)
                } else {
                    TimelineView(.animation) { context in
                        let cycle = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.4) / 1.4
                        let eased = cycle * cycle * (3 - 2 * cycle)
                        Capsule()
                            .fill(Color.accentColor.gradient)
                            .frame(width: proxy.size.width * 0.35)
                            .offset(x: proxy.size.width * 1.35 * eased - proxy.size.width * 0.35)
                    }
                }
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .animation(.spring(duration: 0.35, bounce: 0), value: progress)
    }
}

private struct TransferPressStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(RecordingMotion.reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(RecordingMotion.pressRelease, value: configuration.isPressed)
    }
}
