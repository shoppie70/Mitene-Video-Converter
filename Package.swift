// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiteneVideoConverter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MiteneVideoConverter", targets: ["MiteneVideoConverter"]),
    ],
    targets: [
        .executableTarget(
            name: "MiteneVideoConverter",
            path: "Sources/MiteneVideoConverter"
        ),
        .testTarget(
            name: "MiteneVideoConverterTests",
            dependencies: ["MiteneVideoConverter"],
            path: "Tests/MiteneVideoConverterTests"
        ),
    ]
)
