// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PanelClaude",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PanelClaude",
            path: "Sources/PanelClaude"
        )
    ],
    swiftLanguageModes: [.v5]
)
