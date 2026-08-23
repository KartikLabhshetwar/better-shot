import AppKit
import ScreenCaptureKit

/// Lists the displays and app windows the picker bar can offer as a recording source. Ported from screendrop (github.com/fayazara/screendrop, CC0-1.0).
@MainActor
@Observable
final class RecordingSourceCatalog {
    static let shared = RecordingSourceCatalog()

    private(set) var displays: [SCDisplay] = []
    private(set) var windows: [SCWindow] = []

    private init() {}

    func refresh() async {
        guard let content = try? await ScreenCaptureStream.availableContent() else {
            displays = []
            windows = []
            return
        }
        displays = content.displays
        windows = Self.filteredWindows(from: content)
    }

    static func displayTitle(_ display: SCDisplay, index: Int) -> String {
        let name = displayName(for: display.displayID) ?? "Display \(index + 1)"
        return "\(name) (\(display.width)x\(display.height))"
    }

    static func windowTitle(_ window: SCWindow) -> String {
        let appName = window.owningApplication?.applicationName ?? "Unknown"
        guard let title = window.title, !title.isEmpty else { return appName }
        return "\(appName) - \(title)"
    }

    private static func filteredWindows(from content: SCShareableContent) -> [SCWindow] {
        let ownBundleID = Bundle.main.bundleIdentifier
        var seenKeys: Set<String> = []
        return content.windows
            .filter { window in
                window.isOnScreen
                    && window.windowLayer == 0
                    && window.frame.width >= 160
                    && window.frame.height >= 100
                    && window.owningApplication?.bundleIdentifier != ownBundleID
                    && !isBlockedApplication(window.owningApplication)
            }
            .filter { seenKeys.insert(dedupeKey(for: $0)).inserted }
            .sorted { windowTitle($0).localizedCaseInsensitiveCompare(windowTitle($1)) == .orderedAscending }
    }

    private static func isBlockedApplication(_ app: SCRunningApplication?) -> Bool {
        guard let app else { return true }
        let needle = "\(app.bundleIdentifier) \(app.applicationName)".lowercased()
        let blockedFragments = [
            "controlcenter", "notificationcenter", "systemuiserver",
            "dock", "spotlight", "wallpaper", "windowmanager",
        ]
        return blockedFragments.contains { needle.contains($0) }
    }

    private static func dedupeKey(for window: SCWindow) -> String {
        let frame = window.frame
        return "\(window.owningApplication?.bundleIdentifier ?? "")|\(window.title ?? "")|\(Int(frame.minX))|\(Int(frame.minY))|\(Int(frame.width))|\(Int(frame.height))"
    }

    private static func displayName(for displayID: CGDirectDisplayID) -> String? {
        ActiveDisplayResolver.screen(for: displayID)?.localizedName
    }
}
