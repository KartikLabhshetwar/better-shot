// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "TourKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TourKit", targets: ["TourKit"])],
    targets: [.target(name: "TourKit"), .testTarget(name: "TourKitTests", dependencies: ["TourKit"])]
)
