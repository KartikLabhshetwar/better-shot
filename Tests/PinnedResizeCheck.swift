import AppKit

@main
enum PinnedResizeCheck {
    static func main() {
        let start = CGRect(x: 300, y: 500, width: 400, height: 250)

        let zoomedIn = PinnedScreenshotController.anchoredFrame(start, resizedTo: CGSize(width: 600, height: 375))
        precondition(zoomedIn.maxY == start.maxY, "zooming in must keep the top edge put, not push the window up")
        precondition(zoomedIn.minX == start.minX, "the left edge stays put too")
        precondition(zoomedIn.size == CGSize(width: 600, height: 375), "the requested size must be applied")

        let zoomedOut = PinnedScreenshotController.anchoredFrame(start, resizedTo: CGSize(width: 200, height: 125))
        precondition(zoomedOut.maxY == start.maxY, "zooming out must keep the top edge put, not drop the window down")
        precondition(zoomedOut.minX == start.minX, "the left edge stays put on the way out too")

        precondition(
            PinnedScreenshotController.anchoredFrame(start, resizedTo: start.size) == start,
            "a no-op zoom must not move the window at all"
        )

        var walked = start
        for _ in 0..<40 {
            walked = PinnedScreenshotController.anchoredFrame(walked, resizedTo: CGSize(width: walked.width * 1.05, height: walked.height * 1.05))
        }
        for _ in 0..<40 {
            walked = PinnedScreenshotController.anchoredFrame(walked, resizedTo: CGSize(width: walked.width / 1.05, height: walked.height / 1.05))
        }
        precondition(abs(walked.maxY - start.maxY) < 0.001, "scrolling in and back out must leave the window where it started, not drifting off screen")

        let onScreenTop = CGRect(x: 0, y: 0, width: 400, height: 250)
        let grown = PinnedScreenshotController.anchoredFrame(onScreenTop, resizedTo: CGSize(width: 800, height: 500))
        precondition(grown.origin.y == -250, "growing from the origin extends downward, which is what anchoring the top means")

        print("PinnedResizeCheck: scroll-zoom pins the pinned window by its top-left corner")
    }
}
