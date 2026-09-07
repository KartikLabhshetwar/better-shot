import Foundation
import ScreenCaptureKit

enum RecordingCaptureEntry {
    static func recordAreaOnActiveDisplay() async {
        guard !ScreenRecordingManager.shared.isActive else { return }
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: true)
        let catalog = RecordingSourceCatalog.shared
        await catalog.refresh()
        guard !ScreenRecordingManager.shared.isActive else { return }
        guard catalog.errorMessage == nil,
              let display = catalog.displays.first(where: { $0.displayID == displayID })
                ?? catalog.displays.first else {
            ToastWindow.shared.show(
                title: "Couldn't start recording",
                message: catalog.errorMessage ?? "No display is available to record.",
                systemIcon: "exclamationmark.triangle"
            )
            return
        }
        RecordingBarPresenter.shared.hide()
        recordArea(display)
    }

    static func recordFullscreen(_ display: SCDisplay) {
        Task {
            await CaptureCountdownPresenter.shared.runIfNeeded(
                seconds: BetterShotPreferences.recordingStartDelaySeconds,
                displayID: display.displayID
            )
            ScreenRecordingManager.shared.startRecording(source: ScreenRecordingSource(kind: .fullscreen(display)))
        }
    }

    static func recordWindow(_ window: SCWindow) {
        Task {
            let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: true)
            await CaptureCountdownPresenter.shared.runIfNeeded(
                seconds: BetterShotPreferences.recordingStartDelaySeconds,
                displayID: displayID
            )
            ScreenRecordingManager.shared.startRecording(source: ScreenRecordingSource(kind: .window(window)))
        }
    }

    static func recordArea(_ display: SCDisplay) {
        RecordingAreaSelectionPresenter.shared.selectArea(on: display) { rect in
            guard let rect else { return }
            Task {
                await CaptureCountdownPresenter.shared.runIfNeeded(
                    seconds: BetterShotPreferences.recordingStartDelaySeconds,
                    displayID: display.displayID
                )
                ScreenRecordingManager.shared.startRecording(
                    source: ScreenRecordingSource(kind: .area(display: display, rect: rect))
                )
            }
        }
    }
}
