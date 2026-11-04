# honeycomb-webrtc
WebRTC for Honeycomb Hive: upstream's build with two small patches

This repository builds WebRTC for the Honeycomb Hive iOS app from
[webrtc-sdk](https://github.com/webrtc-sdk/webrtc) `m150_release` at a pinned commit. That
commit is the first whose frame-encryption key provider accepts `keySize: 256`, which gives
AES-256-GCM media frames (`hive-frame/2`). The framework is `LiveKitWebRTC.xcframework`,
prefixed `LKRTC` and built for iOS arm64 devices, the simulator and Mac Catalyst (the Mac
app), the last two for both arm64 and x86_64. The app's 1:1 calls
and LiveKit's Swift SDK share it. The design is honeycomb-ios `docs/design/AES-256-FRAMES.md`
(D82).

## Upstream

| | Commit |
|---|---|
| WebRTC source | [webrtc-sdk/webrtc](https://github.com/webrtc-sdk/webrtc) `a545de45259b47dfac5f3635863e47cb601f1bb2` (`m150_release`, 2026-10-22) |
| Build scripts | [webrtc-sdk/webrtc-build](https://github.com/webrtc-sdk/webrtc-build) `717ec1dc5a94389d691e09cccaf3d7b3364fb4b7` (tag `m150.7871.04`, upstream's build of the same commit) |
| depot_tools | `4be4e4628e093c4ad50210db5dcfa05a88280bda` (HEAD at the first green build, 2026-10-23) |
| Xcode | 26.6, build `17F113`; the Catalyst slice 26.0.1, build `17A400` (`Xcode_26.0.app`) |

`PINS` is the source of truth. This table follows it.

## Build command

On macOS with Xcode at the version and build number in `PINS`, from a clean checkout:

```sh
./build.sh                  # writes out/LiveKitWebRTC.xcframework.zip and out/BUILD-RECORD
```

It takes hours and tens of GB of disk. `OUT=<dir>` and `WORK=<dir>` move the output and the
scratch tree. CI runs the same command (`.github/workflows/build.yml`), twice per change, and
compares the two results.

## What goes in

| File | What it is |
|---|---|
| `PINS` | Every input, exact and required: the webrtc-sdk commit, the [webrtc-build](https://github.com/webrtc-sdk/webrtc-build) commit whose scripts build it, depot_tools, and Xcode by version and build number |
| `patches/UPSTREAM.sha256` | sha256 of the webrtc-build files used. `build.sh` refuses if any differs |
| `patches/webrtc-build-m150.7871.04.patch` | The build-script patch, to webrtc-build's `xcframework.sh` and `run.py`. It builds five platforms instead of eleven, made into three slices (iOS arm64 device; iOS simulator and Mac Catalyst, each arm64 + x86_64), writes a normalised zip, and adds `run.py`'s hook for the WebRTC source patch after upstream's own `apple_prefix.patch`. GN arguments are upstream's |
| `patches/webrtc-a545de4.patch` | The WebRTC source patch (since `build-3`; changed in `build-4`), ten files: the receiver's frame replay check in the frame cryptor, which never resets while the key lives and retires evicted `ssrc`s (SEC PR-01; hive-node wire-protocol.md 6.6 "Replay", D-075, D-086), with its gtest file in `crypto_unittests`; the key index a played frame decrypted under, reported to the cryptor's observer and Objective-C delegate (honeycomb-ios D156); and the RTP audio-level header extensions removed from parsed descriptions at session and media level, from what the voice engine offers, and from what an audio stream sends (SEC WEBRTC-01). Nothing else in WebRTC is patched beyond upstream's `apple_prefix.patch` |
| `patches/WEBRTC-UPSTREAM.sha256`, `WEBRTC-PATCHED.sha256` | sha256 of the WebRTC files the source patch touches, before and after it. `patches/apply-webrtc-patch.sh` refuses if either differs; `build.sh` checks the built tree against the second again |
| `tests/` | The replay check against hive-node's `frame_replay` vectors (`frame_replay.vectors`, extracted by `extract-frame-replay.py`) and its bounds. CI runs it on Linux in minutes, on the patched upstream files |
| `build.sh` | Checks every pin is set and both Xcode build numbers, fetches the pins, checks them, applies both patches, builds, checks the output (`keySize`, every class prefixed, the patched files), and writes `BUILD-RECORD` and `RESOLVED` |

## What comes out

`BUILD-RECORD` lists:
- the pipeline commit it was built from (`COMMIT`);
- every pin;
- the runner image and both Xcode builds;
- both patches' sha256 and the upstream files checked before them;
- the resolved dependency set (`gclient revinfo --actual`, also the `RESOLVED` asset) and its sha256;
- the zip's sha256 and size;
- each slice's sha256 and the key-provider header's sha256;
- the GN arguments;
- the build time and the CI run.

CI builds twice on fresh runners and compares the two records. A tag `build-*` publishes a
release once that comparison has run and the record's pins match `PINS` at the tag; its notes
carry each asset's sha256, the comparison's verdict with both builds' hashes (`COMPARE`), and the
full `BUILD-RECORD`. The comparison is recorded, not yet a gate (D82 3.5).

The workflow runs on pull requests that change the pipeline (`PINS`, `build.sh`, `patches/`,
`tests/`, the workflow), on a manual dispatch, and on a `build-*` tag. Only the tag publishes.

## Releases and their sha256

| Release | Asset | sha256 |
|---|---|---|
| `build-1`, `build-2` | see `releases/build-1.md`, `releases/build-2.md` and each release's notes | |
| `build-3` | the WebRTC source patch (PR-01, WEBRTC-01); see `releases/build-3.md` | `LiveKitWebRTC.xcframework.zip` `34fc6d2b82aa2b568af8751b6c08c650c5859013125af5b12c7001551d399a89` |
| `build-4` | no replay reset while the key lives, retired `ssrc`s (D-086), the decrypted key index (D156); see `releases/build-4.md` | once tagged |

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
