// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Antena",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Antena",
            path: "Sources/Antena",
            linkerSettings: [.linkedFramework("CoreWLAN"), .linkedFramework("CoreLocation")]
        )
    ],
    swiftLanguageModes: [.v5]
)
