# Release `build-3`: the WebRTC source patch (SEC PR-01 and WEBRTC-01)

`build-2`'s slices, GN arguments and Xcode, plus the first patch to WebRTC's own source,
`patches/webrtc-a545de4.patch` (honeycomb-security PR #10, `code-audit-webrtc.md`). It has two
parts.

**1. Frame replay check (SEC PR-01; hive-node wire-protocol.md 6.6 "Replay", D-075).**
- GCM proves a frame came from the key's holder, not that it is new. The SFU terminates SRTP
  and re-packetizes, so it can send a member's earlier frames again; until now every receiver
  played them.
- After a frame decrypts, `FrameCryptorTransformer::decryptFrame` reads the IV's `ssrc` and
  timestamp (authenticated by GCM; the RTP header's timestamp, which the SFU rewrites, is never
  read). It asks the key set it decrypted under whether the IV is new
  (`api/crypto/frame_replay_guard.h`).
- Per key and `ssrc`, the guard keeps the newest timestamp (serial arithmetic mod 2^32) and the
  IVs within 2 s of the codec clock behind it: 96 000 ticks for audio, 180 000 for video. It
  refuses a repeated IV, or a timestamp more than the window behind. A late frame inside the
  window plays.
- Bounds: at most 16 `ssrc`s per key, and per `ssrc` only the IVs inside the window. An `ssrc`
  whose every frame was refused as window-behind for 2 s is reset.
- The state lives on the key set. A new key starts empty, and the state goes when the key is
  dropped. Setting the key a slot already holds keeps that key and its state. Frames that do
  not decrypt never touch it.
- `tests/frame_replay_guard_test.cc` checks the guard against hive-node's `frame_replay`
  vectors (15 frames, 5 drops, `a65d2c0`) and the bounds. The `source-patch` CI job runs it on
  the patched upstream files.

**2. Audio level stays off the wire (SEC WEBRTC-01; wire-protocol.md 6.6).**
- The RTP `ssrc-audio-level` and `csrc-audio-level` header extensions travel outside the frame
  encryption and would tell the SFU who speaks when.
- `build-2` relied on the LiveKit fork stripping them from the SFU's descriptions. That strip
  read media sections only: a session-level `a=extmap`, which libwebrtc copies into every
  section, got through. The fork also left them in local offers.
- Now WebRTC itself:
  - drops both from every parsed description, at session level and in media sections
    (`api/webrtc_sdp.cc`);
  - lists `ssrc-audio-level` as stopped, so it is never offered or answered
    (`WebRtcVoiceEngine::GetRtpHeaderExtensions`);
  - never sends either on an audio stream, whatever was negotiated (the send channel's
    extension filter).
- This covers the one-to-one engine and the LiveKit path alike.

**The pipeline (WEBRTC-03 to WEBRTC-07).**
- `run.py` gains a hook after upstream's `apple_prefix.patch` (in the webrtc-build patch).
  `patches/apply-webrtc-patch.sh` checks the five upstream files against
  `WEBRTC-UPSTREAM.sha256`, applies the patch, refuses rejects, and checks
  `WEBRTC-PATCHED.sha256`. `build.sh` checks the built tree against that list again.
- `PINS` adds the Xcode build numbers: `XCODE_BUILD=17F113`, and `CATALYST_XCODE_BUILD=17A400`
  (`Xcode_26.0.app` is 26.0.1). `build.sh` and the workflow refuse another build. Every pin is
  required: depot_tools no longer falls back to HEAD.
- `BUILD-RECORD` adds:
  - `COMMIT`, the pipeline commit;
  - `WEBRTC_PATCH_SHA256` and the two Xcode build pins;
  - the upstream file hashes checked before each patch;
  - the resolved dependency set (`gclient revinfo --actual`, also the `RESOLVED` asset) and its
    sha256.
- The release job now waits for the comparison and checks the record against `PINS` and both
  patches at the tag (`COMMIT` equal to the tag's commit). Its notes then carry `COMPARE` (the
  verdict and both builds' hashes) beside every asset's sha256. The comparison is recorded, not
  a gate (D82 3.5).
- The workflow still runs on pull requests that touch the pipeline. That run is the build
  evidence and D82 3.5's measurement, and honeycomb-ios D82 now says so.

## What this PR's CI shows

- **`source-patch` (minutes, Linux):** the patch applies to `a545de4` with every hash as listed,
  and the replay guard passes the vectors.
- **The two macOS builds (about two hours each, as `build-2`):** the patched WebRTC compiles
  with upstream's warnings-as-errors. The checks still pass, and both records carry `COMMIT` and
  `RESOLVED`.
- **`compare`:** the two builds' verdict.

## Then, in order (a person pushes the tags; agent sessions can't)

1. Merge this PR, then tag `build-3` at the merge commit on `main` (as `build-2`). The release
   job refuses unless the record's `COMMIT` is that commit.
   ```sh
   git fetch origin main
   git tag -a build-3 -m "LiveKitWebRTC build-3: frame replay check and audio-level strip (SEC PR-01, WEBRTC-01)" origin/main
   git push origin build-3
   ```
2. **The package:** I open a PR on a branch off `agent/ui-ux/webrtc-package-catalyst`.
   `Package.swift` points at `build-3` with the zip's sha256 from the release notes. You tag it
   `150.7871.4-hc.3`.
3. **The fork** (`NGS-Labs-LLC/client-sdk-swift`, its own draft PR) pins `150.7871.4-hc.3`
   exactly, and the shared-key initialiser builds 256-bit providers too (WEBRTC-08). You tag it
   `2.18.0-hc.3`.
4. **honeycomb-ios** pins `2.18.0-hc.3`, commits `Package.resolved`, and resolves only from it
   in CI (WEBRTC-02).
5. **Tag rulesets** on both public repositories, for `build-*`, `150.*` and `2.18.*`.
