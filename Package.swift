// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ImageCanvas",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ImageCanvas", targets: ["ImageCanvas"])
    ],
    targets: [
        .executableTarget(name: "ImageCanvas"),
        .testTarget(name: "ImageCanvasTests", dependencies: ["ImageCanvas"])
    ]
)
