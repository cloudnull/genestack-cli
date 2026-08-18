// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "genestack",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "genectl", targets: ["genestackctl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "4.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "genestackctl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(
            name: "GenestackSpecTests",
            dependencies: [.target(name: "genestackctl")],
            path: "Tests/GenestackSpecTests"
        ),
        .testTarget(
            name: "GenestackUtilsTests",
            dependencies: [.target(name: "genestackctl")],
            path: "Tests/GenestackUtilsTests"
        ),
        .testTarget(
            name: "GenestackCLITests",
            dependencies: [.target(name: "genestackctl")],
            path: "Tests/GenestackCLITests"
        ),
    ]
)
