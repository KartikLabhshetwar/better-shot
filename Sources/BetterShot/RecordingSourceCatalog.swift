//
//  RecordingSourceCatalog.swift
//  BetterShot
//
//  Created by Codex on 05/05/26.
//

import AppKit
import Observation
import ScreenCaptureKit

@MainActor
@Observable
final class RecordingSourceCatalog {
    static let shared = RecordingSourceCatalog()

    private(set) var displays: [SCDisplay] = []
    private(set) var windows: [SCWindow] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private init() {}

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            let content = try await ScreenRecordingCapture.availableContent()
            displays = content.displays
            windows = Self.filteredWindows(from: content)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    static func displayTitle(_ display: SCDisplay, index: Int) -> String {
        let resolution = "\(display.width)x\(display.height)"
        let name = displayName(for: display.displayID) ?? "Display \(index + 1)"
        return "\(name) (\(resolution))"
    }

    static func windowTitle(_ window: SCWindow) -> String {
        let appName = window.owningApplication?.applicationName ?? "Unknown"
        guard let title = window.title, !title.isEmpty else {
            return appName
        }

        return "\(appName) - \(title)"
    }

    static func filteredWindows(from content: SCShareableContent) -> [SCWindow] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let includesAppWindows = PreviewWindowCaptureExclusion.includesAppWindowsInCaptures
        var seenKeys: Set<String> = []

        return content.windows
            .filter { window in
                guard window.isOnScreen,
                      window.windowLayer == 0,
                      window.frame.width >= 160,
                      window.frame.height >= 100,
                      let app = window.owningApplication,
                      (includesAppWindows || app.bundleIdentifier != ownBundleID),
                      !isBlockedApplication(app),
                      !isBlockedTitle(window.title, app: app) else {
                    return false
                }

                return true
            }
            .filter { window in
                let key = dedupeKey(for: window)
                guard !seenKeys.contains(key) else { return false }

                seenKeys.insert(key)
                return true
            }
            .sorted { lhs, rhs in
                windowTitle(lhs).localizedCaseInsensitiveCompare(windowTitle(rhs)) == .orderedAscending
            }
    }

    private static func isBlockedApplication(_ app: SCRunningApplication) -> Bool {
        let bundleID = app.bundleIdentifier.lowercased()
        let appName = app.applicationName.lowercased()
        let blockedFragments = [
            "controlcenter",
            "notificationcenter",
            "systemuiserver",
            "dock",
            "wallpaper",
            "windowmanager",
            "spotlight"
        ]

        return blockedFragments.contains { fragment in
            bundleID.contains(fragment) || appName.contains(fragment)
        }
    }

    private static func isBlockedTitle(_ title: String?, app: SCRunningApplication) -> Bool {
        let normalizedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedTitle.isEmpty {
            return app.bundleIdentifier == "com.apple.finder"
        }

        let blockedFragments = [
            "backstop",
            "menubar",
            "underbelly",
            "wallpaper",
            "bentobox",
            "battery",
            "clock",
            "wi-fi",
            "wifi",
            "forecast",
            "symbol",
            "item-"
        ]

        return blockedFragments.contains { normalizedTitle.contains($0) }
    }

    private static func dedupeKey(for window: SCWindow) -> String {
        let bundleID = window.owningApplication?.bundleIdentifier ?? ""
        let title = window.title ?? ""
        let frame = window.frame
        return "\(bundleID)|\(title)|\(Int(frame.minX))|\(Int(frame.minY))|\(Int(frame.width))|\(Int(frame.height))"
    }

    private static func displayName(for displayID: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }

            return CGDirectDisplayID(screenNumber.uint32Value) == displayID
        }?.localizedName
    }
}
