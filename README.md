# honeycomb-webrtc
unmodified build or a one-patch fork for Honeycomb Hive

This repository builds WebRTC for the Honeycomb Hive iOS app from
[webrtc-sdk](https://github.com/webrtc-sdk/webrtc) `m150_release` at a pinned commit. That
commit is the first whose frame-encryption key provider accepts `keySize: 256`, which gives
AES-256-GCM media frames (`hive-frame/2`). The framework is `LiveKitWebRTC.xcframework`,
prefixed `LKRTC` and built for iOS arm64 devices and the arm64 simulator. The app's 1:1 calls
and LiveKit's Swift SDK share it. The design is honeycomb-ios `docs/design/AES-256-FRAMES.md`
(D82).

## What goes in

| File | What it is |
|---|---|
| `PINS` | Every input, exact: the webrtc-sdk commit, the [webrtc-build](https://github.com/webrtc-sdk/webrtc-build) commit whose scripts build it, depot_tools, Xcode |
| `patches/UPSTREAM.sha256` | sha256 of the webrtc-build files used. `build.sh` refuses if any differs |
| `patches/webrtc-build-m150.7871.04.patch` | The one patch, to webrtc-build's `xcframework.sh`. It builds two slices instead of eleven and writes a normalised zip. GN arguments are upstream's. Nothing in WebRTC itself is patched beyond upstream's own `apple_prefix.patch` |
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
release whose notes carry the zip's sha256 and the full `BUILD-RECORD`.

## Checking a release

```sh
shasum -a 256 LiveKitWebRTC.xcframework.zip   # equals the sha256 in the release notes
```

To rebuild it, run `./build.sh` on macOS with Xcode at the version in `PINS`. It takes hours and
tens of GB of disk.

## Rules

- Draft PRs only, merged by a person.
- No secrets in any file.
- `gitleaks dir --redact .` before every push.
