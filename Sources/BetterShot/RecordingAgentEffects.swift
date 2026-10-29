import CoreGraphics
import Foundation
import MCP

/// The agent surface carries visual settings only, never stored documents or filesystem references.
enum RecordingAgentEffects {
    static let maximumItems = 64
    static let maximumPageSize = 64

    struct Capabilities: Codable {
        let rawDuration: Double
        let editorDuration: Double
        let videoWidth: Double
        let videoHeight: Double
        let canRestyleCursor: Bool
        let hasCamera: Bool
        let canShowClickEffects: Bool
        let hasKeystrokes: Bool
        let hasSubtitles: Bool

        init(model: RecordingStudioModel) {
            rawDuration = model.sourceDuration
            editorDuration = model.duration
            videoWidth = model.videoSize.width
            videoHeight = model.videoSize.height
            canRestyleCursor = model.pointerIsSynthesized
            hasCamera = model.hasCameraVideo
            canShowClickEffects = model.canShowPressEffects
            hasKeystrokes = model.hasKeystrokes
            hasSubtitles = model.hasSubtitles
        }
    }

    struct Page: Codable {
        let offset: Int
        let limit: Int
        let total: Int
        let items: [Value]
    }

    struct Snapshot: Codable {
        let capabilities: Capabilities
        let settings: [String: Value]
        let catalogs: [String: Value]
        let zoomCues: Page
        let masks: Page
        let shots3D: Page
        let zoomClock: String
        let maskAnd3DClock: String
    }

