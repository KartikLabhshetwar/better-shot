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
