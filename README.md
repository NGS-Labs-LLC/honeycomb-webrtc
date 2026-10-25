# honeycomb-webrtc
unmodified build or a one-patch fork for Honeycomb Hive

This repository builds WebRTC for the Honeycomb Hive iOS app from
[webrtc-sdk](https://github.com/webrtc-sdk/webrtc) `m150_release` at a pinned commit. That
commit is the first whose frame-encryption key provider accepts `keySize: 256`, which gives
AES-256-GCM media frames (`hive-frame/2`). The framework is `LiveKitWebRTC.xcframework`,
prefixed `LKRTC` and built for iOS arm64 devices, the arm64 simulator and Mac Catalyst on
arm64 (the Mac app). The app's 1:1 calls
and LiveKit's Swift SDK share it. The design is honeycomb-ios `docs/design/AES-256-FRAMES.md`
(D82).

## Upstream

| | Commit |
|---|---|
| WebRTC source | [webrtc-sdk/webrtc](https://github.com/webrtc-sdk/webrtc) `a545de45259b47dfac5f3635863e47cb601f1bb2` (`m150_release`, 2026-10-22) |
| Build scripts | [webrtc-sdk/webrtc-build](https://github.com/webrtc-sdk/webrtc-build) `717ec1dc5a94389d691e09cccaf3d7b3364fb4b7` (tag `m150.7871.04`, upstream's build of the same commit) |
| depot_tools | `4be4e4628e093c4ad50210db5dcfa05a88280bda` (HEAD at the first green build, 2026-10-23) |
| Xcode | 26.6 |

`PINS` is the source of truth. This table follows it.

## Build command

On macOS with Xcode at the version in `PINS`, from a clean checkout:

```sh
./build.sh                  # writes out/LiveKitWebRTC.xcframework.zip and out/BUILD-RECORD
```

It takes hours and tens of GB of disk. `OUT=<dir>` and `WORK=<dir>` move the output and the
scratch tree. CI runs the same command (`.github/workflows/build.yml`), twice per change, and
compares the two results.

## What goes in

| File | What it is |
|---|---|
| `PINS` | Every input, exact: the webrtc-sdk commit, the [webrtc-build](https://github.com/webrtc-sdk/webrtc-build) commit whose scripts build it, depot_tools, Xcode |
| `patches/UPSTREAM.sha256` | sha256 of the webrtc-build files used. `build.sh` refuses if any differs |
| `patches/webrtc-build-m150.7871.04.patch` | The one patch, to webrtc-build's `xcframework.sh`. It builds three slices instead of eleven (iOS device, iOS simulator, Mac Catalyst, all arm64) and writes a normalised zip. GN arguments are upstream's. Nothing in WebRTC itself is patched beyond upstream's own `apple_prefix.patch` |
| `build.sh` | Fetches the pins, checks them, applies the patch, builds, checks the output (`keySize`, every class prefixed), and writes `BUILD-RECORD` |

## What comes out

`BUILD-RECORD` lists:
- every pin;
- the runner image and Xcode build;
- the patch's sha256;
- the zip's sha256 and size;
- each slice's sha256 and the key-provider header's sha256;
- the GN arguments;
- the build time and the CI run.

CI builds twice on fresh runners and compares the two records. A tag `build-*` publishes a
release whose notes carry each asset's sha256 and the full `BUILD-RECORD`.

## Releases and their sha256

| Release | Asset | sha256 |
|---|---|---|
| (none yet; the first is `build-1` once the build PR merges) | | |

Each release's notes list the sha256 of **every asset**: `LiveKitWebRTC.xcframework.zip`,
`BUILD-RECORD` and `MANIFEST.sha256` (the sha256 of every file inside the framework). Each release adds a row here. The zip's sha256 is the checksum SwiftPM checks in
`Package.swift`. To check a download:

```sh
shasum -a 256 LiveKitWebRTC.xcframework.zip BUILD-RECORD MANIFEST.sha256   # equal the sha256 values in the notes and here
```

## Rules

- Draft PRs only, merged by a person.
- No secrets in any file.
- `gitleaks dir --redact .` before every push.
