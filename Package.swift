// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "app-snap",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "app-snap",
            path: "Sources/app-snap"
        )
    ]
)
