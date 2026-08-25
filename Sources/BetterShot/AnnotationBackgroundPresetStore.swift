//
//  AnnotationBackgroundPresetStore.swift
//  BetterShot
//

import Foundation
import Observation

/// A named, reusable snapshot of the annotation editor's background, layout,
/// camera, focus blur, screenshot border, and watermark settings.
/// `StoredBackground` is shared with editable `.bettershot` documents so both
/// persistence paths round-trip identically.
struct AnnotationBackgroundPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var background: StoredBackground

    init(
        id: UUID = UUID(),
        name: String,
        settings: AnnotationBackgroundSettings
    ) {
        self.id = id
        self.name = name
        self.background = StoredBackground(settings)
    }

    var settings: AnnotationBackgroundSettings {
        background.settings
    }

    /// Hidden recent-wallpaper state should not make an otherwise identical
    /// solid or gradient preset appear edited.
    func matches(_ candidate: AnnotationBackgroundSettings) -> Bool {
        Self.settingsMatch(settings, candidate)
    }

    static func settingsMatch(
        _ lhs: AnnotationBackgroundSettings,
        _ rhs: AnnotationBackgroundSettings
    ) -> Bool {
        lhs.presetComparable == rhs.presetComparable
    }

    var hasMissingWallpaper: Bool {
        guard case .customWallpaper(let path) = background.style else { return false }
        return !FileManager.default.fileExists(atPath: path)
    }
}

extension AnnotationBackgroundSettings {
    fileprivate var presetComparable: AnnotationBackgroundSettings {
        var comparable = self
        switch comparable.style {
        case .customWallpaper(let wallpaper):
            comparable.customWallpaper = wallpaper
        case .none, .solid, .gradient:
            comparable.customWallpaper = nil
        }
        if !comparable.progressiveBlur.isEnabled {
            comparable.progressiveBlur = AnnotationProgressiveBlurSettings()
        }
        if !comparable.border.isEnabled {
            comparable.border = AnnotationScreenshotBorderSettings()
        }
        return comparable
    }

    var hasMissingCustomWallpaper: Bool {
        guard case .customWallpaper(let wallpaper) = style else { return false }
        return !FileManager.default.fileExists(atPath: wallpaper.url.path)
    }
}

@MainActor
@Observable
final class AnnotationBackgroundPresetStore {
    static let shared = AnnotationBackgroundPresetStore()

    private struct Library: Codable {
        var version: Int
        var presets: [AnnotationBackgroundPreset]
        var activePresetID: AnnotationBackgroundPreset.ID?
    }

    private enum LoadSource {
        case current
        case legacy
        case empty
        case unreadable
    }

    private static let libraryKey = "annotationBackgroundPresetLibrary.v1"
    private static let recoveryLibraryKey = "annotationBackgroundPresetLibrary.v1.recovery"

    // Keys used by the abandoned prototype. Reading them once makes this
    // implementation safe for anyone who briefly ran that build.
    private static let legacyPresetsKey = "annotationBackgroundPresets"
    private static let legacyActivePresetIDKey = "annotationBackgroundActivePresetID"

    static let maximumNameLength = 48

    private let defaults: UserDefaults
    @ObservationIgnored private var unreadableLibraryData: Data?
    private(set) var presets: [AnnotationBackgroundPreset]
    private(set) var activePresetID: AnnotationBackgroundPreset.ID?

    var activePreset: AnnotationBackgroundPreset? {
        guard let activePresetID else { return nil }
        return presets.first { $0.id == activePresetID && !$0.hasMissingWallpaper }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loadedLibrary = Self.loadLibrary(from: defaults)
        unreadableLibraryData = loadedLibrary.unreadableData
        let sanitizedPresets = Self.sanitize(loadedLibrary.presets)
        presets = sanitizedPresets
        activePresetID = sanitizedPresets.contains { $0.id == loadedLibrary.activePresetID }
            ? loadedLibrary.activePresetID
            : nil

        let shouldRepairCurrentLibrary = loadedLibrary.source == .current
            && (sanitizedPresets != loadedLibrary.presets
                || activePresetID != loadedLibrary.activePresetID)
        if loadedLibrary.source == .legacy || shouldRepairCurrentLibrary {
            persist()
            if loadedLibrary.source == .legacy {
                defaults.removeObject(forKey: Self.legacyPresetsKey)
                defaults.removeObject(forKey: Self.legacyActivePresetIDKey)
            }
        }
    }

    func preset(id: AnnotationBackgroundPreset.ID?) -> AnnotationBackgroundPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    func preset(named rawName: String) -> AnnotationBackgroundPreset? {
        let candidate = Self.normalizedName(rawName)
        guard !candidate.isEmpty else { return nil }
        return presets.first { Self.namesMatch($0.name, candidate) }
    }

