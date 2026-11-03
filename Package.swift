// swift-tools-version:5.9
// LiveKitWebRTC for Honeycomb Hive (honeycomb-ios D82): the binary built by this repository's
// CI from the pins in PINS, published as release build-1. SwiftPM refuses a download whose
// sha256 differs from `checksum`, which is ZIP_SHA256 in that release's BUILD-RECORD.
// The product is named LiveKitWebRTC so LiveKit's Swift SDK (our fork) resolves it unchanged.

import PackageDescription

let package = Package(
    name: "honeycomb-webrtc",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "LiveKitWebRTC", targets: ["LiveKitWebRTC"]),
    ],
    targets: [
        .binaryTarget(
            name: "LiveKitWebRTC",
            url: "https://github.com/NGS-Labs-LLC/honeycomb-webrtc/releases/download/build-1/LiveKitWebRTC.xcframework.zip",
            checksum: "660396f289a4bb73588b15bc976aacecbb2ef425ae2f17bfe24c80603eefc5b6"
        ),
    ]
)
