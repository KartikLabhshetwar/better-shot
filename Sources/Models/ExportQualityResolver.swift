import Foundation

enum ExportQualityResolver {
    static let sliderRange: ClosedRange<Double> = 0.0...1.0

    static func resolve(_ storedValue: Double?) -> Double {
        storedValue ?? 0.9
    }
}
