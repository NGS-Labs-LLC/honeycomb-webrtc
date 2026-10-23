# Release `build-1`

The first release of `LiveKitWebRTC.xcframework` from this repository (honeycomb-ios D82). It is
made by pushing the tag `build-1` at this PR's head. The tag runs `.github/workflows/build.yml`:
two builds on fresh `macos-26` runners, the comparison, and then `gh release create`. Nothing
else in this PR changes the pipeline, so opening it starts no build.

## What it costs

From run [39972294655](https://github.com/NGS-Labs-LLC/honeycomb-webrtc/actions/runs/39972294655)
on the same pins (PR #1's head `203b87d`):

| Job | Runner | Minutes |
|---|---|---|
| LiveKitWebRTC, build 1 | `macos-26` | 67 |
| LiveKitWebRTC, build 2 | `macos-26` | 60 |
| Compare the two builds | `ubuntu-latest` | < 1 |
| Publish the release | `ubuntu-latest` | about 1 (uploads about 60 MB) |

- **Total:** about 128 macOS runner-minutes and 2 Ubuntu minutes, about 70 minutes from push to
  release (the two macOS builds run in parallel).
- **Billing:** this repository is public, so standard runners are free. GitHub reported 0
  billable ms for that run.
- **Limit:** each job stops at 360 minutes.

## Pushing the tag

Agent sessions can push branches but not tags (HTTP 403), so a person pushes it:

```sh
git fetch origin agent/ui-ux/webrtc-build-1
git tag -a build-1 -m "LiveKitWebRTC build-1 (D82)" FETCH_HEAD
git push origin build-1
```

The tag doesn't need a merge. The workflow runs from the tagged commit, and the tag keeps that
commit even if the branch goes.

## What the release must show

The builds were byte-identical on PR #1 (`REPRODUCIBLE`), so this release must reproduce them:

| Asset | sha256 |
|---|---|
| `LiveKitWebRTC.xcframework.zip` | `660396f289a4bb73588b15bc976aacecbb2ef425ae2f17bfe24c80603eefc5b6` |

Check the published release before anything uses it:

```sh
gh release download build-1 --repo NGS-Labs-LLC/honeycomb-webrtc --dir /tmp/build-1
shasum -a 256 /tmp/build-1/*        # the zip must equal the value above and the release notes
```

- **Also check:** the run's "Compare the two builds" summary says `REPRODUCIBLE`.
- **If the zip differs:** PR #2's `Package.swift` checksum is wrong. Don't tag
  `150.7871.4-hc.1`; the agent pushes a new checksum to #2 first.

## Then, in order

1. **PR #2:** tag `150.7871.4-hc.1` at its head. That is the SwiftPM version client-sdk-swift
   pins.
   ```sh
   git fetch origin agent/ui-ux/webrtc-package
   git tag -a 150.7871.4-hc.1 -m "honeycomb-webrtc 150.7871.4-hc.1: LiveKitWebRTC build-1" FETCH_HEAD
   git push origin 150.7871.4-hc.1
   ```
2. **The fork:** push `2.18.0-hc.1` at `NGS-Labs-LLC/client-sdk-swift`
   `agent/ui-ux/livekit-keysize` head `ed19584d`. That fork tag doesn't start the fork's CI,
   which runs only on pull requests to `main` and on published releases.
   ```sh
   git fetch origin agent/ui-ux/livekit-keysize
   git tag -a 2.18.0-hc.1 -m "LiveKit Swift SDK 2.18.0 for Honeycomb (D82)" ed19584d2142b621fe029d45608fcc80082e7b9e
   git push origin 2.18.0-hc.1
   ```
3. **honeycomb-ios:** the G3b PR's CI resolves both. It fails until all three tags exist.
