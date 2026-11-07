#!/usr/bin/env bash
# Compares two builds' outputs (each a directory holding out/BUILD-RECORD, out/MANIFEST.sha256 and
# out/RESOLVED) and writes the verdict to COMPARE. Exits 1 unless the builds are reproducible
# (SEC WEBRTC-03, D82 3.5): the release job needs this job, so a difference stops the release.
#
# Reproducible means:
#   - every slice's binary has the same sha256 (BINARY_SHA256[...]), and so does the key-provider
#     header (HEADER_SHA256[...]);
#   - the resolved dependency set (RESOLVED, gclient revinfo --actual) is the same, byte for byte;
#   - every other file in the framework has the same sha256 (MANIFEST.sha256), except the
#     Info.plist files.
# The Info.plist files are left out: Xcode writes the build machine's macOS build number into them
# (BuildMachineOSBuild), which differs between runner images though the binaries don't (build-4).
# The zip contains them, so its sha256 is recorded but not compared either.
#
# Usage: scripts/compare-builds.sh BUILD1_DIR BUILD2_DIR COMPARE_FILE
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: $0 BUILD1_DIR BUILD2_DIR COMPARE_FILE" >&2; exit 2; }
one=$1 two=$2 compare=$3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for i in 1 2; do
	dir=$one; [ "$i" = 2 ] && dir=$two
	for f in BUILD-RECORD MANIFEST.sha256 RESOLVED; do
		[ -s "$dir/out/$f" ] || { echo "build $i has no out/$f" >&2; exit 2; }
	done
	grep -E '^(BINARY_SHA256|HEADER_SHA256)\[' "$dir/out/BUILD-RECORD" > "$work/slices-$i" || true
	grep -E '^(ZIP_SHA256|MANIFEST_SHA256|RESOLVED_SHA256)=' "$dir/out/BUILD-RECORD" > "$work/recorded-$i" || true
	grep -v '/Info\.plist$' "$dir/out/MANIFEST.sha256" > "$work/files-$i" || true
	grep '/Info\.plist$' "$dir/out/MANIFEST.sha256" > "$work/plists-$i" || true
done

failures=()
[ -s "$work/slices-1" ] || failures+=("build 1 records no slice hashes")
[ -s "$work/slices-2" ] || failures+=("build 2 records no slice hashes")
cmp -s "$work/slices-1" "$work/slices-2" || failures+=("the slices or the header differ")
cmp -s "$one/out/RESOLVED" "$two/out/RESOLVED" || failures+=("the resolved dependency sets differ")
cmp -s "$work/files-1" "$work/files-2" || failures+=("files other than Info.plist differ")

if [ ${#failures[@]} -eq 0 ]; then
	verdict="REPRODUCIBLE: both builds have the same slices, header, resolved dependencies and files (Info.plist files excluded)"
else
	verdict="NOT REPRODUCIBLE: $(IFS=';'; echo "${failures[*]}" | sed 's/;/; /g')"
fi

{
	echo "$verdict"
	echo "RUN=${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-local}"
	echo "# Compared: BINARY_SHA256[...] and HEADER_SHA256[...], RESOLVED, MANIFEST.sha256 without the Info.plist files"
	for i in 1 2; do
		echo "# build $i"
		cat "$work/slices-$i" "$work/recorded-$i"
	done
	echo "# Slice and header lines that differ"
	diff "$work/slices-1" "$work/slices-2" || true
	echo "# RESOLVED lines that differ"
	diff "$one/out/RESOLVED" "$two/out/RESOLVED" || true
	echo "# MANIFEST.sha256 lines that differ, Info.plist files excluded"
	diff "$work/files-1" "$work/files-2" || true
	echo "# Info.plist files that differ (not compared)"
	diff "$work/plists-1" "$work/plists-2" || true
} > "$compare"

cat "$compare"
[ ${#failures[@]} -eq 0 ]
