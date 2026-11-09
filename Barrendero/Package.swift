// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barrendero",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Barrendero",
            path: "Sources/Barrendero"
        )
    ],
    swiftLanguageModes: [.v5]
)
