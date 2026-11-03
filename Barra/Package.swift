// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barra",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Barra",
            path: "Sources/Barra"
        )
    ],
    swiftLanguageModes: [.v5]
)
