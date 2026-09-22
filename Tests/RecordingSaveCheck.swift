import Foundation

@MainActor
struct RecordingSession {
    let directoryURL: URL
    static var metadata: [URL: RecordingProjectMetadata] = [:]
    static func isSessionDirectory(_ url: URL) -> Bool { url.pathExtension == "bettershotrec" }
    func effectiveEditDocument() -> Int? { nil }
    func freshFinalURL(matching document: Int?) -> URL? { nil }
    func loadProjectMetadata() -> RecordingProjectMetadata? { Self.metadata[directoryURL] }
    func updateProjectMetadata(_ mutate: (inout RecordingProjectMetadata) -> Void) {
        var metadata = Self.metadata[directoryURL] ?? RecordingProjectMetadata()
        mutate(&metadata)
        Self.metadata[directoryURL] = metadata
    }
}

@MainActor
enum RecordingSessionRenderer {
    static var calls = 0
    static var shouldFail = false
    static func ensureDeliverable(
        for session: RecordingSession,
        progress: (Double) -> Void = { _ in }
    ) async throws -> URL {
        calls += 1
        try await Task.sleep(for: .milliseconds(10))
        if shouldFail { throw CocoaError(.fileReadCorruptFile) }
        progress(1)
        return session.directoryURL.appendingPathComponent("final.mp4")
    }
}

@MainActor
final class DockExportProgressCoordinator {
    static let shared = DockExportProgressCoordinator()
    func start() -> UUID { UUID() }
    func finish(_ id: UUID) {}
    func update(_ id: UUID, progress: Double) {}
}

@MainActor
enum VideoFileActions {
    static var directory = FileManager.default.temporaryDirectory
    static var calls = 0
    static var lastSuggestedFileName: String?
    static func saveToDefaultLocation(from source: URL, suggestedFileName: String? = nil) async throws -> URL {
        calls += 1
        lastSuggestedFileName = suggestedFileName
        let destination = directory.appendingPathComponent("saved-\(calls)-\(suggestedFileName ?? "unnamed.mp4")")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

@main
struct RecordingSaveCheck {
    @MainActor
    static func main() async throws {
        // Start from empty settings: a run that crashed mid-check must not hand
        // its template or counter to the next run.
        UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = root.appendingPathComponent("Test.bettershotrec")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        VideoFileActions.directory = root
        let raw = session.appendingPathComponent("screen.mov")
        let final = session.appendingPathComponent("final.mp4")
        try Data("raw".utf8).write(to: raw)
        try Data("flattened".utf8).write(to: final)
        async let automatic = RecordingDeliverable.saveToDefaultLocation(for: raw)
        async let manual = RecordingDeliverable.saveToDefaultLocation(for: final)
        let (first, second) = try await (automatic, manual)
        assert(first == second)
        assert(RecordingSessionRenderer.calls == 1 && VideoFileActions.calls == 1)
        assert((try? Data(contentsOf: first)) == Data("flattened".utf8))
        assert((try? Data(contentsOf: raw)) == Data("raw".utf8))
        RecordingSessionRenderer.shouldFail = true
        do {
            _ = try await RecordingDeliverable.saveToDefaultLocation(for: raw)
            assertionFailure("Expected rendering to fail")
        } catch {}
        assert(VideoFileActions.calls == 1)
        RecordingSessionRenderer.shouldFail = false
        _ = try await RecordingDeliverable.saveToDefaultLocation(for: raw)
        assert(VideoFileActions.calls == 2)
        let standalone = root.appendingPathComponent("standalone.mp4")
        try Data("standalone".utf8).write(to: standalone)
        let copied = try await RecordingDeliverable.saveToDefaultLocation(for: standalone)
        assert((try? Data(contentsOf: copied)) == Data("standalone".utf8))
        // A recording leaving for the save folder is named from the template,
        // not from its package, which stays `Test.bettershotrec` in the gallery.
        let suggested = VideoFileActions.lastSuggestedFileName
        assert(suggested?.hasPrefix("BetterShot_") == true, "expected a template name, got \(suggested ?? "nil")")
        assert(suggested?.hasSuffix(".mp4") == true, "the deliverable's container must survive, got \(suggested ?? "nil")")
        assert(suggested?.contains("Test") == false, "the package name must not leak into the save folder")

        // A recording is named once. Saving it again, even after the template
        // changes, keeps that name and spends no further number.
        let defaults = UserDefaults.standard
        defaults.set("rec-{counter:3}", forKey: ScreenshotFileNaming.templateKey)
        defaults.removeObject(forKey: ScreenshotFileNaming.counterKey)
        defer {
            defaults.removeObject(forKey: ScreenshotFileNaming.templateKey)
            defaults.removeObject(forKey: ScreenshotFileNaming.counterKey)
        }
        let named = root.appendingPathComponent("Named.bettershotrec")
        try FileManager.default.createDirectory(at: named, withIntermediateDirectories: true)
        let namedRaw = named.appendingPathComponent("screen.mov")
        try Data("raw".utf8).write(to: namedRaw)
        try Data("flattened".utf8).write(to: named.appendingPathComponent("final.mp4"))
        _ = try await RecordingDeliverable.saveToDefaultLocation(for: namedRaw)
        let firstName = VideoFileActions.lastSuggestedFileName
        assert(firstName == "rec-001.mp4", "a recording takes its name from the template, got \(firstName ?? "nil")")
        defaults.set("later-{counter}", forKey: ScreenshotFileNaming.templateKey)
        _ = try await RecordingDeliverable.saveToDefaultLocation(for: namedRaw)
        assert(VideoFileActions.lastSuggestedFileName == firstName,
               "saving again keeps the recording's name, got \(VideoFileActions.lastSuggestedFileName ?? "nil")")
        assert(ScreenshotFileNaming.counter() == 2, "one recording spends one number, counter is \(ScreenshotFileNaming.counter())")
        print("RecordingSaveCheck: flattened output, concurrent saves, failure retry, template naming, one name per recording, and source preservation verified")
    }
}
