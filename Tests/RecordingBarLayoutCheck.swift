import AppKit
import SwiftUI

@MainActor
func check(_ condition: Bool, _ message: String) {
    guard condition else {
        FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!)
        exit(1)
    }
}

private struct BarRoot: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { _ in Color.clear.frame(width: 34, height: 34) }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .fixedSize()
    }
}

@main
enum RecordingBarLayoutCheck {
    @MainActor
    static func main() {
        run()
    }
}

@MainActor
func run() {
    _ = NSApplication.shared

    let root = BarRoot().environment(\.colorScheme, .dark)
    let hostingView = NSHostingView(rootView: root)
    hostingView.setFrameSize(hostingView.fittingSize)

    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.contentView = hostingView

    check(
        panel.contentView as? NSHostingView<BarRoot> == nil,
        "casting a modified root view to NSHostingView<BarRoot> must not be relied on for measurement"
    )

    guard let contentView = panel.contentView else {
        check(false, "panel has no content view")
        return
    }
    contentView.layoutSubtreeIfNeeded()
    let size = contentView.fittingSize
    check(size.width > 100, "measured bar width should reflect its content, got \(size.width)")
    check(size.height == 54, "measured bar height should be 54, got \(size.height)")

    let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 948)
    let bottomInset: CGFloat = 64
    let frame = RecordingBarFrame.centered(size: size, in: screenFrame, bottomInset: bottomInset)

    check(abs(frame.midX - screenFrame.midX) < 0.5, "bar should be horizontally centered, midX \(frame.midX) vs \(screenFrame.midX)")
    check(frame.minY == screenFrame.minY + bottomInset, "bar should clear the bottom edge by \(bottomInset)")
    check(frame.minX > screenFrame.minX + 100, "a centered bar must not sit against the left edge, minX \(frame.minX)")

    let wider = RecordingBarFrame.resized(frame, to: NSSize(width: size.width + 120, height: size.height), in: screenFrame)
    check(abs(wider.midX - frame.midX) < 0.5, "a mode swap must grow about the bar's own centre, midX \(wider.midX) vs \(frame.midX)")
    check(wider.minY == frame.minY, "a resize must not move the bar vertically")
    check(wider.width == size.width + 120, "a resize must adopt the new width")

    let atRightEdge = NSRect(x: screenFrame.maxX - size.width, y: 20, width: size.width, height: size.height)
    let grownAtEdge = RecordingBarFrame.resized(atRightEdge, to: NSSize(width: size.width + 200, height: size.height), in: screenFrame)
    check(grownAtEdge.maxX <= screenFrame.maxX + 0.5, "a bar widening at the right edge must be pulled back on screen, maxX \(grownAtEdge.maxX)")
    check(grownAtEdge.minX >= screenFrame.minX - 0.5, "clamping must not push the bar off the left edge, minX \(grownAtEdge.minX)")

    let offScreen = NSRect(x: -900, y: 20, width: size.width, height: size.height)
    let rescued = RecordingBarFrame.clamped(offScreen, in: screenFrame)
    check(screenFrame.contains(rescued), "a saved origin off screen must be clamped back into the visible frame, got \(rescued)")

    let tooWide = RecordingBarFrame.clamped(NSRect(x: -50, y: 20, width: screenFrame.width + 400, height: size.height), in: screenFrame)
    check(tooWide.minX == screenFrame.minX, "a bar wider than the screen must pin to the left edge, minX \(tooWide.minX)")

    print("RecordingBarLayoutCheck: all assertions passed")
}
