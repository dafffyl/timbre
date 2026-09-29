// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimbreDiarization",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "TimbreDiarization", targets: ["TimbreDiarization"])
    ],
    dependencies: [
        .package(path: "../TimbreTranscription"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.6"),
    ],
    targets: [
        .target(
            name: "TimbreDiarization",
            dependencies: [
                "TimbreTranscription",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(
            name: "TimbreDiarizationTests",
            dependencies: ["TimbreDiarization"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
