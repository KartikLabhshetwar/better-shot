//
//  AnnotationPresetStore.swift
//  BetterShot
//
//  Created by Codex on 01/05/26.
//

import AppKit
import Foundation

enum AnnotationPresetStore {
    private static let key = "annotationStylePreset"

    static func load() -> AnnotationStylePreset {
        guard let data = UserDefaults.standard.data(forKey: key),
              let preset = try? JSONDecoder().decode(AnnotationStylePreset.self, from: data) else {
            return AnnotationStylePreset()
        }

        return preset
    }

    static func save(_ preset: AnnotationStylePreset) {
        guard let data = try? JSONEncoder().encode(preset) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct AnnotationStylePreset: Codable, Equatable {
    var selectedToolRawValue = AnnotationTool.rectangle.rawValue
    var swatchID = AnnotationSwatch.red.id
    var customSwatch: CodableSwatch?
    var strokeWidth: Double = 4
    var redactionDensity: Double = 0.55
    var textFontName = AnnotationTextMetrics.defaultFontName
    var textFontSize: Double = 48
    var textIsBold = true
    var textIsItalic = false
    var textIsUnderline = false
    var textAlignmentRawValue = NSTextAlignment.left.rawValue

    var selectedTool: AnnotationTool {
        AnnotationTool(rawValue: selectedToolRawValue) ?? .rectangle
    }

    var swatch: AnnotationSwatch {
        if let customSwatch {
            return customSwatch.annotationSwatch
        }

        return AnnotationSwatch.allCases.first { $0.id == swatchID } ?? .red
    }

    var textAlignment: NSTextAlignment {
        NSTextAlignment(rawValue: textAlignmentRawValue) ?? .left
    }
}

struct CodableSwatch: Codable, Equatable {
    var id: String
    var title: String
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(swatch: AnnotationSwatch) {
        id = swatch.id
        title = swatch.title
        red = Double(swatch.red)
        green = Double(swatch.green)
        blue = Double(swatch.blue)
        alpha = Double(swatch.alpha)
    }

    var annotationSwatch: AnnotationSwatch {
        AnnotationSwatch(
            id,
            title: title,
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
