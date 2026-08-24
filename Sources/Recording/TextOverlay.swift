import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Cap's text segments: a line of text that lives on the canvas for a stretch of the recording, with its own entrance and exit.
nonisolated struct TextOverlay: Identifiable, Equatable, Sendable {
    enum Motion: String, CaseIterable, Identifiable, Sendable {
        case none
        case fade
        case slideUp
        case slideDown
        case pop
        case typewriter

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .fade: "Fade"
            case .slideUp: "Slide Up"
            case .slideDown: "Slide Down"
            case .pop: "Pop"
            case .typewriter: "Type"
            }
        }

        var icon: String {
            switch self {
            case .none: "minus"
            case .fade: "circle.lefthalf.filled"
            case .slideUp: "arrow.up"
            case .slideDown: "arrow.down"
            case .pop: "sparkles"
            case .typewriter: "keyboard"
            }
        }
    }

    enum Align: String, CaseIterable, Identifiable, Sendable {
        case left
        case center
        case right

        var id: String { rawValue }
        var icon: String { "text.align\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())" }
    }

    enum Weight: String, CaseIterable, Identifiable, Sendable {
        case regular
        case medium
        case bold
        case heavy

        var id: String { rawValue }
        var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
        var value: CGFloat {
            switch self {
            case .regular: 0
            case .medium: 0.23
            case .bold: 0.4
            case .heavy: 0.56
            }
        }
    }

    static let referenceHeight: CGFloat = 1080
    static let fontSizeRange: ClosedRange<Double> = 12...220
    static let minimumDuration: TimeInterval = 0.3
    static let defaultDuration: TimeInterval = 3
    static let popMinimumScale: CGFloat = 0.8

    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var content = "Text"
    /// Normalized in the output canvas, top-down, so the text sits on the background rather than inside the video card.
    var center = CGPoint(x: 0.5, y: 0.82)
    var maxWidth: CGFloat = 0.8
    var fontSize: CGFloat = 56
    var weight: Weight = .bold
    var align: Align = .center
    var red: CGFloat = 1
    var green: CGFloat = 1
    var blue: CGFloat = 1
    var opacity: CGFloat = 1
    var shadow: CGFloat = 0.5
    var lineHeight: CGFloat = 1.2
    var animationIn: Motion = .fade
    var animationOut: Motion = .fade
    var animationInDuration: TimeInterval = 0.25
    var animationOutDuration: TimeInterval = 0.25
    var isEnabled = true

    var duration: TimeInterval { end - start }

    static func resolved(_ overlays: [TextOverlay], atSourceTime time: TimeInterval, canvasSize: CGSize) -> [ResolvedText] {
        let heightScale = canvasSize.height > 0 ? canvasSize.height / referenceHeight : 1
        return overlays.compactMap { $0.resolved(atSourceTime: time, canvasSize: canvasSize, heightScale: heightScale) }
    }

    private func resolved(atSourceTime time: TimeInterval, canvasSize: CGSize, heightScale: CGFloat) -> ResolvedText? {
        guard isEnabled, !content.isEmpty, time >= start, time <= end else { return nil }

        let size = min(max(fontSize, CGFloat(Self.fontSizeRange.lowerBound)), CGFloat(Self.fontSizeRange.upperBound)) * heightScale
        let slide = size * 0.5
        let enter = Self.sample(animationIn, progress: Self.progress(time - start, animationInDuration), direction: 1, slide: slide)
        let exit = Self.sample(animationOut, progress: Self.progress(end - time, animationOutDuration), direction: -1, slide: slide)

        let alpha = min(max(opacity, 0), 1) * enter.alpha * exit.alpha
        guard alpha > 0.001 else { return nil }

        let visible = Self.revealed(content, by: min(enter.reveal, exit.reveal))
        guard !visible.isEmpty else { return nil }

        return ResolvedText(
            content: visible,
            center: CGPoint(x: min(max(center.x, 0), 1) * canvasSize.width, y: min(max(center.y, 0), 1) * canvasSize.height),
            offset: CGSize(width: enter.offset.width + exit.offset.width, height: enter.offset.height + exit.offset.height),
            scale: max(0.01, enter.scale * exit.scale),
            opacity: alpha,
            fontSize: size,
            maxWidth: max(size, min(max(maxWidth, 0.05), 1) * canvasSize.width),
            weight: weight,
            align: align,
            red: red,
            green: green,
            blue: blue,
            shadow: min(max(shadow, 0), 1),
            lineHeight: min(max(lineHeight, 0.6), 3)
        )
    }

    /// Both edges run 0 to 1 toward fully visible, and the direction flips so a slide carries on through the text instead of retracing itself.
    private static func sample(_ motion: Motion, progress: CGFloat, direction: CGFloat, slide: CGFloat) -> Sample {
        guard progress < 1 else { return .rest }
        let eased = easeOutCubic(progress)
        switch motion {
        case .none: return .rest
        case .fade: return Sample(alpha: eased)
        case .slideUp: return Sample(alpha: eased, offset: CGSize(width: 0, height: direction * (1 - eased) * slide))
        case .slideDown: return Sample(alpha: eased, offset: CGSize(width: 0, height: -direction * (1 - eased) * slide))
        case .pop: return Sample(alpha: eased, scale: popMinimumScale + (1 - popMinimumScale) * easeOutBack(progress))
        case .typewriter: return Sample(reveal: progress)
        }
    }

    private static func progress(_ elapsed: TimeInterval, _ duration: TimeInterval) -> CGFloat {
        duration <= 0 ? 1 : min(max(CGFloat(elapsed / duration), 0), 1)
    }

    static func revealed(_ content: String, by reveal: CGFloat) -> String {
        guard reveal < 1 else { return content }
        return String(content.prefix(Int((CGFloat(content.count) * max(reveal, 0)).rounded(.up))))
    }

    private static func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    private static func easeOutBack(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        let c1: CGFloat = 1.70158
        let p = t - 1
        return 1 + (c1 + 1) * p * p * p + c1 * p * p
    }

    private struct Sample {
        var alpha: CGFloat = 1
        var offset = CGSize.zero
        var scale: CGFloat = 1
        var reveal: CGFloat = 1
        static let rest = Sample()
    }
}

