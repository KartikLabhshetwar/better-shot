import Foundation

struct RecordingSession {
    let directoryURL: URL
    static func isSessionDirectory(_ url: URL) -> Bool { url.pathExtension == "bettershotrec" }
    func effectiveEditDocument() -> Int? { nil }
    func freshFinalURL(matching document: Int?) -> URL? { nil }
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
    static func saveToDefaultLocation(from source: URL) async throws -> URL {
        calls += 1
        let destination = directory.appendingPathComponent("saved-\(calls).mp4")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

@main
struct RecordingSaveCheck {
    @MainActor
    static func main() async throws {
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
        print("RecordingSaveCheck: flattened output, concurrent saves, failure retry, and source preservation verified")
    }
}
