#!/bin/sh
# Freeze the candidate digest from the same inventory used for the upload ZIP.

set -eu

pass() { printf '%s\n' "PASS: $*"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }

case "$#" in
  1)
    case "$1" in
      --check|--write) mode=$1 ;;
      -*) fail "unknown flag: $1" ;;
      *) fail "expected --check or --write" ;;
    esac
    ;;
  *) fail "expected --check or --write" ;;
esac

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
repo_dir=$(CDPATH= cd "$script_dir/.." && pwd) || exit 1
inventory=$script_dir/candidate_inventory.py
notes=$repo_dir/docs/release-notes-draft.md

[ -f "$inventory" ] || fail "missing candidate inventory tool"
[ -f "$notes" ] || fail "missing release notes: $notes"
digest=$(python3 "$inventory" inventory --repo "$repo_dir" --digest) || fail "could not calculate candidate digest"

case "$mode" in
  --check)
    recorded=$(python3 "$inventory" release-notes --notes "$notes" --check) || fail "release notes must record one valid digest"
    [ "$recorded" = "$digest" ] || fail "candidate digest does not match release notes"
    pass "candidate digest matches release notes"
    ;;
  --write)
    python3 "$inventory" release-notes --notes "$notes" --write "$digest" || fail "release notes must contain one valid digest"
    pass "recorded candidate digest"
    ;;
esac
