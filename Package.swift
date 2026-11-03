// swift-tools-version:5.9
// LiveKitWebRTC for Honeycomb Hive (honeycomb-ios D82): the binary built by this repository's
// CI from the pins in PINS, published as release build-3 (iOS arm64 device; iOS simulator and Mac
// Catalyst, each arm64 + x86_64), with the frame replay check and the audio-level strip
// (patches/webrtc-a545de4.patch; SEC PR-01, WEBRTC-01). SwiftPM refuses a download whose
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
            url: "https://github.com/NGS-Labs-LLC/honeycomb-webrtc/releases/download/build-3/LiveKitWebRTC.xcframework.zip",
            checksum: "34fc6d2b82aa2b568af8751b6c08c650c5859013125af5b12c7001551d399a89"
        ),
    ]
)
