// swift-tools-version:5.9
// LiveKitWebRTC for Honeycomb Hive (honeycomb-ios D82): the binary built by this repository's
// CI from the pins in PINS, published as release build-4 (iOS arm64 device; iOS simulator and Mac
// Catalyst, each arm64 + x86_64), with the frame replay check that never resets while the key
// lives, the decrypted key index and the audio-level strip (patches/webrtc-a545de4.patch;
// D-086, honeycomb-ios D156; SEC PR-01, WEBRTC-01). SwiftPM refuses a download whose
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
            url: "https://github.com/NGS-Labs-LLC/honeycomb-webrtc/releases/download/build-4/LiveKitWebRTC.xcframework.zip",
            checksum: "90d2a4eea356cade7b63e11937df777f6ba8723f7c56bd7587b31722d8cf0aa3"
        ),
    ]
)
