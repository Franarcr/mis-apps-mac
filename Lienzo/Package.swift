// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lienzo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Lienzo", path: "Sources/Lienzo")
    ],
    swiftLanguageModes: [.v5]
)
