# Release `build-4`: planned

This is a list, not a release. Nothing on it is built yet. Each item says what changes in WebRTC,
why, how it is checked, and what the consumers do with it. The pipeline, pins and release steps
stay as in `build-3` (`releases/build-3.md`). When the list is complete, its items are added to
`patches/webrtc-a545de4.patch` (or a successor) and this file becomes the release notes.

## 1. Report the key index a frame decrypted under (honeycomb-ios D156; Paul, 2026-11-04)

**Why.**
- honeycomb-ios re-keys one-to-one calls every 10 minutes (hive-node wire-protocol.md §6.6 and
  §6.8.1, D-079; SEC PR-05). The callee answers with `key_index` + 1 and fresh keys, and each
  side then drops its old keys 30 s after its first frame under the new ones.
- The cryptor reports only state changes (`FrameCryptionState`), never which `key_index` a frame
  decrypted under. So honeycomb-ios infers the switch from time and packet counts:
  - the callee switches 10 s after its re-answer, at the next frame from the caller;
  - the caller takes the first frame 15 s after installing the new keys as the callee's first
    frame under them.
- Paul accepted that inference on 2026-11-04 because it fails closed: if every re-answer is lost
  while the caller's offers still arrive, the call ends, and nothing is ever played in the clear.
  This item makes the switch observed rather than inferred.

**What changes in WebRTC** (`api/crypto/frame_crypto_transformer.h` and `.cc`, and the
Objective-C wrapper in `sdk/objc/api/peerconnection/RTCFrameCryptor*`):
- **The C++ observer:** `FrameCryptorTransformerObserver` gains
  `virtual void OnFrameDecryptedWithKeyIndex(const std::string participant_id, int key_index) {}`.
  It has an empty default body, so observers that don't implement it, LiveKit's included, are
  unchanged.
- **When `decryptFrame` calls it:**
  - only after a frame has decrypted and passed the replay check (`build-3`'s
    `FrameReplayGuard`), so a frame that isn't played never reports;
  - with the `key_index` read from the frame trailer, which is the index whose key set decrypted
    it (after a ratchet, that index too);
  - once per change: the transformer keeps the last index it reported (initially none) and calls
    the observer only when a played frame's index differs. That's one call when the first frame
    arrives and one per switch, never per frame.
- **Threading:** the call is posted the way `onFrameCryptionStateChanged` posts state changes,
  never on the decode path.
- **The Objective-C wrapper:** `RTCFrameCryptorDelegate` gains an optional
  `frameCryptor:didDecryptFrameWithKeyIndex:participantId:` (an `@optional` method, so existing
  delegates still compile). `RTCFrameCryptor`'s observer adapter forwards the C++ call to it on
  the same queue as `didStateChangeWithParticipantId:withState:`.
- **Encryption is unchanged:** the sender already chooses its index (`key_index_`, set by
  `SetKeyIndex`), so nothing new is reported for it.

**How it is checked.**
- **A unit test beside `tests/frame_replay_guard_test.cc`:** a transformer with a test observer
  decrypts frames under index 0, then 1, then 0 again (a late frame), then 1. Expected: the
  reports are 0, 1, 0, 1. A frame that fails to decrypt reports nothing, and neither does a
  replayed frame the guard refuses. The `source-patch` CI job runs it on the patched upstream
  files, as it does the replay vectors.
- **The two macOS builds:** as in `build-3`, they show that the patched tree compiles with
  upstream's warnings-as-errors and that the hash lists hold.
- **Hashes:** `WEBRTC-UPSTREAM.sha256` and `WEBRTC-PATCHED.sha256` gain the Objective-C files the
  patch touches.

**What the consumers do.**
- **honeycomb-ios:** `WebRTCMediaEngine` forwards the report, and `HiveCallService` replaces both
  inferences with it:
  - **The callee** switches its sending index when the caller's first frame under the new index
    is reported. It no longer waits for 10 s after its re-answer.
  - **The caller** starts the 30 s old-key timer when the callee's first frame under the new
    index is reported. It no longer uses install + 15 s.
  - **If no report comes:** the re-key is given up, as an unanswered one is today. Old keys stay
    until a report arrives, so the lost re-answer case keeps the call instead of ending it.
  - D156 and `CallRekeyVectorTests` change to match, and the two-phone step in
    `docs/TESTNET-TWO-PHONE.md` (C4 P10-1) is run again on this build.
- **The fork (`client-sdk-swift`):** it pins `150.7871.4-hc.4` exactly, and nothing else changes,
  since LiveKit doesn't implement the new method.
- **The package:** `150.7871.4-hc.4` at `build-4`'s zip and sha256, as `hc.3` was.

**The spec already says this** (hive-node wire-protocol.md §6.8.1, "Switching"):
- the callee sends with the new key "once a frame from the caller under `k` decrypts";
- each side keeps the old receive key "until 30 s after the first frame it **received** under
  the new one".

This item lets honeycomb-ios implement that wording as written. The wire format doesn't change.
