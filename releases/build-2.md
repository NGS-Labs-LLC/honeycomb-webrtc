# Release `build-2`: Mac Catalyst

`build-1` plus a third slice, **Mac Catalyst arm64** (`ios-arm64-maccatalyst`), for the
honeycomb-ios Mac app (Phase 5; Paul chose Catalyst on 2026-10-25). The pins are unchanged. The
patch keeps upstream's `catalyst-arm64` platform with upstream's GN arguments, except the
deployment target. That is 26.0 (the app's minimum), not upstream's 14.0. The first CI run
showed that at 14.0 the macOS 26.5 SDK's newer system libraries (`libsystem_eligibility`,
`libsystem_sanitizers`, `libsystem_trial`) refuse to link: "incompatible with arm64
(macCatalyst14.0.0)". At 26.0, the second run then stopped on a deprecation that only Catalyst
reports (`RTCFileVideoCapturer`'s `tracksWithMediaType:`, deprecated since macCatalyst 18), under
upstream's `treat_warnings_as_errors`. That is off for the Catalyst slice only: the iOS slices keep
upstream's arguments exactly, so they can still be compared with `build-1`. The iOS slices are built from the same inputs as `build-1`, so they should
match it.

`build.sh` also checks the new slice:
- it is a versioned bundle (`LiveKitWebRTC` → `Versions/Current/LiveKitWebRTC`);
- `vtool` reports `platform MACCATALYST` and `minos 26.0`;
- it is arm64 only.

Intel Macs aren't built: Paul's MacBook and CI's runners are Apple silicon. Adding
`catalyst-x64` back is one line.

## What this PR's CI shows

Opening the PR runs the build twice on fresh `macos-26` runners and compares them. The Catalyst
slice adds a third GN build, so expect about a third longer than `build-1`'s 60–67 minutes per
build. That's still free on this public repository.

## Then, in order (a person pushes the tags; agent sessions can't)

1. **This PR:** tag `build-2` at its head. The tag publishes the release with the zip's sha256.
   ```sh
   git fetch origin agent/ui-ux/webrtc-catalyst
   git tag -a build-2 -m "LiveKitWebRTC build-2: Mac Catalyst (honeycomb-ios Phase 5)" FETCH_HEAD
   git push origin build-2
   ```
2. **The package:** `Package.swift` points at `build-2` with its sha256 and adds
   `.macCatalyst(.v14)`. I push that to a branch off `agent/ui-ux/webrtc-package` once the
   release exists. You tag it `150.7871.4-hc.2`.
3. **The fork** (`NGS-Labs-LLC/client-sdk-swift`) pins `honeycomb-webrtc` exactly. It needs
   `150.7871.4-hc.2` and a tag `2.18.0-hc.2`. This also needs access to that repository in
   the agent session.
4. **honeycomb-ios:** the Mac PR pins both new versions, and CI builds and tests on
   `platform=macOS,variant=Mac Catalyst`.
