// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimbreCore",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "TimbreCore", targets: ["TimbreCore"])
    ],
    targets: [
        .target(name: "TimbreCore"),
        .testTarget(name: "TimbreCoreTests", dependencies: ["TimbreCore"]),
    ]
)
