import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent("AnnotationReopenCheck-\(UUID().uuidString)")
let historyDir = root.appendingPathComponent("History", isDirectory: true)
let rawDir = root.appendingPathComponent("raw", isDirectory: true)
let desktopDir = root.appendingPathComponent("Desktop", isDirectory: true)
try! FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: desktopDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

struct Item {
    let url: URL
    let sourceCapturePath: String?
}

var items: [Item] = []

func write(_ content: String, to url: URL) {
    FileManager.default.createFile(atPath: url.path, contents: Data(content.utf8))
}

func hasEditDocument(for url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appendingPathExtension("bettershot").path)
}

func resolveRawSource(for url: URL, beautifiedPath: String?, rawURL: URL) -> URL {
    if url.path == beautifiedPath, FileManager.default.fileExists(atPath: rawURL.path) {
        return rawURL
    }
    return url
}

func annotationEditorURL(for url: URL, beautifiedPath: String?, rawURL: URL) -> URL {
    if hasEditDocument(for: url) { return url }
    let raw = resolveRawSource(for: url, beautifiedPath: beautifiedPath, rawURL: rawURL)
    let candidatePaths = [raw.standardizedFileURL.path, url.standardizedFileURL.path]
    if let item = items.first(where: { item in
        guard let sourceCapturePath = item.sourceCapturePath else { return false }
        return candidatePaths.contains(sourceCapturePath)
    }), hasEditDocument(for: item.url) {
        return item.url
    }
    return raw
}

let rawURL = rawDir.appendingPathComponent("bettershot_1.png")
let desktopURL = desktopDir.appendingPathComponent("bettershot_1.png")
write("raw", to: rawURL)
write("beautified", to: desktopURL)

let unedited = annotationEditorURL(for: desktopURL, beautifiedPath: desktopURL.path, rawURL: rawURL)
assert(unedited == rawURL, "unedited capture must open the raw source")

let historyURL = historyDir.appendingPathComponent("BetterShot_1.png")
write("composite", to: historyURL)
write("doc", to: historyURL.appendingPathExtension("bettershot"))
items.append(Item(url: historyURL, sourceCapturePath: rawURL.standardizedFileURL.path))

let reopened = annotationEditorURL(for: desktopURL, beautifiedPath: desktopURL.path, rawURL: rawURL)
assert(reopened == historyURL, "reopening an edited capture must open the history copy that owns the sidecar")

let direct = annotationEditorURL(for: historyURL, beautifiedPath: nil, rawURL: rawURL)
assert(direct == historyURL, "a history URL with a sidecar must open as-is, never remapped to its base")

func loadRenderSource(displayURL: URL, hasDocument: Bool, baseURL: URL) -> URL {
    if hasDocument, FileManager.default.fileExists(atPath: baseURL.path) {
        return baseURL
    }
    return displayURL
}

let baseURL = historyDir.appendingPathComponent("BetterShot_1.base.png")
write("base", to: baseURL)
let backgroundOnlySource = loadRenderSource(displayURL: historyURL, hasDocument: true, baseURL: baseURL)
assert(backgroundOnlySource == baseURL, "a background-only document must render from the base, not the baked composite")
let freshSource = loadRenderSource(displayURL: historyURL, hasDocument: false, baseURL: baseURL)
assert(freshSource == historyURL, "an image without a document must render as-is")

try! FileManager.default.removeItem(at: historyURL.appendingPathExtension("bettershot"))
let cleared = annotationEditorURL(for: desktopURL, beautifiedPath: desktopURL.path, rawURL: rawURL)
assert(cleared == rawURL, "a stale mapping without a sidecar must fall back to the raw source")

print("AnnotationReopenCheck: all assertions passed")
