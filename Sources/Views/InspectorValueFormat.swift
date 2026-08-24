import Foundation

struct InspectorValueFormat {
    let multiplier: CGFloat
    let fractionDigits: Int
    let suffix: String
    let showsPositiveSign: Bool
    let step: CGFloat
    let acceptedSuffixes: [String]

    static let integer = InspectorValueFormat(
        multiplier: 1,
        fractionDigits: 0,
        suffix: "",
        showsPositiveSign: false,
        step: 1,
        acceptedSuffixes: []
    )

    static let pixels = InspectorValueFormat(
        multiplier: 1,
        fractionDigits: 0,
        suffix: " px",
        showsPositiveSign: false,
        step: 1,
        acceptedSuffixes: ["pixels", "pixel", "px"]
    )

    static let degrees = InspectorValueFormat(
        multiplier: 1,
        fractionDigits: 0,
        suffix: "°",
        showsPositiveSign: true,
        step: 1,
        acceptedSuffixes: ["°", "deg", "degrees"]
    )

    static func percent(signed: Bool = false, fractionDigits: Int = 0) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: 100,
            fractionDigits: fractionDigits,
            suffix: "%",
            showsPositiveSign: signed,
            step: step(forFractionDigits: fractionDigits) / 100,
            acceptedSuffixes: ["%"]
        )
    }

    static func scaled(by multiplier: CGFloat, fractionDigits: Int = 0) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: multiplier,
            fractionDigits: fractionDigits,
            suffix: "",
            showsPositiveSign: false,
            step: step(forFractionDigits: fractionDigits) / multiplier,
            acceptedSuffixes: []
        )
    }

    static func decimal(fractionDigits: Int) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: 1,
            fractionDigits: fractionDigits,
            suffix: "",
            showsPositiveSign: false,
            step: step(forFractionDigits: fractionDigits),
            acceptedSuffixes: []
        )
    }

    static func magnification(fractionDigits: Int) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: 1,
            fractionDigits: fractionDigits,
            suffix: "×",
            showsPositiveSign: false,
            step: step(forFractionDigits: fractionDigits),
            acceptedSuffixes: ["×", "x"]
        )
    }

    static func seconds(fractionDigits: Int = 1) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: 1,
            fractionDigits: fractionDigits,
            suffix: "s",
            showsPositiveSign: false,
            step: step(forFractionDigits: fractionDigits),
            acceptedSuffixes: ["seconds", "second", "secs", "sec", "s"]
        )
    }

    func displayString(for value: CGFloat) -> String {
        let scaledValue = value * multiplier
        let number = formattedNumber(scaledValue)
        let sign = showsPositiveSign && roundedForDisplay(scaledValue) > 0 ? "+" : ""
        return sign + number + suffix
    }

    func editingString(for value: CGFloat) -> String {
        formattedNumber(value * multiplier)
    }

    func parse(_ text: String) -> CGFloat? {
        var numericText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")

        for acceptedSuffix in acceptedSuffixes {
            numericText = numericText.replacingOccurrences(
                of: acceptedSuffix,
                with: "",
                options: [.caseInsensitive, .anchored, .backwards]
            )
        }

        numericText = numericText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let parsed = try? FloatingPointFormatStyle<Double>.number.parseStrategy.parse(numericText),
              parsed.isFinite else {
            return nil
        }

        return CGFloat(parsed) / multiplier
    }

    private func formattedNumber(_ value: CGFloat) -> String {
        let normalizedValue = roundedForDisplay(value)
        return Double(normalizedValue).formatted(
            .number.precision(.fractionLength(fractionDigits)).grouping(.never)
        )
    }

    private func roundedForDisplay(_ value: CGFloat) -> CGFloat {
        let scale = CGFloat(pow(10, Double(fractionDigits)))
        let rounded = (value * scale).rounded() / scale
        return abs(rounded) < CGFloat.ulpOfOne ? 0 : rounded
    }

    private static func step(forFractionDigits fractionDigits: Int) -> CGFloat {
        1 / CGFloat(pow(10, Double(max(fractionDigits, 0))))
    }
}
