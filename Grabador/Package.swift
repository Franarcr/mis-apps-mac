// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Grabador",
    platforms: [.macOS(.v14)],
    targets: [
        // libarchive (incluida en macOS) para descomprimir .zip/.gz/.xz/.bz2 al vuelo,
        // y la recepción del descriptor que devuelve authopen.
        .target(
            name: "CGrabador",
            path: "Sources/CGrabador",
            linkerSettings: [.linkedLibrary("archive")]
        ),
        .executableTarget(
            name: "Grabador",
            dependencies: ["CGrabador"],
            path: "Sources/Grabador",
            linkerSettings: [.linkedFramework("DiskArbitration"), .linkedFramework("Security")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
