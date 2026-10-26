# Release `build-2`: Mac Catalyst

`build-1` plus a third slice, **Mac Catalyst arm64** (`ios-arm64-maccatalyst`), for the
honeycomb-ios Mac app (Phase 5; Paul chose Catalyst on 2026-10-25). The patch keeps upstream's
`catalyst-arm64` platform and its GN arguments unchanged.

**One difference, the SDK:** the Catalyst slice links against **Xcode 26.0**, which is upstream's
Xcode for this tag (`CATALYST_XCODE_VERSION` in `PINS`). The iOS slices stay on Xcode 26.6, so
they should match `build-1`.
- **Why:** with Xcode 26.6, the macOS 26.5 SDK's `libsystem_eligibility`, `libsystem_sanitizers`
  and `libsystem_trial` stubs list no Catalyst target, and lld refuses them. The error is
  "incompatible with arm64 (macCatalyst14.0.0)", and the same at 26.0.
- **What it isn't:** the first two CI runs tried a higher deployment target, then
  warnings-not-errors. Neither was the cause, so both are reverted.

`build.sh` also checks the new slice:
- it is a versioned bundle (`LiveKitWebRTC` → `Versions/Current/LiveKitWebRTC`);
- `vtool` reports `platform MACCATALYST` and `minos 14.0`;
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
