// swift-tools-version: 6.0
import PackageDescription

// Spike: run netmd-js + netmd-exploits in JavaScriptCore over a Swift WebUSB shim.
// Run `npm install && npm run build` first to produce the JS bundle.
let package = Package(
    name: "NetMDJSC",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NetMDJSC", targets: ["NetMDJSC"]),
        .executable(name: "netmd-jsc-spike", targets: ["netmd-jsc-spike"]),
    ],
    targets: [
        .target(
            name: "NetMDJSC",
            resources: [
                .copy("Resources/netmd-bundle.js"),
                .copy("Resources/assembler.wasm"),
                .copy("Resources/webusb-shim.js"),
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
            ]
        ),
        .executableTarget(name: "netmd-jsc-spike", dependencies: ["NetMDJSC"]),
    ],
    swiftLanguageModes: [.v5]
)
