// swift-tools-version:5.9
// LiveKitWebRTC for Honeycomb Hive (honeycomb-ios D82): the binary built by this repository's
// CI from the pins in PINS, published as release build-2 (iOS arm64 device; iOS simulator and Mac
// Catalyst, each arm64 + x86_64). SwiftPM refuses a download whose
// sha256 differs from `checksum`, which is ZIP_SHA256 in that release's BUILD-RECORD.
// The product is named LiveKitWebRTC so LiveKit's Swift SDK (our fork) resolves it unchanged.

import PackageDescription

let package = Package(
    name: "honeycomb-webrtc",
    platforms: [.iOS(.v13), .macCatalyst(.v14)],
    products: [
        .library(name: "LiveKitWebRTC", targets: ["LiveKitWebRTC"]),
    ],
    targets: [
        .binaryTarget(
            name: "LiveKitWebRTC",
            url: "https://github.com/NGS-Labs-LLC/honeycomb-webrtc/releases/download/build-2/LiveKitWebRTC.xcframework.zip",
            checksum: "a7d1743fdf50e003f664fa146835d0528b7772235684eafa75465e327539ecd4"
        ),
    ]
)
