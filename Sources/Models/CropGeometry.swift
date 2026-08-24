import CoreGraphics

/// Crop rectangles are fractions of the frame they sit in, so the same math serves the image canvas, the video preview and the exporter.
enum CropGeometry {
    static let identity = CGRect(x: 0, y: 0, width: 1, height: 1)
    static let minFraction: CGFloat = 0.08

    struct Edges: OptionSet, Sendable {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }

        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    static func resized(_ rect: CGRect, edges: Edges, to point: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        if edges.contains(.left) { minX = min(max(0, point.x), maxX - minFraction) }
        if edges.contains(.right) { maxX = max(min(1, point.x), minX + minFraction) }
        if edges.contains(.top) { minY = min(max(0, point.y), maxY - minFraction) }
        if edges.contains(.bottom) { maxY = max(min(1, point.y), minY + minFraction) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func moved(_ rect: CGRect, by translation: CGSize) -> CGRect {
        CGRect(
            x: min(max(0, rect.minX + translation.width), 1 - rect.width),
            y: min(max(0, rect.minY + translation.height), 1 - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    /// Cropping an already cropped frame, expressed back in the original frame's coordinates.
    static func composed(_ outer: CGRect, _ inner: CGRect) -> CGRect {
        CGRect(
            x: outer.minX + inner.minX * outer.width,
            y: outer.minY + inner.minY * outer.height,
            width: outer.width * inner.width,
            height: outer.height * inner.height
        )
    }

    /// The rect that undoes `rect` when fed back through the same remapping, so resetting a crop restores coordinates instead of discarding them.
    static func inverted(_ rect: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return identity }
        return CGRect(
            x: -rect.minX / rect.width,
            y: -rect.minY / rect.height,
            width: 1 / rect.width,
            height: 1 / rect.height
        )
    }

    static func pixels(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
}
