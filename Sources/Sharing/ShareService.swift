import AppKit
import Foundation

/// Glues R2 upload to the UI: uploads a capture, copies its share page link, and toasts the result.
@MainActor
final class ShareService {
    static let shared = ShareService()

    let uploader = R2Uploader.shared

    private init() {}

    @discardableResult
    func share(itemID: UUID, fileURL: URL, title: String? = nil) async -> URL? {
        do {
            let shareURL = try await uploader.uploadShare(
                itemID: itemID,
                fileURL: fileURL,
                title: title ?? fileURL.deletingPathExtension().lastPathComponent
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(shareURL.absoluteString, forType: .string)
            ToastWindow.shared.show(title: "Link Copied", message: shareURL.absoluteString, systemIcon: "link")
            return shareURL
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ToastWindow.shared.show(title: "Share Failed", message: message, systemIcon: "exclamationmark.triangle")
            return nil
        }
    }
}
