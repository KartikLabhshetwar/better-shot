import Foundation

enum VideoExportError: LocalizedError {
    case noSourceRecording
    case noVideoTrack
    case emptyClipTimeline
    case clipCompositionFailed(Error?)
    case compositionTrackUnavailable
    case trimInsertFailed(Error)
    case exportSessionUnavailable
    case exportFailed(Error?)
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noSourceRecording:
            return "This recording is no longer available."
        case .noVideoTrack:
            return "The recording has no video track."
        case .emptyClipTimeline:
            return "Every clip has been trimmed away."
        case .clipCompositionFailed(let error):
            return "Could not assemble the clips.\(Self.detail(error))"
        case .compositionTrackUnavailable:
            return "Could not build the video composition."
        case .trimInsertFailed(let error):
            return "Could not apply the trim.\(Self.detail(error))"
        case .exportSessionUnavailable:
            return "Could not start the export session."
        case .exportFailed(let error):
            return "The export did not finish.\(Self.detail(error))"
        case .exportCancelled:
            return "The export was cancelled."
        }
    }

    private static func detail(_ error: Error?) -> String {
        guard let error else { return "" }
        return " (\(error.localizedDescription))"
    }
}
