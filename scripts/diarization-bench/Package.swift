// swift-tools-version: 6.0
// Banc d'essai de la diarisation (hors app) — voir README.md.
import PackageDescription

let package = Package(
    name: "diarization-bench",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.6")
    ],
    targets: [
        .executableTarget(
            name: "diarbench", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "reassign", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
