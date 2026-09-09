import Foundation
import ScreenCaptureKit

enum RecordingCaptureEntry {
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

    static func recordArea() {
        RecordingAreaSelectionPresenter.shared.selectArea { display, rect in
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
