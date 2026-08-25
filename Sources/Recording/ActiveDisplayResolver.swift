import AppKit
import CoreGraphics

@MainActor
enum ActiveDisplayResolver {
    static func activeDisplayID(preferPointer: Bool = true) -> CGDirectDisplayID? {
        activeScreen(preferPointer: preferPointer).flatMap(displayID(for:))
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { Self.displayID(for: $0) == displayID }
    }

    static func activeScreen(preferPointer: Bool = true) -> NSScreen? {
        let pointerScreen = screen(containing: NSEvent.mouseLocation)
        if preferPointer {
            return pointerScreen ?? screenContainingFrontmostWindow() ?? NSScreen.main ?? NSScreen.screens.first
        }
        return screenContainingFrontmostWindow() ?? pointerScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Flips a Quartz global point (top-left origin) into AppKit screen space (bottom-left origin on the primary display).
    nonisolated static func appKitPoint(fromQuartz point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Resolves the screen under a Quartz global point, as delivered by CGEvent.
    static func screen(containingQuartzPoint point: CGPoint) -> NSScreen? {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return screen(containing: appKitPoint(fromQuartz: point, primaryHeight: primaryHeight))
            ?? activeScreen()
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private static func screenContainingFrontmostWindow() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != getpid(),
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowList {
            guard (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let windowBounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  windowBounds.width > 1, windowBounds.height > 1 else {
                continue
            }
            if let screen = bestScreen(forWindowBounds: windowBounds) { return screen }
        }
        return nil
    }

    private static func bestScreen(forWindowBounds windowBounds: CGRect) -> NSScreen? {
        let desktopFrame = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let quartzCandidate = CGRect(
            x: windowBounds.minX,
            y: desktopFrame.maxY - windowBounds.maxY,
            width: windowBounds.width,
            height: windowBounds.height
        )

        var bestMatch: (screen: NSScreen, area: CGFloat)?
        for candidate in [windowBounds, quartzCandidate] where !candidate.isNull && !candidate.isEmpty {
            for screen in NSScreen.screens {
                let intersection = screen.frame.intersection(candidate)
                guard !intersection.isNull else { continue }
                let area = intersection.width * intersection.height
                guard area > (bestMatch?.area ?? 0) else { continue }
                bestMatch = (screen, area)
            }
        }
        return bestMatch?.screen
    }
}
