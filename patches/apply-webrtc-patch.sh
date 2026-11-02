#!/bin/bash
# Applies patches/webrtc-a545de4.patch to a WebRTC source tree (the argument: webrtc/src), as
# build/run.py's last patch step (the webrtc-build patch adds the hook; build.sh sets
# HONEYCOMB_WEBRTC_PATCH_STEP to this script). Refuses unless every file the patch touches
# matches WEBRTC-UPSTREAM.sha256 before, the files it adds do not exist yet, it applies without
# rejects, and every file matches WEBRTC-PATCHED.sha256 after. CI's source-patch job runs the
# same script on a sparse checkout of the pinned commit.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=${1:?usage: apply-webrtc-patch.sh <webrtc src dir>}
patchfile=$here/webrtc-a545de4.patch
if command -v sha256sum >/dev/null 2>&1; then sha256="sha256sum"; else sha256="shasum -a 256"; fi
say() { echo "build.sh: $*"; }
fail() { echo "build.sh: $*" >&2; exit 1; }

check() { # check <list> <phase>: every listed file has its sha256
	while read -r sum path; do
		case "$sum" in ''|'#'*) continue ;; esac
		[ -f "$src/$path" ] || fail "$2: no $path in $src"
		got=$($sha256 "$src/$path" | cut -d' ' -f1)
		[ "$got" = "$sum" ] || fail "$2: $path is $got, expected $sum; re-derive $(basename "$patchfile")"
	done < "$1"
}

check "$here/WEBRTC-UPSTREAM.sha256" "before the WebRTC patch"
while read -r sum path; do
	case "$sum" in ''|'#'*) continue ;; esac
	grep -q "  $path\$" "$here/WEBRTC-UPSTREAM.sha256" || [ ! -e "$src/$path" ] || fail "$path already exists before the WebRTC patch"
done < "$here/WEBRTC-PATCHED.sha256"
patch -p1 -N -s -d "$src" < "$patchfile" || fail "$(basename "$patchfile") does not apply"
[ -z "$(cd "$src" && find api media -name '*.rej' -o -name '*.orig')" ] || fail "$(basename "$patchfile") left .rej or .orig files"
check "$here/WEBRTC-PATCHED.sha256" "after the WebRTC patch"
say "WebRTC source patched: $(basename "$patchfile") (sha256 $($sha256 "$patchfile" | cut -d' ' -f1))"
