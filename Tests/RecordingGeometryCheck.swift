import CoreGraphics
import Foundation

func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
    guard bounds.width > 0, bounds.height > 0 else { return .zero }
    let width = min(max(rect.width, 1), bounds.width)
    let height = min(max(rect.height, 1), bounds.height)
    let minX = min(max(rect.minX, bounds.minX), bounds.maxX - width)
    let minY = min(max(rect.minY, bounds.minY), bounds.maxY - height)
    return CGRect(x: minX, y: minY, width: width, height: height)
}

func sourceRect(forGlobalQuartzRect selectionRect: CGRect, displayBounds: CGRect, contentRect: CGRect) -> CGRect {
    guard displayBounds.width > 0, displayBounds.height > 0,
          contentRect.width > 0, contentRect.height > 0 else {
        return clamped(selectionRect, to: contentRect)
    }
    let scaleX = contentRect.width / displayBounds.width
    let scaleY = contentRect.height / displayBounds.height
    let minLocalX = min(max(selectionRect.minX - displayBounds.minX, 0), displayBounds.width)
    let maxLocalX = min(max(selectionRect.maxX - displayBounds.minX, 0), displayBounds.width)
    let minLocalY = min(max(selectionRect.minY - displayBounds.minY, 0), displayBounds.height)
    let maxLocalY = min(max(selectionRect.maxY - displayBounds.minY, 0), displayBounds.height)
    let rect = CGRect(
        x: contentRect.minX + minLocalX * scaleX,
        y: contentRect.minY + minLocalY * scaleY,
        width: max(1, (maxLocalX - minLocalX) * scaleX),
        height: max(1, (maxLocalY - minLocalY) * scaleY)
    )
    return clamped(rect, to: contentRect)
}

@main
enum RecordingGeometryCheck {
    static func main() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let primaryContent = CGRect(x: 0, y: 0, width: 1512, height: 982)

        let a = sourceRect(forGlobalQuartzRect: CGRect(x: 100, y: 200, width: 400, height: 300),
                           displayBounds: primary, contentRect: primaryContent)
        assert(a == CGRect(x: 100, y: 200, width: 400, height: 300), "primary passthrough failed: \(a)")

        let secondary = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let secondaryContent = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let b = sourceRect(forGlobalQuartzRect: CGRect(x: 1612, y: 300, width: 800, height: 600),
                           displayBounds: secondary, contentRect: secondaryContent)
        assert(b == CGRect(x: 100, y: 300, width: 800, height: 600), "secondary display offset failed: \(b)")

        let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
        let c = sourceRect(forGlobalQuartzRect: CGRect(x: 40, y: -1400, width: 200, height: 100),
                           displayBounds: above, contentRect: secondaryContent)
        assert(c == CGRect(x: 40, y: 40, width: 200, height: 100), "display-above mapping failed: \(c)")

        let d = sourceRect(forGlobalQuartzRect: CGRect(x: -500, y: -500, width: 4000, height: 4000),
                           displayBounds: primary, contentRect: primaryContent)
        assert(primaryContent.contains(d), "overflow not clamped: \(d)")

        let e = sourceRect(forGlobalQuartzRect: CGRect(x: 1400, y: 900, width: 400, height: 400),
                           displayBounds: primary, contentRect: primaryContent)
        assert(primaryContent.contains(e), "edge overflow not clamped: \(e)")

        func bitRate(_ w: Int, _ h: Int) -> Int { RecordingSession.averageBitRate(width: w, height: h) }
        assert(bitRate(3840, 2160) == 33_177_600, "4K bitrate wrong")

        let oldRate = 2560 * 1440 * 30 * 4
        assert(oldRate / bitRate(2560, 1440) > 20, "sanity: the pre-fix formula should be >20x larger")

        assert(bitRate(800, 600) == 4_000_000, "a tiny window rests on the 4Mbps floor, not the old 20Mbps one")
        assert(bitRate(1600, 1200) == 7_680_000, "a small window is computed, not dragged up to the old 20Mbps floor")
        assert(bitRate(5120, 2880) == 40_000_000, "a 5K display must be capped, not left unbounded")
        assert(bitRate(7680, 4320) == 40_000_000, "the ceiling must hold above 5K too")
        assert(bitRate(2560, 1440) == 14_745_600, "1440p sits between the floor and the ceiling and is left alone")

        print("all recording geometry + bitrate checks passed")
    }
}
