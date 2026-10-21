// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Volumen",
    // Los taps de audio por proceso existen desde macOS 14.2.
    platforms: [.macOS("14.2")],
    targets: [
        // La parte de Core Audio va en Objective-C: el bloque que procesa el sonido corre en tiempo real.
        .target(
            name: "CoreAudioTaps",
            path: "Sources/CoreAudioTaps",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .executableTarget(
            name: "Volumen",
            dependencies: ["CoreAudioTaps"],
            path: "Sources/Volumen"
        ),
    ],
    swiftLanguageModes: [.v5]
)
