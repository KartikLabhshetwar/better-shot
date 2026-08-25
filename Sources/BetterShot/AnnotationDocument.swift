//
//  AnnotationDocument.swift
//  BetterShot
//
//  Codable sidecar document that stores the editable annotation state for a
//  screenshot. Persisted next to the rendered image as `<image>.bettershot`
//  so annotations remain non-destructive and can be re-opened for editing.
//

import AppKit
import Foundation
import SwiftUI

/// The persisted edit document for a single screenshot.
///
/// Version 2 stores engine shapes. Version 1 stored the old normalized-rect annotation items,
/// which had no rotation and no shared geometry; there is no faithful conversion, so a v1 sidecar
/// is ignored and its screenshot opens as a flat image.
struct AnnotationDocument: Codable, Equatable {
    static let currentVersion = 2

    /// Schema version, for forward-compatible migrations.
    var version: Int
    /// File name of the untouched base image stored in the same directory.
    var baseImageFileName: String
    var shapes: [AnnoShape]
    var bindings: [ArrowBinding]
    var background: StoredBackground

    init(
        shapes: [AnnoShape],
        bindings: [ArrowBinding] = [],
        background: AnnotationBackgroundSettings,
        baseImageFileName: String = "",
        version: Int = AnnotationDocument.currentVersion
    ) {
        self.version = version
        self.baseImageFileName = baseImageFileName
        self.shapes = shapes
        self.bindings = bindings
        self.background = StoredBackground(background)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        baseImageFileName = try container.decodeIfPresent(String.self, forKey: .baseImageFileName) ?? ""
        background = try container.decode(StoredBackground.self, forKey: .background)
        // A v1 document's annotations can't be expressed in the shape model, so only its
        // background survives.
        shapes = version >= 2 ? (try container.decodeIfPresent([AnnoShape].self, forKey: .shapes) ?? []) : []
        bindings = version >= 2 ? (try container.decodeIfPresent([ArrowBinding].self, forKey: .bindings) ?? []) : []
    }

    var backgroundSettings: AnnotationBackgroundSettings {
        background.settings
    }
}

// MARK: - Background

struct StoredBackground: Codable, Equatable {
    var style: StoredBackgroundStyle
    var padding: Double
    var cornerRadius: Double
    var shadow: Double
    var shadowStyle: String?
    var aspectRatio: String
    var alignment: String
    var customWallpaperPath: String?
    var camera: StoredCameraSettings?
    var progressiveBlur: StoredProgressiveBlurSettings?
    var border: StoredScreenshotBorder?
    var watermark: StoredWatermark?

    init(_ settings: AnnotationBackgroundSettings) {
        switch settings.style {
        case .none:
            style = .none
        case .solid(let color):
            style = .solid(StoredColor(color))
        case .gradient(let gradient):
            style = .gradient(StoredGradient(gradient))
        case .customWallpaper(let wallpaper):
            style = .customWallpaper(path: wallpaper.url.path)
        }

        padding = Double(settings.padding)
        cornerRadius = Double(settings.cornerRadius)
        shadow = Double(settings.shadow)
        shadowStyle = settings.shadowStyle.rawValue
        aspectRatio = settings.aspectRatio.rawValue
        alignment = settings.alignment.rawValue
        customWallpaperPath = settings.customWallpaper?.url.path
        camera = StoredCameraSettings(settings.camera)
        progressiveBlur = StoredProgressiveBlurSettings(settings.progressiveBlur)
        border = StoredScreenshotBorder(settings.border)
        watermark = StoredWatermark(settings.watermark)
    }

