//
//  RecordingStudioStylePresetStore.swift
//  BetterShot
//

import Foundation
import Observation

/// A named, reusable snapshot of the Studio's background, layout (padding,
/// corner radius, shadow), cursor size, and camera bubble settings.
struct RecordingStudioStylePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var style: StoredRecordingStudioStyle

    init(id: UUID = UUID(), name: String, style: RecordingStudioStyle) {
        self.id = id
        self.name = name
        self.style = StoredRecordingStudioStyle(style)
    }

    fileprivate init(id: UUID, name: String, storedStyle: StoredRecordingStudioStyle) {
        self.id = id
        self.name = name
        self.style = storedStyle
    }

    var value: RecordingStudioStyle {
        style.value
    }

    func matches(_ candidate: RecordingStudioStyle) -> Bool {
        style == StoredRecordingStudioStyle(candidate)
    }

    var hasMissingWallpaper: Bool {
        guard case .customWallpaper(let path) = style.background else { return false }
        return !FileManager.default.fileExists(atPath: path)
    }
}

extension RecordingStudioStyle {
    var hasMissingCustomWallpaper: Bool {
        guard case .customWallpaper(let wallpaper) = background else { return false }
        return !FileManager.default.fileExists(atPath: wallpaper.url.path)
    }
}

@MainActor
@Observable
final class RecordingStudioStylePresetStore {
    static let shared = RecordingStudioStylePresetStore()

    private struct Library: Codable {
        var version: Int
        var presets: [RecordingStudioStylePreset]
        var activePresetID: RecordingStudioStylePreset.ID?
    }

    private static let libraryKey = "recordingStudioStylePresetLibrary.v1"

    static let maximumNameLength = 48

    private let defaults: UserDefaults
    private(set) var presets: [RecordingStudioStylePreset]
    private(set) var activePresetID: RecordingStudioStylePreset.ID?

    var activePreset: RecordingStudioStylePreset? {
        guard let activePresetID else { return nil }
        return presets.first { $0.id == activePresetID && !$0.hasMissingWallpaper }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loadedLibrary = Self.loadLibrary(from: defaults)
        let sanitizedPresets = Self.sanitize(loadedLibrary.presets)
        presets = sanitizedPresets
        activePresetID = sanitizedPresets.contains { $0.id == loadedLibrary.activePresetID }
            ? loadedLibrary.activePresetID
            : nil

        if sanitizedPresets != loadedLibrary.presets || activePresetID != loadedLibrary.activePresetID {
            persist()
        }
    }

    func preset(id: RecordingStudioStylePreset.ID?) -> RecordingStudioStylePreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    func preset(named rawName: String) -> RecordingStudioStylePreset? {
        let candidate = Self.normalizedName(rawName)
        guard !candidate.isEmpty else { return nil }
        return presets.first { Self.namesMatch($0.name, candidate) }
    }

    /// Creates a new preset. Duplicate names are rejected so saving from the
    /// naming popover can never overwrite an existing recipe.
    @discardableResult
    func savePreset(named rawName: String, style: RecordingStudioStyle) -> RecordingStudioStylePreset? {
        let name = Self.normalizedName(rawName)
        guard !name.isEmpty,
              preset(named: name) == nil,
              !style.hasMissingCustomWallpaper else {
            return nil
        }

        let preset = RecordingStudioStylePreset(name: name, style: style)
        presets.append(preset)
        persist()
        return preset
    }

    func setActivePreset(id: RecordingStudioStylePreset.ID?) {
        guard id == nil
            || presets.contains(where: { $0.id == id && !$0.hasMissingWallpaper }) else {
            return
        }
        activePresetID = id
        persist()
    }

    @discardableResult
    func deletePreset(id: RecordingStudioStylePreset.ID) -> RecordingStudioStylePreset? {
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
        defaults.set(data, forKey: Self.libraryKey)
    }

    private static func loadLibrary(
        from defaults: UserDefaults
    ) -> (presets: [RecordingStudioStylePreset], activePresetID: UUID?) {
        guard let data = defaults.data(forKey: libraryKey),
              let library = try? JSONDecoder().decode(Library.self, from: data),
              library.version == 1 else {
            return ([], nil)
        }
        return (library.presets, library.activePresetID)
    }

    private static func sanitize(
        _ loadedPresets: [RecordingStudioStylePreset]
    ) -> [RecordingStudioStylePreset] {
        var seenIDs = Set<RecordingStudioStylePreset.ID>()
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
            return RecordingStudioStylePreset(id: id, name: name, storedStyle: preset.style)
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
