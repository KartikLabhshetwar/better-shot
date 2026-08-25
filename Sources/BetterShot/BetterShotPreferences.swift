//
//  BetterShotPreferences.swift
//  BetterShot
//
//  Created by Codex on 26/04/26.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum BetterShotPreferences {
    static let autoSaveKey = "autoSaveScreenshots"
    static let saveButtonUsesFolderKey = "saveButtonUsesConfiguredFolder"
    static let autoCopyKey = "autoCopyScreenshotsToClipboard"
    static let fullscreenHotkeyKey = "captureHotkey.fullscreen"
    static let windowHotkeyKey = "captureHotkey.window"
    static let areaHotkeyKey = "captureHotkey.area"
    static let screenRecordingHotkeyKey = "captureHotkey.screenRecording"
    static let playSoundsKey = "playSounds"
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let includeAppWindowsInCapturesKey = "includeAppWindowsInCaptures"
    static let captureWindowShadowKey = "captureWindowShadow"
    static let captureDelaySecondsKey = "captureDelaySeconds"
    static let previewPositionKey = "previewPosition"
    static let previewAutoCloseSecondsKey = "previewAutoCloseSeconds"
    static let previewCloseAfterDraggingKey = "previewCloseAfterDragging"
    static let overlayCardLayoutKey = "overlayCardLayout"
    static let lowResolutionEditorPreviewKey = "lowResolutionEditorPreview"
    static let trimFullscreenMenuBarKey = "trimFullscreenMenuBar"
    static let recordingCameraDeviceIDKey = "recordingCameraDeviceID"
    static let recordingMicrophoneDeviceIDKey = "recordingMicrophoneDeviceID"
    static let recordingSystemAudioKey = "recordingSystemAudio"
    static let recordingStartDelaySecondsKey = "recordingStartDelaySeconds"
    static let recordingTeleprompterEnabledKey = "recordingTeleprompterEnabled"
    static let recordingTeleprompterScriptKey = "recordingTeleprompterScript"
    static let recordingTeleprompterLineCountKey = "recordingTeleprompterLineCount"
    static let revealExportInFinderKey = "revealExportInFinder"

    static var autoSave: Bool {
        UserDefaults.standard.bool(forKey: autoSaveKey)
    }

    static var saveButtonUsesConfiguredFolder: Bool {
        if UserDefaults.standard.object(forKey: saveButtonUsesFolderKey) == nil {
            return autoSave
        }
        return UserDefaults.standard.bool(forKey: saveButtonUsesFolderKey)
    }
    
    static var autoCopy: Bool {
        UserDefaults.standard.bool(forKey: autoCopyKey)
    }
    
    /// Format, quality, and destination all mirror the choices made in
    /// Settings > General, so editor exports and fresh captures always land
    /// in the same folder as the same kind of file.
    static var exportFormat: ScreenshotExportFormat {
        AppPreferences.exportFormat == .jpeg ? .jpeg : .png
    }

    static var compressionQuality: Double {
        min(max(AppPreferences.exportQuality, 0.1), 1)
    }

    static var exportDirectory: URL {
        URL(fileURLWithPath: AppPreferences.saveDirectory, isDirectory: true)
    }

    /// Unique ID of the camera recorded alongside the screen. Empty = camera off.
    static var recordingCameraDeviceID: String {
        get { UserDefaults.standard.string(forKey: recordingCameraDeviceIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: recordingCameraDeviceIDKey) }
    }

    /// Unique ID of the microphone captured during recordings. Empty = mic off.
    static var recordingMicrophoneDeviceID: String {
        get { UserDefaults.standard.string(forKey: recordingMicrophoneDeviceIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: recordingMicrophoneDeviceIDKey) }
    }

    /// Whether recordings include system audio. Defaults to off.
    static var recordingSystemAudio: Bool {
        get { UserDefaults.standard.bool(forKey: recordingSystemAudioKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingSystemAudioKey) }
    }

    /// Countdown delay (in seconds) before a recording starts. 0 means off.
    static var recordingStartDelaySeconds: Int {
        max(0, UserDefaults.standard.integer(forKey: recordingStartDelaySecondsKey))
    }

    /// Whether the notch teleprompter appears during recordings. Defaults to off.
    static var recordingTeleprompterEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: recordingTeleprompterEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingTeleprompterEnabledKey) }
    }

    /// The script read from the teleprompter. Empty means nothing to show.
    static var recordingTeleprompterScript: String {
        get { UserDefaults.standard.string(forKey: recordingTeleprompterScriptKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: recordingTeleprompterScriptKey) }
    }

    static let teleprompterLineCountRange = 2...5

    /// How many script lines the teleprompter shows at once.
    static var recordingTeleprompterLineCount: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: recordingTeleprompterLineCountKey)
            guard stored != 0 else { return 3 }
            return min(max(stored, teleprompterLineCountRange.lowerBound), teleprompterLineCountRange.upperBound)
        }
        set { UserDefaults.standard.set(newValue, forKey: recordingTeleprompterLineCountKey) }
    }

    /// Whether to play the shutter sound after a screenshot. Defaults to on.
    static var playSounds: Bool {
        if UserDefaults.standard.object(forKey: playSoundsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: playSoundsKey)
    }

    /// Whether the menu bar icon is shown. Defaults to on.
    static var showMenuBarIcon: Bool {
        if UserDefaults.standard.object(forKey: showMenuBarIconKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: showMenuBarIconKey)
    }

    /// Whether BetterShot's own windows and floating controls are visible in
    /// screenshots and screen recordings. Defaults to off for capture privacy.
    static var includeAppWindowsInCaptures: Bool {
        UserDefaults.standard.bool(forKey: includeAppWindowsInCapturesKey)
    }

    /// Whether captured windows include their drop shadow. Defaults to off
    /// (tighter, shadow-free crops).
    static var captureWindowShadow: Bool {
        UserDefaults.standard.bool(forKey: captureWindowShadowKey)
    }

    /// Countdown delay (in seconds) before a capture is taken. 0 means off.
    static var captureDelaySeconds: Int {
        max(0, UserDefaults.standard.integer(forKey: captureDelaySecondsKey))
    }

    /// Which screen corner the preview overlay docks to.
    static var previewPosition: PreviewOverlayPosition {
        guard let raw = UserDefaults.standard.string(forKey: previewPositionKey),
              let position = PreviewOverlayPosition(rawValue: raw) else {
            return .right
        }
        return position
    }

    /// Seconds before the preview overlay auto-dismisses. 0 means never.
    static var previewAutoCloseSeconds: Int {
        max(0, UserDefaults.standard.integer(forKey: previewAutoCloseSecondsKey))
    }

    /// Whether dragging a preview card out dismisses it. Defaults to on.
    static var previewCloseAfterDragging: Bool {
        if UserDefaults.standard.object(forKey: previewCloseAfterDraggingKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: previewCloseAfterDraggingKey)
    }

    /// Whether the annotation editor displays a downscaled preview of the
    /// screenshot to reduce memory usage. This only affects the on-screen
    /// editing preview - exported images are always rendered at full
    /// resolution. Defaults to on.
    static var lowResolutionEditorPreview: Bool {
        if UserDefaults.standard.object(forKey: lowResolutionEditorPreviewKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: lowResolutionEditorPreviewKey)
    }
    
    /// Whether a finished Studio export selects the file in Finder. An export
    /// is a deliberate "hand me the file" action, so this defaults to on.
    static var revealExportInFinder: Bool {
        if UserDefaults.standard.object(forKey: revealExportInFinderKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: revealExportInFinderKey)
    }

    /// Whether fullscreen captures on notched displays trim the empty black
    /// menu-bar strip at the top. The strip is only removed when it's solid
    /// black (menu bar hidden); a revealed menu bar is preserved. Defaults to on.
    static var trimFullscreenMenuBar: Bool {
        if UserDefaults.standard.object(forKey: trimFullscreenMenuBarKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: trimFullscreenMenuBarKey)
    }
}

