import SwiftUI

@main
struct BetterShotApp: App {
    @NSApplicationDelegateAdaptor(BetterShotDelegate.self) var delegate
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        let _ = configureEditorPresentation()

        Settings {
            PreferencesView()
        }
        .defaultLaunchBehavior(.suppressed)

        WindowGroup("BetterShot Annotate", id: "ANNOTATION_EDITOR", for: URL.self) { value in
            AnnotationEditorWindow(url: value)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 760)

        WindowGroup("BetterShot Recording Editor", id: "VIDEO_EDITOR", for: URL.self) { value in
            RecordingStudioWindow(url: value)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1360, height: 860)
    }

    /// The menu bar popover, preview card, and settings history are
    /// AppKit-hosted and have no scene of their own, so they reach the
    /// editors through these closures.
    private func configureEditorPresentation() {
        PreviewPanelPresenter.shared.onAnnotate = { [openWindow] url in
            openWindow(id: "ANNOTATION_EDITOR", value: ScreenshotHistoryStore.shared.annotationEditorURL(for: url))
        }
        PreviewPanelPresenter.shared.onEditVideo = { [openWindow] url in
            openWindow(id: "VIDEO_EDITOR", value: ScreenshotHistoryStore.shared.editorURL(for: url))
        }
        RecordingProjectOpener.shared.openHandler = { [openWindow] directoryURL in
            openWindow(id: "VIDEO_EDITOR", value: directoryURL)
        }

        ScreenRecordingManager.shared.onFinishRecording = { session, _ in
            Task { @MainActor in
                let historyURL = await ScreenshotHistoryStore.shared.importRecordingSession(session)
                RecordingProjectStore.shared.reload()
                if AppPreferences.openEditorAfterCapture {
                    PreviewPanelPresenter.shared.onEditVideo?(historyURL)
                } else {
                    PreviewOverlay.shared.show(url: historyURL)
                }
            }
        }
    }
}
