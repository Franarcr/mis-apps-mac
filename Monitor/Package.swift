// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Monitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Monitor",
            path: "Sources/Monitor",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreWLAN"), .linkedFramework("CoreLocation"), .linkedFramework("SystemConfiguration")]
        )
    ],
    swiftLanguageModes: [.v5]
)
