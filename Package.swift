// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "workr",
    platforms: [.macOS(.v13)],
    products: [
        // The `work` CLI.
        .executable(name: "work", targets: ["work"]),
        // The remote-provider plugin contract, depended on by out-of-tree
        // provider plugins (e.g. workr-remote-coder).
        .library(name: "WorkRemoteContract", targets: ["WorkRemoteContract"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "WorkRemoteContract",
            path: "Sources/WorkRemoteContract"
        ),
        .executableTarget(
            name: "work",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                "WorkRemoteContract",
            ],
            path: "Sources/work"
        ),
        .testTarget(
            name: "workTests",
            dependencies: ["work"],
            path: "Tests/workTests"
        ),
    ]
)
