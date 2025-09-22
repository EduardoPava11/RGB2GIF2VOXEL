// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RGB2GIF2VOXEL",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RGB2GIF2VOXEL",
            targets: ["RGB2GIF2VOXEL"]),
    ],
    dependencies: [
        // YAML parsing for configuration
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        // CBOR encoding/decoding for frame serialization
        .package(url: "https://github.com/valpackett/SwiftCBOR", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "RGB2GIF2VOXEL",
            dependencies: ["Yams", "SwiftCBOR"],
            path: "RGB2GIF2VOXEL",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "RGB2GIF2VOXEL-Bridging-Header.h"
            ]
        )
    ]
)