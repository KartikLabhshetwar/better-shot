import AppKit
import CoreGraphics
import Foundation

@main
enum KeystrokeCheck {
    static let canvas = CGSize(width: 1920, height: 1080)

    static func typed(_ key: String, _ time: TimeInterval, _ modifiers: KeyModifiers = []) -> KeyPress {
        KeyPress(time: time, key: key, modifiers: modifiers)
    }

    static func main() {
        let word = KeystrokeSegment.grouped([typed("h", 0), typed("i", 0.1)])
        precondition(word.count == 1 && word[0].text == "hi", "keys typed together read as one word")
        precondition(word[0].start == 0 && word[0].end == 0.1 + KeystrokeSegment.lingerDuration, "a line lingers after the last key")

        let paused = KeystrokeSegment.grouped([typed("h", 0), typed("i", 0.1), typed("x", 2)])
        precondition(paused.count == 2 && paused[0].text == "hi" && paused[1].text == "x", "a pause starts a new line")

        let corrected = KeystrokeSegment.grouped([typed("a", 0), typed("b", 0.1), typed("Backspace", 0.2)])
        precondition(corrected.count == 1 && corrected[0].text == "a", "backspace takes the character back instead of showing itself")

        let erased = KeystrokeSegment.grouped([typed("a", 0), typed("Backspace", 0.1)])
        precondition(erased.isEmpty, "erasing everything leaves nothing on screen")

        let spaced = KeystrokeSegment.grouped([typed("h", 0), typed("i", 0.1), typed("Space", 0.2), typed("y", 0.3)])
        precondition(spaced.count == 2 && spaced[0].text == "hi" && spaced[1].text == "y", "space ends the word without drawing itself")

        let lone = KeystrokeSegment.grouped([typed("Space", 5)])
        precondition(lone.count == 1 && lone[0].text == KeystrokeSegment.symbols["Space"], "space pressed on its own shows its symbol")

        let shortcut = KeystrokeSegment.grouped([typed("a", 0), typed("s", 0.2, [.command])])
        precondition(shortcut.count == 2, "a shortcut interrupts whatever was being typed")
        precondition(shortcut[0].text == "a" && shortcut[1].text == "\u{2318}S", "a shortcut is drawn with its modifier symbols")

        let combo = KeystrokeSegment.grouped([typed("z", 1, [.command, .shift])])
        precondition(combo[0].text == "\u{2318}\u{21E7}Z", "modifiers keep a stable order")

        let arrows = KeystrokeSegment.grouped([typed("Left", 0), typed("Left", 0.1)])
        precondition(arrows.count == 1 && arrows[0].text == "\u{2190}\u{2190}", "special keys type as their symbols")

        let unsorted = KeystrokeSegment.grouped([typed("i", 0.1), typed("h", 0)])
        precondition(unsorted.count == 1 && unsorted[0].text == "hi", "presses are read in time order however they arrive")

        var style = KeystrokeStyle()
        let segments = KeystrokeSegment.grouped([typed("h", 0), typed("i", 0.1)])
        let overlays = style.overlays(segments)
        precondition(overlays.count == 1 && overlays[0].id == segments[0].id, "each line keeps its identity as an overlay")

        let resting = TextOverlay.resolved(overlays, atSourceTime: 0.5, canvasSize: canvas)
        precondition(resting.count == 1 && resting[0].content == "hi", "typing is drawn while its line is on screen")
        precondition(resting[0].opacity == 1 && resting[0].backgroundOpacity == style.backgroundOpacity, "a resting line is opaque and keeps its backdrop")
        precondition(resting[0].center.y == canvas.height * KeystrokeStyle.Position.bottom.center, "the bottom seat sits above the caption lane")
        precondition(KeystrokeStyle.Position.bottom.center < 0.88 && KeystrokeStyle.Position.top.center < 0.12, "neither seat lands on a caption")

        precondition(TextOverlay.resolved(overlays, atSourceTime: 5, canvasSize: canvas).isEmpty, "nothing is drawn once the line is gone")

        let fading = TextOverlay.resolved(overlays, atSourceTime: 0.02, canvasSize: canvas)
        precondition(fading.count == 1 && fading[0].opacity < 1, "a line fades in rather than snapping on")

        style.position = .top
        precondition(style.overlays(segments)[0].center.y == KeystrokeStyle.Position.top.center, "the top seat moves the line up")

        style.isUppercase = true
        precondition(style.overlays(segments)[0].content == "HI" && segments[0].text == "hi", "uppercase changes what is drawn, not what was typed")

        style.isEnabled = false
        precondition(style.overlays(segments).isEmpty, "turning the overlay off draws nothing")

        print("PASS KeystrokeCheck: keyboard overlay: typing groups into words and shortcuts that fade in on the canvas")
    }
}
