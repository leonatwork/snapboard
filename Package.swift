// swift-tools-version: 6.0
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
        )
    ]
)
