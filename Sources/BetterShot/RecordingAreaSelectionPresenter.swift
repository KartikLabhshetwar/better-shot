import AppKit
import ScreenCaptureKit

@MainActor
final class RecordingAreaSelectionPresenter {
    static let shared = RecordingAreaSelectionPresenter()
    private var isSelecting = false

    func selectArea(completion: @escaping (SCDisplay, CGRect) -> Void) {
        guard !isSelecting else { return }
        isSelecting = true
        Task {
            defer { isSelecting = false }
            let outcome = await RegionSelectionOverlay().selectRegion(allowsWindowSelection: false)
            guard case .region(let selection) = outcome else {
                RecordingBarPresenter.shared.showPicker(recordingOptions: true)
                return
            }
            await RecordingSourceCatalog.shared.refresh()
            guard let display = RecordingSourceCatalog.shared.displays.first(where: { $0.displayID == selection.displayID }) else {
                RecordingBarPresenter.shared.showPicker(recordingOptions: true)
                return
            }
            let rect = RegionGeometry.pointsRect(global: selection.pointsRect,
                primaryHeight: CGDisplayBounds(CGMainDisplayID()).height)
            completion(display, rect)
        }
    }
}
