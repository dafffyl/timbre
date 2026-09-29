// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimbreDiarization",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "TimbreDiarization", targets: ["TimbreDiarization"])
    ],
    dependencies: [
        .package(path: "../TimbreTranscription")
    ],
    targets: [
        .target(name: "TimbreDiarization", dependencies: ["TimbreTranscription"]),
        .testTarget(
            name: "TimbreDiarizationTests",
            dependencies: ["TimbreDiarization"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
