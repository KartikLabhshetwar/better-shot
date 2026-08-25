import AppKit
import CoreGraphics
import Foundation

@main
enum CaptionCheck {
    static let canvas = CGSize(width: 1920, height: 1080)

    static func main() {
        let gapped = CaptionCue.grouped([
            SpokenWord(text: "we", start: 0, end: 0.2),
            SpokenWord(text: "ship", start: 0.2, end: 0.5),
            SpokenWord(text: "today", start: 1.4, end: 1.9),
        ])
        precondition(gapped.count == 2, "a pause longer than the breaking gap starts a new line")
        precondition(gapped[0].text == "we ship" && gapped[1].text == "today", "words keep their order and their spacing")
        precondition(gapped[0].start == 0 && gapped[0].end == 0.5, "a cue spans its own words, not the silence after them")

        let sentence = CaptionCue.grouped([
            SpokenWord(text: "done.", start: 0, end: 0.4),
            SpokenWord(text: "next", start: 0.5, end: 0.9),
        ])
        precondition(sentence.count == 2, "a full stop closes the line even without a pause")

        let long = CaptionCue.grouped((0..<12).map {
            SpokenWord(text: "word", start: Double($0) * 0.2, end: Double($0) * 0.2 + 0.15)
        })
        precondition(long.count > 1, "a line never grows past what fits on screen")
        precondition(long.allSatisfy { $0.text.split(separator: " ").count <= CaptionCue.maximumWords }, "no line runs past the word ceiling")

        let slow = CaptionCue.grouped((0..<6).map {
            SpokenWord(text: "word", start: Double($0) * 0.7, end: Double($0) * 0.7 + 0.65)
        })
        precondition(slow.count > 1, "a line that lingers too long is split even when it is short")

        let dragged = CaptionCue(start: -2, end: 1, text: "early").clamped(to: 10)
        precondition(dragged.start == 0 && dragged.end == 1, "a cue dragged off the left edge lands at zero and keeps its tail")

        let overshot = CaptionCue(start: 9.9, end: 12, text: "late").clamped(to: 10)
        precondition(overshot.start <= 10 - CaptionCue.minimumDuration && overshot.end <= 10, "a cue dragged past the end stays inside the recording")

        let squashed = CaptionCue(start: 3, end: 3.05, text: "tiny").clamped(to: 10)
        precondition(squashed.end - squashed.start >= CaptionCue.minimumDuration, "a cue never collapses below the minimum duration")

        var style = CaptionStyle()
        style.fadeDuration = 0.2
        let cues = [CaptionCue(start: 1, end: 3, text: "ship it"), CaptionCue(start: 4, end: 5, text: "again")]

        precondition(resolve(style, cues, at: 0.5) == nil, "nothing is drawn before anyone speaks")
        precondition(resolve(style, cues, at: 3.5) == nil, "nothing is drawn between two lines")

        let resting = resolve(style, cues, at: 2)!
        precondition(resting.content == "ship it", "the line at the playhead is the line drawn")
        precondition(resting.opacity == 1, "a settled caption is fully opaque")
        precondition(abs(resting.center.x - 960) < 0.001, "captions are centred on the canvas")
        precondition(resting.center.y > canvas.height * 0.5, "the default seat is the bottom of the frame")
        precondition(abs(resting.fontSize - style.fontSize) < 0.001, "size is authored against 1080p and this canvas is 1080p")

        precondition(resolve(style, cues, at: 1.1)!.opacity < 1, "a caption fades in")
        precondition(resolve(style, cues, at: 2.95)!.opacity < 1, "and fades back out")

        var top = style
        top.position = .top
        precondition(resolve(top, cues, at: 2)!.center.y < canvas.height * 0.5, "the top seat sits above the middle")

        var shouted = style
        shouted.isUppercase = true
        precondition(resolve(shouted, cues, at: 2)!.content == "SHIP IT", "uppercase is applied to what is drawn, not to what is stored")
        precondition(cues[0].text == "ship it", "and the cue itself is left alone")

        var off = style
        off.isEnabled = false
        precondition(resolve(off, cues, at: 2) == nil, "captions turned off draw nothing")

        let half = resolve(style, cues, at: 2, canvasSize: CGSize(width: 960, height: 540))!
        precondition(abs(half.fontSize - style.fontSize / 2) < 0.001, "half the canvas height means half the type size")

        precondition(painted(resting) > 0, "a resolved caption actually puts pixels down")
        precondition(painted(withBackdrop(resting)) > painted(resting), "the backdrop plate paints behind the words")

        print("captions: speech groups into readable lines that fade in on the canvas")
    }

    static func resolve(_ style: CaptionStyle, _ cues: [CaptionCue], at time: TimeInterval, canvasSize: CGSize? = nil) -> ResolvedText? {
        style.resolved(cues, atSourceTime: time, canvasSize: canvasSize ?? canvas)
    }

    static func withBackdrop(_ text: ResolvedText) -> ResolvedText {
        var plated = text
        plated.backgroundOpacity = 1
        return plated
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
        return stride(from: 3, to: pixels.count, by: 4).count { pixels[$0] > 16 }
    }
}
