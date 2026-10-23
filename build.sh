#!/bin/bash
# Builds LiveKitWebRTC.xcframework (prefixed LKRTC classes, iOS arm64 device and simulator) from
# the inputs in PINS (honeycomb-ios D82, docs/design/AES-256-FRAMES.md). It refuses when an upstream
# file differs from patches/UPSTREAM.sha256 or the patch does not apply cleanly, as honeycomb-sfu's
# scripts/patched-livekit.sh does, and writes the zip and BUILD-RECORD to $OUT (default
# out/). Runs on macOS with Xcode selected; takes hours and tens of GB of disk.
set -euo pipefail
cd "$(dirname "$0")"
here=$PWD
out=${OUT:-$here/out}
work=${WORK:-$here/work}
# shellcheck disable=SC1091
. ./PINS
if command -v sha256sum >/dev/null 2>&1; then sha256="sha256sum"; else sha256="shasum -a 256"; fi
patchfile=patches/webrtc-build-m150.7871.04.patch
say() { echo "build.sh: $*"; }
fail() { echo "build.sh: $*" >&2; exit 1; }

rm -rf "$work" "$out"
mkdir -p "$work" "$out"

say "webrtc-build at $WEBRTC_BUILD_COMMIT"
git init -q "$work/webrtc-build"
git -C "$work/webrtc-build" fetch -q --depth 1 "$WEBRTC_BUILD_REPO" "$WEBRTC_BUILD_COMMIT"
git -C "$work/webrtc-build" checkout -q FETCH_HEAD
[ "$(git -C "$work/webrtc-build" rev-parse HEAD)" = "$WEBRTC_BUILD_COMMIT" ] || fail "webrtc-build is not at $WEBRTC_BUILD_COMMIT"

while read -r sum path; do
	[ -n "$sum" ] || continue
	got=$($sha256 "$work/webrtc-build/$path" | cut -d' ' -f1)
	[ "$got" = "$sum" ] || fail "$path is $got, expected $sum; re-derive $patchfile for this webrtc-build"
done < patches/UPSTREAM.sha256
patch -p1 -N -s -d "$work/webrtc-build" < "$patchfile" || fail "$patchfile does not apply"
[ -z "$(find "$work/webrtc-build" -name '*.rej' -o -name '*.orig')" ] || fail "$patchfile left .rej or .orig files"

# run.py clones depot_tools at its HEAD unless the directory exists; put the pinned one there and
# keep it from updating itself.
src=$work/webrtc-build/build/_source/apple_prefixed
mkdir -p "$src"
git clone -q "$DEPOT_TOOLS_REPO" "$src/depot_tools"
if [ -n "$DEPOT_TOOLS_COMMIT" ]; then
	git -C "$src/depot_tools" checkout -q "$DEPOT_TOOLS_COMMIT"
else
	say "no DEPOT_TOOLS_COMMIT pinned yet: using HEAD and recording it"
fi
depot_tools_commit=$(git -C "$src/depot_tools" rev-parse HEAD)
say "depot_tools at $depot_tools_commit"
export DEPOT_TOOLS_UPDATE=0
# With updates off, depot_tools never bootstraps its own Python (python3_bin_reldir.txt), which
# gn and ninja's wrappers need; ensure_bootstrap does that without moving the checkout.
(cd "$src/depot_tools" && ./ensure_bootstrap)
[ "$(git -C "$src/depot_tools" rev-parse HEAD)" = "$depot_tools_commit" ] || fail "depot_tools moved during bootstrap"
df -h "$work" | tail -1

say "building WebRTC $WEBRTC_COMMIT"
start=$(date +%s)
(cd "$work/webrtc-build/build" && ./build.apple_prefixed.sh "$WEBRTC_COMMIT" release)
minutes=$(( ($(date +%s) - start) / 60 ))
df -h "$work" | tail -1

webrtc_src=$src/webrtc/src
[ "$(git -C "$webrtc_src" rev-parse HEAD)" = "$WEBRTC_COMMIT" ] || fail "WebRTC is not at $WEBRTC_COMMIT"
pkg=$work/webrtc-build/build/_package/apple_prefixed
zip=$pkg/LiveKitWebRTC.xcframework.zip
xcf=$pkg/LiveKitWebRTC.xcframework
[ -f "$zip" ] || fail "no $zip"

# What the app relies on: the 256-bit key provider, exported, and every class prefixed.
header=$(find "$xcf/ios-arm64/LiveKitWebRTC.framework/Headers" -name RTCFrameCryptorKeyProvider.h)
grep -q "keySize:(int)keySize" "$header" || fail "RTCFrameCryptorKeyProvider.h has no keySize"
# The symbol list is read in full before matching: grep -q stopping early would break nm's pipe,
# and with pipefail that reads as a missing symbol.
for bin in "$xcf"/*/LiveKitWebRTC.framework/LiveKitWebRTC; do
	symbols=$(nm -gU "$bin") || fail "nm could not read $bin"
	grep -q '_OBJC_CLASS_\$_LKRTCFrameCryptorKeyProvider$' <<<"$symbols" || fail "$bin does not export LKRTCFrameCryptorKeyProvider"
	if grep -q '_OBJC_CLASS_\$_RTC' <<<"$symbols"; then fail "$bin exports unprefixed RTC classes"; fi
	say "$(basename "$(dirname "$(dirname "$bin")")"): LKRTCFrameCryptorKeyProvider exported, $(grep -c '_OBJC_CLASS_\$_LKRTC' <<<"$symbols") LKRTC classes, no RTC classes"
done

cp "$zip" "$out/"
# Every file in the framework, so two builds can be compared file by file.
(cd "$pkg" && find LiveKitWebRTC.xcframework -type f | LC_ALL=C sort | while read -r f; do
	printf '%s  %s\n' "$($sha256 "$f" | cut -d' ' -f1)" "$f"
done) > "$out/MANIFEST.sha256"
{
	echo "# LiveKitWebRTC build record (honeycomb-ios D82). Written by build.sh."
	echo "WEBRTC_COMMIT=$WEBRTC_COMMIT"
	echo "WEBRTC_BUILD_COMMIT=$WEBRTC_BUILD_COMMIT"
	echo "DEPOT_TOOLS_COMMIT=$depot_tools_commit"
	echo "PATCH_SHA256=$($sha256 "$patchfile" | cut -d' ' -f1)"
	echo "RUNNER_IMAGE=${ImageOS:-?} ${ImageVersion:-?}"
	echo "XCODE=$(xcodebuild -version | tr '\n' ' ')"
	echo "BUILD_MINUTES=$minutes"
	echo "RUN=${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-local}"
	echo "ZIP_SHA256=$($sha256 "$zip" | cut -d' ' -f1)"
	echo "ZIP_BYTES=$(wc -c < "$zip" | tr -d ' ')"
	for bin in "$xcf"/*/LiveKitWebRTC.framework/LiveKitWebRTC; do
		slice=$(basename "$(dirname "$(dirname "$bin")")")
		echo "BINARY_SHA256[$slice]=$($sha256 "$bin" | cut -d' ' -f1)"
	done
	echo "HEADER_SHA256[RTCFrameCryptorKeyProvider.h]=$($sha256 "$header" | cut -d' ' -f1)"
	echo "MANIFEST_SHA256=$($sha256 "$out/MANIFEST.sha256" | cut -d' ' -f1)  # MANIFEST.sha256: every file in the framework"
	echo "# GN arguments (iOS-arm64-device):"
	sed 's/^/#   /' "$pkg/iOS-arm64-device/args.gn"
} > "$out/BUILD-RECORD"
cat "$out/BUILD-RECORD"
