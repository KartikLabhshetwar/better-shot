import Foundation
import AppKit
import AVFoundation

/// Persists capture history as a JSON file in Application Support.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var records: [CaptureRecord] = []
    private let storageDir: URL
    private let manifestURL: URL

    init(storageDirectory: URL? = nil) {
        storageDir = storageDirectory ?? ScreenshotHistoryStore.applicationSupportDirectory
        manifestURL = storageDir.appendingPathComponent("history.json")

        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadRecords()
        if storageDirectory == nil, ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" {
            pruneOrphanedBases()
        }
    }

    // MARK: - Import

    /// Copies a capture into the library as `fileName`, the name the capture
    /// was given when it was taken; defaults to the source file's own name.
    /// The stored copy keeps the source's extension, since that is its format.
    /// `companion` maps a storage URL to a file that will be written beside it;
    /// the chosen name leaves that path free too.
    func importCapture(from tempURL: URL, named fileName: String? = nil, deleteSource: Bool = true,
                       kind: CaptureKind = .screenshot, companion: ((URL) -> URL)? = nil) -> CaptureRecord? {
        let kind = CaptureKind.resolved(for: tempURL, fallback: kind)
        let name = fileName ?? tempURL.lastPathComponent
        let storedName = ScreenshotFileNaming.fileName(of: URL(fileURLWithPath: name), extension: tempURL.pathExtension)
        let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path) }
        let destURL = ScreenshotFileNaming.uniqueURL(for: storedName, in: storageDir, separator: "-") { url in
            exists(url) || companion.map { exists($0(url)) } == true
        }

        do {
            try FileManager.default.copyItem(at: tempURL, to: destURL)
        } catch {
            print("Failed to import capture: \(error)")
            return nil
        }

        let size = Self.pixelSize(of: destURL, kind: kind)
        let record = CaptureRecord(
            filename: destURL.lastPathComponent,
            name: name,
            pixelWidth: size.width,
            pixelHeight: size.height,
            kind: kind
        )
        insert(record)

        if deleteSource {
            try? FileManager.default.removeItem(at: tempURL)
        }

        return record
    }

    /// Adds a capture that already lives in its final location, without copying it into Application Support.
    @discardableResult
    func referenceCapture(at url: URL, kind: CaptureKind = .screenshot, filename: String? = nil) -> CaptureRecord? {
        let url = url.standardizedFileURL
        let kind = CaptureKind.resolved(for: url, fallback: kind)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let existing = records.first(where: { $0.sourcePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == url.path }) {
            return existing
        }

        let size = Self.pixelSize(of: url, kind: kind)
        let record = CaptureRecord(
            filename: filename ?? url.lastPathComponent,
            pixelWidth: size.width,
            pixelHeight: size.height,
            kind: kind,
            sourcePath: url.path
        )
        insert(record)
        return record
    }

    func syncRecordingsFromDisk() {
        RecordingProjectStore.shared.reload()
        for project in RecordingProjectStore.shared.projects.reversed() {
            referenceCapture(
                at: project.session.screenURL,
                kind: .recording,
                filename: project.displayName
            )
        }
    }

    private func insert(_ record: CaptureRecord) {
        records.insert(record, at: 0)
        trimToRetentionLimit()
        saveRecords()
    }

    private static func pixelSize(of url: URL, kind: CaptureKind) -> (width: Int, height: Int) {
        if kind == .recording {
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else { return (0, 0) }
            let size = track.naturalSize.applying(track.preferredTransform)
            return (Int(abs(size.width)), Int(abs(size.height)))
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (0, 0)
        }
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    // MARK: - Update

    @discardableResult
    func setBeautifiedPath(_ path: String, for recordID: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return false }
        if let superseded = records[index].beautifiedPath, superseded != path, isInLibrary(superseded) {
            try? FileManager.default.removeItem(atPath: superseded)
        }
        records[index].beautifiedPath = path
        saveRecords()
        return true
    }

    // MARK: - Access

    func annotationExportURL(for url: URL) -> URL? {
        guard let record = record(matching: url), record.kind == .screenshot,
              let path = record.beautifiedPath else { return nil }
        let exportURL = URL(fileURLWithPath: path).standardizedFileURL
        guard !isInLibrary(path), exportURL != urlForRecord(record).standardizedFileURL else { return nil }
        return exportURL
    }

    func urlForRecord(_ record: CaptureRecord) -> URL {
        if let sourcePath = record.sourcePath {
            return URL(fileURLWithPath: sourcePath)
        }
        return storageDir.appendingPathComponent(record.filename)
    }

    /// Matches the raw capture, its beautified output, the edited copy the preview card shows,
    /// or any flattened deliverable inside a recording's project package.
    func record(matching url: URL) -> CaptureRecord? {
        let path = url.standardizedFileURL.path
        let packagePath = url.standardizedFileURL.deletingLastPathComponent().path
        return records.first { record in
            urlForRecord(record).standardizedFileURL.path == path
                || record.beautifiedPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path == path } == true
                || displayURLForRecord(record).standardizedFileURL.path == path
                || (record.kind == .recording
                    && urlForRecord(record).standardizedFileURL.deletingLastPathComponent().path == packagePath
                    && RecordingSession.isSessionDirectory(URL(fileURLWithPath: packagePath, isDirectory: true)))
        }
    }

    func displayURLForRecord(_ record: CaptureRecord) -> URL {
        var capturePaths = [urlForRecord(record).standardizedFileURL.path]
        if let beautifiedPath = record.beautifiedPath {
            capturePaths.append(URL(fileURLWithPath: beautifiedPath).standardizedFileURL.path)
        }
        if let editedURL = ScreenshotHistoryStore.shared.editedHistoryURL(forCapturePaths: capturePaths) {
            return editedURL
        }
        if let path = record.beautifiedPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return urlForRecord(record)
    }

    /// What `decodeThumbnail` needs, resolved on the main actor before the decode is handed off.
    struct ThumbnailSource: Sendable {
        let url: URL
        let kind: CaptureKind
    }

    func thumbnailSource(for record: CaptureRecord) -> ThumbnailSource {
        ThumbnailSource(url: displayURLForRecord(record), kind: record.kind)
    }

    nonisolated static func decodeThumbnail(_ source: ThumbnailSource, maxSize: CGFloat = 120) -> NSImage? {
        if CaptureKind.resolved(for: source.url, fallback: source.kind) == .recording {
            let directory = source.url.deletingLastPathComponent()
            if RecordingSession.isSessionDirectory(directory),
               FileManager.default.fileExists(atPath: directory.appendingPathComponent(RecordingSession.posterFileName).path),
               let poster = decodeThumbnail(ThumbnailSource(
                    url: directory.appendingPathComponent(RecordingSession.posterFileName),
                    kind: .screenshot), maxSize: maxSize) {
                return poster
            }
            return videoThumbnail(url: source.url, maxSize: maxSize)
        }

        guard let imageSource = CGImageSourceCreateWithURL(source.url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let thumb = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
    }

    nonisolated static func videoThumbnail(url: URL, maxSize: CGFloat = 120) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Delete

    func forgetLocalRecords(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        let remaining = records.filter { !ids.contains($0.id) || $0.shareURL != nil }
        try JSONEncoder().encode(remaining).write(to: manifestURL, options: .atomic)
        records = remaining
    }

    func forgetCloudLink(_ link: String) throws {
        guard records.contains(where: { $0.shareURL == link }) else { return }
        var remaining = records
        for index in remaining.indices where remaining[index].shareURL == link {
            remaining[index].shareURL = nil
        }
        remaining.removeAll { $0.shareURL == nil && !FileManager.default.fileExists(atPath: urlForRecord($0).path) }
        try JSONEncoder().encode(remaining).write(to: manifestURL, options: .atomic)
        records = remaining
    }

    func deleteRecord(_ record: CaptureRecord) {
        let url = urlForRecord(record)

        if record.kind == .recording, record.sourcePath != nil {
            let packageURL = url.deletingLastPathComponent()
            if RecordingSession.isSessionDirectory(packageURL) {
                let packagePath = packageURL.standardizedFileURL.path
                if let item = ScreenshotHistoryStore.shared.items.first(where: { $0.recordingSessionPath == packagePath }) {
                    ScreenshotHistoryStore.shared.delete(item)
                } else {
                    try? FileManager.default.removeItem(at: packageURL)
                    RecordingProjectStore.shared.reload()
                }
                records.removeAll { $0.id == record.id }
                saveRecords()
                return
            }
        }

        try? FileManager.default.removeItem(at: url)
        if let beautifiedPath = record.beautifiedPath {
            let beautifiedURL = URL(fileURLWithPath: beautifiedPath)
            try? FileManager.default.removeItem(at: beautifiedURL)
            let baseURL = CaptureOrchestrator.baseImageURL(for: beautifiedURL)
            try? FileManager.default.removeItem(at: baseURL)
        }
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    /// Drops records that live inside a deleted recording package, without
    /// touching files: the package owner has already removed them.
    func removeRecords(underDirectory directoryURL: URL) {
        let prefix = directoryURL.standardizedFileURL.path + "/"
        let survivors = records.filter { record in
            guard let sourcePath = record.sourcePath else { return true }
            return !URL(fileURLWithPath: sourcePath).standardizedFileURL.path.hasPrefix(prefix)
        }
        guard survivors.count != records.count else { return }
        records = survivors
        saveRecords()
    }

    /// Removes leftovers from when every capture kept a duplicated raw copy under `BetterShot/bases`.
    private func pruneOrphanedBases() {
        let dir = CaptureOrchestrator.baseStorageDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        var referenced = Set(records.map { CaptureOrchestrator.baseImageURL(for: urlForRecord($0)).path })
        referenced.formUnion(records.compactMap { $0.beautifiedPath }.map {
            CaptureOrchestrator.baseImageURL(for: URL(fileURLWithPath: $0)).path
        })

        for file in files where !referenced.contains(file.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoded = (try? JSONDecoder().decode([CaptureRecord].self, from: data)) ?? []
        // Filter out records whose files no longer exist
        records = decoded.map { record in
            var record = record
            record.kind = CaptureKind.resolved(for: urlForRecord(record), fallback: record.kind)
            return record
        }.filter {
            FileManager.default.fileExists(atPath: urlForRecord($0).path) || $0.shareURL != nil
        }
        trimToRetentionLimit()
        if records.count != decoded.count { saveRecords() }
    }

    /// Drops the oldest records past the retention limit, deleting only files BetterShot owns.
    func trimToRetentionLimit() {
        let limit = AppPreferences.historyRetentionLimit
        guard limit > 0, records.count > limit else { return }

        for record in records[limit...] where record.isManaged {
            try? FileManager.default.removeItem(at: urlForRecord(record))
            // The deck preview companion is library-owned too; leaving it behind
            // would block the next capture that reuses this name.
            if let companion = record.beautifiedPath,
               URL(fileURLWithPath: companion).deletingLastPathComponent().standardizedFileURL
                   == storageDir.standardizedFileURL {
                try? FileManager.default.removeItem(atPath: companion)
            }
        }
        records.removeSubrange(limit...)
        saveRecords()
    }

    /// Whether `path` is a file BetterShot owns inside the library folder,
    /// as opposed to an export the user keeps elsewhere.
    private func isInLibrary(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(storageDir.standardizedFileURL.path + "/")
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
