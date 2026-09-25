import AppKit
import ScreenCaptureKit
@testable import BetterShot

/// Opt-in real display/scroll-event check; runs a separate fixture app so auto
/// scroll exercises its production target-app routing without touching user apps.
@main
struct ScrollCaptureIntegration {
    @MainActor static var fixtureWindow: NSWindow?

    @MainActor static var selection: CGRect {
        let screen = NSScreen.main!.visibleFrame
        return CGRect(x: screen.minX + 200, y: screen.minY + 160, width: 480, height: 300)
    }

    @MainActor static func main() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if CommandLine.arguments.count > 1 {
            let window = NSWindow(contentRect: selection, styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "BetterShot scroll capture fixture"
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: CGRect(origin: .zero, size: selection.size))
            scroll.hasVerticalScroller = false
            scroll.verticalScrollElasticity = .none
            scroll.documentView = Page(frame: CGRect(x: 0, y: 0, width: 480, height: 600))
            window.contentView = scroll
            fixtureWindow = window
            app.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            try! Data().write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        } else {
            Task { @MainActor in
                do { try await check(); exit(0) }
                catch { print("FAIL live scroll capture: \(error)"); exit(1) }
            }
        }
        app.run()
    }

    @MainActor static func check() async throws {
        guard CGPreflightScreenCaptureAccess(), ShortcutService.hasAccessibilityPermission else {
            throw NSError(domain: "ScrollCaptureCheck", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Requires existing Screen Recording and Accessibility permissions; no permission changes were made."])
        }
        let ready = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixture = Process()
        fixture.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        fixture.arguments = [ready.path]
        let previousApp = NSWorkspace.shared.frontmostApplication
        let previousPointer = CGEvent(source: nil)?.location
        try fixture.run()
        defer {
            fixture.terminate()
            try? FileManager.default.removeItem(at: ready)
            previousApp?.activate(options: [])
            if let previousPointer { CGWarpMouseCursorPosition(previousPointer) }
        }
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: ready.path) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(300))
        setbuf(stdout, nil)
        let controller = ScrollCaptureController(captureRect: selection, screen: NSScreen.main!)
        defer { controller.cancelSession() }
        var completed: NSImage?
        var finished = false
        controller.onSessionDone = { completed = $0; finished = true }
        UserDefaults.standard.set(false, forKey: "scrollAutoScrollEnabled")
        UserDefaults.standard.set(1, forKey: "scrollAutoScrollSpeed")
        UserDefaults.standard.set(30_000, forKey: "scrollMaxHeight")
        await controller.startSession()
        guard controller.stripCount == 1, let first = controller.stitchedImage else {
            throw failure("Initial frame was not captured")
        }
        controller.toggleAutoScroll()
        guard controller.autoScrollActive else { throw failure("Auto Scroll did not start") }
        var checkedPause = false
        for _ in 0..<600 {
            if finished { break }
            if !controller.autoScrollActive && NSWorkspace.shared.frontmostApplication?.processIdentifier != fixture.processIdentifier {
                throw failure("Live check interrupted by an app switch; rerun with the fixture in front")
            }
            if !checkedPause && controller.stripCount >= 3 {
                checkedPause = true
                controller.toggleAutoScroll()
                let pausedCount = controller.stripCount
                try await Task.sleep(for: .milliseconds(400))
                guard !controller.autoScrollActive, controller.stripCount == pausedCount else {
                    throw failure("Pause must stop the auto-scroll cycle")
                }
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                    wheel1: -60, wheel2: 0, wheel3: 0)!
                event.location = CGPoint(x: selection.midX,
                    y: CGDisplayBounds(CGMainDisplayID()).height - selection.midY)
                event.post(tap: .cghidEventTap)
                for _ in 0..<50 {
                    if controller.stripCount > pausedCount { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard controller.stripCount > pausedCount else {
                    throw failure("Manual scrolling after Pause did not capture the next strip")
                }
                controller.toggleAutoScroll()
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard finished, completed != nil, let pixels = controller.stitchedImage else {
            throw failure("Auto Scroll did not finish at page end; strips=\(controller.stripCount)")
        }
        let scale = NSScreen.main!.backingScaleFactor
        guard pixels.width == Int(480 * scale), pixels.height == Int(600 * scale) else {
            throw failure("Expected full 480×600-point document, got \(pixels.width)×\(pixels.height) pixels, \(controller.stripCount) strips")
        }
        let bitmap = NSBitmapImageRep(cgImage: pixels)
        let initial = NSBitmapImageRep(cgImage: first)
        let output = URL(fileURLWithPath: ".build/editor-snapshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("scroll-live.png"))
        let reds = (0..<20).map { row in
            bitmap.colorAt(x: Int(10 * scale), y: Int((CGFloat(row * 30) + 10) * scale))!
                .usingColorSpace(.sRGB)!.redComponent
        }
        // Screen profiles alter absolute RGB values. Check the first viewport
        // against its captured pixels and all unique row colors by their order.
        for row in 0..<10 {
            let original = initial.colorAt(x: Int(10 * scale), y: Int((CGFloat(row * 30) + 10) * scale))!
                .usingColorSpace(.sRGB)!.redComponent
            guard abs(reds[row] - original) < 0.015 else { throw failure("Initial row \(row) changed") }
        }
        for row in 0..<20 {
            for other in 0..<row {
                guard abs(reds[row] - reds[other]) > 0.005,
                      (reds[row] < reds[other]) == (Page.red(row) < Page.red(other)) else {
                    throw failure("Row \(row) was repeated or omitted at a seam")
                }
            }
        }
        let cancelled = ScrollCaptureController(captureRect: selection, screen: NSScreen.main!)
        cancelled.onSessionDone = { _ in preconditionFailure("Cancel must not deliver an image") }
        cancelled.cancelSession()
        await cancelled.startSession()
        precondition(!cancelled.isActive && cancelled.stitchedImage == nil)
        let startup = ScrollCaptureController(captureRect: selection, screen: NSScreen.main!)
        startup.onSessionDone = { _ in preconditionFailure("Cancelling startup must not deliver an image") }
        let start = Task { await startup.startSession() }
        try await Task.sleep(for: .milliseconds(10))
        startup.cancelSession()
        await start.value
        precondition(!startup.isActive)
        print("PASS live auto/manual scroll, pause/resume, page-end completion, full-resolution ordered pixels, and startup cancellation")
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "ScrollCaptureCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@MainActor private final class Page: NSView {
    override var isFlipped: Bool { true }
    static func red(_ row: Int) -> CGFloat { CGFloat((row * 37 + 17) % 200 + 20) / 255 }
    override func draw(_ dirtyRect: NSRect) {
        for row in 0..<20 {
            NSColor(srgbRed: Self.red(row), green: 0.2, blue: 0.3, alpha: 1).setFill()
            NSRect(x: 0, y: row * 30, width: 480, height: 30).fill()
            ("Row \(row + 1) — scroll capture regression" as NSString).draw(
                at: NSPoint(x: 35, y: row * 30 + 6),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
        }
    }
}
