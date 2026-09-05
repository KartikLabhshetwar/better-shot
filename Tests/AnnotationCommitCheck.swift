import Foundation

// Mirror of ScreenshotHistoryStore.commitAnnotations (Sources/BetterShot/ScreenshotHistoryStore.swift).

let root = FileManager.default.temporaryDirectory.appendingPathComponent("AnnotationCommitCheck-\(UUID().uuidString)")
let historyDir = root.appendingPathComponent("History", isDirectory: true)
let rawDir = root.appendingPathComponent("raw", isDirectory: true)
try! FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

func isHistoryURL(_ url: URL) -> Bool {
    url.standardizedFileURL.path.hasPrefix(historyDir.standardizedFileURL.path)
}

func baseImageURL(for displayURL: URL) -> URL {
    let ext = displayURL.pathExtension
    let stem = displayURL.deletingPathExtension().lastPathComponent
    let directory = displayURL.deletingLastPathComponent()
    let fileName = ext.isEmpty ? "\(stem).base" : "\(stem).base.\(ext)"
    return directory.appendingPathComponent(fileName)
}

func editDocumentURL(for displayURL: URL) -> URL {
    displayURL.appendingPathExtension("bettershot")
}

var importedCount = 0

@MainActor
func importScreenshot(from sourceURL: URL) -> URL {
    let destinationURL = historyDir.appendingPathComponent("Imported_\(importedCount).png")
    try! FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    importedCount += 1
    return destinationURL
}

@MainActor
func commitAnnotations(displayURL: URL, baseURL: URL, renderedURL: URL) -> URL {
    let displayURL = isHistoryURL(displayURL) ? displayURL : importScreenshot(from: renderedURL)
    guard isHistoryURL(displayURL) else { return displayURL }

    let baseDestination = baseImageURL(for: displayURL)
    if baseURL.standardizedFileURL != baseDestination.standardizedFileURL {
        if baseURL.standardizedFileURL == displayURL.standardizedFileURL {
            if !FileManager.default.fileExists(atPath: baseDestination.path), FileManager.default.fileExists(atPath: displayURL.path) {
                try! FileManager.default.copyItem(at: displayURL, to: baseDestination)
            }
        } else {
            if FileManager.default.fileExists(atPath: baseDestination.path) {
                try! FileManager.default.removeItem(at: baseDestination)
            }
            try! FileManager.default.copyItem(at: baseURL, to: baseDestination)
        }
    }

    if FileManager.default.fileExists(atPath: displayURL.path) {
        try! FileManager.default.removeItem(at: displayURL)
    }
    try! FileManager.default.copyItem(at: renderedURL, to: displayURL)
    FileManager.default.createFile(atPath: editDocumentURL(for: displayURL).path, contents: Data("doc".utf8))
    return displayURL
}

func write(_ content: String, to url: URL) {
    FileManager.default.createFile(atPath: url.path, contents: Data(content.utf8))
}

func read(_ url: URL) -> String {
    String(data: FileManager.default.contents(atPath: url.path) ?? Data(), encoding: .utf8) ?? ""
}

let rawURL = rawDir.appendingPathComponent("capture.png")
write("raw", to: rawURL)
let rendered1 = root.appendingPathComponent("rendered1.png")
write("rendered1", to: rendered1)

let firstResult = commitAnnotations(displayURL: rawURL, baseURL: rawURL, renderedURL: rendered1)
assert(isHistoryURL(firstResult), "first commit must land in History")
assert(read(firstResult) == "rendered1", "display image must be the rendered composite")
assert(FileManager.default.fileExists(atPath: baseImageURL(for: firstResult).path),
       "issue #118: the base image the editor re-renders from must exist after a non-history commit")
assert(read(baseImageURL(for: firstResult)) == "raw", "base image must preserve the untouched pixels")
assert(FileManager.default.fileExists(atPath: editDocumentURL(for: firstResult).path), "sidecar document must be written")

let editorSourceURL = firstResult
let editorBaseURL = baseImageURL(for: firstResult)
let rendered2 = root.appendingPathComponent("rendered2.png")
write("rendered2", to: rendered2)

let secondResult = commitAnnotations(displayURL: editorSourceURL, baseURL: editorBaseURL, renderedURL: rendered2)
assert(secondResult == firstResult, "a repointed editor must commit in place")
assert(importedCount == 1, "a second save must not import a duplicate History copy")
assert(read(secondResult) == "rendered2", "second commit must refresh the display image")
assert(read(baseImageURL(for: secondResult)) == "raw", "second commit must keep the original base")

print("AnnotationCommitCheck: all assertions passed")
