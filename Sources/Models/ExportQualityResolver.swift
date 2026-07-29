import Foundation

enum ExportQualityResolver {
    static let sliderRange: ClosedRange<Double> = 0.0...1.0

    static func resolve(_ storedValue: Double?) -> Double {
        let value = storedValue ?? 0.9
        return min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
    }
}
