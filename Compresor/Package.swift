// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Compresor",
    platforms: [.macOS(.v14)],
    targets: [
        // libarchive viene con macOS: lee ZIP, 7z, RAR 4/5, TAR, ISO, CAB, LHA… y escribe ZIP (con AES-256), 7z y TAR.
        .target(
            name: "CArchive",
            path: "Sources/CArchive",
            linkerSettings: [.linkedLibrary("archive")]
        ),
        .executableTarget(
            name: "Compresor",
            dependencies: ["CArchive"],
            path: "Sources/Compresor",
            linkerSettings: [.linkedFramework("Quartz")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