    static func applying(_ patch: Value, to original: RecordingEditDocument,
                         capabilities: Capabilities) throws -> RecordingEditDocument {
        try requireLeaf(original)
        let fields = try object(patch, keys: ["background", "framing", "cursor", "camera", "zooms", "crop", "masks", "shots3D", "overlays"])
        var document = original
        if let value = fields["background"] {
            let values = try object(value, keys: ["kind", "color", "gradientId"])
            switch try text(values, "kind") {
            case "none":
                guard values.count == 1 else { throw invalid("A background of kind none has no color or gradientId.") }
                document.style.background = .none
            case "solid":
                guard values["gradientId"] == nil, let color = values["color"] else { throw invalid("A solid background requires only color.") }
                let rgba = try object(color, keys: ["red", "green", "blue", "alpha"])
                let r = try number(rgba, "red", 0...1), g = try number(rgba, "green", 0...1), b = try number(rgba, "blue", 0...1)
                let a = try optionalNumber(rgba, "alpha", 0...1) ?? 1
                document.style.background = .solid(StoredColor(AnnotationBackgroundColor("agent-solid", title: "Custom", red: r, green: g, blue: b, alpha: a)))
            case "gradient":
                guard values["color"] == nil,
                      let preset = AnnotationBackgroundGradient.presets.first(where: { $0.id == values["gradientId"]?.stringValue }) else {
                    throw invalid("gradientId must identify an approved built-in gradient.")
                }
                document.style.background = .gradient(StoredGradient(preset))
            default: throw invalid("background.kind must be none, solid, or gradient.")
            }
        }
        if let value = fields["framing"] {
            let values = try object(value, keys: ["padding", "cornerRadius", "shadow", "aspect", "contentMode"])
            if let value = try optionalNumber(values, "padding", 0...0.18) { document.style.padding = value }
            if let value = try optionalNumber(values, "cornerRadius", 0...0.08) { document.style.cornerRadius = value }
            if let value = try optionalNumber(values, "shadow", 0...1) { document.style.shadow = value }
            if let value = values["aspect"] { document.exportAspect = try choice(value, ExportAspectPreset.allCases.map(\.rawValue), "aspect") }
            if let value = values["contentMode"] { document.exportAspectMode = try choice(value, ExportAspectContentMode.allCases.map(\.rawValue), "contentMode") }
        }
        if let value = fields["cursor"] {
            let values = try object(value, keys: ["visible", "appearance", "scale", "smoothMotion", "pressEffect", "rippleEffect", "hideWhenIdle"])
            guard capabilities.canRestyleCursor || values.isEmpty else { throw invalid("This recording has a baked-in cursor that cannot be restyled or hidden.") }
            var cursor = document.style.cursor ?? RecordingCursorOptions()
            if let value = try optionalBool(values, "visible") { cursor.isVisible = value }
            if let value = values["appearance"] { cursor.appearance = RecordingCursorAppearance(rawValue: try choice(value, RecordingCursorAppearance.selectableCases.map(\.rawValue), "appearance"))! }
            if let value = try optionalNumber(values, "scale", 1...4) { document.style.cursorScale = value }
            if let value = try optionalBool(values, "smoothMotion") { cursor.smoothMotion = value }
            if let value = try optionalBool(values, "pressEffect") { cursor.pressEffect = value }
            if let value = try optionalBool(values, "rippleEffect") { cursor.rippleEffect = value }
            if let value = try optionalBool(values, "hideWhenIdle") { cursor.hideWhenIdle = value }
            if !values.isEmpty { document.style.cursor = cursor }
        }
        if let value = fields["camera"] {
            let values = try object(value, keys: ["visible", "layout", "onLeft", "centerX", "centerY", "size", "roundness", "aspect"])
            guard capabilities.hasCamera || values.isEmpty else { throw invalid("This recording has no camera footage to arrange.") }
            if let value = try optionalBool(values, "visible") { document.style.cameraIsVisible = value }
            if let value = values["layout"] { document.style.layoutPreset = try choice(value, RecordingLayoutPreset.allCases.map(\.rawValue), "layout") }
            if let value = try optionalBool(values, "onLeft") { document.style.cameraOnLeft = value }
            if let value = try optionalNumber(values, "centerX", 0...1) { document.style.cameraCenterX = value }
            if let value = try optionalNumber(values, "centerY", 0...1) { document.style.cameraCenterY = value }
            if let value = try optionalNumber(values, "size", 0.12...0.7) { document.style.cameraSize = value }
            if let value = try optionalNumber(values, "roundness", 0...0.5) { document.style.cameraRoundness = value }
            if let value = values["aspect"] { document.style.cameraAspectRatio = try choice(value, RecordingCameraAspectRatio.allCases.map(\.rawValue), "aspect") }
        }
        if let value = fields["zooms"] {
            let values = try object(value, keys: ["enabled", "cues"])
            if let value = try optionalBool(values, "enabled") { document.zoomEnabled = value }
            if let value = values["cues"] {
                document.zoomCues = try collection(value, name: "cues").map { item in
                    let cue = try object(item, keys: ["id", "start", "end", "zoom", "anchorMode", "pinnedX", "pinnedY", "boundsBias", "enabled", "skipEasing"])
                    let (start, end) = try range(cue, duration: capabilities.rawDuration, minimum: min(ZoomCue.minimumDuration, capabilities.rawDuration))
                    return ZoomCue(id: try id(cue), start: start, end: end,
                        zoom: try number(cue, "zoom", 1...4),
                        anchorMode: ZoomAnchorMode(rawValue: try choice(cue["anchorMode"] ?? .string("pinnedAnchor"), ZoomAnchorMode.allCases.map(\.rawValue), "anchorMode"))!,
                        pinnedPoint: CGPoint(x: try optionalNumber(cue, "pinnedX", 0...1) ?? 0.5, y: try optionalNumber(cue, "pinnedY", 0...1) ?? 0.5),
                        boundsBias: try optionalNumber(cue, "boundsBias", 0...1) ?? 0.25,
                        isEnabled: try optionalBool(cue, "enabled") ?? true,
                        skipsEasing: try optionalBool(cue, "skipEasing") ?? false)
                }
                try unique(document.zoomCues.map(\.id), "cues")
                document.zoomCues.sort { $0.start < $1.start }
            }
        }
        if let value = fields["crop"] {
            if value == .null { document.crop = nil }
            else {
                let rect = try rectangle(value, minimumWidth: min(0.5, max(Double(RecordingVideoCrop.minimumSpan), 24 / capabilities.videoWidth)),
                                         minimumHeight: min(0.5, max(Double(RecordingVideoCrop.minimumSpan), 24 / capabilities.videoHeight)))
                document.crop = RecordingVideoCrop.isUnit(rect) ? nil : [rect.minX, rect.minY, rect.width, rect.height]
            }
        }
        if let value = fields["masks"] {
            let masks = try collection(value, name: "masks").map { item -> RecordingMaskSegment in
                let values = try object(item, keys: ["id", "scope", "rect", "effect", "amount", "start", "end"])
                let scope = try choice(values["scope"] ?? .null, ["cropOnly", "fullFrame"], "scope")
                var mask = RecordingMaskSegment()
                mask.id = try id(values)
                mask.effect = RecordingMaskSegment.Effect(rawValue: try choice(values["effect"] ?? .null, RecordingMaskSegment.Effect.allCases.map(\.rawValue), "effect"))!
                mask.amount = try number(values, "amount", RecordingMaskSegment.minimumAmount...RecordingMaskSegment.maximumAmount)
                if scope == "cropOnly" {
                    guard let rect = values["rect"] else { throw invalid("A Crop Only mask requires rect.") }
                    mask.rect = try rectangle(rect)
                } else {
                    if let rect = values["rect"], try rectangle(rect) != RecordingVideoCrop.unit { throw invalid("A Full Frame mask cannot specify a partial rectangle.") }
                    mask.rect = RecordingVideoCrop.unit
                }
                if values["start"] != nil || values["end"] != nil {
                    let (start, end) = try range(values, duration: capabilities.editorDuration, minimum: min(RecordingMaskSegment.minimumDuration, capabilities.editorDuration))
                    mask.start = start; mask.end = end
                }
                return mask
            }
            try unique(masks.map(\.id), "masks")
            document.masks = masks.isEmpty ? nil : masks
        }
        if let value = fields["shots3D"] {
            let shots = try collection(value, name: "shots3D").map { item -> Recording3DShot in
                let values = try object(item, keys: ["id", "start", "end", "preset", "enabled"])
                let (start, end) = try range(values, duration: capabilities.editorDuration, minimum: Recording3DShot.minimumDuration)
                let preset = Recording3DPreset(rawValue: try choice(values["preset"] ?? .null, Recording3DPreset.allCases.map(\.rawValue), "preset"))!
                var shot = Recording3DShot(start: start, end: end)
                shot.id = try id(values); shot.apply(preset)
                shot.isEnabled = try optionalBool(values, "enabled") ?? true
                return shot
            }.sorted { $0.start < $1.start }
            try unique(shots.map(\.id), "shots3D")
            for pair in zip(shots, shots.dropFirst()) where pair.0.end > pair.1.start { throw invalid("3D shots cannot overlap.") }
            document.shots3D = shots.isEmpty ? nil : shots
        }
        if let value = fields["overlays"] {
            let values = try object(value, keys: ["clicksVisible", "keystrokesVisible", "keystrokePlacement", "subtitlesVisible", "subtitleVerticalPosition", "subtitleFontScale", "subtitleWordHighlight"])
            if let value = try optionalBool(values, "clicksVisible") {
                guard !value || capabilities.canShowClickEffects else { throw invalid("This recording cannot render synthetic click effects.") }
                document.showsClickEffects = value
            }
            if let value = try optionalBool(values, "keystrokesVisible") {
                guard !value || capabilities.hasKeystrokes else { throw invalid("This recording has no recorded keystroke overlays.") }
                document.showsKeystrokes = value
            }
            if let value = values["keystrokePlacement"] { document.keystrokePlacement = RecordingKeystrokePlacement(rawValue: try choice(value, RecordingKeystrokePlacement.allCases.map(\.rawValue), "keystrokePlacement"))! }
            if let value = try optionalBool(values, "subtitlesVisible") {
                guard !value || capabilities.hasSubtitles else { throw invalid("This recording has no subtitles to show.") }
                document.showsSubtitles = value
            }
            if let value = try optionalNumber(values, "subtitleVerticalPosition", SubtitleBarStyle.verticalRange) { document.subtitleVerticalPosition = value }
            if let value = try optionalNumber(values, "subtitleFontScale", SubtitleBarStyle.fontScaleRange) { document.subtitleFontScale = value }
            if let value = try optionalBool(values, "subtitleWordHighlight") { document.subtitleWordHighlight = value }
        }
        return document
    }

