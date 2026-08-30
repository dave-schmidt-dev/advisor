#!/bin/sh
# Emit only allowlisted identity/isolation evidence for one exact, zero-tool advisor rollout.

set -eu
fail() { printf '%s\n' "ERROR: $*" >&2; exit 1; }

sessions_dir='' expected_role='' expected_model='' expected_parent='' thread_id=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sessions-dir) [ "$#" -ge 2 ] || fail "--sessions-dir requires DIR"; sessions_dir=$2; shift 2 ;;
    --expected-role) [ "$#" -ge 2 ] || fail "--expected-role requires ROLE"; expected_role=$2; shift 2 ;;
    --expected-model) [ "$#" -ge 2 ] || fail "--expected-model requires MODEL"; expected_model=$2; shift 2 ;;
    --expected-parent) [ "$#" -ge 2 ] || fail "--expected-parent requires THREAD_ID"; expected_parent=$2; shift 2 ;;
    --*) fail "unknown argument: $1" ;;
    *) [ -z "$thread_id" ] || fail "only one THREAD_ID is allowed"; thread_id=$1; shift ;;
  esac
done
[ -n "$thread_id" ] && [ -n "$expected_role" ] && [ -n "$expected_model" ] && [ -n "$expected_parent" ] || fail "usage: inspect-agent-runtime.sh [--sessions-dir DIR] --expected-role ROLE --expected-model MODEL --expected-parent THREAD_ID THREAD_ID"
case "$expected_role:$expected_model" in advisor-terra:gpt-5.6-terra|advisor-sol:gpt-5.6-sol) ;; *) fail "unsupported expected role/model pair" ;; esac
printf '%s\n' "$thread_id" | LC_ALL=C grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || fail "THREAD_ID must be a lowercase UUID"
printf '%s\n' "$expected_parent" | LC_ALL=C grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || fail "expected parent must be a lowercase UUID"
[ "$thread_id" != "$expected_parent" ] || fail "advisor thread must differ from parent"
if [ -z "$sessions_dir" ]; then
  if [ -n "${CODEX_HOME-}" ]; then sessions_dir=$CODEX_HOME/sessions
  else [ -n "${HOME-}" ] || fail "HOME is unset"; sessions_dir=$HOME/.codex/sessions
  fi
fi
[ -d "$sessions_dir" ] || fail "sessions directory unavailable"

matches=$(find "$sessions_dir" -type f -name "rollout-*-$thread_id.jsonl" -print) || fail "rollout enumeration failed"
[ "$(printf '%s\n' "$matches" | awk 'NF {count++} END {print count+0}')" -eq 1 ] || fail "expected exactly one rollout match"
rollout=$matches

jq -ce -s --arg id "$thread_id" --arg expected_parent "$expected_parent" --arg expected_role "$expected_role" --arg expected_model "$expected_model" '
  [ .[] | select(.type=="session_meta") | .payload ] as $s |
  [ .[] | select(.type=="turn_context") | .payload ] as $t |
  if ($s|length)!=1 or ($t|length)==0 then error("missing metadata") else
    [$t[].model] as $m | [$t[].effort] as $e |
    [$t[].sandbox_policy.type] as $b | [$t[].permission_profile.type] as $p |
    [ .[] | .. | objects | .type? |
      select(. == "function_call" or . == "custom_tool_call" or . == "collab_tool_call" or . == "tool_call" or . == "tool_use") ] as $tool_events |
    if $s[0].id!=$id or $s[0].source!="exec" or $s[0].originator!="codex_exec" or
       ($s[0].agent_role // null)!=null or ($s[0].parent_thread_id // null)!=null or
       ($m|unique)!=[$expected_model] or ($e|unique)!=["high"] or
       ($b|unique)!=["read-only"] or ($p|unique|length)!=1 or
       any($p[]; type!="string" or length==0) or ($tool_events|length)!=0
    then error("unexpected, non-read-only, or tool-using advisor evidence")
    else {
      thread_id:$s[0].id,
      parent_thread_id:$expected_parent,
      agent_role:$expected_role,
      transport:"codex-exec",
      model:$m[0], effort:$e[0],
      sandbox_policy_type:$b[0], permission_profile_type:$p[0]
    } end
  end
' "$rollout" 2>/dev/null || fail "rollout lacks exact allowlisted advisor evidence"
