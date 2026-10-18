import AppKit
import QuartzCore

// The standalone runner supplies only the selector's preferences, in memory.
// Rendering, event handling, display conversion, and cropping use production code.
@MainActor
enum AppPreferences {
    static var captureRegionOnRelease = false
    static var preselectPreviousRegion = false
    static var lastRegionRect: CGRect?
    static let overlayFollowsMouse = true
    static let overlayPinnedDisplayID: CGDirectDisplayID? = nil
}

@main
enum RegionSelectionOverlayCheck {
    @MainActor static func main() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                NSApp.appearance = NSAppearance(named: appearance)
                AppPreferences.captureRegionOnRelease = false
                await check()
            }
            print("RegionSelectionOverlayCheck passed: light/dark, frozen/live opacity, dimmed/undimmed pixels, drag, resize, Return, Space, Escape, and capture on release")
            exit(0)
        }
        NSApplication.shared.run()
    }

    @MainActor static func check() async {
        guard let screen = NSScreen.screens.first,
              let id = ActiveDisplayResolver.displayID(for: screen) else {
            preconditionFailure("Requires a desktop session")
        }
        let image = redImage()
        let frame = FrozenScreenFrame(displayID: id, pointsRect: CGDisplayBounds(id), image: image)
        let area = CGRect(x: screen.frame.width * 0.25, y: screen.frame.height * 0.25,
                          width: screen.frame.width * 0.5, height: screen.frame.height * 0.5)

        for dimmed in [true, false] {
            let overlay = RegionSelectionOverlay(dimsOutsideSelection: dimmed)
            let task = Task { await overlay.selectRegion(frozenFrames: [id: frame]) }
            await Task.yield()
            let (window, root, view) = selector(on: screen)
            precondition(window.isOpaque && root.isOpaque, "A frozen frame must occlude the live desktop")
            precondition(view.wantsUpdateLayer, "Pointer updates must not rasterize a display-sized view")
            assertRed(root, at: CGPoint(x: 0.1, y: 0.1), expected: dimmed ? 0.7 : 1)
            sendMouse(.leftMouseDown, area.origin, to: view)
            sendMouse(.leftMouseDragged, CGPoint(x: area.maxX, y: area.maxY), to: view)
            sendMouse(.leftMouseUp, CGPoint(x: area.maxX, y: area.maxY), to: view)
            window.displayIfNeeded()
            assertRed(root, at: CGPoint(x: 0.5, y: 0.5), expected: 1)
            assertRed(root, at: CGPoint(x: 0.1, y: 0.1), expected: dimmed ? 0.7 : 1)

            // The label must pass pointer events through to the selector.
            let label = view.subviews.first!
            precondition(label.hitTest(CGPoint(x: label.bounds.midX, y: label.bounds.midY)) == nil)
            // Resize from the right edge without changing the other three edges.
            let right = CGPoint(x: area.maxX, y: area.midY)
            sendMouse(.leftMouseDown, right, to: view)
            sendMouse(.leftMouseDragged, CGPoint(x: right.x + 20, y: right.y), to: view)
            sendMouse(.leftMouseUp, CGPoint(x: right.x + 20, y: right.y), to: view)
            sendKey(36, to: view)
            guard case let .region(selection) = await task.value else { preconditionFailure("Return must capture") }
            let resized = CGRect(x: area.minX, y: area.minY, width: area.width + 20, height: area.height)
            let global = RegionGeometry.globalRect(local: resized, screenFrame: screen.frame)
            precondition(selection.pointsRect == RegionGeometry.pointsRect(global: global, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height))
            precondition(selection.displayID == id)
        }

        for key: UInt16 in [53, 49] {
            let task = Task { await RegionSelectionOverlay().selectRegion() }
            await Task.yield()
            let (window, _, view) = selector(on: screen)
            precondition(!window.isOpaque, "Live selection must retain desktop transparency")
            sendKey(key, to: view)
            let outcome = await task.value
            if key == 53 { guard case .cancelled = outcome else { preconditionFailure("Escape must cancel") } }
            else { guard case .window = outcome else { preconditionFailure("Space must switch to window selection") } }
        }

        AppPreferences.captureRegionOnRelease = true
        let task = Task { await RegionSelectionOverlay().selectRegion(frozenFrames: [id: frame]) }
        await Task.yield()
        let (_, _, view) = selector(on: screen)
        sendMouse(.leftMouseDown, area.origin, to: view)
        sendMouse(.leftMouseDragged, CGPoint(x: area.maxX, y: area.maxY), to: view)
        sendMouse(.leftMouseUp, CGPoint(x: area.maxX, y: area.maxY), to: view)
        guard case .region = await task.value else { preconditionFailure("Release must capture") }
    }

    @MainActor static func selector(on screen: NSScreen) -> (NSWindow, NSView, NSView) {
        let window = NSApp.windows.first { $0.isVisible && $0.level == .screenSaver && $0.frame == screen.frame }!
        let root = window.contentView!
        return (window, root, window.isOpaque ? root.subviews.first! : root)
    }

    @MainActor static func sendMouse(_ type: NSEvent.EventType, _ point: CGPoint, to view: NSView) {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                      windowNumber: view.window!.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type {
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        default: view.mouseUp(with: event)
        }
    }

    @MainActor static func sendKey(_ key: UInt16, to view: NSView) {
        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: view.window!.windowNumber, context: nil,
                                          characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!)
    }

    @MainActor static func assertRed(_ view: NSView, at point: CGPoint, expected: CGFloat) {
        view.window!.displayIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 160, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.scaleBy(x: 320 / view.bounds.width, y: 160 / view.bounds.height)
        view.layer!.render(in: context)
        let color = bitmap.colorAt(x: Int(point.x * 320), y: Int(point.y * 160))!.usingColorSpace(.deviceRGB)!
        precondition(abs(color.redComponent - expected) < 0.03 && color.alphaComponent > 0.99,
                     "Unexpected dimming/selection pixel: \(color), expected red \(expected)")
    }

    static func redImage() -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()!
    }
}
