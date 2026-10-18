// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-minidisc",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ATRACKit", targets: ["ATRACKit"]),
    ],
    targets: [
        // kai-h/atrac-encoder compiled unmodified from the submodule. Its internal.h sets
        // `#pragma STDC FP_CONTRACT OFF`, which byte-exact output depends on.
        .target(name: "CATRAC3"),
        .target(name: "ATRACKit", dependencies: ["CATRAC3"]),
        // at3tool-compatible CLI so upstream's tests/run_tests.py can check our build.
        .executableTarget(name: "atrac3-swift", dependencies: ["ATRACKit"]),
        .testTarget(name: "ATRACKitTests", dependencies: ["ATRACKit"]),
    ]
)
