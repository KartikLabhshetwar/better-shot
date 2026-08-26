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

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("BetterShot", isDirectory: true)
        manifestURL = storageDir.appendingPathComponent("history.json")

        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadRecords()
        pruneOrphanedBases()
    }

    // MARK: - Import

    func importCapture(from tempURL: URL, deleteSource: Bool = true, kind: CaptureKind = .screenshot) -> CaptureRecord? {
        let ext = tempURL.pathExtension.isEmpty ? "png" : tempURL.pathExtension
        var filename = "bettershot_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
        var destURL = storageDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destURL.path) {
            filename = "bettershot_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6)).\(ext)"
            destURL = storageDir.appendingPathComponent(filename)
        }

        do {
            try FileManager.default.copyItem(at: tempURL, to: destURL)
        } catch {
            print("Failed to import capture: \(error)")
            return nil
        }

        let size = Self.pixelSize(of: destURL, kind: kind)
        let record = CaptureRecord(
            filename: filename,
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
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let existing = records.first(where: { $0.sourcePath == url.path }) {
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

    func setBeautifiedPath(_ path: String, for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        if let superseded = records[index].beautifiedPath, superseded != path {
            try? FileManager.default.removeItem(atPath: superseded)
        }
        records[index].beautifiedPath = path
        saveRecords()
    }

    // MARK: - Access

    func urlForRecord(_ record: CaptureRecord) -> URL {
        if let sourcePath = record.sourcePath {
            return URL(fileURLWithPath: sourcePath)
        }
        return storageDir.appendingPathComponent(record.filename)
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
        if source.kind == .recording {
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
        let prefix = directoryURL.standardizedFileURL.path
        let survivors = records.filter { record in
            guard let sourcePath = record.sourcePath else { return true }
            return !URL(fileURLWithPath: sourcePath).standardizedFileURL.path.hasPrefix(prefix)
        }
        guard survivors.count != records.count else { return }
        records = survivors
        saveRecords()
    }

    func deleteAllRecords() {
        for record in records {
            let url = urlForRecord(record)
            try? FileManager.default.removeItem(at: url)
            if let beautifiedPath = record.beautifiedPath {
                let beautifiedURL = URL(fileURLWithPath: beautifiedPath)
                try? FileManager.default.removeItem(at: beautifiedURL)
                let baseURL = CaptureOrchestrator.baseImageURL(for: beautifiedURL)
                try? FileManager.default.removeItem(at: baseURL)
            }
        }
        records.removeAll()
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
        records = decoded.filter { FileManager.default.fileExists(atPath: urlForRecord($0).path) }
        trimToRetentionLimit()
        if records.count != decoded.count { saveRecords() }
    }

    /// Drops the oldest records past the retention limit, deleting only files BetterShot owns.
    func trimToRetentionLimit() {
        let limit = AppPreferences.historyRetentionLimit
        guard limit > 0, records.count > limit else { return }

        for record in records[limit...] where record.isManaged {
            try? FileManager.default.removeItem(at: urlForRecord(record))
        }
        records.removeSubrange(limit...)
        saveRecords()
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
