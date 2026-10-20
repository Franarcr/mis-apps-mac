// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ventanas",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ventanas",
            path: "Sources/Ventanas"
        )
    ],
    swiftLanguageModes: [.v5]
)