    static func inspect(document: RecordingEditDocument, capabilities: Capabilities,
                        offset: Int = 0, limit: Int = 32) throws -> Snapshot {
        try requireLeaf(document)
        guard offset >= 0, (1...maximumPageSize).contains(limit) else { throw invalid("offset must be nonnegative and limit must be between 1 and 64.") }
        let style = document.style
        let cursor = style.cursor ?? RecordingCursorOptions()
        let background: Value
        switch style.background {
        case .none: background = .object(["kind": .string("none")])
        case .solid(let color): background = .object(["kind": .string("solid"), "color": .object(["red": .double(color.red), "green": .double(color.green), "blue": .double(color.blue), "alpha": .double(color.alpha)])])
        case .gradient(let gradient):
            if let preset = AnnotationBackgroundGradient.presets.first(where: { StoredGradient($0) == gradient }) {
                background = .object(["kind": .string("gradient"), "gradientId": .string(preset.id)])
            } else { background = .object(["kind": .string("existingGradient")]) }
        case .customWallpaper: background = .object(["kind": .string("existingWallpaper")])
        }
        let settings: [String: Value] = [
            "background": background,
            "framing": .object(["padding": .double(style.padding), "cornerRadius": .double(style.cornerRadius), "shadow": .double(style.shadow), "aspect": .string(document.exportAspectPreset.rawValue), "contentMode": .string(document.exportAspectContentMode.rawValue)]),
            "cursor": .object(["visible": .bool(cursor.isVisible), "appearance": .string(cursor.appearance.rawValue), "scale": .double(style.cursorScale ?? Double(RecordingStudioStyle.defaultCursorScale)), "smoothMotion": .bool(cursor.smoothMotion), "pressEffect": .bool(cursor.pressEffect), "rippleEffect": .bool(cursor.rippleEffect), "hideWhenIdle": .bool(cursor.hideWhenIdle)]),
            "camera": .object(["visible": .bool(style.cameraIsVisible), "layout": .string(style.value.layoutPreset.rawValue), "onLeft": .bool(style.cameraOnLeft ?? false), "centerX": .double(style.cameraCenterX), "centerY": .double(style.cameraCenterY), "size": .double(style.cameraSize), "roundness": .double(style.cameraRoundness), "aspect": .string(style.value.camera.aspectRatio.rawValue)]),
            "zooms": .object(["enabled": .bool(document.zoomEnabled)]),
            "crop": document.crop == nil ? .null : rectValue(document.cropValue),
            "overlays": .object(["clicksVisible": .bool(document.showsClickEffects ?? true), "keystrokesVisible": .bool(document.showsKeystrokes ?? true), "keystrokePlacement": .string((document.keystrokePlacement ?? .bottomCenter).rawValue), "subtitlesVisible": .bool(document.showsSubtitles ?? true), "subtitleVerticalPosition": .double(document.subtitleStyle.verticalPosition), "subtitleFontScale": .double(document.subtitleStyle.fontScale), "subtitleWordHighlight": .bool(document.subtitleStyle.highlightsSpokenWord)])
        ]
        func page<T>(_ values: [T], transform: (T) -> Value) -> Page {
            Page(offset: offset, limit: limit, total: values.count, items: values.dropFirst(min(offset, values.count)).prefix(limit).map(transform))
        }
        return Snapshot(capabilities: capabilities, settings: settings, catalogs: catalogs,
            zoomCues: page(document.zoomCues) { cue in .object(["id": .string(cue.id.uuidString), "start": .double(cue.start), "end": .double(cue.end), "zoom": .double(cue.zoom), "anchorMode": .string(cue.anchorMode.rawValue), "pinnedX": .double(cue.pinnedPoint.x), "pinnedY": .double(cue.pinnedPoint.y), "boundsBias": .double(cue.boundsBias), "enabled": .bool(cue.isEnabled), "skipEasing": .bool(cue.skipsEasing), "implicit": .bool(cue.isImplicit)]) },
            masks: page(document.masks ?? []) { mask in
                var values: [String: Value] = ["id": .string(mask.id.uuidString), "scope": .string(RecordingVideoCrop.isUnit(mask.rect) ? "fullFrame" : "cropOnly"), "effect": .string(mask.effect.rawValue), "amount": .double(mask.amount), "rect": rectValue(mask.rect)]
                if let start = mask.start { values["start"] = .double(start) }
                if let end = mask.end { values["end"] = .double(end) }
                return .object(values)
            },
            shots3D: page(document.shots3D ?? []) { shot in
                var values: [String: Value] = ["id": .string(shot.id.uuidString), "start": .double(shot.start), "end": .double(shot.end), "enabled": .bool(shot.isEnabled)]
                if let preset = Recording3DPreset.allCases.first(where: { preset in
                    var expected = Recording3DShot(start: shot.start, end: shot.end)
                    expected.id = shot.id; expected.isEnabled = shot.isEnabled; expected.apply(preset)
                    return expected == shot
                }) { values["preset"] = .string(preset.rawValue) }
                else { values["preset"] = .string("existingCustom") }
                return .object(values)
            }, zoomClock: "rawSourceTime", maskAnd3DClock: "sourceEditorTime")
    }