    /// Creates a new preset. Duplicate names are rejected so saving from the
    /// naming popover can never overwrite a user's existing recipe.
    @discardableResult
    func savePreset(
        named rawName: String,
        settings: AnnotationBackgroundSettings
    ) -> AnnotationBackgroundPreset? {
        let name = Self.normalizedName(rawName)
        guard !name.isEmpty,
              preset(named: name) == nil,
              !settings.hasMissingCustomWallpaper else {
            return nil
        }

        let preset = AnnotationBackgroundPreset(name: name, settings: settings)
        presets.append(preset)
        persist()
        return preset
    }

    func setActivePreset(id: AnnotationBackgroundPreset.ID?) {
        guard id == nil
            || presets.contains(where: { $0.id == id && !$0.hasMissingWallpaper }) else {
            return
        }
        activePresetID = id
        persist()
    }

    @discardableResult
    func deletePreset(id: AnnotationBackgroundPreset.ID) -> AnnotationBackgroundPreset? {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return nil }
        let deletedPreset = presets.remove(at: index)
        if activePresetID == id {
            activePresetID = nil
        }
        persist()
        return deletedPreset
    }

    static func normalizedName(_ rawName: String) -> String {
        let collapsed = rawName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(maximumNameLength))
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(
            rhs,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: nil,
            locale: .current
        ) == .orderedSame
    }

    private func persist() {
        let library = Library(
            version: 1,
            presets: presets,
            activePresetID: activePresetID
        )
        guard let data = try? JSONEncoder().encode(library) else { return }
        if let unreadableLibraryData {
            defaults.set(unreadableLibraryData, forKey: Self.recoveryLibraryKey)
            self.unreadableLibraryData = nil
        }
        defaults.set(data, forKey: Self.libraryKey)
    }

    private static func loadLibrary(
        from defaults: UserDefaults
    ) -> (
        presets: [AnnotationBackgroundPreset],
        activePresetID: UUID?,
        source: LoadSource,
        unreadableData: Data?
    ) {
        if let data = defaults.data(forKey: libraryKey) {
            guard let library = try? JSONDecoder().decode(Library.self, from: data),
                  library.version == 1 else {
                return ([], nil, .unreadable, data)
            }
            return (library.presets, library.activePresetID, .current, nil)
        }

        let legacyPresets: [AnnotationBackgroundPreset]?
        if let data = defaults.data(forKey: legacyPresetsKey),
           let decoded = try? JSONDecoder().decode([AnnotationBackgroundPreset].self, from: data) {
            legacyPresets = decoded
        } else {
            legacyPresets = nil
        }

        let legacyActivePresetID = defaults
            .string(forKey: legacyActivePresetIDKey)
            .flatMap(UUID.init(uuidString:))
        if let legacyPresets {
            return (legacyPresets, legacyActivePresetID, .legacy, nil)
        }

        let hasUnreadableLegacyData = defaults.object(forKey: legacyPresetsKey) != nil
        return (
            [],
            nil,
            hasUnreadableLegacyData ? .unreadable : .empty,
            defaults.data(forKey: legacyPresetsKey)
        )
    }

    private static func sanitize(
        _ loadedPresets: [AnnotationBackgroundPreset]
    ) -> [AnnotationBackgroundPreset] {
        var seenIDs = Set<AnnotationBackgroundPreset.ID>()
        var seenNames: [String] = []

        return loadedPresets.map { preset in
            let id = seenIDs.insert(preset.id).inserted ? preset.id : UUID()
            seenIDs.insert(id)

            let normalized = normalizedName(preset.name)
            let name = uniqueSanitizedName(
                normalized.isEmpty ? "Untitled Preset" : normalized,
                existingNames: seenNames
            )
            seenNames.append(name)

            guard id != preset.id || name != preset.name else { return preset }
            return AnnotationBackgroundPreset(
                id: id,
                name: name,
                settings: preset.settings
            )
        }
    }

    private static func uniqueSanitizedName(
        _ baseName: String,
        existingNames: [String]
    ) -> String {
        guard existingNames.contains(where: { namesMatch($0, baseName) }) else {
            return baseName
        }

        var suffix = 2
        while true {
            let suffixText = " \(suffix)"
            let availableCharacters = max(1, maximumNameLength - suffixText.count)
            let candidate = String(baseName.prefix(availableCharacters)) + suffixText
            if !existingNames.contains(where: { namesMatch($0, candidate) }) {
                return candidate
            }
            suffix += 1
        }
    }
}
