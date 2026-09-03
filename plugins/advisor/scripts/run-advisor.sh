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
chmod 700 "$transport_dir" || fail "temporary directory protection failed"
heartbeat_pid=''
stop_heartbeat() {
  if [ -n "$heartbeat_pid" ]; then
    kill "$heartbeat_pid" 2>/dev/null || :
    wait "$heartbeat_pid" 2>/dev/null || :
    heartbeat_pid=''
  fi
}
cleanup() {
  stop_heartbeat
  case "$transport_dir" in "$transport_root"/run.*) rm -rf -- "$transport_dir" ;; esac
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

packet=$transport_dir/packet.txt
base_prompt=$transport_dir/prompt.1.txt
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
  printf '%s\n' 'Return exactly one JSON object matching the supplied schema, with no prose or code fences.'
  printf '\n'
  sed -n '1,$p' "$packet"
} >"$base_prompt"

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || fail "script directory unavailable"
plugin_dir=$(CDPATH= cd "$script_dir/.." && pwd) || fail "plugin directory unavailable"
response_schema=$plugin_dir/advisor-response.schema.json
[ -f "$response_schema" ] && [ ! -L "$response_schema" ] || fail "response schema is unavailable"

validation_class='' validation_field=''
validation_failure() {
  validation_class=$1
  validation_field=$2
  return 1
}

validate_response() {
  candidate=$1 stream=$2 parser_status_file=$3 normalized=$4 rendered=$5

  parser_status=0
  jq --stream -c 'select(length == 2)' "$candidate" >"$stream" 2>/dev/null || parser_status=$?
  printf '%s\n' "$parser_status" >"$parser_status_file"
  if [ "$parser_status" -ne 0 ]; then
    first_line=$(LC_ALL=C sed -n '1p' "$candidate")
    if [ "$first_line" = 'ADVISOR RESPONSE' ]; then
      validation_failure legacy-text response || return 1
    fi
    validation_failure invalid-json response || return 1
  fi
  if [ ! -s "$candidate" ] || [ ! -s "$stream" ]; then
    validation_failure empty-output response || return 1
  fi

  if ! jq -se '
    def scalar_keys: ["recommendation", "why", "strongest_objection", "change_my_mind", "risks", "follow_up_areas"];
    . as $events
    | ([$events[] | select((.[0] | length) == 2 and .[0][0] == "acceptance_checks") | .[0][1]]) as $indices
    | (all($events[];
          ((.[0] | length) == 1 and (.[0][0] as $key | scalar_keys | index($key)) != null and (.[1] | type) == "string")
          or
          ((.[0] | length) == 2 and .[0][0] == "acceptance_checks" and (.[0][1] | type) == "number" and .[0][1] >= 0 and (.[0][1] | floor) == .[0][1] and (.[1] | type) == "string")
        )
      and ([scalar_keys[] as $key | ([$events[] | select(.[0] == [$key])] | length) == 1] | all)
      and ($indices | length) > 0
      and $indices == [range(0; $indices | length)])
  ' "$stream" >/dev/null 2>&1; then
    structure_diagnostic=$(jq -sr '
      def scalar_keys: ["recommendation", "why", "strongest_objection", "change_my_mind", "risks", "follow_up_areas"];
      def all_keys: scalar_keys + ["acceptance_checks"];
      . as $events
      | (if any($events[]; (.[0] | length) == 0 or (.[0][0] | type) != "string")
         then "wrong-type/response" else empty end) //
        ([all_keys[] as $key
          | ([$events[] | select(.[0][0] == $key)]) as $matches
          | ([$matches[] | .[0]] | group_by(.) | any(length > 1)) as $repeated_path
          | ([$matches[] | select(.[0] == [$key])]) as $direct
          | ([$matches[] | select((.[0] | length) > 1)]) as $nested
          | select($repeated_path or (($direct | length) > 0 and ($nested | length) > 0) or (($direct | length) > 1))
          | "duplicate-or-overwritten-field/" + $key][0]) //
        ([all_keys[] as $key
          | select(([$events[] | select(.[0][0] == $key)] | length) == 0)
          | "missing-field/" + $key][0]) //
        (if any($events[]; (.[0] | length) == 0 or (.[0][0] as $key | all_keys | index($key)) == null)
         then "extra-field/response" else empty end) //
        ([scalar_keys[] as $key
          | ([$events[] | select(.[0][0] == $key)]) as $matches
          | select(($matches | length) != 1 or $matches[0][0] != [$key] or ($matches[0][1] | type) != "string")
          | "wrong-type/" + $key][0]) //
        (([$events[] | select(.[0][0] == "acceptance_checks")]) as $checks
         | ([$checks[] | select((.[0] | length) == 2 and (.[0][1] | type) == "number" and .[0][1] >= 0 and (.[0][1] | floor) == .[0][1] and (.[1] | type) == "string") | .[0][1]]) as $indices
         | if (($checks | length) == 0 or ($checks | length) != ($indices | length) or $indices != [range(0; $indices | length)]) then "invalid-acceptance-checks/acceptance_checks" else empty end) //
        "wrong-type/response"
    ' "$stream" 2>/dev/null) || structure_diagnostic=wrong-type/response
    validation_class=${structure_diagnostic%%/*}
    validation_field=${structure_diagnostic#*/}
    case "$validation_class" in duplicate-or-overwritten-field|missing-field|extra-field|wrong-type|invalid-acceptance-checks) ;; *) validation_class=wrong-type; validation_field=response ;; esac
    case "$validation_field" in recommendation|why|strongest_objection|change_my_mind|acceptance_checks|risks|follow_up_areas|response) ;; *) validation_field=response ;; esac
    return 1
  fi

  for field in recommendation why strongest_objection change_my_mind risks follow_up_areas; do
    if ! jq -e --arg field "$field" '
      def clean: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
      (.[$field] | clean | length) > 0
    ' "$candidate" >/dev/null 2>&1; then
      validation_failure blank-field "$field" || return 1
    fi
  done
  if ! jq -e '
    def clean: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
    all(.acceptance_checks[]; (clean | length) > 0)
  ' "$candidate" >/dev/null 2>&1; then
    validation_failure blank-field acceptance_checks || return 1
  fi

  if ! jq -c '
    def clean: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
    {
      recommendation: (.recommendation | clean),
      why: (.why | clean),
      strongest_objection: (.strongest_objection | clean),
      change_my_mind: (.change_my_mind | clean),
      acceptance_checks: [.acceptance_checks[] | clean],
      risks: (.risks | clean),
      follow_up_areas: (.follow_up_areas | clean)
    }
  ' "$candidate" >"$normalized" 2>/dev/null; then
    validation_failure wrong-type response || return 1
  fi

  if ! jq -r '
    "ADVISOR RESPONSE",
    "RECOMMENDATION: \(.recommendation)",
    "WHY: \(.why)",
    "STRONGEST OBJECTION: \(.strongest_objection)",
    "CHANGE MY MIND: \(.change_my_mind)",
    "ACCEPTANCE CHECKS: \(.acceptance_checks | join("; "))",
    "RISKS: \(.risks)",
    "FOLLOW-UP AREAS: \(.follow_up_areas)"
  ' "$normalized" >"$rendered" 2>/dev/null; then
    validation_failure render-failure response || return 1
  fi
  [ "$(wc -l <"$rendered" | tr -d ' ')" -eq 8 ] || validation_failure render-failure response || return 1
}

