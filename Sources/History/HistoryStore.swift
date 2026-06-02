import Foundation
import AppKit

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
    }

    // MARK: - Import

    func importCapture(from tempURL: URL) -> CaptureRecord? {
        let ext = tempURL.pathExtension.isEmpty ? "png" : tempURL.pathExtension
        let filename = "bettershot_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
        let destURL = storageDir.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: tempURL, to: destURL)
        } catch {
            print("Failed to import capture: \(error)")
            return nil
        }

        var width = 0, height = 0
        if let source = CGImageSourceCreateWithURL(destURL as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        }

        let record = CaptureRecord(
            filename: filename,
            pixelWidth: width,
            pixelHeight: height
        )
        records.insert(record, at: 0)
        saveRecords()

        try? FileManager.default.removeItem(at: tempURL)

        return record
    }

    // MARK: - Access

    func urlForRecord(_ record: CaptureRecord) -> URL {
        storageDir.appendingPathComponent(record.filename)
    }

    func thumbnail(for record: CaptureRecord, maxSize: CGFloat = 120) -> NSImage? {
        let url = urlForRecord(record)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
    }

    // MARK: - Delete

    func deleteRecord(_ record: CaptureRecord) {
        let url = urlForRecord(record)
        try? FileManager.default.removeItem(at: url)
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoded = (try? JSONDecoder().decode([CaptureRecord].self, from: data)) ?? []
        // Filter out records whose files no longer exist
        records = decoded.filter { FileManager.default.fileExists(atPath: urlForRecord($0).path) }
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
