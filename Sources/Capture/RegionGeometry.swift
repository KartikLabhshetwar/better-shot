import CoreGraphics

enum RegionGeometry {
    static func globalRect(local: CGRect, screenFrame: CGRect) -> CGRect {
        local.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
    }

    static func localRect(global: CGRect, screenFrame: CGRect) -> CGRect {
        global.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    /// Flips a global AppKit (bottom-left) rect into screencapture's top-left point space.
    static func pointsRect(global: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: global.minX, y: primaryHeight - global.maxY, width: global.width, height: global.height)
    }

    static func screencaptureArgument(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0.rounded())) }.joined(separator: ",")
    }
}

enum RegionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move

    var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
    var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }

    func point(in rect: CGRect) -> CGPoint {
        let x = movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX
        let y = movesTop ? rect.maxY : movesBottom ? rect.minY : rect.midY
        return CGPoint(x: x, y: y)
    }
}

enum RegionAdjustment {
    static let handleRadius: CGFloat = 8

    static func handle(at point: CGPoint, in rect: CGRect) -> RegionHandle? {
        let nearest = RegionHandle.allCases
            .filter { $0 != .move }
            .map { ($0, distance(point, $0.point(in: rect))) }
            .min { $0.1 < $1.1 }
        if let nearest, nearest.1 <= handleRadius { return nearest.0 }
        return rect.contains(point) ? .move : nil
    }

    static func apply(_ handle: RegionHandle, delta: CGSize, to rect: CGRect, within bounds: CGRect) -> CGRect {
        if handle == .move {
            return CGRect(
                x: min(max(rect.minX + delta.width, bounds.minX), bounds.maxX - rect.width),
                y: min(max(rect.minY + delta.height, bounds.minY), bounds.maxY - rect.height),
                width: rect.width,
                height: rect.height
            )
        }
        let x0 = clamp(rect.minX + (handle.movesLeft ? delta.width : 0), bounds.minX, bounds.maxX)
        let x1 = clamp(rect.maxX + (handle.movesRight ? delta.width : 0), bounds.minX, bounds.maxX)
        let y0 = clamp(rect.minY + (handle.movesBottom ? delta.height : 0), bounds.minY, bounds.maxY)
        let y1 = clamp(rect.maxY + (handle.movesTop ? delta.height : 0), bounds.minY, bounds.maxY)
        return CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
