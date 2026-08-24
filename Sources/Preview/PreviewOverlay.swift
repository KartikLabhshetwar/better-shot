import AppKit
import AVFoundation
import SwiftUI

/// Shows a floating preview card after capture. Uses a borderless NSPanel.
@MainActor
@Observable
final class PreviewOverlay {
    static let shared = PreviewOverlay()

    static let panelSize = CGSize(width: 228, height: 208)

    private(set) var currentURL: URL?
    private(set) var isVisible = false
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var targetScreen: NSScreen?

    private init() {}

    func show(url: URL, on screen: NSScreen? = nil) {
        dismissTask?.cancel()
        dismissTask = nil

        currentURL = url
        targetScreen = screen
        isVisible = true

        if panel == nil {
            createPanel()
        }

        positionPanel()
        panel?.orderFront(nil)

        scheduleDismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        panel?.orderOut(nil)
        panel = nil
        isVisible = false
        currentURL = nil
    }

    /// Held open while the pointer is on the card: nothing should vanish out from under someone who is reaching for it.
    func holdOpen() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    func resumeDismiss() {
        scheduleDismiss()
    }

    func deleteCapture() {
        if let url = currentURL {
            if let record = HistoryStore.shared.records.first(where: { HistoryStore.shared.urlForRecord($0) == url }) {
                HistoryStore.shared.deleteRecord(record)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        dismiss()
    }

    func copyCapture() {
        guard let url = currentURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let fullSize = NSImage(contentsOf: url) {
            pasteboard.writeObjects([fullSize])
        } else {
            pasteboard.writeObjects([url as NSURL])
        }
        dismiss()
    }

    func revealInFinder() {
        guard let url = currentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        dismiss()
    }

    func pinCapture() {
        if let url = currentURL {
            PinnedScreenshotController.shared.pin(url: url)
        }
        dismiss()
    }

    // MARK: - Panel Setup

    func openAnnotateEditor() {
        guard let url = currentURL else { return }
        let screen = targetScreen
        dismiss()
        let ext = url.pathExtension.lowercased()
        if ext == "mov" || ext == "mp4" {
            VideoEditorWindowController.shared.open(url: url, on: screen)
        } else {
            EditorWindowController.shared.open(url: url, on: screen)
        }
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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
        panel.isMovableByWindowBackground = false

        let hostingView = NSHostingView(rootView: PreviewCardView(overlay: self))
        panel.contentView = hostingView

        self.panel = panel
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = targetScreen
            ?? NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        guard let panel, let screen else { return }

        let screenFrame = screen.visibleFrame
        let size = Self.panelSize

        let x = switch AppPreferences.overlayPosition {
        case .bottomRight: screenFrame.maxX - size.width
        case .bottomLeft: screenFrame.minX
        }

        panel.setFrame(NSRect(origin: NSPoint(x: x, y: screenFrame.minY), size: size), display: true)
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(AppPreferences.overlayDismissDelay))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

// MARK: - Preview Card SwiftUI View

struct PreviewCardView: View {
    let overlay: PreviewOverlay

    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    @State private var hasEntered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cardSize = CGSize(width: 156, height: 108)
    private static let cardShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    private var isVideo: Bool {
        guard let ext = overlay.currentURL?.pathExtension.lowercased() else { return false }
        return ext == "mov" || ext == "mp4"
    }

    private var trailingAligned: Bool {
        AppPreferences.overlayPosition == .bottomRight
    }

    var body: some View {
        VStack(alignment: trailingAligned ? .trailing : .leading, spacing: 8) {
            if let image = thumbnail {
                card(image)
                actionBar
                    .opacity(isHovered ? 1 : 0)
                    .offset(y: isHovered ? 0 : -6)
                    .allowsHitTesting(isHovered)
            }
        }
        .scaleEffect(hasEntered ? 1 : 0.88, anchor: .bottom)
        .opacity(hasEntered ? 1 : 0)
        .blur(radius: hasEntered ? 0 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trailingAligned ? .bottomTrailing : .bottomLeading)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .frame(width: PreviewOverlay.panelSize.width, height: PreviewOverlay.panelSize.height)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                isHovered = hovering
            }
            if hovering {
                overlay.holdOpen()
            } else {
                overlay.resumeDismiss()
            }
        }
        .onChange(of: overlay.currentURL) { _, newURL in
            loadThumbnail(from: newURL)
        }
        .onAppear {
            loadThumbnail(from: overlay.currentURL)
        }
    }

    private func card(_ image: NSImage) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                .clipped()

            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .symbolRenderingMode(.palette)
                    .frame(width: Self.cardSize.width, height: Self.cardSize.height)
            }

            LinearGradient(
                colors: [.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .frame(width: Self.cardSize.width, height: Self.cardSize.height)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(false)

            closeButton
                .padding(7)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .clipShape(Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .contentShape(Self.cardShape)
        .onTapGesture { overlay.openAnnotateEditor() }
        .accessibilityLabel(isVideo ? "Recording preview" : "Screenshot preview")
        .accessibilityHint("Opens the editor. Drag to copy the file into another app.")
        .onDrag {
            if let url = overlay.currentURL {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider(object: image)
        }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.36, dampingFraction: 0.82)) {
                hasEntered = true
            }
        }
    }

    private var closeButton: some View {
        Button { overlay.dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .help("Dismiss")
        .accessibilityLabel("Dismiss preview")
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            actionButton("pencil.tip.crop.circle", "Edit", overlay.openAnnotateEditor)
            actionButton("doc.on.doc", "Copy", overlay.copyCapture)
            actionButton("pin", "Pin on top", overlay.pinCapture)
            actionButton("folder", "Show in Finder", overlay.revealInFinder)
            actionButton("trash", "Delete", overlay.deleteCapture, tint: .red)
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .glassSurface(cornerRadius: 18, depth: .floating, isInteractive: true)
    }

    private func actionButton(_ systemName: String, _ title: String, _ action: @escaping () -> Void, tint: Color = .primary) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(PreviewActionButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }

    private func loadThumbnail(from url: URL?) {
        guard let url else {
            thumbnail = nil
            return
        }

        let ext = url.pathExtension.lowercased()
        if ext == "mov" || ext == "mp4" {
            Task.detached {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 320, height: 220)
                if let result = try? await generator.image(at: .zero) {
                    let cgImage = result.image
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    await MainActor.run { thumbnail = nsImage }
                }
            }
        } else {
            Task.detached {
                let image = Self.downsampledImage(at: url, maxPixelSize: 320)
                await MainActor.run { thumbnail = image }
            }
        }
    }

    /// Decodes a thumbnail-sized image instead of the full capture: a 5K screenshot costs
    /// ~60 MB decoded, and the card only ever shows it at 156x108 points.
    nonisolated private static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
    }
}

private struct PreviewActionButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(Color.primary.opacity(0.12))
                    .opacity(isHovered ? 1 : 0)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}
