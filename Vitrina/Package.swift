// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vitrina",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Vitrina", path: "Sources/Vitrina")
    ],
    swiftLanguageModes: [.v5]
)
