// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snapboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Snapboard", targets: ["Snapboard"])
    ],
    targets: [
        .executableTarget(
            name: "Snapboard",
            path: "Sources"
        ),
        .testTarget(
            name: "SnapboardTests",
            dependencies: ["Snapboard"],
            path: "Tests/SnapboardTests"
        )
    ]
)
