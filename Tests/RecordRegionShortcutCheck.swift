import AppKit
import Foundation

@MainActor
enum ActiveDisplayResolver {
    static func activeScreen(preferPointer: Bool) -> NSScreen? { nil }
}

@MainActor
final class ScreenRecordingManager {
    static let shared = ScreenRecordingManager()
    var isActive = false
}

@MainActor
final class RecordingBarPresenter {
    static let shared = RecordingBarPresenter()
    func togglePicker() {}
}

@MainActor
enum RecordingCaptureEntry {
    static func recordAreaOnActiveDisplay() async {}
}

@MainActor
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()
    func performCapture(_ action: ShortcutService.Action, on screen: NSScreen?) async {}
}

@main
struct RecordRegionShortcutCheck {
    @MainActor
    static func main() throws {
        let action = ShortcutService.Action.recordingArea
        let shortcut = action.defaultShortcut!
        assert(action.rawValue == 7)
        assert(ShortcutService.Action.recording.rawValue == 6)
        assert(!shortcut.enabled)
        assert(shortcut.keyCode == ShortcutService.Shortcut.defaultRecording.keyCode)
        assert(shortcut.modifiers != ShortcutService.Shortcut.defaultRecording.modifiers)
        assert(Set(ShortcutService.Action.allCases.map(\.rawValue)).count == 7)
        var rebound = shortcut
        rebound.keyCode = 15
        rebound.enabled = true
        let data = try JSONEncoder().encode(rebound)
        let decoded = try JSONDecoder().decode(ShortcutService.Shortcut.self, from: data)
        assert(decoded == rebound)
        print("RecordRegionShortcutCheck: separate action, safe defaults, and rebinding verified")
    }
}
