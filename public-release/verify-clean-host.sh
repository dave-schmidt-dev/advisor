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
  (if (.runtime? | type) == "object" then .runtime else . end) as $runtime |
    if (($runtime.thread_id | type) != "string" or ($runtime.thread_id | length) == 0) then error("thread id missing") else . end |
    if (($runtime.parent_thread_id | type) != "string" or ($runtime.parent_thread_id | length) == 0) then error("parent thread id missing") else . end |
    if (($runtime.thread_id | test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") | not)) then error("thread id must be a lowercase UUID") else . end |
    if (($runtime.parent_thread_id | test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") | not)) then error("parent thread id must be a lowercase UUID") else . end |
    if ($runtime.thread_id == $runtime.parent_thread_id) then error("thread ids must differ") else . end |
    if ($runtime.transport != "codex-exec") then error("transport mismatch") else . end |
    if ($runtime.effort != "high") then error("effort mismatch") else . end |
    if ($runtime.sandbox_policy_type != "read-only") then error("sandbox mismatch") else . end |
    if (($runtime.permission_profile_type | type) != "string" or ($runtime.permission_profile_type | length) == 0) then error("permission profile missing") else . end |
    if ($runtime.permission_profile_type != "managed") then error("permission profile mismatch") else . end |
    if (($runtime.agent_role == "advisor-terra" and $runtime.model == "gpt-5.6-terra") or
        ($runtime.agent_role == "advisor-sol" and $runtime.model == "gpt-5.6-sol")) | not then
      error("wrong role/model pair")
    else . end |
    {
      agent_role: $runtime.agent_role,
      transport: $runtime.transport,
      model: $runtime.model,
      effort: $runtime.effort,
      sandbox_policy_type: $runtime.sandbox_policy_type,
      permission_profile_type: $runtime.permission_profile_type
    }
  ' "$evidence" >"$output" || return 1
}

receipt_matches_contract() {
  jq -e '
    . as $r |
    ($r | keys | sort) == [
      "agent_role",
      "effort",
      "model",
      "permission_profile_type",
      "sandbox_policy_type",
      "transport"
    ] and
    ($r.transport == "codex-exec") and
    ((($r.agent_role == "advisor-terra" and $r.model == "gpt-5.6-terra") or
      ($r.agent_role == "advisor-sol" and $r.model == "gpt-5.6-sol"))) and
    ($r.effort == "high") and
    ($r.sandbox_policy_type == "read-only") and
    ($r.permission_profile_type == "managed")
  ' "$1" >/dev/null
}

assert_receipt_keys() {
  jq -e '
    keys | sort == [
      "agent_role",
      "effort",
      "model",
      "permission_profile_type",
      "sandbox_policy_type",
      "transport"
    ]
  ' "$1" >/dev/null || return 1
}

write_observed_runtime() {
  output=$1
  thread_id=$2
  parent_thread_id=$3
  agent_role=$4
  model=$5
  sandbox=$6
  permission_profile_type=$7
  jq -cn \
    --arg thread_id "$thread_id" \
    --arg parent_thread_id "$parent_thread_id" \
    --arg agent_role "$agent_role" \
    --arg transport "codex-exec" \
    --arg model "$model" \
    --arg effort "high" \
    --arg sandbox "$sandbox" \
    --arg permission_profile_type "$permission_profile_type" \
    '{thread_id:$thread_id,parent_thread_id:$parent_thread_id,agent_role:$agent_role,transport:$transport,model:$model,effort:"high",sandbox_policy_type:$sandbox,permission_profile_type:$permission_profile_type}' \
    >"$output" || return 1
}

synthetic() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/advisor-clean-host.XXXXXX") || fail "cannot create temporary directory"
  cleanup() { rm -rf "$tmp"; }
  # A signal handler that only cleans up would return and resume with $tmp gone.
  trap cleanup 0
  trap 'cleanup; exit 130' HUP INT TERM

  observed=$tmp/observed-runtime.json
  receipt=$tmp/receipt.json
  mutated=$tmp/mutated-receipt.json
  wrong=$tmp/wrong-receipt.json
  same_ids=$tmp/same-ids.json

  write_observed_runtime \
    "$observed" \
    '11111111-1111-1111-1111-111111111111' \
    '22222222-2222-2222-2222-222222222222' \
    'advisor-terra' \
    'gpt-5.6-terra' \
    'read-only' \
    'managed' || fail "cannot create synthetic runtime evidence"
  generate_receipt "$observed" "$receipt" || fail "cannot generate synthetic receipt"
  assert_receipt_keys "$receipt" || fail "synthetic receipt did not persist expected key set"
  receipt_matches_contract "$receipt" || fail "synthetic receipt does not satisfy the parent predicate"

  write_observed_runtime \
    "$wrong" \
    '11111111-1111-1111-1111-111111111111' \
    '22222222-2222-2222-2222-222222222222' \
    'advisor-terra' \
    'gpt-5.6-sol' \
    'read-only' \
    'managed' || fail "cannot create synthetic wrong runtime evidence"
  if generate_receipt "$wrong" "$mutated" 2>/dev/null; then
    fail "predicate accepted a mismatch role/model pair"
  fi

  write_observed_runtime \
    "$wrong" \
    '11111111-1111-1111-1111-111111111111' \
    '22222222-2222-2222-2222-222222222222' \
    'advisor-sol' \
    'gpt-5.6-terra' \
    'read-only' \
    'managed' || fail "cannot create synthetic wrong-role runtime evidence"
  if generate_receipt "$wrong" "$mutated" 2>/dev/null; then
    fail "predicate accepted a role-model swap"
  fi

  write_observed_runtime \
    "$same_ids" \
    '11111111-1111-1111-1111-111111111111' \
    '11111111-1111-1111-1111-111111111111' \
    'advisor-terra' \
    'gpt-5.6-terra' \
    'read-only' \
    'managed' || fail "cannot create synthetic same-thread runtime evidence"
  if generate_receipt "$same_ids" "$mutated" 2>/dev/null; then
    fail "predicate accepted matching parent and child thread IDs"
  fi

  write_observed_runtime \
    "$wrong" \
    '11111111-1111-1111-1111-111111111111' \
    '22222222-2222-2222-2222-222222222222' \
    'advisor-terra' \
    'gpt-5.6-terra' \
    'workspace-write' \
    'managed' || fail "cannot create synthetic non-read-only runtime evidence"
  if generate_receipt "$wrong" "$mutated" 2>/dev/null; then
    fail "predicate accepted a non-read-only sandbox"
  fi

  write_observed_runtime \
    "$observed" \
    '11111111-1111-1111-1111-111111111111' \
    '22222222-2222-2222-2222-222222222222' \
    'advisor-sol' \
    'gpt-5.6-sol' \
    'read-only' \
    'managed' || fail "cannot create synthetic solver runtime evidence"
  generate_receipt "$observed" "$receipt" || fail "cannot generate synthetic solver receipt"
  assert_receipt_keys "$receipt" || fail "synthetic solver receipt did not persist expected key set"
  if ! receipt_matches_contract "$receipt"; then
    fail "synthetic advisor-sol receipt does not satisfy the parent predicate"
  fi
  if jq -e 'if .agent_role == "advisor-sol" then true else false end' "$receipt" >/dev/null; then
    pass "synthetic clean-host predicate accepts advisor-sol role"
  else
    fail "synthetic advisor-sol receipt role was not preserved"
  fi

  jq -e 'del(.agent_role)' "$receipt" > "$mutated" || fail "cannot mutate synthetic receipt"
  if receipt_matches_contract "$mutated"; then
    fail "predicate accepted a receipt missing its advisor role"
  fi
  stale=$tmp/stale-receipt.json
  stale_hash=$tmp/stale-receipt.sha256
  receipt_path=$stale
  evidence_path=$observed
  if ! capture; then
    fail "initial capture failed while creating immutable recapture fixture"
  fi
  shasum -a 256 "$stale" > "$stale_hash" || fail "cannot hash existing receipt"
  if (receipt_path=$stale evidence_path=$wrong capture); then
    fail "invalid recapture was accepted"
  fi
  if ! shasum -a 256 -c "$stale_hash" >/dev/null 2>&1; then
    fail "failed recapture changed an existing receipt"
  fi
  pass "synthetic clean-host receipt contract and negative controls"
}

capture() {
  [ -f "$evidence_path" ] || fail "runtime evidence does not exist: $evidence_path"
  receipt_dir=$(dirname "$receipt_path")
  [ -d "$receipt_dir" ] || fail "receipt directory does not exist: $receipt_dir"
  temporary_receipt=$(mktemp "$receipt_dir/.advisor-clean-host-receipt.XXXXXX") || fail "cannot create receipt temporary file"

  if ! generate_receipt "$evidence_path" "$temporary_receipt"; then
    rm -f "$temporary_receipt"
    fail "runtime evidence does not contain a complete observed receipt; existing receipt (if any) was not replaced"
  fi
  # Check before publishing. Publishing first and failing afterwards would leave a
  # non-conforming receipt sitting at the path reserved for attended evidence.
  if ! receipt_matches_contract "$temporary_receipt"; then
    rm -f "$temporary_receipt"
    fail "observed runtime does not satisfy the parent predicate; no existing receipt was replaced"
  fi
  mv "$temporary_receipt" "$receipt_path" || fail "cannot write receipt: $receipt_path"
  pass "captured clean-host receipt: $receipt_path"
}

case "$mode" in
  --synthetic) synthetic ;;
  --capture) capture ;;
esac
