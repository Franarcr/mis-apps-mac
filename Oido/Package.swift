// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Oido",
    // Los taps de audio por proceso existen desde macOS 14.2.
    platforms: [.macOS("14.2")],
    targets: [
        // La captura del audio va en Objective-C: el bloque que recibe el sonido corre en tiempo real.
        .target(
            name: "OidoAudio",
            path: "Sources/OidoAudio",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AudioToolbox")]
        ),
        .executableTarget(
            name: "Oido",
            dependencies: ["OidoAudio"],
            path: "Sources/Oido"
        ),
    ],
    swiftLanguageModes: [.v5]
)