    static var catalogs: [String: Value] {
        ["gradientIds": .array(AnnotationBackgroundGradient.presets.map { .string($0.id) }),
         "cursorAppearances": .array(RecordingCursorAppearance.selectableCases.map { .string($0.rawValue) }),
         "cameraLayouts": .array(RecordingLayoutPreset.allCases.map { .string($0.rawValue) }),
         "cameraAspects": .array(RecordingCameraAspectRatio.allCases.map { .string($0.rawValue) }),
         "exportAspects": .array(ExportAspectPreset.allCases.map { .string($0.rawValue) }),
         "3DPresets": .array(Recording3DPreset.allCases.map { .string($0.rawValue) }),
         "maximumReplacementItems": .int(maximumItems)]
    }

    static var patchSchema: Value {
        let boolean = Value.object(["type": .string("boolean")])
        let identifier = Value.object(["type": .string("string"), "format": .string("uuid")])
        let unit = numberSchema(0...1)
        let time = Value.object(["type": .string("number"), "minimum": .int(0)])
        let rect = objectSchema(["x": unit, "y": unit, "width": numberSchema(Double(RecordingVideoCrop.minimumSpan)...1), "height": numberSchema(Double(RecordingVideoCrop.minimumSpan)...1)], required: ["x", "y", "width", "height"])
        let color = objectSchema(["red": unit, "green": unit, "blue": unit, "alpha": unit], required: ["red", "green", "blue"])
        let cue = objectSchema([
            "id": identifier, "start": time, "end": time, "zoom": numberSchema(1...4),
            "anchorMode": enumSchema(ZoomAnchorMode.allCases.map(\.rawValue)), "pinnedX": unit, "pinnedY": unit,
            "boundsBias": unit, "enabled": boolean, "skipEasing": boolean
        ], required: ["id", "start", "end", "zoom"])
        let fullRect = objectSchema(["x": numberSchema(0...0), "y": numberSchema(0...0),
            "width": numberSchema(1...1), "height": numberSchema(1...1)], required: ["x", "y", "width", "height"])
        func maskVariant(scope: String, timed: Bool) -> Value {
            var properties: [String: Value] = [
                "id": identifier, "scope": enumSchema([scope]), "rect": scope == "cropOnly" ? rect : fullRect,
                "effect": enumSchema(RecordingMaskSegment.Effect.allCases.map(\.rawValue)),
                "amount": numberSchema(RecordingMaskSegment.minimumAmount...RecordingMaskSegment.maximumAmount)
            ]
            var required = ["id", "scope", "effect", "amount"]
            if scope == "cropOnly" { required.append("rect") }
            if timed {
                properties["start"] = time; properties["end"] = time
                required += ["start", "end"]
            }
            return objectSchema(properties, required: required)
        }
        let mask = Value.object(["oneOf": .array([
            maskVariant(scope: "cropOnly", timed: false), maskVariant(scope: "cropOnly", timed: true),
            maskVariant(scope: "fullFrame", timed: false), maskVariant(scope: "fullFrame", timed: true)
        ])])
        let shot = objectSchema([
            "id": identifier, "start": time, "end": time,
            "preset": enumSchema(Recording3DPreset.allCases.map(\.rawValue)), "enabled": boolean
        ], required: ["id", "start", "end", "preset"])
        return objectSchema([
            "background": .object(["oneOf": .array([
                objectSchema(["kind": enumSchema(["none"])], required: ["kind"]),
                objectSchema(["kind": enumSchema(["solid"]), "color": color], required: ["kind", "color"]),
                objectSchema(["kind": enumSchema(["gradient"]), "gradientId": enumSchema(AnnotationBackgroundGradient.presets.map(\.id))], required: ["kind", "gradientId"])
            ])]),
            "framing": objectSchema(["padding": numberSchema(0...0.18), "cornerRadius": numberSchema(0...0.08), "shadow": unit,
                "aspect": enumSchema(ExportAspectPreset.allCases.map(\.rawValue)), "contentMode": enumSchema(ExportAspectContentMode.allCases.map(\.rawValue))]),
            "cursor": objectSchema(["visible": boolean, "appearance": enumSchema(RecordingCursorAppearance.selectableCases.map(\.rawValue)),
                "scale": numberSchema(1...4), "smoothMotion": boolean, "pressEffect": boolean, "rippleEffect": boolean, "hideWhenIdle": boolean]),
            "camera": objectSchema(["visible": boolean, "layout": enumSchema(RecordingLayoutPreset.allCases.map(\.rawValue)), "onLeft": boolean,
                "centerX": unit, "centerY": unit, "size": numberSchema(0.12...0.7), "roundness": numberSchema(0...0.5),
                "aspect": enumSchema(RecordingCameraAspectRatio.allCases.map(\.rawValue))]),
            "zooms": objectSchema(["enabled": boolean, "cues": arraySchema(cue, description: "Replaces all zoom cues. start/end use raw source time, not the source's edited clock; intervals must fit rawDuration and meet the native minimum duration. At most 64 cues.")]),
            "crop": .object(["anyOf": .array([rect, .object(["type": .string("null")])]), "description": .string("A normalized source rectangle, or null to reset. Must fit inside the frame and meet native minimum spans (at least 24 source pixels per axis, capped at half the source dimension).")]),
            "masks": arraySchema(mask, description: "Replaces all masks. start/end use the selected source's authored editor clock. Crop Only requires rect; Full Frame uses the whole frame. Either omit both start/end for the whole source or supply both within editorDuration, meeting the native minimum duration. At most 64 masks."),
            "shots3D": arraySchema(shot, description: "Replaces all 3D shots with built-in presets. Nonoverlapping start/end ranges use the selected source's authored editor clock. At most 64 shots."),
            "overlays": objectSchema(["clicksVisible": boolean, "keystrokesVisible": boolean,
                "keystrokePlacement": enumSchema(RecordingKeystrokePlacement.allCases.map(\.rawValue)), "subtitlesVisible": boolean,
                "subtitleVerticalPosition": numberSchema(SubtitleBarStyle.verticalRange), "subtitleFontScale": numberSchema(SubtitleBarStyle.fontScaleRange), "subtitleWordHighlight": boolean])
        ])
    }

