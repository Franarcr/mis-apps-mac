// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Revela",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Revela",
            path: "Sources/Revela",
            linkerSettings: [.linkedFramework("CoreImage"), .linkedFramework("Vision")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
