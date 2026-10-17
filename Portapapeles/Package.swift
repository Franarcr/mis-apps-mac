// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portapapeles",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Portapapeles",
            path: "Sources/Portapapeles",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ],
    swiftLanguageModes: [.v5]
)