/// Text placed in canvas pixels, so the SwiftUI preview and the CoreText exporter draw the same line at the same moment.
nonisolated struct ResolvedText: Equatable, Sendable {
    var content: String
    /// Canvas pixels, top-down, before the animation offset.
    var center: CGPoint
    var offset: CGSize
    var scale: CGFloat
    var opacity: CGFloat
    var fontSize: CGFloat
    var maxWidth: CGFloat
    var weight: TextOverlay.Weight
    var align: TextOverlay.Align
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var shadow: CGFloat
    var lineHeight: CGFloat
    var backgroundOpacity: CGFloat = 0

    var placement: CGPoint {
        CGPoint(x: center.x + offset.width, y: center.y + offset.height)
    }

    static func composited(_ texts: [ResolvedText], over image: CIImage, canvasSize: CGSize) -> CIImage {
        guard !texts.isEmpty, let drawn = draw(texts, canvasSize: canvasSize) else { return image }
        return CIImage(cgImage: drawn).composited(over: image).cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    static func draw(_ texts: [ResolvedText], canvasSize: CGSize) -> CGImage? {
        guard canvasSize.width >= 1, canvasSize.height >= 1, let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        for text in texts {
            let line = CTFramesetterCreateWithAttributedString(text.attributed)
            let constraint = CGSize(width: text.maxWidth, height: .greatestFiniteMagnitude)
            let fitted = CTFramesetterSuggestFrameSizeWithConstraints(line, CFRange(), nil, constraint, nil)
            let box = CGRect(
                x: -fitted.width / 2,
                y: -fitted.height / 2,
                width: max(fitted.width, 1),
                height: max(fitted.height, 1)
            )
            let frame = CTFramesetterCreateFrame(line, CFRange(), CGPath(rect: box, transform: nil), nil)

            context.saveGState()
            context.translateBy(x: text.placement.x, y: canvasSize.height - text.placement.y)
            context.scaleBy(x: text.scale, y: text.scale)
            context.setAlpha(text.opacity)

            if text.backgroundOpacity > 0 {
                let padding = text.fontSize * 0.3
                let plate = box.insetBy(dx: -padding, dy: -padding * 0.6)
                context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: text.backgroundOpacity))
                context.addPath(CGPath(roundedRect: plate, cornerWidth: padding, cornerHeight: padding, transform: nil))
                context.fillPath()
            }

            if text.shadow > 0 {
                context.setShadow(
                    offset: CGSize(width: 0, height: -text.fontSize * 0.06),
                    blur: text.fontSize * 0.28 * text.shadow,
                    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55 * text.shadow)
                )
            }
            CTFrameDraw(frame, context)
            context.restoreGState()
        }

        return context.makeImage()
    }

    private var attributed: CFAttributedString {
        var alignment = align.coreText
        var height = lineHeight
        let paragraph = withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &height) { heightPointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer),
                    CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: heightPointer),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }

        return NSAttributedString(string: content, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: NSFont.Weight(weight.value)),
            .foregroundColor: CGColor(red: red, green: green, blue: blue, alpha: 1),
            .paragraphStyle: paragraph,
        ])
    }
}

extension TextOverlay.Align {
    var coreText: CTTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}
