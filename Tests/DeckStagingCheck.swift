import Foundation

// Mirror of DeckStaging's rules (Sources/Preview/DeckStaging.swift), run against a scratch directory.

let base = FileManager.default.temporaryDirectory.appendingPathComponent("DeckStagingCheck-\(UUID().uuidString)", isDirectory: true)
let directory = base.appendingPathComponent("deck", isDirectory: true)
let saveDir = base.appendingPathComponent("save", isDirectory: true)
try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: base) }

var savedCopies: [URL: URL] = [:]

func isStaged(_ url: URL) -> Bool {
    url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
}

func rawURL(for stagedURL: URL) -> URL {
    stagedURL.deletingPathExtension().appendingPathExtension("raw.png")
}

@MainActor func promote(_ url: URL) -> URL {
    guard isStaged(url) else { return url }
    if let saved = savedCopies[url] { return saved }
    let dest = saveDir.appendingPathComponent(url.lastPathComponent)
    try! FileManager.default.copyItem(at: url, to: dest)
    try? FileManager.default.removeItem(at: rawURL(for: url))
    savedCopies[url] = dest
    return dest
}

@MainActor func discard(_ url: URL) {
    guard isStaged(url) else { return }
    savedCopies.removeValue(forKey: url)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.removeItem(at: rawURL(for: url))
}

let staged = directory.appendingPathComponent("bettershot_1.jpg")
let raw = rawURL(for: staged)
assert(raw.lastPathComponent == "bettershot_1.raw.png", "raw sibling derives from the staged name")
assert(isStaged(staged) && !isStaged(saveDir.appendingPathComponent("bettershot_1.jpg")), "only files under deck/ count as staged")
assert(!isStaged(base.appendingPathComponent("deckother.png")), "prefix match needs the directory separator")

FileManager.default.createFile(atPath: staged.path, contents: Data([1, 2, 3]))
FileManager.default.createFile(atPath: raw.path, contents: Data([4]))

let outside = saveDir.appendingPathComponent("elsewhere.png")
assert(promote(outside) == outside, "unstaged files promote to themselves")

let saved = promote(staged)
assert(saved == saveDir.appendingPathComponent("bettershot_1.jpg"), "promotion lands in the save folder under the same name")
assert(FileManager.default.fileExists(atPath: saved.path) && FileManager.default.fileExists(atPath: staged.path), "staged copy stays for the deck card")
assert(!FileManager.default.fileExists(atPath: raw.path), "raw moves into the Library on promotion")
assert(promote(staged) == saved, "promoting twice returns the same saved file")
assert((try? FileManager.default.contentsOfDirectory(atPath: saveDir.path))?.count == 1, "promoting twice saves once")

discard(staged)
assert(!FileManager.default.fileExists(atPath: staged.path), "discard removes the staged copy")
assert(FileManager.default.fileExists(atPath: saved.path), "discard leaves the saved copy alone")
assert(savedCopies.isEmpty, "discard forgets the saved mapping")

let untouched = directory.appendingPathComponent("bettershot_2.png")
FileManager.default.createFile(atPath: untouched.path, contents: Data([9]))
FileManager.default.createFile(atPath: rawURL(for: untouched).path, contents: Data([9]))
discard(untouched)
assert((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true, "discarding an unsaved card deletes both staged files")

print("DeckStagingCheck passed")
