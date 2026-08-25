//
//  AnnotationSwatch.swift
//  BetterShot
//

import AppKit
import SwiftUI

struct AnnotationSwatch: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ id: String, title: String, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.id = id
        self.title = title
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var numberedCircleTextColor: Color {
        isLight ? .black : .white
    }

    var numberedCircleTextNSColor: NSColor {
        isLight ? .black : .white
    }

    var numberedCircleOutlineColor: Color {
        isLight ? Color.black.opacity(0.22) : Color.white.opacity(0.42)
    }

    var numberedCircleOutlineNSColor: NSColor {
        isLight ? NSColor.black.withAlphaComponent(0.22) : NSColor.white.withAlphaComponent(0.42)
    }

    private var isLight: Bool {
        (0.299 * red + 0.587 * green + 0.114 * blue) > 0.68
    }

    static let black = AnnotationSwatch("black", title: "Black", red: 0.02, green: 0.02, blue: 0.024)
    static let red = AnnotationSwatch("red", title: "Red", red: 0.97, green: 0.22, blue: 0.2)
    static let orange = AnnotationSwatch("orange", title: "Orange", red: 1.0, green: 0.53, blue: 0.08)
    static let yellow = AnnotationSwatch("yellow", title: "Yellow", red: 1, green: 0.82, blue: 0.18)
    static let green = AnnotationSwatch("green", title: "Green", red: 0.18, green: 0.72, blue: 0.36)
    static let turquoise = AnnotationSwatch("turquoise", title: "Turquoise", red: 0.20, green: 0.77, blue: 0.72)
    static let blue = AnnotationSwatch("blue", title: "Blue", red: 0.18, green: 0.48, blue: 1)
    static let purple = AnnotationSwatch("purple", title: "Purple", red: 0.55, green: 0.30, blue: 0.95)
    static let pink = AnnotationSwatch("pink", title: "Pink", red: 1.0, green: 0.18, blue: 0.43)
    static let white = AnnotationSwatch("white", title: "White", red: 0.96, green: 0.96, blue: 0.96)

    static let allCases: [AnnotationSwatch] = [
        .black, .red, .orange, .yellow, .green, .turquoise, .blue, .purple, .pink, .white
    ]

    static func custom(from color: Color) -> AnnotationSwatch {
        custom(from: NSColor(color))
    }

    static func custom(from nsColor: NSColor) -> AnnotationSwatch {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let red = converted.redComponent
        let green = converted.greenComponent
        let blue = converted.blueComponent
        let alpha = converted.alphaComponent
        return AnnotationSwatch(
            "custom-\(Int(red * 255))-\(Int(green * 255))-\(Int(blue * 255))-\(Int(alpha * 255))",
            title: "Custom",
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}
