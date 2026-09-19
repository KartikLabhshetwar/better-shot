//
//  AfterCaptureActions.swift
//  BetterShot
//
//  Configurable "what happens after a capture" pipeline, per capture type
//  (screenshot vs recording), mirroring CleanShot's General > After capture
//  matrix. Screenshot auto-save is an explicit opt-in starting in 0.5.4.
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

    /// Default when the user hasn't chosen yet. The overlay defaults on, and
    /// recordings open in the studio so zooms/backgrounds are discoverable.
    var defaultValue: Bool {
        self == .showOverlay || self == .openVideoEditor
    }
}

enum AfterCaptureActions {
    static func isEnabled(_ action: AfterCaptureAction, for type: AfterCaptureType) -> Bool {
        let key = action.storageKey(for: type)
        if UserDefaults.standard.object(forKey: key) == nil {
            return action.defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}