    var settings: AnnotationBackgroundSettings {
        var output = AnnotationBackgroundSettings()
        switch style {
        case .none:
            output.style = .none
        case .solid(let color):
            output.style = .solid(color.backgroundColor)
        case .gradient(let gradient):
            output.style = .gradient(gradient.backgroundGradient)
        case .customWallpaper(let path):
            output.style = .customWallpaper(AnnotationCustomWallpaper(url: URL(fileURLWithPath: path)))
        }

        output.padding = CGFloat(padding)
        output.cornerRadius = CGFloat(cornerRadius)
        output.shadow = CGFloat(shadow)
        output.shadowStyle = shadowStyle.flatMap(AnnotationShadowStyle.init(rawValue:)) ?? .soft
        output.aspectRatio = AnnotationBackgroundAspectRatio(rawValue: aspectRatio) ?? .auto
        output.alignment = AnnotationBackgroundAlignment(rawValue: alignment) ?? .center
        if let customWallpaperPath {
            output.customWallpaper = AnnotationCustomWallpaper(url: URL(fileURLWithPath: customWallpaperPath))
        }
        if let camera {
            output.camera = camera.settings
        }
        if let progressiveBlur {
            output.progressiveBlur = progressiveBlur.settings
        }
        if let border {
            output.border = border.settings
        }
        if let watermark {
            output.watermark = watermark.settings
        }
        return output
    }
}

struct StoredScreenshotBorder: Codable, Equatable {
    var isEnabled: Bool
    var color: CodableSwatch
    var thickness: Double
    var opacity: Double

    init(_ settings: AnnotationScreenshotBorderSettings) {
        isEnabled = settings.isEnabled
        color = CodableSwatch(swatch: settings.color)
        thickness = Double(settings.thickness)
        opacity = Double(settings.opacity)
    }

    var settings: AnnotationScreenshotBorderSettings {
        AnnotationScreenshotBorderSettings(
            isEnabled: isEnabled,
            color: color.annotationSwatch,
            thickness: CGFloat(thickness),
            opacity: CGFloat(opacity)
        )
    }
}

struct StoredCameraSettings: Codable, Equatable {
    var projectionVersion: Int?
    var panX: Double
    var panY: Double
    var tiltXDegrees: Double
    var tiltYDegrees: Double
    var rotationXDegrees: Double
    var rotationYDegrees: Double
    var rollDegrees: Double
    var fieldOfViewDegrees: Double
    var zoom: Double

    init(_ settings: AnnotationCameraSettings) {
        projectionVersion = settings.projectionVersion
        panX = Double(settings.panX)
        panY = Double(settings.panY)
        tiltXDegrees = Double(settings.tiltXDegrees)
        tiltYDegrees = Double(settings.tiltYDegrees)
        rotationXDegrees = Double(settings.rotationXDegrees)
        rotationYDegrees = Double(settings.rotationYDegrees)
        rollDegrees = Double(settings.rollDegrees)
        fieldOfViewDegrees = Double(settings.fieldOfViewDegrees)
        zoom = Double(settings.zoom)
    }

    var settings: AnnotationCameraSettings {
        return AnnotationCameraSettings(
            panX: CGFloat(panX),
            panY: CGFloat(panY),
            tiltXDegrees: CGFloat(tiltXDegrees),
            tiltYDegrees: CGFloat(tiltYDegrees),
            rotationXDegrees: CGFloat(rotationXDegrees),
            rotationYDegrees: CGFloat(rotationYDegrees),
            rollDegrees: CGFloat(rollDegrees),
            fieldOfViewDegrees: CGFloat(fieldOfViewDegrees),
            zoom: CGFloat(zoom),
            projectionVersion: projectionVersion ?? 1
        )
    }
}

struct StoredProgressiveBlurSettings: Codable, Equatable {
    var isEnabled: Bool
    var edgeMode: String?
    var mode: String
    var strength: Double
    var falloff: Double
    var focusSize: Double?
    var focusX: Double
    var focusY: Double
    var directionDegrees: Double
    /// Retained as `false` so documents remain readable by builds that exposed
    /// the abandoned highlight-bloom control.
    var isBokehEnabled: Bool?

