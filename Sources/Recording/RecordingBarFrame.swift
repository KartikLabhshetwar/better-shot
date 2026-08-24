import CoreGraphics

/// Where the floating recording bar lands: on first show, after a drag, and whenever its content resizes.
enum RecordingBarFrame {
    static func centered(size: CGSize, in visibleFrame: CGRect, bottomInset: CGFloat) -> CGRect {
        clamped(
            CGRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY + bottomInset,
                width: size.width,
                height: size.height
            ),
            in: visibleFrame
        )
    }

    /// Grows and shrinks about the bar's own centre so a mode swap does not appear to slide sideways.
    static func resized(_ current: CGRect, to size: CGSize, in visibleFrame: CGRect) -> CGRect {
        clamped(
            CGRect(x: current.midX - size.width / 2, y: current.minY, width: size.width, height: size.height),
            in: visibleFrame
        )
    }

    static func clamped(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return frame }
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - frame.width)),
            y: min(max(frame.minY, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }
}
