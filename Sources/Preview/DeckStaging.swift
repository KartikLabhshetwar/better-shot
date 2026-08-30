import Foundation

/// Holds captures the deck has not saved yet, so nothing reaches the save folder or Library until the user acts on a card.
enum DeckStaging {
    nonisolated static let directory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BetterShot/deck", isDirectory: true)
    }()

    private static var savedCopies: [URL: URL] = [:]

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

    /// Copies a staged capture into the save folder and the Library. Returns the saved file, or the input when nothing was staged.
    @discardableResult
    static func promote(_ url: URL) -> URL {
        guard isStaged(url) else { return url }
        if let saved = savedCopies[url] { return saved }

        let dest = URL(fileURLWithPath: AppPreferences.saveDirectory).appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            print("Failed to save staged capture: \(error)")
            return url
        }
        if let record = HistoryStore.shared.importCapture(from: rawURL(for: url)) {
            HistoryStore.shared.setBeautifiedPath(dest.path, for: record.id)
        }
        savedCopies[url] = dest
        return dest
    }

    static func discard(_ url: URL) {
        guard isStaged(url) else { return }
        savedCopies.removeValue(forKey: url)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: rawURL(for: url))
    }

    static func purge() {
        savedCopies.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}
