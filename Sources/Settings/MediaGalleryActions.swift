import AppKit

extension MediaGalleryItem {
    /// Move every owned file before changing history. A failure keeps metadata available for retry.
    func deleteLocal(history: HistoryStore = .shared, edits: ScreenshotHistoryStore = .shared,
                     trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        let urls = Self.deletionTargets(deletionURLs)
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try trash(url)
        }
        try edits.forgetLocalItems(ids: Set([historyID].compactMap { $0 }))
        try history.forgetLocalRecords(ids: Set(captureIDs))
        for url in urls { PreviewOverlay.shared.remove(url) }
        PreviewOverlay.shared.remove(localURL)
        RecordingProjectStore.shared.reload()
    }

    static func deletionTargets(_ urls: [URL]) -> [URL] {
        let unique = Dictionary(urls.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
            uniquingKeysWith: { first, _ in first }).values.sorted { $0.path.count < $1.path.count }
        return unique.reduce(into: [URL]()) { targets, url in
            if !targets.contains(where: { url.path.hasPrefix($0.path + "/") }) { targets.append(url) }
        }
    }

    func deleteCloud() async throws {
        guard let cloudURL else { return }
        let credentials = R2CredentialStore.shared.snapshot()
        guard let slug = Self.deletionSlug(for: cloudURL, publicBaseURL: credentials.publicBaseURL) else {
            throw R2UploadError(message: "This link belongs to different cloud storage. Select its original R2 settings in Settings > Sharing, then retry.")
        }
        try await R2Uploader.deleteShare(slug: slug, credentials: credentials)
        try ScreenshotHistoryStore.shared.forgetCloudLink(cloudURL.absoluteString)
        try HistoryStore.shared.forgetCloudLink(cloudURL.absoluteString)
    }

    static func deletionSlug(for url: URL, publicBaseURL: String) -> String? {
        guard let slug = R2Uploader.slug(fromShareLink: url.absoluteString), !slug.isEmpty,
              slug.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }),
              ShareBundle.pageURL(id: slug, publicBaseURL: publicBaseURL) == url else { return nil }
        return slug
    }
}
