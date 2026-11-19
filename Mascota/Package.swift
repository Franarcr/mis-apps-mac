// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mascota",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Mascota",
            path: "Sources/Mascota"
        )
    ],
    swiftLanguageModes: [.v5]
)
