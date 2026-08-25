//
//  RecordingExportFeedback.swift
//  BetterShot
//
//  Surfaces Studio export progress and completion outside the editor window:
//  a Dock icon progress bar while exporting, and a system notification once
//  the file is saved.
//

import AppKit
import DockProgress
import UserNotifications

/// Mirrors every in-flight Studio export onto the single shared Dock icon.
/// Multiple Studio windows can export at once, so progress is averaged
/// across them rather than one export's updates fighting another's.
@MainActor
final class DockExportProgressCoordinator {
    static let shared = DockExportProgressCoordinator()

    private var progressByTask: [UUID: Double] = [:]

    private init() {}

    func start() -> UUID {
        let id = UUID()
        progressByTask[id] = 0
        updateDockIcon()
        return id
    }

    func update(_ id: UUID, progress: Double) {
        guard progressByTask[id] != nil else { return }
        progressByTask[id] = min(max(progress, 0), 1)
        updateDockIcon()
    }

    func finish(_ id: UUID) {
        guard progressByTask.removeValue(forKey: id) != nil else { return }
        updateDockIcon()
    }

    private func updateDockIcon() {
        guard !progressByTask.isEmpty else {
            DockProgress.resetProgress()
            return
        }
        let average = progressByTask.values.reduce(0, +) / Double(progressByTask.count)
        DockProgress.progress = average
    }
}

/// Delivers the "export finished" notification and reveals the file in
/// Finder when the user clicks it.
enum RecordingExportNotifier {
    private static let fileURLKey = "fileURL"

    static func notifySuccess(fileURL: URL) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                deliver(fileURL: fileURL)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    deliver(fileURL: fileURL)
                }
            case .denied, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }

    private static func deliver(fileURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Export Complete"
        content.body = "\(fileURL.lastPathComponent) has been saved."
        content.sound = .default
        content.userInfo = [fileURLKey: fileURL.path]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Pulled out of the payload before hopping to the main actor, since
    /// the userInfo dictionary itself can't cross isolation boundaries.
    nonisolated static func filePath(in userInfo: [AnyHashable: Any]) -> String? {
        userInfo[fileURLKey] as? String
    }

    /// Lands the user on the file they just exported. On by default: an
    /// export is a deliberate "give me the file" action, and a notification
    /// alone leaves them hunting for the export folder.
    @MainActor
    static func revealIfPreferred(fileURL: URL) {
        guard BetterShotPreferences.revealExportInFinder else { return }
        reveal(path: fileURL.path)
    }

    @MainActor
    static func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Exported files get renamed or moved between the notification
            // and the click; the folder they were written to is still the
            // right place to land.
            NSWorkspace.shared.open(url.deletingLastPathComponent())
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Keeps export notifications visible even while a Studio window is
/// frontmost, and reveals the exported file when the notification is clicked.
final class RecordingExportNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RecordingExportNotificationDelegate()

    private override init() {}

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // `.list` keeps the notification in Notification Center once the
        // banner auto-dismisses, so a missed banner is still clickable.
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Swiping a banner away is not a request to open anything.
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let path = RecordingExportNotifier.filePath(
                  in: response.notification.request.content.userInfo
              ) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            RecordingExportNotifier.reveal(path: path)
            completionHandler()
        }
    }
}
