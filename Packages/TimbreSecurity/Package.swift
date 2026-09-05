// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimbreSecurity",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "TimbreSecurity", targets: ["TimbreSecurity"])
    ],
    targets: [
        .target(name: "TimbreSecurity")
    ]
)
