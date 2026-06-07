import Foundation

/// Errors surfaced to the Shortcuts app / Siri when an intent can't complete.
enum BetterShotIntentError: LocalizedError {
    case captureFailed
    case ocrFailed
    case alreadyRecording
    case notRecording
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "BetterShot couldn't capture the screenshot."
        case .ocrFailed:
            return "BetterShot couldn't extract any text from the selected region."
        case .alreadyRecording:
            return "BetterShot is already recording the screen."
        case .notRecording:
            return "BetterShot isn't currently recording the screen."
        case .recordingFailed:
            return "BetterShot couldn't start screen recording."
        }
    }
}
