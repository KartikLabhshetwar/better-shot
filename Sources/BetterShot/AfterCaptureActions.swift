//
//  AfterCaptureActions.swift
//  BetterShot
//
//  Configurable "what happens after a capture" pipeline, per capture type
//  (screenshot vs recording), mirroring CleanShot's General > After capture
//  matrix. New installs save normal screenshots automatically; upgrades keep
//  their previous saving behavior.
//

import Foundation

enum AfterCaptureType: String {
    case screenshot
    case recording
}

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case showOverlay
    case copy
    case save
    case upload
    case annotate
    case pin
    case openVideoEditor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showOverlay: "Show preview overlay"
        case .copy: "Copy to clipboard"
        case .save: "Save to folder"
        case .upload: "Upload to Cloud & copy link"
        case .annotate: "Open annotation editor"
        case .pin: "Pin to screen"
        case .openVideoEditor: "Open recording editor"
        }
    }

    var subtitle: String {
        switch self {
        case .showOverlay: "Show the floating preview card after capturing."
        case .copy: "Copy the capture to the clipboard."
        case .save: "Automatically save the capture to the export folder."
        case .upload: "Upload to your cloud and copy the share link."
        case .annotate: "Jump straight into the annotation editor."
        case .pin: "Pin the screenshot on top of everything for reference."
        case .openVideoEditor: "Edit the clip, background, camera, audio, and zooms in one place."
        }
    }

    /// The actions that apply to a given capture type, in display order.
    static func actions(for type: AfterCaptureType) -> [AfterCaptureAction] {
        switch type {
        case .screenshot:
            [.showOverlay, .copy, .save, .upload, .annotate, .pin]
        case .recording:
            [.showOverlay, .copy, .save, .upload, .openVideoEditor]
        }
    }

    /// Screenshot Save deliberately ignores the dormant legacy autoSaveScreenshots
    /// key, so upgrading never silently re-enables exports to the save folder.
    func storageKey(for type: AfterCaptureType) -> String {
        switch (self, type) {
        case (.copy, .screenshot):
            return BetterShotPreferences.autoCopyKey
        case (.save, .screenshot):
            return "afterCapture.screenshot.save"
        default:
            return "afterCapture.\(type.rawValue).\(rawValue)"
        }
    }

    /// New-install defaults. Screenshot saving does not enable recording exports.
    func defaultValue(for type: AfterCaptureType) -> Bool {
        self == .showOverlay || self == .openVideoEditor || (self == .save && type == .screenshot)
    }
}

enum AfterCaptureActions {
    /// Pin the previous default off on upgrades, including installs that never
    /// touched the toggle. Explicit choices always win; dormant legacy keys do not.
    static func prepareForLaunch(isNewInstall: Bool, defaults: UserDefaults = .standard) {
        let key = AfterCaptureAction.save.storageKey(for: .screenshot)
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(isNewInstall && AfterCaptureAction.save.defaultValue(for: .screenshot), forKey: key)
    }

    static func isEnabled(_ action: AfterCaptureAction, for type: AfterCaptureType,
                          defaults: UserDefaults = .standard) -> Bool {
        let key = action.storageKey(for: type)
        return defaults.object(forKey: key) as? Bool ?? action.defaultValue(for: type)
    }
}
