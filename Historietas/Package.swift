// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Historietas",
    platforms: [.macOS(.v14)],
    targets: [
        // libarchive viene con macOS y lee ZIP, RAR (4 y 5), 7z y TAR.
        .target(
            name: "CArchive",
            path: "Sources/CArchive",
            linkerSettings: [.linkedLibrary("archive")]
        ),
        .executableTarget(
            name: "Historietas",
            dependencies: ["CArchive"],
            path: "Sources/Historietas"
        ),
    ],
    swiftLanguageModes: [.v5]
)
