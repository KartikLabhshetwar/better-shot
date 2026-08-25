import AppKit

@main
enum PointerScreenCheck {
    @MainActor
    static func main() {
        guard !NSScreen.screens.isEmpty else {
            print("PointerScreenCheck: skipped, no window server session")
            return
        }

        var covered = 0
        for screen in NSScreen.screens {
            guard let displayID = ActiveDisplayResolver.displayID(for: screen) else { continue }
            let quartzBounds = CGDisplayBounds(displayID)

            let probes: [(String, CGPoint)] = [
                ("centre", CGPoint(x: quartzBounds.midX, y: quartzBounds.midY)),
                ("top edge", CGPoint(x: quartzBounds.midX, y: quartzBounds.minY + 1)),
                ("bottom edge", CGPoint(x: quartzBounds.midX, y: quartzBounds.maxY - 1)),
            ]

            for (label, point) in probes {
                let resolved = ActiveDisplayResolver.screen(containingQuartzPoint: point)
                precondition(
                    resolved.flatMap(ActiveDisplayResolver.displayID(for:)) == displayID,
                    "a CGEvent at the \(label) of display \(displayID) resolved to the wrong screen: the Quartz-to-AppKit flip is off"
                )
            }
            covered += 1
        }

        precondition(covered > 0, "no display exposed an NSScreenNumber, so nothing was actually checked")

        let primaryHeight: CGFloat = 1080
        func flipped(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            ActiveDisplayResolver.appKitPoint(fromQuartz: CGPoint(x: x, y: y), primaryHeight: primaryHeight)
        }

        precondition(flipped(100, 0) == CGPoint(x: 100, y: 1080), "the top row in Quartz is the top row in AppKit, not the bottom")
        precondition(flipped(100, 1080) == CGPoint(x: 100, y: 0), "the bottom row in Quartz is AppKit's origin")
        precondition(flipped(100, 540) == CGPoint(x: 100, y: 540), "the middle is the fixed point")
        precondition(flipped(100, -600) == CGPoint(x: 100, y: 1680), "a display stacked above the primary has negative Quartz y and must land above it, not below")
        precondition(flipped(100, 1680) == CGPoint(x: 100, y: -600), "a display stacked below the primary must land below it")
        precondition(flipped(-1920, 540) == CGPoint(x: -1920, y: 540), "a display to the left keeps its x untouched")

        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let topProbe = CGPoint(x: mainBounds.midX, y: mainBounds.minY + 1)
        let bottomProbe = CGPoint(x: mainBounds.midX, y: mainBounds.maxY - 1)
        precondition(
            NSScreen.screens.count > 1 || ActiveDisplayResolver.screen(containingQuartzPoint: topProbe) === ActiveDisplayResolver.screen(containingQuartzPoint: bottomProbe),
            "sanity: on one display both edges are the same screen"
        )

        let farOffscreen = CGPoint(x: -900_000, y: -900_000)
        precondition(
            ActiveDisplayResolver.screen(containingQuartzPoint: farOffscreen) != nil,
            "a point on no display must still fall back to the active screen, not leave the picker homeless"
        )

        print("PointerScreenCheck: a hotkey's own pointer location lands on the right display across \(covered) screen(s)")
    }
}
