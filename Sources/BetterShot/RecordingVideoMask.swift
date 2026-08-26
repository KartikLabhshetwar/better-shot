import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

nonisolated struct RecordingMaskSegment: Codable, Equatable, Identifiable, Sendable {
    nonisolated enum Effect: String, Codable, Sendable, CaseIterable {
        case blur
        case pixelate
    }

    static let minimumAmount: Double = 4
    static let maximumAmount: Double = 80
    static let defaultAmount: Double = 16
    static let minimumDuration: Double = 1

    var id = UUID()
    var x: Double = 0.325
    var y: Double = 0.325
    var width: Double = 0.35
    var height: Double = 0.35
    var effect: Effect = .blur
    var amount: Double = 16
    var start: Double?
    var end: Double?

    var rect: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            let sanitized = RecordingVideoCrop.sanitized(newValue)
            x = sanitized.minX
            y = sanitized.minY
            width = sanitized.width
            height = sanitized.height
        }
    }

    var clampedAmount: Double {
        min(max(amount, Self.minimumAmount), Self.maximumAmount)
    }

    func scaledAmount(forHeight height: CGFloat) -> CGFloat {
        max(1, clampedAmount * height / 1080)
    }

    func isActive(at time: Double) -> Bool {
        time >= (start ?? -.infinity) && time <= (end ?? .infinity)
    }

    func editorRange(duration: Double) -> ClosedRange<Double> {
        let lower = min(max(start ?? 0, 0), max(duration, 0))
        return lower...max(lower, min(end ?? duration, duration))
    }
}

nonisolated enum RecordingMaskRenderer {
    static func masked(_ source: CIImage, segments: [RecordingMaskSegment], at time: Double) -> CIImage {
        segments.reduce(source) { output, segment in
            guard segment.isActive(at: time),
                  let region = filteredRegion(source: source, segment: segment) else { return output }
            return region.composited(over: output)
        }
    }

    static func pixelRect(for segment: RecordingMaskSegment, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + segment.rect.minX * extent.width,
            y: extent.minY + (1 - segment.rect.maxY) * extent.height,
            width: segment.rect.width * extent.width,
            height: segment.rect.height * extent.height
        ).intersection(extent)
    }

    static func filteredRegion(source: CIImage, segment: RecordingMaskSegment) -> CIImage? {
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let rect = pixelRect(for: segment, in: extent)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let strength = segment.scaledAmount(forHeight: extent.height)
        switch segment.effect {
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = source.clampedToExtent()
            filter.radius = Float(strength)
            return filter.outputImage?.cropped(to: rect)
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = source.clampedToExtent()
            filter.scale = Float(max(2, strength))
            filter.center = CGPoint(x: rect.minX, y: rect.minY)
            return filter.outputImage?.cropped(to: rect)
        }
    }
}

nonisolated final class RecordingMaskPreviewState: @unchecked Sendable {
    private let lock = NSLock()
    private var segments: [RecordingMaskSegment] = []

    func update(_ segments: [RecordingMaskSegment]) {
        lock.lock()
        self.segments = segments
        lock.unlock()
    }

    func current() -> [RecordingMaskSegment] {
        lock.lock()
        defer { lock.unlock() }
        return segments
    }
}
