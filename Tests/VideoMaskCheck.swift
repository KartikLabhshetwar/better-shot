import CoreImage
import Foundation

@main
enum VideoMaskCheck {
    static func main() {
        let hide = VideoMask(start: 2, end: 6)
        precondition(hide.intensity(atSourceTime: 1.9) == nil, "a mask is off before it starts")
        precondition(hide.intensity(atSourceTime: 6) == nil, "a mask is off the instant it ends")
        precondition(hide.intensity(atSourceTime: 2) == 1, "hiding is full strength from its first frame")
        precondition(hide.intensity(atSourceTime: 5.95) == 1, "hiding never fades out")

        var disabled = hide
        disabled.isEnabled = false
        precondition(disabled.intensity(atSourceTime: 4) == nil, "a switched-off mask draws nothing")

        var spotlight = VideoMask(start: 0, end: 4)
        spotlight.kind = .spotlight
        spotlight.fadeDuration = 1
        precondition(spotlight.intensity(atSourceTime: 0) == 0, "a spotlight starts dark")
        precondition(spotlight.intensity(atSourceTime: 0.5) == 0.5, "a spotlight rises over its fade")
        precondition(spotlight.intensity(atSourceTime: 2) == 1, "a spotlight is full in the middle")
        precondition(spotlight.intensity(atSourceTime: 3.5) == 0.5, "a spotlight falls over its fade")

        var offscreen = VideoMask(start: 0, end: 1)
        offscreen.rect = CGRect(x: 0.9, y: -0.5, width: 0.4, height: 0.3)
        let clamped = VideoMask.clampedRect(offscreen.rect)
        precondition(clamped.maxX <= 1.0001 && clamped.minY >= -0.0001, "a mask cannot hang off the frame")
        precondition(clamped.width == 0.4, "clamping slides a mask back rather than shrinking it")

        let tiny = VideoMask.clampedRect(CGRect(x: 0.5, y: 0.5, width: 0, height: 0))
        precondition(tiny.width >= VideoMask.minimumSize, "a mask never collapses to nothing")

        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let resolved = VideoMask.resolved([hide, spotlight], atSourceTime: 3, pixelScale: 1) { rect in
            CGRect(x: rect.minX * 1920, y: rect.minY * 1080, width: rect.width * 1920, height: rect.height * 1080)
        }
        precondition(resolved.count == 2, "both masks are live at three seconds")
        precondition(resolved[0].rect.width == 0.34 * 1920, "the projection reaches the resolved rect")
        precondition(resolved[0].feather > 0, "a feathered mask resolves to a real edge width")

        let none = VideoMask.resolved([hide], atSourceTime: 10, pixelScale: 1) { $0 }
        precondition(none.isEmpty, "nothing resolves once every mask has ended")

        let source = CIImage(color: .red).cropped(to: frame)
        let painted = ResolvedMask.applied(resolved, to: source, extent: frame)
        precondition(painted.extent == frame, "masking keeps the frame the same size")

        let context = CIContext()
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            painted,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 40, y: 40, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        precondition(pixel[0] < 250, "the spotlight darkens the corner outside it")

        precondition(
            ResolvedMask.applied([], to: source, extent: frame) === source,
            "no masks means no work"
        )

        print("masks: \(resolved.count) resolved at 3s, fades, clamping and painting all hold")
    }
}
