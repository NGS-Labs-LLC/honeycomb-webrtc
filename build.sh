#!/bin/bash
# Builds LiveKitWebRTC.xcframework (prefixed LKRTC classes, iOS arm64 device, iOS simulator and Mac
# Catalyst for arm64 and x86_64) from the inputs in PINS (honeycomb-ios D82, docs/design/AES-256-FRAMES.md). It
# refuses when a pin is empty, when an Xcode build differs from its pin, when an upstream file
# differs from patches/UPSTREAM.sha256 or WEBRTC-UPSTREAM.sha256, or when a patch does not apply
# cleanly, as honeycomb-sfu's scripts/patched-livekit.sh does, and writes the zip, BUILD-RECORD and
# RESOLVED (gclient revinfo) to $OUT (default out/). Runs on macOS with Xcode selected; takes hours
# and tens of GB of disk.
set -euo pipefail
cd "$(dirname "$0")"
here=$PWD
out=${OUT:-$here/out}
work=${WORK:-$here/work}
# shellcheck disable=SC1091
. ./PINS
if command -v sha256sum >/dev/null 2>&1; then sha256="sha256sum"; else sha256="shasum -a 256"; fi
patchfile=patches/webrtc-build-m150.7871.04.patch
webrtc_patchfile=patches/webrtc-a545de4.patch
say() { echo "build.sh: $*"; }
fail() { echo "build.sh: $*" >&2; exit 1; }

for pin in WEBRTC_REPO WEBRTC_COMMIT WEBRTC_BUILD_REPO WEBRTC_BUILD_COMMIT DEPOT_TOOLS_REPO \
	DEPOT_TOOLS_COMMIT XCODE_VERSION XCODE_BUILD CATALYST_XCODE_VERSION CATALYST_XCODE_BUILD; do
	[ -n "${!pin:-}" ] || fail "PINS has no $pin"
done
# The pipeline commit this build ran from; a build from a tree with local changes says so.
commit=$(git -C "$here" rev-parse HEAD 2>/dev/null) || fail "not a git checkout: the record needs the pipeline commit"
if [ -n "$(git -C "$here" status --porcelain --untracked-files=no)" ]; then commit="$commit (with local changes)"; fi
# Xcode by build number: `xcodebuild -version` ends "Build version <build>".
xcode_build() { DEVELOPER_DIR=$1 xcodebuild -version | sed -n 's/^Build version //p'; }
selected=$(xcode-select -p)
[ "$(xcode_build "$selected")" = "$XCODE_BUILD" ] || fail "Xcode at $selected is build $(xcode_build "$selected"), PINS says $XCODE_BUILD"

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
git -C "$src/depot_tools" checkout -q "$DEPOT_TOOLS_COMMIT"
depot_tools_commit=$(git -C "$src/depot_tools" rev-parse HEAD)
[ "$depot_tools_commit" = "$DEPOT_TOOLS_COMMIT" ] || fail "depot_tools is not at $DEPOT_TOOLS_COMMIT"
say "depot_tools at $depot_tools_commit"
export DEPOT_TOOLS_UPDATE=0
# The Catalyst slice builds against upstream's Xcode (PINS); xcframework.sh reads this.
export CATALYST_DEVELOPER_DIR=/Applications/Xcode_${CATALYST_XCODE_VERSION}.app/Contents/Developer
[ -d "$CATALYST_DEVELOPER_DIR" ] || fail "no Xcode $CATALYST_XCODE_VERSION at $CATALYST_DEVELOPER_DIR for the Catalyst slice"
[ "$(xcode_build "$CATALYST_DEVELOPER_DIR")" = "$CATALYST_XCODE_BUILD" ] || fail "Xcode at $CATALYST_DEVELOPER_DIR is build $(xcode_build "$CATALYST_DEVELOPER_DIR"), PINS says $CATALYST_XCODE_BUILD"
say "Catalyst slice with $(DEVELOPER_DIR=$CATALYST_DEVELOPER_DIR xcodebuild -version | tr '\n' ' ')"
# With updates off, depot_tools never bootstraps its own Python (python3_bin_reldir.txt), which
# gn and ninja's wrappers need; ensure_bootstrap does that without moving the checkout.
(cd "$src/depot_tools" && ./ensure_bootstrap)
[ "$(git -C "$src/depot_tools" rev-parse HEAD)" = "$depot_tools_commit" ] || fail "depot_tools moved during bootstrap"
df -h "$work" | tail -1

# run.py runs this after upstream's apple_prefix.patch (the hook is in $patchfile): the WebRTC
# source patch, checked against WEBRTC-UPSTREAM.sha256 before and WEBRTC-PATCHED.sha256 after.
export HONEYCOMB_WEBRTC_PATCH_STEP=$here/patches/apply-webrtc-patch.sh

say "building WebRTC $WEBRTC_COMMIT"
start=$(date +%s)
(cd "$work/webrtc-build/build" && ./build.apple_prefixed.sh "$WEBRTC_COMMIT" release)
minutes=$(( ($(date +%s) - start) / 60 ))
df -h "$work" | tail -1

