// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Guardian",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Guardian",
            path: "Sources/Guardian"
        )
    ],
    swiftLanguageModes: [.v5]
)
