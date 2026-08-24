import AppKit
import CoreGraphics
import Foundation

@main
enum TextOverlayCheck {
    static let canvas = CGSize(width: 1920, height: 1080)

    static func main() {
        var overlay = TextOverlay(start: 2, end: 6)
        overlay.content = "Ship it"
        overlay.animationIn = .fade
        overlay.animationOut = .fade
        overlay.animationInDuration = 1
        overlay.animationOutDuration = 1

        precondition(resolve(overlay, at: 1.9) == nil, "text stays off screen before its start")
        precondition(resolve(overlay, at: 6.1) == nil, "text leaves when it ends")

        let resting = resolve(overlay, at: 4)!
        precondition(resting.opacity == 1 && resting.scale == 1 && resting.offset == .zero, "a resting text has no animation left in it")
        precondition(resting.content == "Ship it", "a resting text shows every character")
        precondition(abs(resting.fontSize - overlay.fontSize) < 0.001, "font size is authored against 1080p and this canvas is 1080p")

        let half = resolve(overlay, at: 2.5)!.opacity
        precondition(abs(half - 0.875) < 0.001, "fade eases out cubically, so halfway in is most of the way visible")
        precondition(abs(resolve(overlay, at: 5.5)!.opacity - 0.875) < 0.001, "the exit fades on the same curve")

        var disabled = overlay
        disabled.isEnabled = false
        precondition(resolve(disabled, at: 4) == nil, "a disabled text draws nothing")

        var slide = overlay
        slide.animationIn = .slideUp
        slide.animationOut = .slideUp
        precondition(resolve(slide, at: 2.2)!.offset.height > 0, "sliding up enters from below the resting line")
        precondition(resolve(slide, at: 5.8)!.offset.height < 0, "sliding up carries on above instead of retracing itself")
        precondition(resolve(slide, at: 4)!.offset == .zero, "the slide is spent by the time the text rests")

        var pop = overlay
        pop.animationIn = .pop
        let popped = resolve(pop, at: 2.1)!
        precondition(popped.scale >= TextOverlay.popMinimumScale && popped.scale < 1, "pop grows from small and has not overshot this early")

        var typed = overlay
        typed.animationIn = .typewriter
        typed.animationOut = .none
        precondition(resolve(typed, at: 2) == nil, "a typewriter with nothing typed yet draws nothing")
        precondition(resolve(typed, at: 2.5)!.content == "Ship", "halfway through typing shows half the characters")
        precondition(resolve(typed, at: 3.5)!.content == "Ship it", "typing finishes on time")
        precondition(resolve(typed, at: 2.5)!.opacity == 1, "typing reveals characters instead of fading them")

        let small = TextOverlay.resolved([overlay], atSourceTime: 4, canvasSize: CGSize(width: 960, height: 540))[0]
        precondition(abs(small.fontSize - overlay.fontSize / 2) < 0.001, "half the canvas height draws half the type")
        precondition(abs(small.center.x - 480) < 0.001, "the center is normalized against whatever canvas it lands on")

        precondition(painted(resting) > 0, "the exporter's CoreText pass actually puts ink on the canvas")
        precondition(TextOverlay.resolved([], atSourceTime: 4, canvasSize: canvas).isEmpty, "no text, no work")

        print("text overlays: \(overlay.content) fades, slides, pops and types on one clock")
    }

    static func resolve(_ overlay: TextOverlay, at time: TimeInterval) -> ResolvedText? {
        TextOverlay.resolved([overlay], atSourceTime: time, canvasSize: canvas).first
    }

    /// Counts drawn pixels so a silently empty CoreText frame cannot pass as a rendered one.
    static func painted(_ text: ResolvedText) -> Int {
        var text = text
        text.center = CGPoint(x: 200, y: 60)
        text.fontSize = 40
        text.maxWidth = 380
        let size = CGSize(width: 400, height: 120)
        guard let image = ResolvedText.draw([text], canvasSize: size) else { return 0 }

        var pixels = [UInt8](repeating: 0, count: 400 * 120 * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: 400,
                height: 120,
                bitsPerComponent: 8,
                bytesPerRow: 400 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(origin: .zero, size: size))
        }
        return stride(from: 3, to: pixels.count, by: 4).reduce(into: 0) { count, index in
            if pixels[index] > 16 { count += 1 }
        }
    }
}