webrtc_src=$src/webrtc/src
[ "$(git -C "$webrtc_src" rev-parse HEAD)" = "$WEBRTC_COMMIT" ] || fail "WebRTC is not at $WEBRTC_COMMIT"
# The tree that was built carries the WebRTC patch, file for file.
while read -r sum path; do
	case "$sum" in ''|'#'*) continue ;; esac
	[ "$($sha256 "$webrtc_src/$path" | cut -d' ' -f1)" = "$sum" ] || fail "$path in the built tree is not the patched file"
done < patches/WEBRTC-PATCHED.sha256
say "the built tree carries $webrtc_patchfile"
# The resolved dependency set: every git dependency at the revision gclient checked out and every
# cipd package as DEPS names it, sorted.
(cd "$src/webrtc" && PATH="$src/depot_tools:$PATH" gclient revinfo --actual) | LC_ALL=C sort > "$out/RESOLVED" \
	|| fail "gclient revinfo failed"
[ -s "$out/RESOLVED" ] || fail "gclient revinfo listed nothing"
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
# The simulator slice and the Mac app's slice run on Apple silicon and on Intel (Paul's CI Mac).
archs() { lipo -archs "$1" | tr ' ' '\n' | LC_ALL=C sort | xargs; }
simulator=$xcf/ios-arm64_x86_64-simulator/LiveKitWebRTC.framework/LiveKitWebRTC
[ "$(archs "$simulator")" = "arm64 x86_64" ] || fail "the simulator slice is not x86_64 + arm64: $(lipo -archs "$simulator")"
say "ios-arm64_x86_64-simulator: arm64 x86_64"
# The Mac app's slice: a versioned bundle whose binary is built for Mac Catalyst.
catalyst=$xcf/ios-arm64_x86_64-maccatalyst/LiveKitWebRTC.framework
[ -L "$catalyst/LiveKitWebRTC" ] && [ -f "$catalyst/Versions/A/LiveKitWebRTC" ] || fail "$catalyst is not a versioned bundle"
build_info=$(xcrun vtool -show-build "$catalyst/Versions/A/LiveKitWebRTC") || fail "vtool could not read the Catalyst binary"
grep -q 'platform MACCATALYST' <<<"$build_info" || fail "the Catalyst slice is not built for Mac Catalyst"
grep -q 'minos 14.0' <<<"$build_info" || fail "the Catalyst slice's minimum is not 14.0"
[ "$(archs "$catalyst/Versions/A/LiveKitWebRTC")" = "arm64 x86_64" ] || fail "the Catalyst slice is not x86_64 + arm64: $(lipo -archs "$catalyst/Versions/A/LiveKitWebRTC")"
say "ios-arm64_x86_64-maccatalyst: a versioned bundle, platform MACCATALYST, arm64 x86_64"

cp "$zip" "$out/"
# Every file in the framework, so two builds can be compared file by file.
(cd "$pkg" && find LiveKitWebRTC.xcframework -type f | LC_ALL=C sort | while read -r f; do
	printf '%s  %s\n' "$($sha256 "$f" | cut -d' ' -f1)" "$f"
done) > "$out/MANIFEST.sha256"
{
	echo "# LiveKitWebRTC build record (honeycomb-ios D82). Written by build.sh."
	echo "COMMIT=$commit"
	echo "WEBRTC_COMMIT=$WEBRTC_COMMIT"
	echo "WEBRTC_BUILD_COMMIT=$WEBRTC_BUILD_COMMIT"
	echo "DEPOT_TOOLS_COMMIT=$depot_tools_commit"
	echo "PATCH_SHA256=$($sha256 "$patchfile" | cut -d' ' -f1)"
	echo "WEBRTC_PATCH_SHA256=$($sha256 "$webrtc_patchfile" | cut -d' ' -f1)"
	echo "RUNNER_IMAGE=${ImageOS:-?} ${ImageVersion:-?}"
	echo "XCODE=$(xcodebuild -version | tr '\n' ' ')"
	echo "XCODE_BUILD=$XCODE_BUILD"
	echo "CATALYST_XCODE_BUILD=$CATALYST_XCODE_BUILD"
	echo "CATALYST_XCODE=$(DEVELOPER_DIR=$CATALYST_DEVELOPER_DIR xcodebuild -version | tr '\n' ' ')"
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
	echo "RESOLVED_SHA256=$($sha256 "$out/RESOLVED" | cut -d' ' -f1)  # RESOLVED: gclient revinfo --actual"
	echo "# Upstream files checked before patching (patches/UPSTREAM.sha256, WEBRTC-UPSTREAM.sha256):"
	grep -hv '^#' patches/UPSTREAM.sha256 patches/WEBRTC-UPSTREAM.sha256 | sed 's/^/#   /'
	echo "# Resolved dependencies (RESOLVED, gclient revinfo --actual):"
	sed 's/^/#   /' "$out/RESOLVED"
	echo "# GN arguments (iOS-arm64-device):"
	sed 's/^/#   /' "$pkg/iOS-arm64-device/args.gn"
} > "$out/BUILD-RECORD"
cat "$out/BUILD-RECORD"
