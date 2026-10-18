// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Puntos",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Puntos",
            path: "Sources/Puntos",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ],
    swiftLanguageModes: [.v5]
)
