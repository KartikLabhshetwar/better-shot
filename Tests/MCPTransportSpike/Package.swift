// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MCPTransportSpike",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .executableTarget(
            name: "MCPTransportSpike",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
        .target(
            name: "MCPAppSettingsCheck",
            dependencies: [.product(name: "MCP", package: "swift-sdk")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags([
                    "-default-isolation", "MainActor",
                    "-enable-upcoming-feature", "ApproachableConcurrency",
                    "-enable-upcoming-feature", "MemberImportVisibility",
                ]),
            ]
        ),
    ]
)