enum PreviewOverlayPosition: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Bottom left"
        case .right: "Bottom right"
        }
    }
}

enum ScreenshotExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png:
            "PNG"
        case .jpeg:
            "JPEG"
        case .heic:
            "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:
            "png"
        case .jpeg:
            "jpg"
        case .heic:
            "heic"
        }
    }

    var contentType: UTType {
        switch self {
        case .png:
            .png
        case .jpeg:
            .jpeg
        case .heic:
            .heic
        }
    }

    var usesLossyQuality: Bool {
        self != .png
    }
}

enum ScreenshotFileActions {
    static func copyImageToClipboard(from url: URL) throws {
        let contentType = UTType(filenameExtension: url.pathExtension)
        let dataType: NSPasteboard.PasteboardType = if contentType?.conforms(to: .jpeg) == true {
            NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        } else {
            .png
        }

        try copyImageToClipboard(from: url, dataType: dataType)
    }

    static func copyPNGToClipboard(from url: URL) throws {
        try copyImageToClipboard(from: url, dataType: .png)
    }

    private static func copyImageToClipboard(from url: URL, dataType: NSPasteboard.PasteboardType) throws {
        let imageData = try Data(contentsOf: url, options: .mappedIfSafe)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Write several representations on a single pasteboard item so that
        // every kind of paste target can find a flavor it understands:
        //
        // - `.fileURL`: terminals and apps that "paste a file" (e.g. opencode's
        //   terminal, editors, Slack) read the file reference from disk.
        // - image data / `.tiff`: rich-text and web targets (Gmail, Notes, Mail,
        //   image editors) read raw pixels directly.
        //
        // Only providing image data is why pasting worked in Gmail but not in
        // terminal apps - those read the file URL flavor instead.
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(imageData, forType: dataType)
        if let tiffData = NSBitmapImageRep(data: imageData)?.tiffRepresentation
            ?? NSImage(data: imageData)?.tiffRepresentation {
            item.setData(tiffData, forType: .tiff)
        }

        pasteboard.writeObjects([item])
    }
    
