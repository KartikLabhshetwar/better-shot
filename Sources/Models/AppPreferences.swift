import Foundation
import AppKit
import SwiftUI

enum AppPreferences {
    // MARK: - Keys
    private static let appearanceKey = "bs_appAppearance"
    private static let saveDirKey = "bs_saveDirectory"
    private static let copyAfterSaveKey = "bs_copyAfterSave"
    private static let playSoundKey = "bs_playSound"
    private static let overlayPositionKey = "bs_overlayPosition"
    private static let overlayDismissDelayKey = "bs_overlayDismissDelay"
    private static let overlayCardSizeKey = "bs_overlayCardSize"
    private static let overlayEdgeMarginKey = "bs_overlayEdgeMargin"
    private static let exportFormatKey = "bs_exportFormat"
    private static let exportQualityKey = "bs_exportQuality"
    private static let selfTimerKey = "bs_selfTimerDelay"
    static let recordingCaptureKeystrokesKey = "bs_recordingCaptureKeystrokes"
    private static let openEditorAfterCaptureKey = "bs_openEditorAfterCapture"
    private static let keepInDeckUntilSavedKey = "bs_keepInDeckUntilSaved"
    private static let historyRetentionKey = "bs_historyRetentionLimit"
    private static let recordingCaptureMicrophoneKey = "bs_recordingCaptureMicrophone"
    private static let recordingStartDelaySecondsKey = "bs_recordingStartDelaySeconds"
    private static let recordingShowCameraKey = "bs_recordingShowCamera"
    private static let recordingCameraSizeKey = "bs_recordingCameraSize"
    private static let recordingCameraDeviceIDKey = "bs_recordingCameraDeviceID"
    private static let recordingMicrophoneDeviceIDKey = "bs_recordingMicrophoneDeviceID"
    private static let lastRegionRectKey = "bs_lastRegionRect"

