# shellcheck shell=sh
# Sourced by plugins/advisor/scripts/verify.sh; do not run directly.
sessions=$tmp/sessions/2026/08/27; mkdir -p "$sessions"
id=11111111-1111-7111-8111-111111111111
root_id=00000000-0000-7000-8000-000000000000
rollout=$sessions/rollout-fixture-$id.jsonl
printf '%s\n' \
 '{"type":"response_item","payload":{"text":"DO_NOT_LEAK"}}' \
 "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$id\",\"source\":\"exec\",\"originator\":\"codex_exec\",\"agent_role\":null,\"parent_thread_id\":null}}" \
 '{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$rollout"
out=$(TMPDIR=/nonexistent-read-only-path sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$root_id" "$id")
printf '%s\n' "$out" | jq -e '.agent_role=="advisor-sol" and .model=="gpt-6-sol" and .effort=="high" and .sandbox_policy_type=="read-only" and .transport=="codex-exec" and (keys|sort)==["agent_role","effort","model","parent_thread_id","permission_profile_type","sandbox_policy_type","thread_id","transport"]' >/dev/null || fail "inspector allowlist/pins"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-terra --expected-model gpt-5.6-terra --expected-parent "$root_id" "$id" >/dev/null 2>&1; then fail "inspector accepted a role/model pair other than the selected pair"; fi
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$id" "$id" >/dev/null 2>&1; then fail "inspector accepted the parent session as the advisor session"; fi
printf '%s\n' "$out" | grep -Fq DO_NOT_LEAK && fail "inspector leaked payload"
desktop_id=22222222-2222-7222-8222-222222222222
printf '%s\n' \
  '{"type":"response_item","payload":{"text":"DO_NOT_LEAK_DESKTOP"}}' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$desktop_id\",\"source\":\"exec\",\"originator\":\"Codex Desktop\",\"agent_role\":null,\"parent_thread_id\":null}}" \
  '{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$desktop_id.jsonl"
desktop_out=$(sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$root_id" "$desktop_id")
printf '%s\n' "$desktop_out" | jq -e '.agent_role=="advisor-sol" and .model=="gpt-6-sol" and .effort=="high" and .sandbox_policy_type=="read-only" and .permission_profile_type=="managed" and .transport=="codex-exec"' >/dev/null || fail "inspector rejected exact Codex Desktop provenance"
printf '%s\n' "$desktop_out" | grep -Fq DO_NOT_LEAK && fail "desktop inspector leaked payload"
assert_provenance_mismatch() {
  candidate=$1
  error=$tmp/provenance-error-$candidate.txt
  if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$root_id" "$candidate" >"$tmp/provenance-out-$candidate.json" 2>"$error"; then
    fail "inspector accepted mismatched provenance"
  fi
  [ "$(cat "$error")" = 'ERROR: runtime_provenance_mismatch' ] || fail "provenance mismatch category was not fixed and stderr-only"
}
arbitrary_provenance_id=23232323-2323-7232-8232-232323232323
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$arbitrary_provenance_id\",\"source\":\"exec\",\"originator\":\"desktop\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$arbitrary_provenance_id.jsonl"
assert_provenance_mismatch "$arbitrary_provenance_id"
near_provenance_id=24242424-2424-7242-8242-242424242424
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$near_provenance_id\",\"source\":\"exec\",\"originator\":\"Codex desktop\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$near_provenance_id.jsonl"
assert_provenance_mismatch "$near_provenance_id"
nonreadonly_id=33333333-3333-7333-8333-333333333333
nonreadonly=$sessions/rollout-fixture-$nonreadonly_id.jsonl
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$nonreadonly_id\",\"source\":\"exec\",\"originator\":\"codex_exec\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"high","sandbox_policy":{"type":"workspace-write"},"permission_profile":{"type":"managed"}}}' >"$nonreadonly"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$root_id" "$nonreadonly_id" >/dev/null 2>&1; then fail "inspector accepted non-read-only runtime policy"; fi
tool_id=44444444-4444-7444-8444-444444444444
tool_rollout=$sessions/rollout-fixture-$tool_id.jsonl
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$tool_id\",\"source\":\"exec\",\"originator\":\"codex_exec\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' \
  '{"type":"response_item","payload":{"type":"function_call","name":"repo_inspection"}}' >"$tool_rollout"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$root_id" "$tool_id" >/dev/null 2>&1; then fail "inspector accepted advisor tool use"; fi
printf '%s\n' '{"type":"turn_context","payload":{"model":"gpt-5.6-terra","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >>"$rollout"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$root_id" "$id" >/dev/null 2>&1; then fail "inspector accepted conflicting model"; fi
wrong_effort_id=99999999-9999-7999-8999-999999999999
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$wrong_effort_id\",\"source\":\"exec\",\"originator\":\"codex_exec\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"medium","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$wrong_effort_id.jsonl"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$root_id" "$wrong_effort_id" >/dev/null 2>&1; then fail "inspector accepted wrong effort"; fi
wrong_source_id=aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$wrong_source_id\",\"source\":\"tui\",\"originator\":\"codex-tui\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$wrong_source_id.jsonl"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-6-sol --expected-parent "$root_id" "$wrong_source_id" >/dev/null 2>&1; then fail "inspector accepted non-exec provenance"; fi
pass "runtime inspector exact allowlist, pins, redaction, distinct session, exec provenance, wrong effort, non-read-only, tool-use, and conflict refusal"

parent_home=$tmp/parent-home
parent_sessions=$parent_home/sessions
parent_dir=$parent_sessions/2026/08/28
mkdir -p "$parent_dir"
parent_id=55555555-5555-7555-8555-555555555555
parent_rollout=$parent_dir/rollout-fixture-$parent_id.jsonl
printf '%s\n' \
  '{"type":"response_item","payload":{"text":"DO_NOT_LEAK_PARENT_SOURCE"}}' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$parent_id\",\"agent_role\":\"root\"}}" \
  '{"type":"turn_context","payload":{"sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$parent_rollout"
parent_out=$(CODEX_HOME="$parent_home" CODEX_THREAD_ID="$parent_id" sh "$parent_inspector")
printf '%s\n' "$parent_out" | jq -e '.status=="available" and .sandbox_policy_type=="read-only" and .permission_profile_type=="managed" and (keys|sort)==["permission_profile_type","sandbox_policy_type","status","thread_id"]' >/dev/null || fail "parent inspector did not prove read-only default-root runtime"
if printf '%s\n' "$parent_out" | grep -Fq DO_NOT_LEAK_PARENT_SOURCE; then fail "parent inspector leaked source content"; fi
workspace_parent_id=bbbbbbbb-bbbb-7bbb-8bbb-bbbbbbbbbbbb
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$workspace_parent_id\"}}" \
  '{"type":"turn_context","payload":{"sandbox_policy":{"type":"workspace-write"},"permission_profile":{"type":"managed"}}}' >"$parent_dir/rollout-fixture-$workspace_parent_id.jsonl"
workspace_parent_out=$(CODEX_THREAD_ID="$workspace_parent_id" sh "$parent_inspector" --sessions-dir "$parent_sessions")
printf '%s\n' "$workspace_parent_out" | jq -e '.status=="available" and .sandbox_policy_type=="workspace-write"' >/dev/null || fail "parent inspector rejected normal workspace-write root"
danger_parent_id=cccccccc-cccc-7ccc-8ccc-cccccccccccc
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$danger_parent_id\"}}" \
  '{"type":"turn_context","payload":{"sandbox_policy":{"type":"danger-full-access"},"permission_profile":{"type":"managed"}}}' >"$parent_dir/rollout-fixture-$danger_parent_id.jsonl"
parent_unavailable() {
  candidate=$1
  result=$(CODEX_THREAD_ID="$candidate" sh "$parent_inspector" --sessions-dir "$parent_sessions")
  printf '%s\n' "$result" | jq -e '.status=="unavailable" and .reason_type=="parent_runtime_unavailable" and .redacted==true and (keys|sort)==["reason_type","redacted","status"]' >/dev/null || fail "parent inspector did not return typed unavailable: $candidate"
  if printf '%s\n' "$result" | grep -Fq DO_NOT_LEAK_PARENT_SOURCE; then fail "parent inspector leaked unavailable source content"; fi
}
missing_id=66666666-6666-7666-8666-666666666666
parent_unavailable "$missing_id"
parent_unavailable "$danger_parent_id"
session_fallback=$(CODEX_SESSION_ID="$parent_id" CODEX_THREAD_ID= sh "$parent_inspector" --sessions-dir "$parent_sessions")
printf '%s\n' "$session_fallback" | jq -e '.status=="unavailable" and .reason_type=="parent_runtime_unavailable"' >/dev/null || fail "parent inspector used CODEX_SESSION_ID fallback"
duplicate_dir=$parent_sessions/2026/08/29; mkdir -p "$duplicate_dir"
cp "$parent_rollout" "$duplicate_dir/rollout-duplicate-$parent_id.jsonl"
parent_unavailable "$parent_id"
rm "$duplicate_dir/rollout-duplicate-$parent_id.jsonl"
conflict_id=77777777-7777-7777-8777-777777777777
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$conflict_id\"}}" \
  '{"type":"turn_context","payload":{"sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' \
  '{"type":"turn_context","payload":{"sandbox_policy":{"type":"workspace-write"},"permission_profile":{"type":"managed"}}}' >"$parent_dir/rollout-fixture-$conflict_id.jsonl"
parent_unavailable "$conflict_id"
malformed_id=88888888-8888-7888-8888-888888888888
printf '%s\n' '{not-json' >"$parent_dir/rollout-fixture-$malformed_id.jsonl"
parent_unavailable "$malformed_id"
symlink_id=99999999-9999-7999-8999-999999999999
ln -s "$parent_rollout" "$parent_dir/rollout-fixture-$symlink_id.jsonl"
parent_unavailable "$symlink_id"
nonregular_id=aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa
mkdir "$parent_dir/rollout-fixture-$nonregular_id.jsonl"
parent_unavailable "$nonregular_id"
pass "parent preflight read-only/workspace-write success plus danger-full-access, missing identity/rollout, duplicate, conflicting, malformed, symlink, nonregular, and no-session-fallback refusal"
