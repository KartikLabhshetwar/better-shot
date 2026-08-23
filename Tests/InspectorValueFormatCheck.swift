import Foundation

@main
enum InspectorValueFormatCheck {
    static func expect(_ actual: String, _ expected: String, _ label: String) {
        precondition(actual == expected, "\(label): expected \(expected), got \(actual)")
    }

    static func expectValue(_ actual: CGFloat?, _ expected: CGFloat?, _ label: String) {
        switch (actual, expected) {
        case (nil, nil):
            return
        case let (lhs?, rhs?):
            precondition(abs(lhs - rhs) < 1e-9, "\(label): expected \(rhs), got \(lhs)")
        default:
            preconditionFailure("\(label): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
    }

    static func main() {
        let percent = InspectorValueFormat.percent()
        expect(percent.displayString(for: 0.45), "45%", "percent display")
        expect(percent.editingString(for: 0.45), "45", "percent editing")
        expectValue(percent.parse("45%"), 0.45, "percent parse with suffix")
        expectValue(percent.parse(" 45 "), 0.45, "percent parse bare")
        expectValue(percent.parse("abc"), nil, "percent parse garbage")

        let scaled = InspectorValueFormat.scaled(by: 1000)
        expect(scaled.displayString(for: 0.012), "12", "scaled display")
        expectValue(scaled.parse("12"), 0.012, "scaled parse")
        precondition(abs(scaled.step - 0.001) < 1e-9, "scaled step should be one display unit, got \(scaled.step)")

        let magnification = InspectorValueFormat.magnification(fractionDigits: 1)
        expect(magnification.displayString(for: 2.25), "2.3×", "magnification display")
        expectValue(magnification.parse("2.5x"), 2.5, "magnification parse x")
        expectValue(magnification.parse("2.5×"), 2.5, "magnification parse ×")

        let signed = InspectorValueFormat.percent(signed: true)
        expect(signed.displayString(for: 0.2), "+20%", "signed positive")
        expect(signed.displayString(for: -0.2), "-20%", "signed negative")
        expect(signed.displayString(for: 0), "0%", "signed zero has no sign")
        expectValue(signed.parse("−20%"), -0.2, "signed parse unicode minus")

        let seconds = InspectorValueFormat.seconds()
        expect(seconds.displayString(for: 1.25), "1.3s", "seconds display")
        expectValue(seconds.parse("1.5 sec"), 1.5, "seconds parse word suffix")

        expect(InspectorValueFormat.pixels.displayString(for: 24), "24 px", "pixels display")
        expectValue(InspectorValueFormat.pixels.parse("24 pixels"), 24, "pixels parse word suffix")

        expect(InspectorValueFormat.integer.displayString(for: 1200), "1200", "integer display never groups")

        print("InspectorValueFormatCheck: all assertions passed")
    }
}
