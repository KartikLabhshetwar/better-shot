import AppIntents

/// Lets you draw a region, runs OCR on it, and returns the extracted text so it can be
/// chained into other Shortcuts steps (e.g. "Show Result", "Add to Notes").
struct ScanTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Text from Screen"
    static var description = IntentDescription(
        "Lets you draw a region and extracts any text found inside it via OCR."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard case let .text(text) = await CaptureOrchestrator.shared.performCapture(.ocr) else {
            throw BetterShotIntentError.ocrFailed
        }
        return .result(value: text)
    }
}
