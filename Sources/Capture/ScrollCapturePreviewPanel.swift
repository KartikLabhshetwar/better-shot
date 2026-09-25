// Adapted from MacShot (GPLv3); see Resources/Licenses/MacShot.txt.
import Cocoa

/// Floating panel that shows a live preview of the scroll capture as it progresses.
/// Appears to the left or right of the capture region if there's enough space.
/// Grows upward from the selection bottom and scales down at the visible screen edge.
@MainActor
final class ScrollCapturePreviewPanel: NSPanel {

    private let imageView = NSImageView()
    private let captureRect: NSRect
    private let targetScreen: NSScreen
    private let side: Side  // which side of the capture rect the preview appears on
    private let previewWidth: CGFloat = 200
    private let margin: CGFloat = 12
    private let minHeight: CGFloat = 100
    /// Half of the selection border stroke width (2.5pt during scroll capture).
    /// The stroke is centered on the rect edge, so the visible bottom sits this far below minY.
    private let selectionBorderOutset: CGFloat = 1.25

    enum Side { case left, right }

    init?(captureRect: NSRect, screen: NSScreen) {
        self.captureRect = captureRect
        self.targetScreen = screen

        // Determine which side has more space
        let spaceLeft = captureRect.minX - screen.visibleFrame.minX
        let spaceRight = screen.visibleFrame.maxX - captureRect.maxX
        let needed = previewWidth + margin * 2

        if spaceRight >= needed {
            side = .right
        } else if spaceLeft >= needed {
            side = .left
        } else {
            return nil  // not enough space on either side
        }

        // Initial frame — bottom-aligned with capture rect, grows upward
        let x: CGFloat
        switch side {
        case .right: x = captureRect.maxX + margin
        case .left:  x = captureRect.minX - margin - previewWidth
        }
        let initialHeight = minHeight
        let y = captureRect.minY - selectionBorderOutset
        let frame = NSRect(x: x, y: y, width: previewWidth, height: initialHeight)

        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        sharingType = .none
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false

        // Just the image with rounded corners, no container chrome
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]
        contentView = container

        imageView.frame = container.bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTop
        container.addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Update the preview with the latest stitched image.
    func updatePreview(image: NSImage) {
        imageView.image = image

        let screenFrame = targetScreen.visibleFrame
        let x: CGFloat
        switch side {
        case .right: x = captureRect.maxX + margin
        case .left:  x = captureRect.minX - margin - previewWidth
        }

        // Anchor the bottom of the preview at the bottom of the capture rect,
        // and grow upward. Clamp so it doesn't exceed the screen top.
        let anchorBottom = max(screenFrame.minY + margin, min(captureRect.minY - selectionBorderOutset, screenFrame.maxY - minHeight - 20))
        let ceilingY = screenFrame.maxY - 20  // small margin from screen top
        let availableHeight = max(minHeight, ceilingY - anchorBottom)

        // Desired height based on image aspect ratio
        let imageAspect = image.size.height / max(1, image.size.width)
        let contentWidth = previewWidth - 8
        let desiredHeight = contentWidth * imageAspect + 8

        // Clamp to available space — image scales down proportionally inside the view
        let panelHeight = min(desiredHeight, availableHeight)

        // Anchor bottom at capture rect bottom, grow upward
        let panelBottom = anchorBottom + panelHeight <= ceilingY
            ? anchorBottom
            : ceilingY - panelHeight

        let newFrame = NSRect(x: x, y: panelBottom, width: previewWidth, height: panelHeight)
        setFrame(newFrame, display: true, animate: false)
    }
}
