#!/bin/sh
# Freeze the installed Codex Advisor candidate without hashing release tooling.

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
notes=$repo_dir/docs/release-notes-draft.md

# Digest scope is only installed candidate content: the manifest, marketplace entry,
# skill definition and references, and agent profiles. It excludes .git, .logs,
# HISTORY.md, TASKS.md, verifications/, and public-release/ tooling because none is
# part of the installed candidate.
# Algorithm: SHA-256 every file, sort "relative-path sha256" lines bytewise, then
# SHA-256 that sorted listing. Paths are included so identical contents cannot move.
assert_candidate_scope() {
  [ -f "$repo_dir/.agents/plugins/marketplace.json" ] || fail "missing marketplace entry"
  [ -f "$repo_dir/plugins/advisor/.codex-plugin/plugin.json" ] || fail "missing plugin manifest"
  for directory in agents skills scripts; do
    [ -d "$repo_dir/plugins/advisor/$directory" ] || fail "missing candidate directory: $directory"
  done
  command -v shasum >/dev/null 2>&1 || fail "missing SHA-256 utility: shasum"
}

candidate_files() {
  printf '%s\n' \
    "$repo_dir/.agents/plugins/marketplace.json" \
    "$repo_dir/plugins/advisor/.codex-plugin/plugin.json"
  find "$repo_dir/plugins/advisor/agents" \
    "$repo_dir/plugins/advisor/skills" \
    "$repo_dir/plugins/advisor/scripts" -type f -print
}

candidate_digest() {
  candidate_files | LC_ALL=C sort -u | while IFS= read -r file; do
    relative_path=${file#"$repo_dir"/}
    file_digest=$(shasum -a 256 "$file" | awk '{print $1}') || exit 1
    printf '%s %s\n' "$relative_path" "$file_digest"
  done | LC_ALL=C sort | shasum -a 256 | awk '{print $1}'
}

recorded_digest() {
  awk '
    /[Cc]ontent [Dd]igest/ {
      if (match($0, /[0-9a-f]{64}/)) print substr($0, RSTART, RLENGTH)
    }
  ' "$notes"
}

assert_candidate_scope
digest=$(candidate_digest) || fail "could not calculate candidate digest"

case "$mode" in
  --check)
    recorded=$(recorded_digest)
    count=$(printf '%s\n' "$recorded" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    [ "$count" = 1 ] || fail "release notes must record one digest"
    [ "$recorded" = "$digest" ] || fail "candidate digest does not match release notes"
    pass "candidate digest matches release notes"
    ;;
  --write)
    [ -f "$notes" ] || fail "missing release notes: $notes"
    temp_file=$(mktemp "${TMPDIR:-/tmp}/advisor-freeze.XXXXXX") || fail "cannot create temporary file"
    cleanup() { rm -f "$temp_file"; }
    trap cleanup 0 HUP INT TERM
    awk -v digest="$digest" '
      /[Cc]ontent [Dd]igest/ && match($0, /[0-9a-f]{64}/) {
        sub(/[0-9a-f]{64}/, digest)
        found += 1
      }
      { print }
      END { if (found != 1) exit 1 }
    ' "$notes" >"$temp_file" || fail "release notes must contain one digest"
    mv "$temp_file" "$notes"
    pass "recorded candidate digest"
    ;;
esac
