import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent("AnnotationExternalSaveCheck-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

func write(_ content: String, to url: URL) {
    FileManager.default.createFile(atPath: url.path, contents: Data(content.utf8))
}

func read(_ url: URL) -> String {
    String(data: FileManager.default.contents(atPath: url.path) ?? Data(), encoding: .utf8) ?? ""
}

func resolveExternalSaveURL(beautifiedPath: String?) -> URL? {
    beautifiedPath.map { URL(fileURLWithPath: $0) }
}

var reRenderedTo: URL?

func writeBack(externalSaveURL: URL?, annotatedURL: URL) {
    guard let externalURL = externalSaveURL,
          FileManager.default.fileExists(atPath: externalURL.path) else { return }
    if externalURL.pathExtension.lowercased() == "png" {
        try! FileManager.default.removeItem(at: externalURL)
        try! FileManager.default.copyItem(at: annotatedURL, to: externalURL)
    } else {
        reRenderedTo = externalURL
        write("re-rendered", to: externalURL)
    }
}

let annotated = root.appendingPathComponent("annotated.png")
write("composite", to: annotated)

assert(resolveExternalSaveURL(beautifiedPath: nil) == nil, "no beautifiedPath must resolve to nil")

let pngExternal = root.appendingPathComponent("Screenshot.png")
write("plain", to: pngExternal)
writeBack(externalSaveURL: pngExternal, annotatedURL: annotated)
assert(read(pngExternal) == "composite", "saved png must be replaced with the rendered composite")
assert(reRenderedTo == nil, "png write-back must copy, not re-render")

let jpegExternal = root.appendingPathComponent("Screenshot.jpg")
write("plain", to: jpegExternal)
writeBack(externalSaveURL: jpegExternal, annotatedURL: annotated)
assert(reRenderedTo == jpegExternal, "non-png write-back must re-render in the saved format")
assert(read(jpegExternal) == "re-rendered", "saved jpeg must hold the re-rendered composite")

let deletedExternal = root.appendingPathComponent("Deleted.png")
writeBack(externalSaveURL: deletedExternal, annotatedURL: annotated)
assert(!FileManager.default.fileExists(atPath: deletedExternal.path), "a deleted saved file must not be recreated")

writeBack(externalSaveURL: nil, annotatedURL: annotated)

print("AnnotationExternalSaveCheck: all assertions passed")
