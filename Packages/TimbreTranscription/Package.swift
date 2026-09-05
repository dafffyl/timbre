// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimbreTranscription",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "TimbreTranscription", targets: ["TimbreTranscription"])
    ],
    targets: [
        .target(name: "TimbreTranscription"),
        .testTarget(name: "TimbreTranscriptionTests", dependencies: ["TimbreTranscription"]),
    ]
)
