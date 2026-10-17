// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Captura",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Captura",
            path: "Sources/Captura",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
