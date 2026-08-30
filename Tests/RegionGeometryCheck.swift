import CoreGraphics

@main
enum RegionGeometryCheck {
    static func main() {
        let secondScreen = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let local = CGRect(x: 100, y: 50, width: 300, height: 200)
        let global = RegionGeometry.globalRect(local: local, screenFrame: secondScreen)
        precondition(global == CGRect(x: 1540, y: -150, width: 300, height: 200))
        precondition(RegionGeometry.localRect(global: global, screenFrame: secondScreen) == local, "global and local must round-trip")

        let points = RegionGeometry.pointsRect(global: CGRect(x: 10, y: 20, width: 100, height: 50), primaryHeight: 900)
        precondition(points == CGRect(x: 10, y: 830, width: 100, height: 50), "top-left flip must use the rect's top edge")

        precondition(RegionGeometry.screencaptureArgument(CGRect(x: 10.4, y: 830.6, width: 100, height: 50)) == "10,831,100,50")
        print("RegionGeometryCheck passed")
    }
}
