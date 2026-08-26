import CoreGraphics

@main
enum StudioCropCheck {
    static func main() {
        precondition(RecordingVideoCrop.isUnit(RecordingVideoCrop.unit))
        precondition(RecordingVideoCrop.sanitized(CGRect(x: -0.2, y: 0.3, width: 2, height: 0.5)) == CGRect(x: 0, y: 0.3, width: 1, height: 0.5), "out-of-bounds crops must clamp into the unit square")
        precondition(RecordingVideoCrop.isUnit(RecordingVideoCrop.sanitized(CGRect(x: 0.0002, y: 0.0003, width: 0.9995, height: 0.9994))), "near-unit crops must snap back to unit")
        precondition(RecordingVideoCrop.sanitized(CGRect(x: 0.98, y: 0.98, width: 0.001, height: 0.001)) == CGRect(x: 0.98, y: 0.98, width: 0.01, height: 0.01), "tiny crops must grow to the minimum span in place")
        precondition(RecordingVideoCrop.isUnit(RecordingVideoCrop.sanitized(CGRect(x: CGFloat.nan, y: 0, width: CGFloat.nan, height: 1))), "non-finite crops must fall back to unit")

        let size = CGSize(width: 1920, height: 1080)
        precondition(RecordingVideoCrop.croppedSize(size, crop: RecordingVideoCrop.unit) == size, "unit crop must leave the video size untouched")
        precondition(RecordingVideoCrop.croppedSize(size, crop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)) == CGSize(width: 960, height: 540))
        precondition(RecordingVideoCrop.croppedSize(size, crop: CGRect(x: 0, y: 0, width: 0.333, height: 0.5)) == CGSize(width: 640, height: 540), "cropped sizes must round to even pixels")
        precondition(RecordingVideoCrop.croppedSize(CGSize(width: 100, height: 100), crop: CGRect(x: 0, y: 0, width: 0.01, height: 0.01)) == CGSize(width: 2, height: 2), "cropped sizes must never collapse below two pixels")

        let quarter = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        precondition(RecordingVideoCrop.point(CGPoint(x: 0.5, y: 0.5), in: quarter) == CGPoint(x: 0.5, y: 0.5))
        precondition(RecordingVideoCrop.point(CGPoint(x: 0.25, y: 0.75), in: quarter) == CGPoint(x: 0, y: 1))
        precondition(RecordingVideoCrop.point(CGPoint(x: 0.1, y: 0.1), in: RecordingVideoCrop.unit) == CGPoint(x: 0.1, y: 0.1))

        precondition(RecordingVideoCrop.anchor(0.9, origin: 0.25, span: 0.5, magnification: 1) == 0.5, "at magnification 1 every anchor must center")
        precondition(abs(RecordingVideoCrop.anchor(0.55, origin: 0.25, span: 0.5, magnification: 2) - 0.6) < 1e-9, "in-band anchors must remap without clamping")
        precondition(RecordingVideoCrop.anchor(0.3, origin: 0.25, span: 0.5, magnification: 2) == 0.25, "anchors outside the crop must clamp to the visible band")
        precondition(RecordingVideoCrop.anchor(0.99, origin: 0.25, span: 0.5, magnification: 2) == 0.75)
        precondition(RecordingVideoCrop.anchor(0.4, origin: 0, span: 0, magnification: 2) == 0.5, "a degenerate span must fall back to center")

        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        precondition(RecordingVideoCrop.expandedRect(rect, crop: RecordingVideoCrop.unit) == rect)
        let expanded = RecordingVideoCrop.expandedRect(rect, crop: quarter)
        precondition(expanded == CGRect(x: -50, y: -50, width: 200, height: 200))
        precondition(expanded.minX + quarter.minX * expanded.width == rect.minX, "the crop region of the expanded rect must land exactly on the original rect")
        precondition(expanded.minY + quarter.minY * expanded.height == rect.minY)
        precondition(quarter.width * expanded.width == rect.width)

        let offsetRect = CGRect(x: 30, y: 40, width: 120, height: 80)
        let offsetCrop = CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        let offsetExpanded = RecordingVideoCrop.expandedRect(offsetRect, crop: offsetCrop)
        precondition(abs(offsetExpanded.minX + offsetCrop.minX * offsetExpanded.width - offsetRect.minX) < 1e-9)
        precondition(abs(offsetExpanded.minY + offsetCrop.minY * offsetExpanded.height - offsetRect.minY) < 1e-9)
        precondition(abs(offsetCrop.width * offsetExpanded.width - offsetRect.width) < 1e-9)
        precondition(abs(offsetCrop.height * offsetExpanded.height - offsetRect.height) < 1e-9)

        print("StudioCropCheck passed: sanitize, cropped size, point remap, anchor clamp, expanded rect")
    }
}
