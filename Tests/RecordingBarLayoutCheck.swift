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
    let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.minY + bottomInset)
    let frame = NSRect(origin: origin, size: size)

    check(abs(frame.midX - screenFrame.midX) < 0.5, "bar should be horizontally centered, midX \(frame.midX) vs \(screenFrame.midX)")
    check(frame.minY == screenFrame.minY + bottomInset, "bar should clear the bottom edge by \(bottomInset)")
    check(frame.minX > screenFrame.minX + 100, "a centered bar must not sit against the left edge, minX \(frame.minX)")

    let offScreen = NSRect(x: -900, y: 20, width: size.width, height: size.height)
    check(!screenFrame.contains(offScreen), "a saved origin mostly off screen must be rejected")

    let partly = NSRect(x: screenFrame.maxX - 10, y: 20, width: size.width, height: size.height)
    check(screenFrame.intersects(partly), "sanity: this frame does intersect")
    check(!screenFrame.contains(partly), "containment must reject a bar hanging off the right edge that intersects")

    print("RecordingBarLayoutCheck: all assertions passed")
}

MainActor.assumeIsolated { run() }
