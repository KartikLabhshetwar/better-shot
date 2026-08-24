import CoreImage
import Foundation

@main
enum ColorGradeCheck {
    static let context = CIContext(options: [.useSoftwareRenderer: true])
    static let extent = CGRect(x: 0, y: 0, width: 64, height: 64)

    struct Sample {
        var red: Double
        var green: Double
        var blue: Double
        var luma: Double { 0.299 * red + 0.587 * green + 0.114 * blue }
        var chroma: Double { max(red, max(green, blue)) - min(red, min(green, blue)) }
    }

    static func render(_ grade: ColorGrade, source: CIImage, at point: CGPoint = CGPoint(x: 32, y: 32)) -> Sample {
        let graded = grade.applied(to: source, extent: extent, frameTime: 0)
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { raw in
            context.render(
                graded,
                toBitmap: raw.baseAddress!,
                rowBytes: 4,
                bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        return Sample(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    static func flat(red: Double, green: Double, blue: Double) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: extent)
    }

    static func main() {
        let midGray = flat(red: 0.5, green: 0.5, blue: 0.5)
        let salmon = flat(red: 0.8, green: 0.4, blue: 0.3)

        precondition(ColorGrade.neutral.isNeutral, "the default grade must be a no-op")
        precondition(ColorGrade(intensity: 0, exposure: 0.5).isNeutral, "zero intensity must disable the whole grade")
        precondition(ColorGrade.presets.count == 9, "expected Cap's nine presets, got \(ColorGrade.presets.count)")
        precondition(ColorGrade.preset(withID: "noir")?.grade.saturation == -1, "noir must desaturate completely")
        precondition(ColorGrade.neutral.matchingPresetID == "none", "a neutral grade must light up the None swatch")

        var dialedDown = ColorGrade.preset(withID: "vivid")!.grade
        dialedDown.intensity = 0.4
        precondition(dialedDown.matchingPresetID == "vivid", "moving intensity must not deselect the preset")

        let identity = render(.neutral, source: salmon)
        precondition(abs(identity.red - 0.8) < 0.02 && abs(identity.blue - 0.3) < 0.02, "a neutral grade changed the pixel: \(identity)")

        let brighter = render(ColorGrade(exposure: 0.6), source: midGray)
        let darker = render(ColorGrade(exposure: -0.6), source: midGray)
        precondition(brighter.luma > identityGray.luma + 0.05, "positive exposure must brighten: \(brighter)")
        precondition(darker.luma < identityGray.luma - 0.05, "negative exposure must darken: \(darker)")

        let grayed = render(ColorGrade(saturation: -1), source: salmon)
        precondition(grayed.chroma < 0.02, "saturation -1 must produce gray, got chroma \(grayed.chroma)")

        let punchy = render(ColorGrade(saturation: 0.6), source: salmon)
        precondition(punchy.chroma > identity.chroma + 0.02, "positive saturation must widen chroma: \(punchy.chroma) vs \(identity.chroma)")

        let warm = render(ColorGrade(temperature: 0.8), source: midGray)
        let cool = render(ColorGrade(temperature: -0.8), source: midGray)
        precondition(warm.red - warm.blue > 0.04, "positive warmth must push red past blue: \(warm)")
        precondition(cool.blue - cool.red > 0.04, "negative warmth must push blue past red: \(cool)")

        let lifted = render(ColorGrade(fade: 1), source: flat(red: 0.02, green: 0.02, blue: 0.02))
        precondition(lifted.luma > 0.1, "fade must lift the blacks, got \(lifted.luma)")

        let corner = render(ColorGrade(vignette: 1), source: midGray, at: CGPoint(x: 1, y: 1))
        let middle = render(ColorGrade(vignette: 1), source: midGray)
        precondition(corner.luma < middle.luma - 0.05, "vignette must darken the corner more than the centre: \(corner.luma) vs \(middle.luma)")

        let half = render(ColorGrade(intensity: 0.5, exposure: 1), source: midGray)
        let full = render(ColorGrade(exposure: 1), source: midGray)
        precondition(half.luma > identityGray.luma && half.luma < full.luma, "intensity must scale the adjustment: \(half.luma)")

        let shadow = flat(red: 0.12, green: 0.12, blue: 0.12)
        let highlight = flat(red: 0.88, green: 0.88, blue: 0.88)
        let tonedShadow = render(ColorGrade(splitTone: 1), source: shadow)
        let tonedHighlight = render(ColorGrade(splitTone: 1), source: highlight)
        precondition(tonedShadow.blue > tonedShadow.red, "split tone must cool the shadows: \(tonedShadow)")
        precondition(tonedHighlight.red > tonedHighlight.blue, "split tone must warm the highlights: \(tonedHighlight)")

        let clean = render(.neutral, source: midGray)
        var grainDelta = 0.0
        for x in stride(from: 4, to: 60, by: 4) {
            let speck = render(ColorGrade(grain: 1), source: midGray, at: CGPoint(x: CGFloat(x), y: 32))
            grainDelta = max(grainDelta, abs(speck.luma - clean.luma))
        }
        precondition(grainDelta > 0.01, "grain must actually perturb pixels, max delta \(grainDelta)")

        let firstFrame = render(ColorGrade(grain: 1), source: midGray, at: CGPoint(x: 20, y: 20))
        let laterGrade = ColorGrade(grain: 1)
        let laterImage = laterGrade.applied(to: midGray, extent: extent, frameTime: 1)
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { raw in
            context.render(
                laterImage,
                toBitmap: raw.baseAddress!,
                rowBytes: 4,
                bounds: CGRect(x: 20, y: 20, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        let laterLuma = Sample(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255).luma
        precondition(abs(laterLuma - firstFrame.luma) > 0.001, "grain must crawl between frames, not sit still")

        print("color grade: 9 presets, all knobs move the pixels in the right direction")
    }

    static let identityGray = render(.neutral, source: flat(red: 0.5, green: 0.5, blue: 0.5))
}
