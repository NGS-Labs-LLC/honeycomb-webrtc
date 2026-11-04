# Release `build-4`: no replay reset while the key lives, and the decrypted key index

`build-3`'s slices, GN arguments, Xcode and pipeline, with `patches/webrtc-a545de4.patch`
changed in two ways (honeycomb-security PR #10's follow-ups; Paul, 2026-11-04). The WebRTC
commit, the webrtc-build tag and every pin in `PINS` are unchanged.

## 1. The replay check never resets while the key lives (hive-node #71, D-086)

**Why.** `build-3`'s guard reset an `ssrc`'s state after 2 s in which every frame was
window-behind, so that a sender whose own clock jumped back wouldn't go silent. That reset was
argued safe because "only a key holder can cause this". That's wrong: the SFU needs no key. It
withholds an `ssrc`'s live frames and sends that `ssrc`'s old frames instead. They decrypt and
every one is window-behind, so after 2 s the reset restarts the stream at an old timestamp, and
the SFU can replay the rest. Eviction was a reset too. Past 16 `ssrc`s the oldest was replaced,
and a replaced one coming back started fresh, so an SFU ordering frames could choose what to
evict and then replay it whole.

**What changed** (`api/crypto/frame_replay_guard.h`, hive-node wire-protocol.md §6.6 "Replay"
at `7375f82`):
- **No reset on time.** `kResetAfterMs` and the window-behind run are gone, and so is the clock
  argument: `Accept(iv, window_ticks)`. A frame more than the window behind is refused however
  long the run lasts.
- **Evicted `ssrc`s are retired.** A new `ssrc` past the 16 live ones still replaces the one
  heard from longest ago. The replaced `ssrc` is then retired, and its frames are refused for the
  rest of the key's life, whatever their timestamp.
- **Retired bound:** at most 256 retired per key. Past that, a frame of any `ssrc` the guard
  doesn't hold is refused, and the live ones keep playing.
- **Only accepted frames count as heard.** A refused frame no longer refreshes its `ssrc`, so
  repeating an `ssrc`'s frames can't steer which live `ssrc` is evicted.
- **Unchanged:** the state lives on the key set and goes only with its key. A sender whose
  timestamp jumps back on one `ssrc` is heard again at the next key: the next one-to-one re-key
  (about 10 minutes, §6.8.1), or a group's next epoch.

## 2. The key index a played frame decrypted under (honeycomb-ios D156)

**Why.** honeycomb-ios re-keys one-to-one calls every 10 minutes (§6.8.1, D-079). The cryptor
reported state changes but never which `key_index` a frame decrypted under. So the app inferred
the switch from time and packet counts, and Paul accepted that as fail-closed on 2026-11-04. With
this item the app observes the switch, which is how §6.8.1 "Switching" words it.

**What changed:**
- **The C++ observer:** `FrameCryptorTransformerObserver::OnFrameDecryptedWithKeyIndex(participant_id,
  key_index)`. It has an empty default body, so LiveKit's observers are unchanged.
- **When `decryptFrame` posts it:** only for frames that decrypted *and* passed the replay
  check, with the trailer's `key_index`. It's posted for a receiver's first played frame, then
  only when the index changes (`DecryptedKeyIndexReport`), so it's never per frame. It goes to
  the signaling thread, like `OnFrameCryptionStateChanged`.
- **Objective-C:** `RTCFrameCryptorDelegate` gains `@optional`
  `frameCryptor:didDecryptFrameWithKeyIndex:participantId:`. The adapter forwards to it only
  when the delegate responds to it.
- **Unchanged:** encryption. The sender still chooses its index with `SetKeyIndex`.

## Tests, now inside the patch

- **New `api/crypto/frame_replay_guard_unittest.cc`,** added to WebRTC's `crypto_unittests`
  target. Ten gtest cases:
  - repeated IVs, and late frames inside the window;
  - the window edge, wrap-around and the IV length;
  - memory bounded to the window;
  - D-086: a window-behind run of 100 000 frames never reopens an `ssrc`, an evicted `ssrc` stays
    refused at any timestamp, and refused frames don't keep an `ssrc` fresh;
  - the 256 retired bound;
  - the key-index report (indexes 0 0 0 1 1 0 1 1 2 2 report 0 1 0 1 2).
- **Check against `build-3`:** the same cases, run against `build-3`'s guard through an adapter
  clock, fail the three D-086 cases and pass the other six.
- **`tests/frame_replay_guard_test.cc`** now runs only hive-node's `frame_replay` vectors, which
  live outside the WebRTC tree. `tests/frame_replay.vectors` is re-extracted at hive-node
  `7375f82`: the same 15 frames and 5 drops, with only the source hash changed (#71 edited a
  note).
- **The `source-patch` CI job** installs googletest and builds the patch's test file with a
  one-line `test/gtest.h` stand-in. It runs that file and the vectors.
- **The two macOS builds:** `build.sh` also checks that the built `RTCFrameCryptor.h` declares
  `didDecryptFrameWithKeyIndex:`.

## Hash lists

- **`WEBRTC-UPSTREAM.sha256`** adds the three Objective-C files (`RTCFrameCryptor.h`,
  `RTCFrameCryptor+Private.h` and `RTCFrameCryptor.mm`).
- **`WEBRTC-PATCHED.sha256`** has all ten files, the two new ones included.
- **`apply-webrtc-patch.sh`** also looks under `sdk/` for leftover `.rej` and `.orig` files.

## Then, in order (a person pushes the tags; agent sessions can't)

1. **Tag `build-4`.** Merge this PR, then tag `build-4` at the merge commit on `main`, as for
   `build-3`. The release job refuses unless the record's `COMMIT` is that commit.
   ```sh
   git fetch origin main
   git tag -a build-4 -m "LiveKitWebRTC build-4: no replay reset while the key lives, retired ssrcs, decrypted key index (D-086, D156)" origin/main
   git push origin build-4
   ```
2. **The package:** a PR on a branch off `agent/ui-ux/webrtc-package-hc3` points
   `Package.swift` at `build-4`, with the zip's sha256 from the release notes. Tag it
   `150.7871.4-hc.4` at that PR's head.
3. **The fork** (`NGS-Labs-LLC/client-sdk-swift`) pins `150.7871.4-hc.4` exactly. Tag it
   `2.18.0-hc.4`.
4. **honeycomb-ios** pins `2.18.0-hc.4`, commits the new `Package.resolved`, and replaces D156's
   two timing guesses with the report.

The tag rulesets from `build-3` already cover `build-*`, `150.*` and `2.18.*`.
