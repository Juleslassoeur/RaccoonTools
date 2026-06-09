// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RaccoonTools",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RaccoonTools",
            path: "Sources/RaccoonTools"
        ),
        .testTarget(
            name: "RaccoonToolsTests",
            dependencies: ["RaccoonTools"],
            path: "Tests/RaccoonToolsTests"
        )
    ]
)
