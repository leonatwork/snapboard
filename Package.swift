// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screenie",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Screenie", targets: ["Screenie"])
    ],
    targets: [
        .executableTarget(
            name: "Screenie",
            path: "Sources"
        )
    ]
)
