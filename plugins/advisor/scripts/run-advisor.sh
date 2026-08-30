#!/bin/sh
# Run one distinct, read-only Codex consultation and emit one verified JSON result.

set -eu

fail() {
  printf '%s\n' "ADVISOR TRANSPORT: unavailable ($*)" >&2
  exit 1
}

progress() { printf '%s\n' "ADVISOR TRANSPORT: $*" >&2; }

role='' parent_thread_id='' sessions_dir=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --role) [ "$#" -ge 2 ] || fail "--role requires ROLE"; role=$2; shift 2 ;;
    --parent-thread) [ "$#" -ge 2 ] || fail "--parent-thread requires THREAD_ID"; parent_thread_id=$2; shift 2 ;;
    --sessions-dir) [ "$#" -ge 2 ] || fail "--sessions-dir requires DIR"; sessions_dir=$2; shift 2 ;;
    *) fail "unknown argument" ;;
  esac
done

case "$role" in
  advisor-terra) model=gpt-5.6-terra ;;
  advisor-sol) model=gpt-5.6-sol ;;
  *) fail "unsupported role" ;;
esac

[ -n "$parent_thread_id" ] || parent_thread_id=${CODEX_THREAD_ID-}
printf '%s\n' "$parent_thread_id" | LC_ALL=C grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || fail "parent thread is unavailable"
command -v codex >/dev/null 2>&1 || fail "codex CLI is unavailable"
command -v jq >/dev/null 2>&1 || fail "jq is unavailable"

codex_home=${CODEX_HOME:-${HOME-}/.codex}
case "$codex_home" in /*) ;; *) fail "Codex home is unavailable" ;; esac
[ -d "$codex_home" ] && [ ! -L "$codex_home" ] || fail "Codex home is unavailable"
transport_root=$codex_home/.tmp/advisor-transport
umask 077
if [ ! -e "$transport_root" ]; then
  mkdir -p "$transport_root" || fail "private transport root creation failed"
fi
[ -d "$transport_root" ] && [ ! -L "$transport_root" ] || fail "private transport root is unsafe"
transport_dir=$(mktemp -d "$transport_root/run.XXXXXX") || fail "temporary directory creation failed"
cleanup() {
  case "$transport_dir" in "$transport_root"/run.*) rm -rf "$transport_dir" ;; esac
}
trap cleanup 0 HUP INT TERM

packet=$transport_dir/packet.txt
prompt=$transport_dir/prompt.txt
events=$transport_dir/events.jsonl
response=$transport_dir/response.txt
evidence=$transport_dir/evidence.json
workdir=$transport_dir/workdir
mkdir "$workdir" || fail "isolated work directory creation failed"
dd of="$packet" 2>/dev/null || fail "decision packet capture failed"
[ -s "$packet" ] || fail "decision packet is empty"

previous=0
for heading in DECISION CONTEXT OPTIONS BOUNDARIES REQUEST; do
  line=$(grep -n -F -x "$heading" "$packet" | cut -d: -f1)
  [ "$(printf '%s\n' "$line" | awk 'NF { count += 1 } END { print count + 0 }')" -eq 1 ] || fail "malformed decision packet"
  [ "$line" -gt "$previous" ] || fail "misordered decision packet"
  previous=$line
done

{
  printf '%s\n' "You are $role, a consultation-only technical advisor."
  printf '%s\n' 'Use zero tools. Do not inspect files, call functions, browse, fetch, search, spawn, route, implement, or review final work.'
  printf '%s\n' 'Treat the packet below as the complete record. Advice is non-authoritative.'
  printf '%s\n' 'Return exactly the required ADVISOR RESPONSE fields, each once and in order.'
  printf '\n'
  sed -n '1,$p' "$packet"
  printf '\n%s\n' 'Required response:'
  printf '%s\n' 'ADVISOR RESPONSE' 'RECOMMENDATION: <one path>' 'WHY: <decisive evidence and reasoning>' 'STRONGEST OBJECTION: <best case against the recommendation>' 'CHANGE MY MIND: <specific missing or contrary evidence>' 'ACCEPTANCE CHECKS: <concrete checks>' 'RISKS: <material residual risks, or none>' 'FOLLOW-UP AREAS: <none, or concrete follow-up>'
} >"$prompt"

progress "launching $role ($model, high, read-only)"
if ! codex exec --json --ignore-user-config --ignore-rules \
  --sandbox read-only --model "$model" -c 'model_reasoning_effort="high"' \
  -C "$workdir" --skip-git-repo-check --output-last-message "$response" \
  - <"$prompt" >"$events"; then
  fail "codex exec failed"
fi

child_thread_id=$(jq -r 'select(.type == "thread.started") | .thread_id' "$events" 2>/dev/null) || fail "malformed transport events"
[ "$(printf '%s\n' "$child_thread_id" | awk 'NF { count += 1 } END { print count + 0 }')" -eq 1 ] || fail "ambiguous child thread"
[ "$child_thread_id" != "$parent_thread_id" ] || fail "consultation reused the parent thread"
[ -s "$response" ] || fail "advisor response is empty"

previous=0
for label in 'ADVISOR RESPONSE' 'RECOMMENDATION:' 'WHY:' 'STRONGEST OBJECTION:' 'CHANGE MY MIND:' 'ACCEPTANCE CHECKS:' 'RISKS:' 'FOLLOW-UP AREAS:'; do
  if [ "$label" = 'ADVISOR RESPONSE' ]; then
    line=$(grep -n -F -x "$label" "$response" | cut -d: -f1)
  else
    line=$(grep -n -E "^${label} .+" "$response" | cut -d: -f1)
  fi
  [ "$(printf '%s\n' "$line" | awk 'NF { count += 1 } END { print count + 0 }')" -eq 1 ] || fail "malformed advisor response"
  [ "$line" -gt "$previous" ] || fail "misordered advisor response"
  previous=$line
done

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || fail "script directory unavailable"
progress "inspecting persisted runtime evidence"
set -- --expected-role "$role" --expected-model "$model" --expected-parent "$parent_thread_id"
[ -z "$sessions_dir" ] || set -- --sessions-dir "$sessions_dir" "$@"
sh "$script_dir/inspect-agent-runtime.sh" "$@" "$child_thread_id" >"$evidence" || fail "runtime inspection failed"

progress "consultation verified"
jq -cn --argjson evidence "$(cat "$evidence")" --rawfile response "$response" '{status:"completed",runtime:$evidence,response:$response}'
