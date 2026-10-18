// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-minidisc",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ATRACKit", targets: ["ATRACKit"]),
        .library(name: "NetMDKit", targets: ["NetMDKit"]),
    ],
    targets: [
        // kai-h/atrac-encoder compiled unmodified from the submodule. Its internal.h sets
        // `#pragma STDC FP_CONTRACT OFF`, which byte-exact output depends on.
        .target(name: "CATRAC3"),
        .target(name: "ATRACKit", dependencies: ["CATRAC3"]),
        // netmd-js + netmd-exploits in JavaScriptCore over IOUSBHost. `make js` builds the bundle.
        .target(
            name: "NetMDKit",
            resources: [
                .copy("Resources/netmd-bundle.js"),
                .copy("Resources/assembler.wasm"),
                .copy("Resources/webusb-shim.js"),
                .copy("Resources/netmd-host.js"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOUSBHost")]
        ),
        // at3tool-compatible CLI so upstream's tests/run_tests.py can check our build.
        .executableTarget(name: "atrac3-swift", dependencies: ["ATRACKit"]),
        // Hardware test tool (`make cli`): list, upload, erase from the command line.
        .executableTarget(name: "netmd-cli", dependencies: ["ATRACKit", "NetMDKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ATRACKitTests", dependencies: ["ATRACKit"]),
    ]
)
