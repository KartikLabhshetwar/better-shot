import CoreGraphics

nonisolated enum RecordingVideoCrop {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
    static let minimumSpan: CGFloat = 0.01

    static func isUnit(_ rect: CGRect) -> Bool {
        rect == unit
    }

    static func sanitized(_ rect: CGRect) -> CGRect {
        var result = rect.standardized.intersection(unit)
        guard !result.isNull, result.width.isFinite, result.height.isFinite else { return unit }
        result.size.width = max(result.width, minimumSpan)
        result.size.height = max(result.height, minimumSpan)
        result.origin.x = min(max(result.origin.x, 0), 1 - result.width)
        result.origin.y = min(max(result.origin.y, 0), 1 - result.height)
        if result.minX < 0.0005, result.minY < 0.0005, result.width > 0.999, result.height > 0.999 {
            return unit
        }
        return result
    }

    static func croppedSize(_ size: CGSize, crop: CGRect) -> CGSize {
        guard !isUnit(crop) else { return size }
        return CGSize(
            width: max(2, ((size.width * crop.width) / 2).rounded() * 2),
            height: max(2, ((size.height * crop.height) / 2).rounded() * 2)
        )
    }

    static func point(_ point: CGPoint, in crop: CGRect) -> CGPoint {
        guard !isUnit(crop), crop.width > 0, crop.height > 0 else { return point }
        return CGPoint(
            x: (point.x - crop.minX) / crop.width,
            y: (point.y - crop.minY) / crop.height
        )
    }

    static func anchor(_ value: CGFloat, origin: CGFloat, span: CGFloat, magnification: Double) -> CGFloat {
        guard span > 0 else { return 0.5 }
        let remapped = (value - origin) / span
        let half = 1 / (2 * max(CGFloat(magnification), 1))
        return min(max(remapped, half), 1 - half)
    }

    static func expandedRect(_ rect: CGRect, crop: CGRect) -> CGRect {
        guard !isUnit(crop), crop.width > 0, crop.height > 0 else { return rect }
        let width = rect.width / crop.width
        let height = rect.height / crop.height
        return CGRect(
            x: rect.minX - crop.minX * width,
            y: rect.minY - crop.minY * height,
            width: width,
            height: height
        )
    }
}