    // MARK: - Appearance
    static var appearance: AppAppearance {
        get {
            guard let raw = UserDefaults.standard.string(forKey: appearanceKey),
                  let appearance = AppAppearance(rawValue: raw) else { return .system }
            return appearance
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey) }
    }

    @MainActor
    static func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    // MARK: - General
    static var saveDirectory: String {
        get { UserDefaults.standard.string(forKey: saveDirKey) ?? NSHomeDirectory() + "/Desktop" }
        set { UserDefaults.standard.set(newValue, forKey: saveDirKey) }
    }

    static var copyAfterSave: Bool {
        get { UserDefaults.standard.object(forKey: copyAfterSaveKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: copyAfterSaveKey) }
    }

    static var playSound: Bool {
        get { UserDefaults.standard.object(forKey: playSoundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: playSoundKey) }
    }

    /// Last region screenshot in global AppKit screen coordinates, redrawn as a ghost next time.
    static var lastRegionRect: CGRect? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: lastRegionRectKey) else { return nil }
            let rect = NSRectFromString(raw)
            return rect.isEmpty ? nil : rect
        }
        set { UserDefaults.standard.set(newValue.map(NSStringFromRect), forKey: lastRegionRectKey) }
    }

    // MARK: - Overlay
    static var overlayPosition: OverlayPosition {
        get {
            guard let raw = UserDefaults.standard.string(forKey: overlayPositionKey),
                  let pos = OverlayPosition(rawValue: raw) else { return .bottomRight }
            return pos
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: overlayPositionKey) }
    }

    static let overlayDismissNever: Double = 16
    static let overlayDismissRange: ClosedRange<Double> = 2...overlayDismissNever

    /// The top of the slider means "leave it up", so anything at or above the sentinel never auto-hides.
    static func overlayDismisses(after delay: Double) -> Bool { delay < overlayDismissNever }

    static var overlayDismissDelay: Double {
        get {
            let val = UserDefaults.standard.double(forKey: overlayDismissDelayKey)
            return val > 0 ? val : 5.0
        }
        set { UserDefaults.standard.set(newValue, forKey: overlayDismissDelayKey) }
    }

    static var overlayCardSize: OverlayCardSize {
        get {
            guard let raw = UserDefaults.standard.string(forKey: overlayCardSizeKey),
                  let size = OverlayCardSize(rawValue: raw) else { return .small }
            return size
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: overlayCardSizeKey) }
    }

    static let overlayEdgeMarginDefault: Double = 20
    static let overlayEdgeMarginRange: ClosedRange<Double> = 0...48

    static var overlayEdgeMargin: Double {
        get { UserDefaults.standard.object(forKey: overlayEdgeMarginKey) as? Double ?? overlayEdgeMarginDefault }
        set { UserDefaults.standard.set(newValue, forKey: overlayEdgeMarginKey) }
    }

    // MARK: - Export
    static var exportFormat: ExportFormat {
        get {
            guard let raw = UserDefaults.standard.string(forKey: exportFormatKey),
                  let fmt = ExportFormat(rawValue: raw) else { return .png }
            return fmt
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: exportFormatKey) }
    }

    static var exportQuality: Double {
        get {
            let val = UserDefaults.standard.double(forKey: exportQualityKey)
            return val > 0 ? val : 0.9
        }
        set { UserDefaults.standard.set(newValue, forKey: exportQualityKey) }
    }

    // MARK: - Self Timer
    static var selfTimerDelay: SelfTimerDelay {
        get {
            let val = UserDefaults.standard.integer(forKey: selfTimerKey)
            return SelfTimerDelay(rawValue: val) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selfTimerKey) }
    }

    // MARK: - Recording
    static var recordingCaptureKeystrokes: Bool {
        get { UserDefaults.standard.object(forKey: recordingCaptureKeystrokesKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: recordingCaptureKeystrokesKey) }
    }

    static var recordingCaptureMicrophone: Bool {
        get { UserDefaults.standard.object(forKey: recordingCaptureMicrophoneKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: recordingCaptureMicrophoneKey) }
    }

    static var recordingStartDelaySeconds: Int {
        get { UserDefaults.standard.integer(forKey: recordingStartDelaySecondsKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingStartDelaySecondsKey) }
    }

    static var recordingShowCamera: Bool {
        get { UserDefaults.standard.object(forKey: recordingShowCameraKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: recordingShowCameraKey) }
    }

    static var recordingCameraSize: Int {
        get { UserDefaults.standard.object(forKey: recordingCameraSizeKey) as? Int ?? 200 }
        set { UserDefaults.standard.set(newValue, forKey: recordingCameraSizeKey) }
    }

    static var recordingCameraDeviceID: String? {
        get { UserDefaults.standard.string(forKey: recordingCameraDeviceIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingCameraDeviceIDKey) }
    }

    static var recordingMicrophoneDeviceID: String? {
        get { UserDefaults.standard.string(forKey: recordingMicrophoneDeviceIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingMicrophoneDeviceIDKey) }
    }

    static let editorOpensFullScreenKey = "bs_editorOpensFullScreen"
    static var editorOpensFullScreen: Bool {
        UserDefaults.standard.object(forKey: editorOpensFullScreenKey) as? Bool ?? true
    }

    static let openEditorAfterRecordingKey = "bs_openEditorAfterRecording"
    static func migrateEditorPreferences() {
        if UserDefaults.standard.object(forKey: openEditorAfterRecordingKey) == nil {
            UserDefaults.standard.set(openEditorAfterCapture, forKey: openEditorAfterRecordingKey)
        }
    }

    static var openEditorAfterRecording: Bool {
        UserDefaults.standard.object(forKey: openEditorAfterRecordingKey) as? Bool
            ?? openEditorAfterCapture
    }

    // MARK: - Screenshot
    static var openEditorAfterCapture: Bool {
        get { UserDefaults.standard.object(forKey: openEditorAfterCaptureKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: openEditorAfterCaptureKey) }
    }

    static var keepInDeckUntilSaved: Bool {
        get { UserDefaults.standard.bool(forKey: keepInDeckUntilSavedKey) }
        set { UserDefaults.standard.set(newValue, forKey: keepInDeckUntilSavedKey) }
    }

    // MARK: - History
    /// How many captures history keeps. 0 means unlimited.
    static var historyRetentionLimit: Int {
        get { UserDefaults.standard.object(forKey: historyRetentionKey) as? Int ?? 100 }
        set { UserDefaults.standard.set(newValue, forKey: historyRetentionKey) }
    }

    // MARK: - Default Beautifier Config
    static var defaultBeautifierConfig: BeautifierConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: "bs_defaultBeautifierConfig"),
                  let config = try? JSONDecoder().decode(BeautifierConfig.self, from: data)
            else { return .default }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "bs_defaultBeautifierConfig")
            }
        }
    }
}

// MARK: - Enums

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum OverlayPosition: String, CaseIterable, Codable {
    case bottomRight = "bottomRight"
    case bottomLeft = "bottomLeft"
}

enum OverlayCardSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Room for the card's `.shadow(radius: 14, y: 6)` to draw inside the panel bounds.
    private static let shadowHeadroom: CGFloat = 24

    func panelSize(margin: Double) -> CGSize {
        CGSize(
            width: thumbnailSize.width + margin + Self.shadowHeadroom,
            height: thumbnailSize.height + margin + Self.shadowHeadroom
        )
    }

    /// Hover control scale, deliberately sub-linear to the thumbnail ratio.
    var controlScale: CGFloat {
        switch self {
        case .small: return 1.0
        case .medium: return 1.25
        case .large: return 1.5
        }
    }

    /// The visible thumbnail drawn inside the panel.
    var thumbnailSize: CGSize {
        switch self {
        case .small: return CGSize(width: 130, height: 98)
        case .medium: return CGSize(width: 190, height: 140)
        case .large: return CGSize(width: 250, height: 180)
        }
    }
}

enum ExportFormat: String, CaseIterable {
    case png, jpeg

    var utType: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}

enum HistoryRetention: Int, CaseIterable, Identifiable {
    case fifty = 50
    case hundred = 100
    case twoFifty = 250
    case fiveHundred = 500
    case unlimited = 0

    var id: Int { rawValue }

    var label: String {
        self == .unlimited ? "Unlimited" : "\(rawValue) captures"
    }
}

enum SelfTimerDelay: Int, CaseIterable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    var label: String {
        switch self {
        case .off: return "Off"
        default: return "\(rawValue)s"
        }
    }
}
