#!/bin/sh
# Build a deterministic local Advisor candidate archive. This does not approve upload.

set -eu

fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }

json=0
case "$#" in
  1) archive=$1 ;;
  2)
    [ "$1" = "--json" ] || fail "usage: package-candidate.sh [--json] ARCHIVE.zip"
    json=1
    archive=$2
    ;;
  *) fail "usage: package-candidate.sh [--json] ARCHIVE.zip" ;;
esac

case "$archive" in
  -*) fail "archive path must not begin with -" ;;
esac

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
repo_dir=$(CDPATH= cd "$script_dir/.." && pwd) || exit 1
inventory=$script_dir/candidate_inventory.py
[ -f "$inventory" ] || fail "missing candidate inventory tool"

printf '%s\n' "LOCAL CANDIDATE ONLY: run public-release/verify-upload-ready.sh [--json] ARCHIVE.zip immediately before owner upload." >&2

if [ "$json" = 1 ]; then
  exec python3 "$inventory" package --repo "$repo_dir" --output "$archive" --json
fi
exec python3 "$inventory" package --repo "$repo_dir" --output "$archive"
