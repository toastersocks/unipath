// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "unipath",
    products: [
        .executable(name: "unipath", targets: ["unipath"]),
        .library(name: "UnipathCore", targets: ["UnipathCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "UnipathCore"
        ),
        .executableTarget(
            name: "unipath",
            dependencies: [
                "UnipathCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "unipathTests",
            dependencies: ["UnipathCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
