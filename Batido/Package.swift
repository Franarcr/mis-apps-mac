// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Batido",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Batido",
            path: "Sources/Batido",
            linkerSettings: [.linkedFramework("WebKit")]
        )
    ],
    swiftLanguageModes: [.v5]
)
