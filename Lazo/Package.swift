// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lazo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lazo",
            path: "Sources/Lazo",
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("ApplicationServices")]
        )
    ],
    swiftLanguageModes: [.v5]
)
