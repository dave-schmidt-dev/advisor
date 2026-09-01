#!/bin/sh
# Verify the clean-host receipt contract without fabricating attended evidence.

set -eu

pass() { printf '%s\n' "PASS: $*"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }

case "$#" in
  1)
    case "$1" in
      --synthetic) mode=$1 ;;
      -*) fail "unknown flag: $1" ;;
      *) fail "expected --synthetic or --capture RECEIPT RUNTIME_EVIDENCE" ;;
    esac
    ;;
  3)
    case "$1" in
      --capture) mode=$1; receipt_path=$2; evidence_path=$3 ;;
      -*) fail "unknown flag: $1" ;;
      *) fail "expected --synthetic or --capture RECEIPT RUNTIME_EVIDENCE" ;;
    esac
    ;;
  *) fail "expected --synthetic or --capture RECEIPT RUNTIME_EVIDENCE" ;;
esac

command -v jq >/dev/null 2>&1 || fail "jq is required"

# Write only observed, allowlisted runtime fields. The input may be the direct
# inspector output or the wrapper result that contains it under .runtime.
generate_receipt() {
  evidence=$1
  output=$2
  jq -ce '
    if (.runtime? | type) == "object" then .runtime else . end |
    {
      thread_id: .thread_id,
      parent_thread_id: .parent_thread_id,
      agent_role: .agent_role,
      transport: .transport,
      model: .model,
      effort: .effort,
      sandbox_policy_type: .sandbox_policy_type,
      permission_profile_type: .permission_profile_type
    } |
    if all(
      .[];
      type == "string" and length > 0 and (contains("/") | not)
    ) then . else error("runtime evidence is incomplete or unsafe") end
  ' "$evidence" >"$output" || return 1
}

receipt_matches_contract() {
  jq -e '.transport=="codex-exec" and .model and .effort=="high" and .sandbox_policy_type=="read-only"' "$1" >/dev/null
}

synthetic() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/advisor-clean-host.XXXXXX") || fail "cannot create temporary directory"
  cleanup() { rm -rf "$tmp"; }
  trap cleanup 0 HUP INT TERM

  observed=$tmp/observed-runtime.json
  receipt=$tmp/receipt.json
  mutated=$tmp/mutated-receipt.json
  jq -n \
    --arg thread_id '11111111-1111-1111-1111-111111111111' \
    --arg parent_thread_id '22222222-2222-2222-2222-222222222222' \
    --arg agent_role 'advisor-terra' \
    --arg transport 'codex-exec' \
    --arg model 'gpt-5.6-terra' \
    --arg effort 'high' \
    --arg sandbox_policy_type 'read-only' \
    --arg permission_profile_type 'managed' \
    '{thread_id:$thread_id,parent_thread_id:$parent_thread_id,agent_role:$agent_role,transport:$transport,model:$model,effort:$effort,sandbox_policy_type:$sandbox_policy_type,permission_profile_type:$permission_profile_type}' \
    >"$observed" || fail "cannot create synthetic runtime evidence"

  generate_receipt "$observed" "$receipt" || fail "cannot generate synthetic receipt"
  receipt_matches_contract "$receipt" || fail "synthetic receipt does not satisfy the parent predicate"

  jq '.sandbox_policy_type = "workspace-write"' "$receipt" >"$mutated" || fail "cannot mutate synthetic receipt"
  if receipt_matches_contract "$mutated"; then
    fail "predicate accepted a receipt with a non-read-only sandbox"
  fi
  pass "synthetic clean-host receipt contract and negative control"
}

capture() {
  [ -f "$evidence_path" ] || fail "runtime evidence does not exist: $evidence_path"
  receipt_dir=$(dirname "$receipt_path")
  [ -d "$receipt_dir" ] || fail "receipt directory does not exist: $receipt_dir"
  temporary_receipt=$(mktemp "$receipt_dir/.advisor-clean-host-receipt.XXXXXX") || fail "cannot create receipt temporary file"

  if ! generate_receipt "$evidence_path" "$temporary_receipt"; then
    rm -f "$temporary_receipt"
    fail "runtime evidence does not contain a complete observed receipt"
  fi
  # Check before publishing. Publishing first and failing afterwards would leave a
  # non-conforming receipt sitting at the path reserved for attended evidence.
  if ! receipt_matches_contract "$temporary_receipt"; then
    rm -f "$temporary_receipt"
    fail "observed runtime does not satisfy the parent predicate; no receipt written"
  fi
  mv "$temporary_receipt" "$receipt_path" || fail "cannot write receipt: $receipt_path"
  pass "captured clean-host receipt: $receipt_path"
}

case "$mode" in
  --synthetic) synthetic ;;
  --capture) capture ;;
esac
