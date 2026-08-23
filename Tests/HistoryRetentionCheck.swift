import Foundation

// Mirror of HistoryStore's retention rules (Sources/History/HistoryStore.swift).

struct Record {
    let filename: String
    let sourcePath: String?
    var isManaged: Bool { sourcePath == nil }
}

func url(for record: Record, storageDir: URL) -> URL {
    if let sourcePath = record.sourcePath { return URL(fileURLWithPath: sourcePath) }
    return storageDir.appendingPathComponent(record.filename)
}

func trim(records: inout [Record], limit: Int, storageDir: URL) {
    guard limit > 0, records.count > limit else { return }
    for record in records[limit...] where record.isManaged {
        try? FileManager.default.removeItem(at: url(for: record, storageDir: storageDir))
    }
    records.removeSubrange(limit...)
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryRetentionCheck-\(UUID().uuidString)")
let storageDir = root.appendingPathComponent("BetterShot")
let saveDir = root.appendingPathComponent("Desktop")
try! FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

func makeRecords(count: Int) -> [Record] {
    (0..<count).map { index in
        // Newest first, alternating between managed copies and referenced save-folder files.
        if index.isMultiple(of: 2) {
            let name = "managed_\(index).png"
            FileManager.default.createFile(atPath: storageDir.appendingPathComponent(name).path, contents: Data("x".utf8))
            return Record(filename: name, sourcePath: nil)
        }
        let external = saveDir.appendingPathComponent("referenced_\(index).mp4")
        FileManager.default.createFile(atPath: external.path, contents: Data("x".utf8))
        return Record(filename: external.lastPathComponent, sourcePath: external.path)
    }
}

do {
    var records = makeRecords(count: 10)
    let survivors = Array(records.prefix(4))
    let dropped = Array(records.suffix(6))
    trim(records: &records, limit: 4, storageDir: storageDir)

    assert(records.count == 4, "trim should keep exactly the limit")
    assert(records.map(\.filename) == survivors.map(\.filename), "trim should keep the newest records")

    for record in survivors {
        assert(FileManager.default.fileExists(atPath: url(for: record, storageDir: storageDir).path),
               "kept record \(record.filename) must keep its file")
    }
    for record in dropped where record.isManaged {
        assert(!FileManager.default.fileExists(atPath: url(for: record, storageDir: storageDir).path),
               "dropped managed file \(record.filename) should be deleted")
    }
    for record in dropped where !record.isManaged {
        assert(FileManager.default.fileExists(atPath: url(for: record, storageDir: storageDir).path),
               "referenced file \(record.filename) in the user's save folder must survive trimming")
    }
}

do {
    var records = makeRecords(count: 5)
    trim(records: &records, limit: 0, storageDir: storageDir)
    assert(records.count == 5, "limit 0 means unlimited")

    trim(records: &records, limit: 5, storageDir: storageDir)
    assert(records.count == 5, "a count equal to the limit is not trimmed")
}

print("HistoryRetentionCheck: all assertions passed")