attempt=1
first_child_thread_id=''
response_verified=false
prompt=$base_prompt
while [ "$attempt" -le 2 ]; do
  events=$transport_dir/events.$attempt.jsonl
  response=$transport_dir/response.$attempt.json
  evidence=$transport_dir/evidence.$attempt.json
  stream=$transport_dir/response-stream.$attempt.jsonl
  parser_status_file=$transport_dir/response-stream.$attempt.status
  normalized=$transport_dir/normalized.$attempt.json
  rendered=$transport_dir/rendered.$attempt.txt
  workdir=$transport_dir/workdir.$attempt
  mkdir "$workdir" || fail "isolated work directory creation failed"

  progress "launching $role ($model, high, read-only), attempt $attempt of 2"
  (
    while :; do
      progress "child invocation still running (attempt $attempt)"
      sleep 10
    done
  ) &
  heartbeat_pid=$!
  if ! codex exec --json --ignore-user-config --ignore-rules \
    --sandbox read-only --model "$model" -c 'model_reasoning_effort="high"' \
    -C "$workdir" --skip-git-repo-check --output-schema "$response_schema" \
    --output-last-message "$response" - <"$prompt" >"$events"; then
    stop_heartbeat
    fail "codex exec failed"
  fi
  stop_heartbeat

  child_thread_id=$(jq -r 'select(.type == "thread.started") | .thread_id' "$events" 2>/dev/null) || fail "malformed transport events"
  [ "$(printf '%s\n' "$child_thread_id" | awk 'NF { count += 1 } END { print count + 0 }')" -eq 1 ] || fail "ambiguous child thread"
  [ "$child_thread_id" != "$parent_thread_id" ] || fail "consultation reused the parent thread"
  [ "$attempt" -eq 1 ] || [ "$child_thread_id" != "$first_child_thread_id" ] || fail "retry reused the first child thread"
  [ "$attempt" -ne 1 ] || first_child_thread_id=$child_thread_id

  progress "inspecting persisted runtime evidence for attempt $attempt"
  set -- --expected-role "$role" --expected-model "$model" --expected-parent "$parent_thread_id"
  [ -z "$sessions_dir" ] || set -- --sessions-dir "$sessions_dir" "$@"
  inspection_error=$transport_dir/inspection-error.$attempt
  if ! sh "$script_dir/inspect-agent-runtime.sh" "$@" "$child_thread_id" >"$evidence" 2>"$inspection_error"; then
    if grep -Fqx 'ERROR: runtime_provenance_mismatch' "$inspection_error"; then
      fail "runtime_provenance_mismatch"
    fi
    fail "runtime inspection failed"
  fi

  validation_class='' validation_field=''
  if validate_response "$response" "$stream" "$parser_status_file" "$normalized" "$rendered"; then
    response_verified=true
    break
  fi
  progress "response validation failed (class=$validation_class field=$validation_field)"
  [ "$attempt" -eq 1 ] || fail "advisor response failed validation after retry (class=$validation_class field=$validation_field)"
  progress "runtime-valid response failed validation; launching one fresh corrective retry (class=$validation_class field=$validation_field)"
  prompt=$transport_dir/prompt.2.txt
  {
    sed -n '1,$p' "$base_prompt"
    printf '\nCorrection: the previous response failed validation (class=%s field=%s). Return a new schema-valid object.\n' "$validation_class" "$validation_field"
  } >"$prompt"
  attempt=2
done
[ "$response_verified" = true ] || fail "advisor response was not verified"

progress "consultation verified"
jq -cn --argjson evidence "$(cat "$evidence")" --rawfile response "$rendered" '{status:"completed",runtime:$evidence,response:$response}'
