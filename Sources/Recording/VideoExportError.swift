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
    case saveFailed(URL, Error)
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
        case .saveFailed(let folder, let error):
            return "The video rendered, but it could not be saved to \(folder.path).\(Self.detail(error))"
        case .exportCancelled:
            return "The export was cancelled."
        }
    }

    /// AVFoundation hides the real cause behind "The operation could not be completed", so the reason and the underlying error come along too.
    private static func detail(_ error: Error?) -> String {
        guard let error else { return "" }
        let ns = error as NSError
        var parts = [ns.localizedDescription]
        if let reason = ns.localizedFailureReason, !reason.isEmpty { parts.append(reason) }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("\(underlying.domain) \(underlying.code): \(underlying.localizedDescription)")
        }
        parts.append("\(ns.domain) \(ns.code)")
        return " (\(parts.joined(separator: " \u{2022} ")))"
    }
}
