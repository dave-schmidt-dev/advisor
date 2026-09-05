#!/bin/sh
# Verify one existing candidate ZIP immediately before its marketplace upload.

set -eu

fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }

json=0
case "$#" in
  1) archive=$1 ;;
  2)
    [ "$1" = "--json" ] || fail "usage: verify-upload-ready.sh [--json] ARCHIVE.zip"
    json=1
    archive=$2
    ;;
  *) fail "usage: verify-upload-ready.sh [--json] ARCHIVE.zip" ;;
esac
case "$archive" in -*) fail "archive path must not begin with -" ;; esac

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
[ -f "$script_dir/upload_readiness.py" ] || fail "missing upload readiness tool"

if [ "$json" = 1 ]; then
  exec python3 "$script_dir/upload_readiness.py" --json "$archive"
fi
exec python3 "$script_dir/upload_readiness.py" "$archive"
