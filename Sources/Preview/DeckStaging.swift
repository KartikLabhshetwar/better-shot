import Foundation

/// Private working images and untouched source companions for capture cards.
enum DeckStaging {
    nonisolated static let directory: URL = {
        if ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1" {
            return FileManager.default.temporaryDirectory.appendingPathComponent("BetterShotDeckTests-\(UUID().uuidString)")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BetterShot/deck", isDirectory: true)
    }()

    private static var savedCopies: [URL: URL] = [:]
    private static var retainedCopies: [URL: URL] = [:]

    nonisolated static func isStaged(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
    }

    nonisolated static func rawURL(for stagedURL: URL) -> URL {
        stagedURL.deletingPathExtension().appendingPathExtension("raw.png")
    }

    nonisolated static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func savedURL(for url: URL) -> URL? { savedCopies[url] }

    /// Keep the editable source and preview inside BetterShot for Edit, Pin, Share, or drag-out.
    static func retain(_ url: URL) -> URL {
        guard isStaged(url) else { return url }
        if let retained = retainedCopies[url] { return retained }
        guard let record = HistoryStore.shared.importCapture(from: rawURL(for: url), deleteSource: false) else { return url }
        let raw = HistoryStore.shared.urlForRecord(record)
        let preview = raw.deletingPathExtension().appendingPathExtension("preview." + url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: preview)
        } catch {
            HistoryStore.shared.deleteRecord(record)
            return url
        }
        HistoryStore.shared.setBeautifiedPath(preview.path, for: record.id)
        retainedCopies[url] = preview
        return preview
    }

    /// Copies a staged capture into the save folder and the Library. Returns the saved file, or the input when nothing was staged.
    @discardableResult
    static func promote(_ url: URL) -> URL {
        guard isStaged(url) else { return url }
        if let saved = savedCopies[url] { return saved }

        let retained = retain(url)
        guard !isStaged(retained) else { return url }
        do {
            let dest = try ScreenshotFileActions.saveToDefaultLocation(from: url)
            if let record = HistoryStore.shared.record(matching: retained) {
                HistoryStore.shared.setBeautifiedPath(dest.path, for: record.id)
            }
            savedCopies[url] = dest
            retainedCopies[url] = dest
            return dest
        } catch {
            print("Failed to save staged capture: \(error)")
            return url
        }
    }

    static func discard(_ url: URL) {
        guard isStaged(url) else { return }
        savedCopies.removeValue(forKey: url)
        retainedCopies.removeValue(forKey: url)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: rawURL(for: url))
    }

    static func purge() {
        savedCopies.removeAll()
        retainedCopies.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}
