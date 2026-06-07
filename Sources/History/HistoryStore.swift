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
    }

    // MARK: - Import

    func importCapture(from tempURL: URL, deleteSource: Bool = true, kind: CaptureKind = .screenshot) -> CaptureRecord? {
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
        if kind == .recording {
            let asset = AVURLAsset(url: destURL)
            if let track = asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                width = Int(abs(size.width))
                height = Int(abs(size.height))
            }
        } else if let source = CGImageSourceCreateWithURL(destURL as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        }

        let record = CaptureRecord(
            filename: filename,
            pixelWidth: width,
            pixelHeight: height,
            kind: kind
        )
        records.insert(record, at: 0)
        saveRecords()

        if deleteSource {
            try? FileManager.default.removeItem(at: tempURL)
        }

        return record
    }

    // MARK: - Update

    func setBeautifiedPath(_ path: String, for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].beautifiedPath = path
        saveRecords()
    }

    // MARK: - Access

    func urlForRecord(_ record: CaptureRecord) -> URL {
        storageDir.appendingPathComponent(record.filename)
    }

    func displayURLForRecord(_ record: CaptureRecord) -> URL {
        if let path = record.beautifiedPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return urlForRecord(record)
    }

    func thumbnail(for record: CaptureRecord, maxSize: CGFloat = 120) -> NSImage? {
        let url = displayURLForRecord(record)

        if record.kind == .recording {
            return videoThumbnail(url: url, maxSize: maxSize)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
    }

    nonisolated func videoThumbnail(url: URL, maxSize: CGFloat = 120) -> NSImage? {
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
        try? FileManager.default.removeItem(at: url)
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    func deleteAllRecords() {
        for record in records {
            let url = urlForRecord(record)
            try? FileManager.default.removeItem(at: url)
        }
        records.removeAll()
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
