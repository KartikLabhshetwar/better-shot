import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Cap's cinematic grade, ported to Core Image: bipolar knobs around zero, plus `intensity` scaling every one of them except grain.
nonisolated struct ColorGrade: Equatable, Sendable {
    var intensity: CGFloat = 1
    var exposure: CGFloat = 0
    var contrast: CGFloat = 0
    var saturation: CGFloat = 0
    var temperature: CGFloat = 0
    var tint: CGFloat = 0
    var fade: CGFloat = 0
    var splitTone: CGFloat = 0
    var vignette: CGFloat = 0
    var grain: CGFloat = 0

    static let neutral = ColorGrade()

    struct Preset: Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let grade: ColorGrade
    }

    static let presets: [Preset] = [
        Preset(id: "none", name: "None", grade: .neutral),
        Preset(id: "cinematic", name: "Cinematic", grade: ColorGrade(
            contrast: 0.12, saturation: 0.06, temperature: 0.04, splitTone: 0.45, vignette: 0.18, grain: 0.12
        )),
        Preset(id: "noir", name: "Noir", grade: ColorGrade(
            exposure: 0.04, contrast: 0.3, saturation: -1, fade: 0.06, vignette: 0.32, grain: 0.35
        )),
        Preset(id: "vintage", name: "Vintage", grade: ColorGrade(
            contrast: -0.06, saturation: -0.18, temperature: 0.22, tint: 0.08, fade: 0.28, vignette: 0.14, grain: 0.28
        )),
        Preset(id: "frost", name: "Frost", grade: ColorGrade(
            contrast: 0.08, saturation: -0.08, temperature: -0.3, tint: -0.04, fade: 0.06
        )),
        Preset(id: "golden", name: "Golden", grade: ColorGrade(
            exposure: 0.06, contrast: 0.06, saturation: 0.12, temperature: 0.38, fade: 0.04, vignette: 0.1
        )),
        Preset(id: "midnight", name: "Midnight", grade: ColorGrade(
            exposure: -0.08, contrast: 0.16, saturation: -0.22, temperature: -0.1, splitTone: 0.3, vignette: 0.28, grain: 0.18
        )),
        Preset(id: "vivid", name: "Vivid", grade: ColorGrade(
            exposure: 0.02, contrast: 0.14, saturation: 0.32
        )),
        Preset(id: "dreamy", name: "Dreamy", grade: ColorGrade(
            exposure: 0.08, contrast: -0.14, saturation: -0.04, temperature: 0.06, tint: 0.05, fade: 0.3, grain: 0.1
        ))
    ]

    static func preset(withID id: String) -> Preset? { presets.first { $0.id == id } }

    /// The preset this grade still matches, so the picker can keep a swatch lit until a slider moves off it.
    var matchingPresetID: String? {
        var normalized = self
        normalized.intensity = 1
        return Self.presets.first { $0.grade == normalized }?.id
    }

    var isNeutral: Bool { self == .neutral || strength == 0 }

    private var strength: CGFloat { min(max(intensity, 0), 1) }

    func applied(to image: CIImage, extent: CGRect, frameTime: TimeInterval) -> CIImage {
        guard !isNeutral else { return image }
        let amount = strength
        var output = image

        if abs(exposure) > 0.001 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = Float(exposure * amount * 1.5)
            output = filter.outputImage ?? output
        }

        if abs(contrast) > 0.001 || abs(saturation) > 0.001 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.contrast = Float(1 + contrast * amount)
            filter.saturation = Float(1 + saturation * amount)
            filter.brightness = 0
            output = filter.outputImage ?? output
        }

        if abs(temperature) > 0.001 || abs(tint) > 0.001 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 - temperature * amount * 2500, y: tint * amount * 60)
            output = filter.outputImage ?? output
        }

        if fade > 0.001 {
            let lift = fade * amount * 0.22
            let filter = CIFilter.colorMatrix()
            filter.inputImage = output
            let scale = 1 - lift
            filter.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
            filter.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
            filter.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
            filter.biasVector = CIVector(x: lift, y: lift, z: lift, w: 0)
            output = filter.outputImage ?? output
        }

        if abs(splitTone) > 0.001 {
            output = Self.splitToned(output, amount: splitTone * amount)
        }

        if vignette > 0.001 {
            let filter = CIFilter.vignetteEffect()
            filter.inputImage = output
            filter.center = CGPoint(x: extent.midX, y: extent.midY)
            filter.radius = Float(max(extent.width, extent.height) * 0.62)
            filter.intensity = Float(vignette * amount * 1.4)
            filter.falloff = 0.5
            output = filter.outputImage?.cropped(to: output.extent) ?? output
        }

        if grain > 0.001 {
            output = Self.grained(output, amount: grain, extent: extent, frameTime: frameTime)
        }

        return output
    }

    /// Teal into the shadows, orange into the highlights, split by the frame's own luminance. Negative reverses the two.
    private static func splitToned(_ image: CIImage, amount: CGFloat) -> CIImage {
        let mono = CIFilter.colorControls()
        mono.inputImage = image
        mono.saturation = 0
        mono.contrast = 1
        mono.brightness = 0
        guard let gray = mono.outputImage else { return image }

        let toAlpha = CIFilter.maskToAlpha()
        toAlpha.inputImage = gray
        guard let highlightMask = toAlpha.outputImage else { return image }

        let invert = CIFilter.colorInvert()
        invert.inputImage = gray
        let shadowToAlpha = CIFilter.maskToAlpha()
        shadowToAlpha.inputImage = invert.outputImage
        guard let shadowMask = shadowToAlpha.outputImage else { return image }

        let warm = tinted(image, red: 1 + amount * 0.20, green: 1 + amount * 0.04, blue: 1 - amount * 0.16)
        let cool = tinted(image, red: 1 - amount * 0.16, green: 1 + amount * 0.03, blue: 1 + amount * 0.20)

        let highlights = CIFilter.blendWithMask()
        highlights.inputImage = warm
        highlights.backgroundImage = image
        highlights.maskImage = highlightMask
        guard let litHighlights = highlights.outputImage else { return image }

        let shadows = CIFilter.blendWithMask()
        shadows.inputImage = cool
        shadows.backgroundImage = litHighlights
        shadows.maskImage = shadowMask
        return shadows.outputImage?.cropped(to: image.extent) ?? litHighlights.cropped(to: image.extent)
    }

    private static func tinted(_ image: CIImage, red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: red, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: green, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: blue, w: 0)
        return filter.outputImage ?? image
    }

    /// Film grain has to crawl or it reads as a dirty lens, so the noise field slides a whole pixel block per frame.
    private static func grained(_ image: CIImage, amount: CGFloat, extent: CGRect, frameTime: TimeInterval) -> CIImage {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let step = CGFloat((frameTime * 60).rounded())
        let drift = noise.transformed(by: CGAffineTransform(
            translationX: step.truncatingRemainder(dividingBy: 512),
            y: (step * 1.7).truncatingRemainder(dividingBy: 512)
        ))

        let gray = CIFilter.colorMatrix()
        gray.inputImage = drift
        let weight: CGFloat = 0.333
        gray.rVector = CIVector(x: weight, y: weight, z: weight, w: 0)
        gray.gVector = CIVector(x: weight, y: weight, z: weight, w: 0)
        gray.bVector = CIVector(x: weight, y: weight, z: weight, w: 0)
        gray.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        gray.biasVector = CIVector(x: 0, y: 0, z: 0, w: amount * 0.24)
        guard let speckle = gray.outputImage?.cropped(to: extent) else { return image }

        let blend = CIFilter.overlayBlendMode()
        blend.inputImage = speckle
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: image.extent) ?? image
    }
}