    init(_ settings: AnnotationProgressiveBlurSettings) {
        isEnabled = settings.isEnabled
        edgeMode = settings.edgeMode.rawValue
        mode = settings.mode.rawValue
        strength = Double(settings.strength)
        falloff = Double(settings.falloff)
        focusSize = Double(settings.focusSize)
        focusX = Double(settings.focusPosition.x)
        focusY = Double(settings.focusPosition.y)
        directionDegrees = Double(settings.directionDegrees)
        isBokehEnabled = false
    }

    var settings: AnnotationProgressiveBlurSettings {
        AnnotationProgressiveBlurSettings(
            isEnabled: isEnabled,
            edgeMode: edgeMode.flatMap(AnnotationProgressiveBlurEdgeMode.init(rawValue:))
                ?? (isEnabled ? .clipped : .bleed),
            mode: AnnotationProgressiveBlurMode(rawValue: mode) ?? .radial,
            strength: CGFloat(strength),
            falloff: CGFloat(falloff),
            focusSize: CGFloat(focusSize ?? 0.45),
            focusPosition: CGPoint(x: CGFloat(focusX), y: CGFloat(focusY)),
            directionDegrees: CGFloat(directionDegrees)
        )
    }
}

enum StoredBackgroundStyle: Codable, Equatable {
    case none
    case solid(StoredColor)
    case gradient(StoredGradient)
    case customWallpaper(path: String)
}

struct StoredColor: Codable, Equatable {
    var id: String
    var title: String
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: AnnotationBackgroundColor) {
        id = color.id
        title = color.title
        red = Double(color.red)
        green = Double(color.green)
        blue = Double(color.blue)
        alpha = Double(color.alpha)
    }

    var backgroundColor: AnnotationBackgroundColor {
        AnnotationBackgroundColor(
            id,
            title: title,
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

struct StoredGradient: Codable, Equatable {
    var id: String
    var title: String
    var colors: [StoredColor]
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double

    init(_ gradient: AnnotationBackgroundGradient) {
        id = gradient.id
        title = gradient.title
        colors = gradient.colors.map(StoredColor.init)
        startX = Double(gradient.startPoint.x)
        startY = Double(gradient.startPoint.y)
        endX = Double(gradient.endPoint.x)
        endY = Double(gradient.endPoint.y)
    }

    var backgroundGradient: AnnotationBackgroundGradient {
        AnnotationBackgroundGradient(
            id: id,
            title: title,
            colors: colors.map(\.backgroundColor),
            startPoint: UnitPoint(x: CGFloat(startX), y: CGFloat(startY)),
            endPoint: UnitPoint(x: CGFloat(endX), y: CGFloat(endY))
        )
    }
}

struct StoredWatermark: Codable, Equatable {
    var isEnabled: Bool
    var text: String
    var density: Double
    var fontSize: Double
    var rotationDegrees: Double
    var opacity: Double
    var color: StoredWatermarkColor

    init(_ settings: AnnotationWatermarkSettings) {
        isEnabled = settings.isEnabled
        text = settings.text
        density = Double(settings.density)
        fontSize = Double(settings.fontSize)
        rotationDegrees = Double(settings.rotationDegrees)
        opacity = Double(settings.opacity)
        color = StoredWatermarkColor(settings.color)
    }

    var settings: AnnotationWatermarkSettings {
        AnnotationWatermarkSettings(
            isEnabled: isEnabled,
            text: text,
            density: CGFloat(density),
            fontSize: CGFloat(fontSize),
            rotationDegrees: CGFloat(rotationDegrees),
            opacity: CGFloat(opacity),
            color: color.watermarkColor
        )
    }
}

struct StoredWatermarkColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: AnnotationWatermarkColor) {
        red = Double(color.red)
        green = Double(color.green)
        blue = Double(color.blue)
        alpha = Double(color.alpha)
    }

    var watermarkColor: AnnotationWatermarkColor {
        AnnotationWatermarkColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
