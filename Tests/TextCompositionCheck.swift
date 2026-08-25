import AppKit

@main
enum TextCompositionCheck {
    @MainActor
    static func main() {
        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 60))

        precondition(textView.syncPreservingComposition(to: "Hello"), "an idle text view must accept new text")
        precondition(textView.string == "Hello", "the new text must actually land")

        precondition(textView.syncPreservingComposition(to: "Hello"), "an unchanged sync still styles, so it must report success")
        precondition(textView.string == "Hello", "an unchanged sync must not disturb the text")

        textView.string = "Hello world"
        textView.selectedRanges = [NSValue(range: NSRange(location: 2, length: 3))]
        precondition(textView.syncPreservingComposition(to: "Hello there"), "a plain edit must go through")
        precondition(textView.string == "Hello there", "the edit must land")
        precondition(
            textView.selectedRanges.first?.rangeValue == NSRange(location: 2, length: 3),
            "the caret must not jump to the start on every keystroke"
        )

        textView.string = "caf"
        textView.selectedRanges = [NSValue(range: NSRange(location: 3, length: 0))]
        textView.setMarkedText("\u{00B4}", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 3, length: 0))
        precondition(textView.hasMarkedText(), "sanity: the dead key must leave a live composition, or this check proves nothing")
        let composing = textView.string

        precondition(
            !textView.syncPreservingComposition(to: "caf"),
            "a SwiftUI refresh mid-composition must be refused, not allowed to overwrite the pending accent"
        )
        precondition(textView.string == composing, "the pending accent must survive the refresh")
        precondition(textView.hasMarkedText(), "the composition must still be live after the refused sync")

        textView.insertText("\u{00E9}", replacementRange: textView.markedRange())
        precondition(!textView.hasMarkedText(), "committing the accent ends the composition")
        precondition(textView.string == "caf\u{00E9}", "the dead key plus e must commit as e-acute, which is the whole point of #77")

        precondition(textView.syncPreservingComposition(to: "caf\u{00E9}s"), "once the composition is committed, syncing resumes")
        precondition(textView.string == "caf\u{00E9}s", "the post-composition edit must land")

        print("TextCompositionCheck: a dead-key accent survives SwiftUI refreshes and commits as one character")
    }
}
