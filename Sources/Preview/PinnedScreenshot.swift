import AppKit
import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

enum PinnedMedia {
    case image(NSImage)
    case video(url: URL, player: AVQueuePlayer, looper: AVPlayerLooper, size: CGSize)

    var size: CGSize {
        switch self {
        case .image(let image): image.size
        case .video(_, _, _, let size): size
        }
    }
}

// MARK: - PinnedScreenshotController

/// Manages multiple pinned screenshot floating windows.
@MainActor
final class PinnedScreenshotController {
    static let shared = PinnedScreenshotController()
    private var panels: [NSPanel] = []
    private init() {}

    var hasPinnedWindows: Bool {
        !panels.isEmpty
    }

    /// Grows or shrinks a panel from its top-left corner, so scroll-zooming does not walk the window down the screen.
    nonisolated static func anchoredFrame(_ frame: CGRect, resizedTo newSize: CGSize) -> CGRect {
        CGRect(
            x: frame.minX,
            y: frame.maxY - newSize.height,
            width: newSize.width,
            height: newSize.height
        )
    }

    /// Creates a new borderless, always-on-top floating panel showing the capture at `url`.
    func pin(url: URL, on preferredScreen: NSScreen? = nil) {
        let isVideo = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
        guard isVideo else {
            if let image = NSImage(contentsOf: url) { pin(.image(image), on: preferredScreen) }
            return
        }
        Task { @MainActor in
            guard let media = await Self.loadVideo(url) else { return }
            pin(media, on: preferredScreen)
        }
    }

    private static func loadVideo(_ url: URL) async -> PinnedMedia? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform) else {
            return nil
        }
        let rotated = naturalSize.applying(transform)
        let size = CGSize(width: abs(rotated.width), height: abs(rotated.height))
        guard size.width > 0, size.height > 0 else { return nil }
        let player = AVQueuePlayer()
        player.isMuted = true
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        player.play()
        return .video(url: url, player: player, looper: looper, size: size)
    }

    private func pin(_ media: PinnedMedia, on preferredScreen: NSScreen?) {
        // Compute initial panel size: scale to max 400pt on longest side.
        let maxSide: CGFloat = 400
        let imgSize = media.size
        let scale: CGFloat
        if imgSize.width >= imgSize.height {
            scale = min(maxSide / imgSize.width, 1)
        } else {
            scale = min(maxSide / imgSize.height, 1)
        }
        let panelSize = CGSize(
            width: max(imgSize.width * scale, 80),
            height: max(imgSize.height * scale, 60)
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
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

        let contentView = PinnedScreenshotView(
            media: media,
            originalDisplaySize: panelSize,
            onClose: { [weak self, weak panel] in
                guard let self, let panel else { return }
                panel.orderOut(nil)
                self.panels.removeAll { $0 === panel }
            },
            onResize: { [weak panel] newSize in
                guard let panel else { return }
                panel.setFrame(Self.anchoredFrame(panel.frame, resizedTo: newSize), display: true, animate: false)
            }
        )
        panel.contentView = NSHostingView(rootView: contentView)

        if let screen = preferredScreen ?? NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.midX - panelSize.width / 2 + CGFloat(panels.count) * 20
            let y = sf.midY - panelSize.height / 2 - CGFloat(panels.count) * 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panels.append(panel)
        panel.orderFront(nil)
    }

    /// Closes all pinned panels.
    func unpinAll() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

// MARK: - PinnedScreenshotView

/// SwiftUI content view for a single pinned screenshot panel.
struct PinnedScreenshotView: View {
    let media: PinnedMedia
    let originalDisplaySize: CGSize
    let onClose: () -> Void
    let onResize: (CGSize) -> Void

    @State private var scaleFactor: CGFloat = 1.0
    @State private var isHovered: Bool = false

    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 4.0

    var body: some View {
        let w = originalDisplaySize.width * scaleFactor
        let h = originalDisplaySize.height * scaleFactor

        ZStack(alignment: .topTrailing) {
            mediaView
                .frame(width: w, height: h)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

            // Close (X) button — visible on hover
            if isHovered {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .padding(4)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(width: w, height: h)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        // Resize via scroll wheel
        .onScrollWheel { delta in
            let newScale = (scaleFactor + delta * 0.05).clamped(to: minScale...maxScale)
            scaleFactor = newScale
            onResize(CGSize(width: originalDisplaySize.width * newScale,
                            height: originalDisplaySize.height * newScale))
        }
        // Right-click context menu
        .contextMenu {
            Button(copyTitle) {
                let pb = NSPasteboard.general
                pb.clearContents()
                switch media {
                case .image(let image): pb.writeObjects([image])
                case .video(let url, _, _, _): pb.writeObjects([url as NSURL])
                }
            }
            Button("Close", action: close)
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        switch media {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        case .video(_, let player, _, _):
            PassthroughPlayerView(player: player)
        }
    }

    private var copyTitle: String {
        if case .video = media { return "Copy Video" }
        return "Copy Image"
    }

    private func close() {
        if case .video(_, let player, _, _) = media { player.pause() }
        onClose()
    }
}

// MARK: - Video surface

/// Draws the looping player while staying invisible to hit-testing, so hover,
/// scroll-zoom, drag-to-move and the context menu keep working like the image pin.
private struct PassthroughPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = _PassthroughAVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private final class _PassthroughAVPlayerView: AVPlayerView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Scroll-wheel modifier

private struct ScrollWheelModifier: ViewModifier {
    let handler: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelView(handler: handler)
        )
    }
}

private struct ScrollWheelView: NSViewRepresentable {
    let handler: (CGFloat) -> Void

    func makeNSView(context: Context) -> _ScrollWheelNSView {
        let v = _ScrollWheelNSView()
        v.handler = handler
        return v
    }

    func updateNSView(_ nsView: _ScrollWheelNSView, context: Context) {
        nsView.handler = handler
    }
}

final class _ScrollWheelNSView: NSView {
    var handler: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.deltaY
        handler?(delta)
    }
}

private extension View {
    func onScrollWheel(_ handler: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(handler: handler))
    }
}

// MARK: - Comparable clamped helper (local, no collision risk)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
