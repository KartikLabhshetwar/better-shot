import AppKit
import SwiftUI
import TipKit

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        guard OnboardingState.shouldPresent() else { return }
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(step: OnboardingState.shouldResumePermissions() ? .permissions : .welcome)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to BetterShot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 680))
        window.contentMinSize = NSSize(width: 520, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        AppActivationPolicy.enter()
        window.makeKeyAndOrderFront(nil)
    }

    func finish(openCaptureBar: Bool = false, recordingOptions: Bool = false) {
        OnboardingState.markSeen()
        window?.close()
        if openCaptureBar { RecordingBarPresenter.shared.showPicker(recordingOptions: recordingOptions) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Explicit close dismisses the guide; quitting for a permission restart does not.
        OnboardingState.markSeen()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        AppActivationPolicy.leave()
    }
}

enum OnboardingSample: String, CaseIterable, Identifiable {
    case coast, desk
    var id: String { rawValue }
    var title: String { self == .coast ? "Coastal walk" : "A quiet workspace" }

    func sourceURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: rawValue, withExtension: "png", subdirectory: "Onboarding")
    }

    /// Work on a new, durable copy; never edit the bundle or evict a real capture from history.
    func makeWorkingCopy(in directory: URL, bundle: Bundle = .main) throws -> URL {
        guard let source = sourceURL(in: bundle) else { throw CocoaError(.fileNoSuchFile) }
        let data = try Data(contentsOf: source)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(title)-\(UUID().uuidString).png")
        try data.write(to: destination, options: .atomic)
        return destination
    }
}

struct ImageEditingTip: Tip {
    var title: Text { Text("Point out what matters") }
    var message: Text? { Text("Choose Arrow, then drag on the image. Click the tool again to return to Select. Undo with ⌘Z.") }
    var image: Image? { Image(systemName: "arrow.up.right") }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}
