//
//  AnnotationShadowStyle.swift
//  BetterShot
//
//  Created by Codex on 02/08/26.
//

import CoreGraphics
import Foundation
import SwiftUI

/// The shape of the card shadow, ported from Framekit. Each style rescales the
/// same base drop: how far it spreads, how far it falls, and how dark it lands.
enum AnnotationShadowStyle: String, CaseIterable, Identifiable, Codable {
    case soft
    case long
    case glow
    case crisp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: "Soft"
        case .long: "Long"
        case .glow: "Glow"
        case .crisp: "Crisp"
        }
    }

    var radiusScale: CGFloat {
        switch self {
        case .soft: 1
        case .long: 1.2
        case .glow: 1.6
        case .crisp: 0.8
        }
    }

    var yOffsetScale: CGFloat {
        switch self {
        case .soft: 0.3
        case .long: 0.9
        case .glow: 0
        case .crisp: 0.2
        }
    }

    var opacityScale: CGFloat {
        switch self {
        case .soft: 1
        case .long: 0.85
        case .glow: 0.7
        case .crisp: 1.1
        }
    }

    /// The slider mostly grows the drop rather than darkening it: opacity
    /// reaches its ceiling early and stays there, which is what keeps a large
    /// shadow from turning into a black smear.
    func layer(strength: CGFloat, referenceEdge: CGFloat) -> AnnotationShadowLayer? {
        let strength = min(max(strength, 0), 1)
        guard strength > 0, referenceEdge > 0 else { return nil }

        let radius = referenceEdge * 0.17 * strength * radiusScale
        let alpha = min(0.5, min(0.35, 0.08 + strength * 1.35) * opacityScale)
        return AnnotationShadowLayer(
            yOffset: radius * yOffsetScale,
            radius: radius,
            alpha: alpha
        )
    }
}

/// A resolved card shadow.
struct AnnotationShadowLayer {
    /// Downward drop, in the same units as `radius`.
    var yOffset: CGFloat
    /// SwiftUI blur radius. Core Graphics wants roughly twice this.
    var radius: CGFloat
    var alpha: CGFloat

    var coreGraphicsBlur: CGFloat { radius * 2 }
}

/// Casts the shadow and nothing else: an opaque caster feeds the blur, then the
/// card interior is punched back out. SwiftUI scales a shadow by the caster's
/// own alpha, so the caster has to be solid for the alpha to mean what it says,
/// and the knockout keeps that solid black from showing through translucent
/// borders or screenshots with alpha - same result as the exporter's clipped
/// fill.
struct AnnotationCardShadowBackdrop: View {
    var cornerRadii: RectangleCornerRadii
    var size: CGSize
    var strength: CGFloat
    var style: AnnotationShadowStyle

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
        ZStack {
            shape
                .fill(Color.black)
                .modifier(
                    AnnotationCardShadow(strength: strength, style: style, size: size)
                )
            shape
                .fill(Color.black)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: size.width, height: size.height)
    }
}

/// Live-canvas counterpart to the exporter's shadow. Sized from the card itself
/// so the preview keeps matching the render at any zoom level.
struct AnnotationCardShadow: ViewModifier {
    var strength: CGFloat
    var style: AnnotationShadowStyle
    var size: CGSize

    func body(content: Content) -> some View {
        let layer = style.layer(
            strength: strength,
            referenceEdge: min(size.width, size.height)
        )
        return content.shadow(
            color: .black.opacity(Double(layer?.alpha ?? 0)),
            radius: layer?.radius ?? 0,
            x: 0,
            y: layer?.yOffset ?? 0
        )
    }
}