    private static func objectSchema(_ properties: [String: Value], required: [String] = []) -> Value {
        .object(["type": .string("object"), "properties": .object(properties),
                 "required": .array(required.map(Value.string)), "additionalProperties": .bool(false)])
    }
    private static func enumSchema(_ values: [String]) -> Value {
        .object(["type": .string("string"), "enum": .array(values.map(Value.string))])
    }
    private static func numberSchema(_ range: ClosedRange<Double>) -> Value {
        .object(["type": .string("number"), "minimum": .double(range.lowerBound), "maximum": .double(range.upperBound)])
    }
    private static func arraySchema(_ items: Value, description: String) -> Value {
        .object(["type": .string("array"), "items": items, "maxItems": .int(maximumItems), "description": .string(description)])
    }

    private static func requireLeaf(_ document: RecordingEditDocument) throws {
        guard document.sources == nil, document.sourceDocuments == nil,
              document.clips?.contains(where: { $0.sourceID != nil }) != true else {
            throw invalid("Select a leaf recording source for visual effects.")
        }
    }
    private static func object(_ value: Value, keys: Set<String>) throws -> [String: Value] {
        guard case .object(let fields) = value, Set(fields.keys).isSubset(of: keys) else { throw invalid("An effects object contains unsupported fields or has the wrong type.") }
        return fields
    }
    private static func number(_ fields: [String: Value], _ key: String, _ range: ClosedRange<Double>) throws -> Double {
        guard let value = fields[key]?.doubleValue ?? fields[key]?.intValue.map(Double.init), value.isFinite, range.contains(value) else { throw invalid("\(key) must be a finite number between \(range.lowerBound) and \(range.upperBound).") }
        return value
    }
    private static func optionalNumber(_ fields: [String: Value], _ key: String, _ range: ClosedRange<Double>) throws -> Double? {
        try fields[key].map { _ in try number(fields, key, range) }
    }
    private static func optionalBool(_ fields: [String: Value], _ key: String) throws -> Bool? {
        guard let value = fields[key] else { return nil }
        guard case .bool(let result) = value else { throw invalid("\(key) must be a boolean.") }
        return result
    }
    private static func text(_ fields: [String: Value], _ key: String) throws -> String {
        guard let value = fields[key]?.stringValue else { throw invalid("\(key) must be a string.") }
        return value
    }
    private static func choice(_ value: Value, _ choices: [String], _ key: String) throws -> String {
        guard let value = value.stringValue, choices.contains(value) else { throw invalid("\(key) must be a supported value from inspect_effects catalogs.") }
        return value
    }
    private static func id(_ fields: [String: Value]) throws -> UUID {
        guard let id = UUID(uuidString: try text(fields, "id")) else { throw invalid("id must be a UUID.") }
        return id
    }
    private static func collection(_ value: Value, name: String) throws -> [Value] {
        guard case .array(let items) = value, items.count <= maximumItems else { throw invalid("\(name) must be an array of at most 64 items.") }
        return items
    }
    private static func unique(_ ids: [UUID], _ name: String) throws {
        guard Set(ids).count == ids.count else { throw invalid("\(name) cannot contain duplicate IDs.") }
    }
    private static func range(_ values: [String: Value], duration: Double, minimum: Double) throws -> (Double, Double) {
        guard duration.isFinite, duration > 0 else { throw invalid("This recording has no valid duration.") }
        let start = try number(values, "start", 0...duration), end = try number(values, "end", 0...duration)
        guard end - start >= minimum - 0.000_001 else { throw invalid("The effect interval is too short or reversed.") }
        return (start, end)
    }
    private static func rectangle(_ value: Value, minimumWidth: Double = Double(RecordingVideoCrop.minimumSpan), minimumHeight: Double = Double(RecordingVideoCrop.minimumSpan)) throws -> CGRect {
        let values = try object(value, keys: ["x", "y", "width", "height"])
        let x = try number(values, "x", 0...1), y = try number(values, "y", 0...1)
        let width = try number(values, "width", minimumWidth...1), height = try number(values, "height", minimumHeight...1)
        guard x + width <= 1, y + height <= 1 else { throw invalid("A rectangle must fit wholly inside the normalized source frame.") }
        return CGRect(x: x, y: y, width: width, height: height)
    }
    private static func rectValue(_ rect: CGRect) -> Value {
        .object(["x": .double(rect.minX), "y": .double(rect.minY), "width": .double(rect.width), "height": .double(rect.height)])
    }
    private static func invalid(_ message: String) -> RecordingAgentOperationError { .invalidArgument(message) }
}