    @discardableResult
    static func saveToDefaultLocation(from url: URL) throws -> URL {
        let destinationDirectory = BetterShotPreferences.exportDirectory
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        
        let destinationURL = uniqueDestinationURL(
            for: exportFileName(for: url),
            in: destinationDirectory
        )
        try save(from: url, to: destinationURL)
        return destinationURL
    }
    
    static func save(from sourceURL: URL, to destinationURL: URL) throws {
        if BetterShotPreferences.exportFormat == .png {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } else {
            try exportImage(from: sourceURL, to: destinationURL, contentType: BetterShotPreferences.exportFormat.contentType)
        }
    }

    /// Updates an already-associated export without changing its file format.
    /// The replacement is staged beside the destination and atomically swapped
    /// in only after encoding succeeds, so the last good export is never deleted
    /// first. Pixel dimensions are preserved; PNG-to-PNG updates copy bytes.
    static func replaceExistingExport(from sourceURL: URL, at destinationURL: URL) throws {
        guard let destinationType = exportContentType(for: destinationURL) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".BetterShot-\(UUID().uuidString)-\(destinationURL.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        if destinationType == .png, actualImageContentType(at: sourceURL) == .png {
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
        } else {
            try exportImage(from: sourceURL, to: stagingURL, contentType: destinationType)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
        }
    }
    
    static func exportFileName(for sourceURL: URL) -> String {
        return sourceURL
            .deletingPathExtension()
            .appendingPathExtension(BetterShotPreferences.exportFormat.fileExtension)
            .lastPathComponent
    }
    
    static var exportContentType: UTType {
        BetterShotPreferences.exportFormat.contentType
    }
    
    private static func exportImage(from sourceURL: URL, to destinationURL: URL, contentType: UTType) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        let options: [CFString: Any] = contentType == .png ? [:] : [
            kCGImageDestinationLossyCompressionQuality: BetterShotPreferences.compressionQuality
        ]
        
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func exportContentType(for url: URL) -> UTType? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .heic) { return .heic }
        return nil
    }

    private static func actualImageContentType(at url: URL) -> UTType? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let identifier = CGImageSourceGetType(source) else {
            return nil
        }

        guard let type = UTType(identifier as String) else { return nil }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .heic) { return .heic }
        return type
    }
    
    private static func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let originalURL = directory.appendingPathComponent(fileName)
        
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return originalURL
        }
        
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension
        
        for index in 1...10_000 {
            let numberedName = "\(baseName) \(index)"
            let candidateURL = directory
                .appendingPathComponent(numberedName)
                .appendingPathExtension(pathExtension)
            
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        
        return directory
            .appendingPathComponent("\(baseName) \(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}
