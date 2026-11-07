#!/usr/bin/env bash
# scripts/compare-builds.sh (SEC WEBRTC-03): passes identical builds and builds that differ only in
# their Info.plist files (and so their zips), fails any other difference. Runs on Linux in seconds.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
compare="$here/scripts/compare-builds.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0

# A build's out/: a record, a manifest with three Info.plist files, and a resolved set.
make_build() {
	local dir=$1 zip=$2 plist=$3 slice=$4 header=$5 resolved=$6 file=$7
	mkdir -p "$dir/out"
	cat > "$dir/out/BUILD-RECORD" <<RECORD
COMMIT=abc
ZIP_SHA256=$zip
BINARY_SHA256[ios-arm64]=$slice
BINARY_SHA256[ios-arm64_x86_64-simulator]=bbbb
BINARY_SHA256[ios-arm64_x86_64-maccatalyst]=cccc
HEADER_SHA256[RTCFrameCryptorKeyProvider.h]=$header
MANIFEST_SHA256=whatever
RESOLVED_SHA256=whatever
RECORD
	cat > "$dir/out/MANIFEST.sha256" <<MANIFEST
$plist  LiveKitWebRTC.xcframework/Info.plist
$slice  LiveKitWebRTC.xcframework/ios-arm64/LiveKitWebRTC.framework/LiveKitWebRTC
$plist  LiveKitWebRTC.xcframework/ios-arm64/LiveKitWebRTC.framework/Info.plist
$file  LiveKitWebRTC.xcframework/ios-arm64/LiveKitWebRTC.framework/Modules/module.modulemap
$plist  LiveKitWebRTC.xcframework/ios-arm64_x86_64-maccatalyst/LiveKitWebRTC.framework/Versions/A/Resources/Info.plist
MANIFEST
	printf 'src: https://webrtc.googlesource.com/src@%s\nsrc/third_party/boringssl: x@1\n' "$resolved" > "$dir/out/RESOLVED"
}

expect() {
	local want=$1 name=$2; shift 2
	local got=0
	"$compare" "$work/$name-1" "$work/$name-2" "$work/$name.COMPARE" > /dev/null 2>&1 || got=$?
	if [ "$want" = pass ] && [ "$got" -ne 0 ]; then echo "FAIL $name: expected reproducible, exit $got"; cat "$work/$name.COMPARE"; exit 1; fi
	if [ "$want" = fail ] && [ "$got" -ne 1 ]; then echo "FAIL $name: expected not reproducible, exit $got"; exit 1; fi
	for text in "$@"; do
		grep -qF "$text" "$work/$name.COMPARE" || { echo "FAIL $name: COMPARE lacks: $text"; cat "$work/$name.COMPARE"; exit 1; }
	done
	echo "ok   $name"
	pass=$((pass + 1))
}

make_build "$work/same-1" z1 p1 s1 h1 r1 f1; make_build "$work/same-2" z1 p1 s1 h1 r1 f1
expect pass same "REPRODUCIBLE: both builds"

# build-4's case: the Info.plist files (BuildMachineOSBuild) and so the zip differ, nothing else.
make_build "$work/plist-1" z1 p1 s1 h1 r1 f1; make_build "$work/plist-2" z2 p2 s1 h1 r1 f1
expect pass plist "REPRODUCIBLE" "# Info.plist files that differ (not compared)" "ZIP_SHA256=z2"

make_build "$work/slice-1" z1 p1 s1 h1 r1 f1; make_build "$work/slice-2" z1 p1 s2 h1 r1 f1
expect fail slice "NOT REPRODUCIBLE: the slices or the header differ; files other than Info.plist differ" "BINARY_SHA256[ios-arm64]=s2"

make_build "$work/header-1" z1 p1 s1 h1 r1 f1; make_build "$work/header-2" z1 p1 s1 h2 r1 f1
expect fail header "NOT REPRODUCIBLE: the slices or the header differ"

make_build "$work/resolved-1" z1 p1 s1 h1 r1 f1; make_build "$work/resolved-2" z1 p1 s1 h1 r2 f1
expect fail resolved "NOT REPRODUCIBLE: the resolved dependency sets differ" "src@r2"

make_build "$work/file-1" z1 p1 s1 h1 r1 f1; make_build "$work/file-2" z1 p1 s1 h1 r1 f2
expect fail file "NOT REPRODUCIBLE: files other than Info.plist differ" "module.modulemap"

# A build whose record names no slices can't pass, even against another like it.
make_build "$work/empty-1" z1 p1 s1 h1 r1 f1; make_build "$work/empty-2" z1 p1 s1 h1 r1 f1
sed -i.bak '/^BINARY_SHA256\|^HEADER_SHA256/d' "$work/empty-1/out/BUILD-RECORD" "$work/empty-2/out/BUILD-RECORD"
expect fail empty "build 1 records no slice hashes"

# A missing file is a usage error (2), not a verdict.
make_build "$work/missing-1" z1 p1 s1 h1 r1 f1; mkdir -p "$work/missing-2/out"
code=0; "$compare" "$work/missing-1" "$work/missing-2" "$work/missing.COMPARE" > /dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] || { echo "FAIL missing: expected exit 2, got $code"; exit 1; }
echo "ok   missing"; pass=$((pass + 1))

echo "$pass passed"
