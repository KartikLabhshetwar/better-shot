import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Cap's mask segments: a rectangle that either hides part of the frame or spotlights it, for a stretch of the recording.
nonisolated struct VideoMask: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case hide
        case spotlight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hide: "Hide"
            case .spotlight: "Spotlight"
            }
        }

        var icon: String {
            switch self {
            case .hide: "eye.slash"
            case .spotlight: "flashlight.on.fill"
            }
        }
    }

    enum Effect: String, CaseIterable, Identifiable, Sendable {
        case blur
        case pixelate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .blur: "Blur"
            case .pixelate: "Pixelate"
            }
        }

        var icon: String {
            switch self {
            case .blur: "drop.fill"
            case .pixelate: "square.grid.3x3.fill"
            }
        }
    }

    static let minimumSize: CGFloat = 0.02
    static let minimumDuration: TimeInterval = 0.2
    static let defaultDuration: TimeInterval = 3
    static let amountRange: ClosedRange<Double> = 4...80
    static let referenceHeight: CGFloat = 1080

    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var kind: Kind = .hide
    var effect: Effect = .blur
    /// Normalized in the full source frame, top-down, the same frame the pointer capture writes its samples in.
    var rect = CGRect(x: 0.33, y: 0.36, width: 0.34, height: 0.2)
    var amount: CGFloat = 24
    var feather: CGFloat = 0.12
    var darkness: CGFloat = 0.6
    var fadeDuration: TimeInterval = 0.25
    var isEnabled = true

    var duration: TimeInterval { end - start }

    /// Hiding never fades, because a half-faded password is still a readable password.
    func intensity(atSourceTime time: TimeInterval) -> CGFloat? {
        guard isEnabled, duration > 0, time >= start, time < end else { return nil }
        guard kind == .spotlight, fadeDuration > 0 else { return 1 }
        let rising = min((time - start) / fadeDuration, 1)
        let falling = min((end - time) / fadeDuration, 1)
        return max(0, CGFloat(min(rising, falling)))
    }

    static func clampedRect(_ rect: CGRect) -> CGRect {
        let width = min(max(rect.width, minimumSize), 1)
        let height = min(max(rect.height, minimumSize), 1)
        return CGRect(
            x: min(max(rect.minX, 0), 1 - width),
            y: min(max(rect.minY, 0), 1 - height),
            width: width,
            height: height
        )
    }

    static func resolved(
        _ masks: [VideoMask],
        atSourceTime time: TimeInterval,
        pixelScale: CGFloat,
        project: (CGRect) -> CGRect
    ) -> [ResolvedMask] {
        masks.compactMap { mask in
            guard let intensity = mask.intensity(atSourceTime: time) else { return nil }
            let projected = project(clampedRect(mask.rect))
            guard projected.width > 0, projected.height > 0 else { return nil }
            return ResolvedMask(
                rect: projected,
                kind: mask.kind,
                effect: mask.effect,
                amount: max(1, mask.amount * pixelScale),
                feather: min(projected.width, projected.height) * 0.5 * max(0, mask.feather),
                darkness: min(max(mask.darkness, 0), 1),
                intensity: intensity
            )
        }
    }
}

/// A mask placed in the pixels of whichever image is about to be drawn, so the preview and the export share one painter.
nonisolated struct ResolvedMask: Equatable, Sendable {
    var rect: CGRect
    var kind: VideoMask.Kind
    var effect: VideoMask.Effect
    var amount: CGFloat
    var feather: CGFloat
    var darkness: CGFloat
    var intensity: CGFloat

    static func applied(_ masks: [ResolvedMask], to image: CIImage, extent: CGRect) -> CIImage {
        guard !masks.isEmpty, extent.width > 0, extent.height > 0 else { return image }
        var output = image
        for mask in masks where mask.intensity > 0.001 {
            let shape = softRect(mask.rect, feather: mask.feather, extent: extent)
            let blend = CIFilter.blendWithMask()
            switch mask.kind {
            case .hide:
                blend.inputImage = obscured(output, mask: mask, extent: extent)
                blend.backgroundImage = output
                blend.maskImage = shape
            case .spotlight:
                blend.inputImage = output
                blend.backgroundImage = dimmed(output, by: mask.darkness * mask.intensity)
                blend.maskImage = shape
            }
            output = (blend.outputImage ?? output).cropped(to: extent)
        }
        return output
    }

    private static func obscured(_ image: CIImage, mask: ResolvedMask, extent: CGRect) -> CIImage {
        switch mask.effect {
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = image.clampedToExtent()
            filter.center = CGPoint(x: mask.rect.midX, y: mask.rect.midY)
            filter.scale = Float(mask.amount)
            return (filter.outputImage ?? image).cropped(to: extent)
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image.clampedToExtent()
            filter.radius = Float(mask.amount)
            return (filter.outputImage ?? image).cropped(to: extent)
        }
    }

    private static func dimmed(_ image: CIImage, by darkness: CGFloat) -> CIImage {
        let scale = 1 - min(max(darkness, 0), 1)
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        return filter.outputImage ?? image
    }

    /// White inside the rectangle, black outside, with the edge blurred so a mask does not read as a sticker.
    private static func softRect(_ rect: CGRect, feather: CGFloat, extent: CGRect) -> CIImage {
        let bounds = extent.insetBy(dx: -feather * 3 - 1, dy: -feather * 3 - 1)
        let plate = CIImage(color: .white).cropped(to: rect)
            .composited(over: CIImage(color: .black).cropped(to: bounds))
        guard feather > 0.5 else { return plate.cropped(to: extent) }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = plate
        blur.radius = Float(feather)
        return (blur.outputImage ?? plate).cropped(to: extent)
    }
}
