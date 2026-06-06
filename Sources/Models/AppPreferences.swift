import Foundation
import SwiftUI

enum AppPreferences {
    // MARK: - Keys
    private static let saveDirKey = "bs_saveDirectory"
    private static let copyAfterSaveKey = "bs_copyAfterSave"
    private static let playSoundKey = "bs_playSound"
    private static let showOverlayKey = "bs_showOverlay"
    private static let screenshotModeKey = "bs_screenshotMode"
    private static let overlayPositionKey = "bs_overlayPosition"
    private static let overlayDismissDelayKey = "bs_overlayDismissDelay"
    private static let exportFormatKey = "bs_exportFormat"
    private static let exportQualityKey = "bs_exportQuality"
    private static let selfTimerKey = "bs_selfTimerDelay"

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

    static var showOverlayAfterCapture: Bool {
        get { UserDefaults.standard.object(forKey: showOverlayKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showOverlayKey) }
    }

    static var screenshotMode: ScreenshotMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: screenshotModeKey),
                  let mode = ScreenshotMode(rawValue: raw) else { return .editor }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: screenshotModeKey) }
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

    static var overlayDismissDelay: Double {
        get {
            let val = UserDefaults.standard.double(forKey: overlayDismissDelayKey)
            return val > 0 ? val : 5.0
        }
        set { UserDefaults.standard.set(newValue, forKey: overlayDismissDelayKey) }
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

enum OverlayPosition: String, CaseIterable, Codable {
    case bottomRight = "bottomRight"
    case bottomLeft = "bottomLeft"
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

enum ScreenshotMode: String, CaseIterable {
    case editor
    case gallery

    var label: String {
        switch self {
        case .editor: return "Editor"
        case .gallery: return "Gallery"
        }
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
