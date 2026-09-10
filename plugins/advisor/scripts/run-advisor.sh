#!/bin/sh
# Run one distinct, read-only Codex consultation and emit one verified JSON result.

set -eu

fail() {
  printf '%s\n' "ADVISOR TRANSPORT: unavailable ($*)" >&2
  if command -v terminal_failure >/dev/null 2>&1; then terminal_failure "$*" || :; fi
  exit 1
}

progress() { printf '%s\n' "ADVISOR TRANSPORT: $*" >&2; }

role='' tier='' preset='' canary_token='' parent_thread_id='' sessions_dir=''
selection_source='' selection_revision=null source_revision=null
while [ "$#" -gt 0 ]; do
  case "$1" in
    --role) [ "$#" -ge 2 ] || fail "--role requires ROLE"; role=$2; shift 2 ;;
    --tier) [ "$#" -ge 2 ] || fail "--tier requires TIER"; tier=$2; shift 2 ;;
    --preset) [ "$#" -ge 2 ] || fail "--preset requires NAME"; preset=$2; shift 2 ;;
    --compatibility-canary) [ "$#" -ge 2 ] || fail "--compatibility-canary requires TOKEN"; canary_token=$2; shift 2 ;;
    --parent-thread) [ "$#" -ge 2 ] || fail "--parent-thread requires THREAD_ID"; parent_thread_id=$2; shift 2 ;;
    --sessions-dir) [ "$#" -ge 2 ] || fail "--sessions-dir requires DIR"; sessions_dir=$2; shift 2 ;;
    *) fail "unknown argument" ;;
  esac
done

[ -z "$role" ] || [ -z "$tier" ] || fail "--role and --tier are mutually exclusive"
[ -z "$canary_token" ] || { [ -z "$role" ] && [ -z "$tier" ] && [ -z "$preset" ]; } || fail "compatibility canary cannot be mixed with role, tier, or preset"
[ -z "$preset" ] || [ -n "$tier" ] || fail "--preset requires --tier"
[ -n "$role" ] || [ -n "$tier" ] || [ -n "$canary_token" ] || fail "--role or --tier is required"
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || fail "script directory unavailable"
command -v python3 >/dev/null 2>&1 || fail "python3 is unavailable"
command -v codex >/dev/null 2>&1 || fail "codex CLI is unavailable"
command -v jq >/dev/null 2>&1 || fail "jq is unavailable"
for helper in advisor_config.py advisor_process.py inspect-agent-runtime.sh; do
  [ -f "$script_dir/$helper" ] && [ ! -L "$script_dir/$helper" ] || fail "installed Advisor helper is unsafe"
done
if [ -n "$canary_token" ]; then
  resolution=$(python3 "$script_dir/advisor_config.py" --json _consume-canary "$canary_token") || fail "compatibility canary authorization is unavailable"
  model=$(printf '%s' "$resolution" | jq -r '.launch.model') || fail "invalid compatibility canary authorization"
  effort=$(printf '%s' "$resolution" | jq -r '.launch.effort') || fail "invalid compatibility canary authorization"
  deadline_seconds=$(printf '%s' "$resolution" | jq -r '.launch.deadline_seconds') || fail "invalid compatibility canary authorization"
  tier=compatibility-test
  selection_source=authorized-synthetic-canary
  selection_revision=$(printf '%s' "$resolution" | jq -c '.launch.selection_revision') || fail "invalid compatibility canary authorization"
  source_revision=$(printf '%s' "$resolution" | jq -c '.launch.source_revision // .launch.selection_revision') || fail "invalid compatibility canary authorization"
  role=advisor-compatibility-test
elif [ -n "$role" ]; then
  case "$role" in
    advisor-terra) tier=standard; model=gpt-5.6-terra; effort=high; deadline_seconds=300 ;;
    advisor-sol) tier=specialist; model=gpt-5.6-sol; effort=high; deadline_seconds=300 ;;
    advisor-astra) tier=opt-in; model=gpt-6-astra; effort=high; deadline_seconds=300 ;;
    *) fail "unsupported role" ;;
  esac
  case "$role" in
    advisor-astra) selection_source=explicit-fixed ;;
    *) selection_source=legacy-fixed ;;
  esac
else
  resolution_label='live Advisor configuration'
  fallback_error='advisor.toml is unavailable'
  if [ -n "$preset" ]; then resolution_label='legacy preset configuration'; fallback_error='legacy preset configuration is unavailable'; fi
  set -- --json resolve --tier "$tier"
  [ -z "$preset" ] || set -- "$@" --preset "$preset"
  if ! resolution=$(python3 "$script_dir/advisor_config.py" "$@"); then
    config_error=$(printf '%s' "$resolution" | jq -r '.error // empty' 2>/dev/null || :)
    [ -n "$config_error" ] || config_error=$fallback_error
    fail "$config_error"
  fi
  model=$(printf '%s' "$resolution" | jq -r '.launch.model') || fail "invalid $resolution_label"
  effort=$(printf '%s' "$resolution" | jq -r '.launch.effort') || fail "invalid $resolution_label"
  deadline_seconds=$(printf '%s' "$resolution" | jq -r '.launch.deadline_seconds') || fail "invalid $resolution_label"
  selection_source=$(printf '%s' "$resolution" | jq -r '.launch.selection_source') || fail "invalid $resolution_label"
  selection_revision=$(printf '%s' "$resolution" | jq -c '.launch.selection_revision') || fail "invalid $resolution_label"
  source_revision=$(printf '%s' "$resolution" | jq -c '.launch.source_revision') || fail "invalid $resolution_label"
  role=advisor-tier-$tier
fi

journal_status=$(python3 "$script_dir/advisor_config.py" --json journal status 2>/dev/null || printf '%s' '{"enabled":false}')
journal_enabled=$(printf '%s' "$journal_status" | jq -r '.enabled == true' 2>/dev/null || printf '%s' false)
consultation_id=$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
) || fail "consultation identifier generation failed"
consultation_started=$(python3 - <<'PY'
import datetime as dt
print(dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"))
PY
) || fail "consultation timestamp initialization failed"
attempt_records='[]'
consultation_started_ms=$(python3 - <<'PY'
import time
print(time.monotonic_ns() // 1_000_000)
PY
) || fail "consultation timing initialization failed"
attempt_open=false
terminal_emitted=false

usage_totals() {
  jq -cn --argjson attempts "$attempt_records" '
    def metric($name):
      [$attempts[].usage[$name]] as $all
      | [$all[] | select(. != null)] as $known
      | {value:(if ($known|length)>0 then ($known|add) else null end),
         availability:(if ($all|length)==0 or ($known|length)==0 then "unavailable" elif ($known|length)==($all|length) then "available" else "partial" end)};
    {input:metric("input"),cached_input:metric("cached_input"),output:metric("output"),reasoning:metric("reasoning")}
  '
}

terminal_failure() {
  [ "$terminal_emitted" = false ] || return 0
  terminal_emitted=true
  failure_message=$1
  case "$failure_message" in
    *deadline*|*timed*out*) consultation_outcome=timed_out; attempt_outcome=timed_out ;;
    *cancel*) consultation_outcome=cancelled; attempt_outcome=cancelled ;;
    *validation*retry*) consultation_outcome=retry_exhausted; attempt_outcome=rejected_response ;;
    *runtime*|*inspection*) consultation_outcome=failed; attempt_outcome=runtime_failed ;;
    *) consultation_outcome=failed; attempt_outcome=launch_failed ;;
  esac
  if [ "$attempt_open" = true ]; then
    failure_finished_ms=$(python3 - <<'PY'
import time
print(time.monotonic_ns() // 1_000_000)
PY
    ) || return 0
    failure_duration_ms=$((failure_finished_ms - attempt_started_ms))
    failure_usage=$(python3 "$script_dir/advisor_process.py" usage --events "$events" --duration-ms "$failure_duration_ms" 2>/dev/null || printf '{"duration_ms":%s,"usage":{"input":null,"cached_input":null,"output":null,"reasoning":null},"availability":{"input":"unavailable","cached_input":"unavailable","output":"unavailable","reasoning":"unavailable"}}' "$failure_duration_ms")
    attempt_records=$(jq -cn --argjson prior "$attempt_records" --argjson usage "$failure_usage" --argjson number "$attempt" --arg outcome "$attempt_outcome" '$prior + [{number:$number,outcome:$outcome,duration_ms:$usage.duration_ms,usage:$usage.usage,availability:$usage.availability}]') || return 0
    attempt_open=false
  fi
  consultation_finished=$(python3 - <<'PY'
import datetime as dt
print(dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"))
PY
  ) || return 0
  finish_ms=$(python3 - <<'PY'
import time
print(time.monotonic_ns() // 1_000_000)
PY
  ) || return 0
  total_duration_ms=$((finish_ms - consultation_started_ms))
  metric_rows=$(usage_totals) || return 0
  totals=$(printf '%s' "$metric_rows" | jq -c '{input:.input.value,cached_input:.cached_input.value,output:.output.value,reasoning:.reasoning.value}') || return 0
  availability=$(printf '%s' "$metric_rows" | jq -c '{input:.input.availability,cached_input:.cached_input.availability,output:.output.availability,reasoning:.reasoning.availability}') || return 0
  if [ "$journal_enabled" = true ]; then
    progress "writing content-free usage journal"
    journal_record=$(jq -cn --arg id "$consultation_id" --arg started "$consultation_started" --arg finished "$consultation_finished" --arg tier "$tier" --arg model "$model" --arg effort "$effort" --arg outcome "$consultation_outcome" --argjson duration "$total_duration_ms" --argjson attempts "$attempt_records" --argjson totals "$totals" '{schema_version:1,consultation_id:$id,started_at:$started,finished_at:$finished,tier:$tier,model:$model,effort:$effort,outcome:$outcome,transport_contract_version:"1.4",total_duration_ms:$duration,attempts:[$attempts[]|{number,duration_ms,outcome,usage}],totals:$totals}') || journal_record=''
    if [ -z "$journal_record" ] || ! python3 "$script_dir/advisor_config.py" --json _journal-record "$journal_record" >/dev/null 2>&1; then printf '%s\n' 'ADVISOR TRANSPORT: warning (usage journal write unavailable)' >&2; fi
  fi
  jq -cn --arg id "$consultation_id" --arg tier "$tier" --arg model "$model" --arg effort "$effort" --arg source "$selection_source" --argjson revision "$selection_revision" --argjson source_revision "$source_revision" --arg outcome "$consultation_outcome" --argjson attempts "$attempt_records" --argjson totals "$totals" --argjson availability "$availability" --argjson duration "$total_duration_ms" '{schema_version:3,status:"unavailable",outcome:$outcome,consultation_id:$id,selection:{tier:$tier,model:$model,effort:$effort,source:$source,revision:$revision,source_revision:$source_revision,transport_contract_version:"1.4"},attempts:$attempts,usage:{total_duration_ms:$duration,totals:$totals,availability:$availability},runtime:null,response:null}' || :
}

[ -n "$parent_thread_id" ] || parent_thread_id=${CODEX_THREAD_ID-}
printf '%s\n' "$parent_thread_id" | LC_ALL=C grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || fail "parent thread is unavailable"
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
supervisor_pid=''
cleanup() {
  if [ -n "$supervisor_pid" ]; then
    kill -TERM "$supervisor_pid" 2>/dev/null || :
    wait "$supervisor_pid" 2>/dev/null || :
    supervisor_pid=''
  fi
  case "$transport_dir" in "$transport_root"/run.*) rm -rf -- "$transport_dir" ;; esac
}
cancelled() {
  if [ -n "$supervisor_pid" ]; then
    kill -TERM "$supervisor_pid" 2>/dev/null || :
    wait "$supervisor_pid" 2>/dev/null || :
    supervisor_pid=''
  fi
  terminal_failure "consultation cancelled" || :
  exit 130
}
trap cleanup 0
trap cancelled HUP INT TERM

packet=$transport_dir/packet.txt
base_prompt=$transport_dir/prompt.1.txt
deadline_at=$(python3 - "$deadline_seconds" <<'PY'
import sys, time
print(time.monotonic() + int(sys.argv[1]))
PY
) || fail "deadline initialization failed"
deadline_ok() {
  python3 - "$deadline_at" <<'PY'
import sys, time
raise SystemExit(0 if time.monotonic() < float(sys.argv[1]) else 1)
PY
}
if [ -n "$canary_token" ]; then
  cat >"$packet" <<'ADVISOR_CANARY'
DECISION
Confirm technical compatibility of this fixed synthetic consultation.

CONTEXT
This is a content-free transport canary authorized by the user.

OPTIONS
Return a schema-valid neutral response.

BOUNDARIES
Use zero tools and only the configured read-only model transport.

REQUEST
Return the required JSON object with a neutral recommendation and concrete transport acceptance checks.
ADVISOR_CANARY
else
  python3 "$script_dir/advisor_process.py" --deadline-at "$deadline_at" --capture-to "$packet" <&0 &
  supervisor_pid=$!
  capture_status=0
  wait "$supervisor_pid" || capture_status=$?
  supervisor_pid=''
  [ "$capture_status" -eq 0 ] || fail "decision packet capture failed"
fi
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

  [ -f "$candidate" ] && [ "$(wc -c <"$candidate" | tr -d ' ')" -le 1000000 ] || validation_failure oversized-output response || return 1

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
  deadline_ok || fail "consultation deadline exceeded"
  events=$transport_dir/events.$attempt.jsonl
  response=$transport_dir/response.$attempt.json
  evidence=$transport_dir/evidence.$attempt.json
  stream=$transport_dir/response-stream.$attempt.jsonl
  parser_status_file=$transport_dir/response-stream.$attempt.status
  normalized=$transport_dir/normalized.$attempt.json
  rendered=$transport_dir/rendered.$attempt.txt
  workdir=$transport_dir/workdir.$attempt
  mkdir "$workdir" || fail "isolated work directory creation failed"

  attempt_started_ms=$(python3 - <<'PY'
import time
print(time.monotonic_ns() // 1_000_000)
PY
) || fail "attempt timing initialization failed"
  attempt_open=true
  progress "launching $role ($model, $effort, read-only) deadline ${deadline_seconds}s, attempt $attempt of 2"
  # Legacy calls serialize model_reasoning_effort="high"; saved tiers serialize the validated effort.
  python3 "$script_dir/advisor_process.py" --deadline-at "$deadline_at" -- codex exec --json --ignore-user-config --ignore-rules \
    --sandbox read-only --model "$model" -c "model_reasoning_effort=\"$effort\"" \
    -C "$workdir" --skip-git-repo-check --output-schema "$response_schema" \
    --output-last-message "$response" - <"$prompt" >"$events" &
  supervisor_pid=$!
  transport_status=0
  wait "$supervisor_pid" || transport_status=$?
  supervisor_pid=''
  if [ "$transport_status" -ne 0 ]; then
    fail "codex exec failed"
  fi
  deadline_ok || fail "consultation deadline exceeded"
  [ -f "$events" ] && [ "$(wc -c <"$events" | tr -d ' ')" -le 1000000 ] || fail "transport events exceeded byte limit"
  attempt_finished_ms=$(python3 - <<'PY'
import time
print(time.monotonic_ns() // 1_000_000)
PY
) || fail "attempt timing failed"
  attempt_duration_ms=$((attempt_finished_ms - attempt_started_ms))
  attempt_usage=$(python3 "$script_dir/advisor_process.py" usage --events "$events" --duration-ms "$attempt_duration_ms" 2>/dev/null || printf '{"duration_ms":%s,"usage":{"input":null,"cached_input":null,"output":null,"reasoning":null},"availability":{"input":"unavailable","cached_input":"unavailable","output":"unavailable","reasoning":"unavailable"}}' "$attempt_duration_ms")

  child_thread_id=$(jq -r 'select(.type == "thread.started") | .thread_id' "$events" 2>/dev/null) || fail "malformed transport events"
  [ "$(printf '%s\n' "$child_thread_id" | awk 'NF { count += 1 } END { print count + 0 }')" -eq 1 ] || fail "ambiguous child thread"
  [ "$child_thread_id" != "$parent_thread_id" ] || fail "consultation reused the parent thread"
  [ "$attempt" -eq 1 ] || [ "$child_thread_id" != "$first_child_thread_id" ] || fail "retry reused the first child thread"
  [ "$attempt" -ne 1 ] || first_child_thread_id=$child_thread_id

  progress "inspecting persisted runtime evidence for attempt $attempt"
  set -- --expected-role "$role" --expected-model "$model" --expected-effort "$effort" --expected-parent "$parent_thread_id"
  [ -z "$sessions_dir" ] || set -- --sessions-dir "$sessions_dir" "$@"
  inspection_error=$transport_dir/inspection-error.$attempt
  python3 "$script_dir/advisor_process.py" --deadline-at "$deadline_at" -- sh "$script_dir/inspect-agent-runtime.sh" "$@" "$child_thread_id" >"$evidence" 2>"$inspection_error" &
  supervisor_pid=$!
  inspection_status=0
  wait "$supervisor_pid" || inspection_status=$?
  supervisor_pid=''
  if [ "$inspection_status" -ne 0 ]; then
    if grep -Fqx 'ERROR: runtime_provenance_mismatch' "$inspection_error"; then
      fail "runtime_provenance_mismatch"
    fi
    fail "runtime inspection failed"
  fi
  deadline_ok || fail "consultation deadline exceeded"

  validation_class='' validation_field=''
  if validate_response "$response" "$stream" "$parser_status_file" "$normalized" "$rendered"; then
    attempt_records=$(jq -cn --argjson prior "$attempt_records" --argjson usage "$attempt_usage" --argjson number "$attempt" '$prior + [{number:$number,outcome:"accepted",duration_ms:$usage.duration_ms,usage:$usage.usage,availability:$usage.availability}]') || fail "usage record construction failed"
    attempt_open=false
    response_verified=true
    break
  fi
  attempt_records=$(jq -cn --argjson prior "$attempt_records" --argjson usage "$attempt_usage" --argjson number "$attempt" '$prior + [{number:$number,outcome:"rejected_response",duration_ms:$usage.duration_ms,usage:$usage.usage,availability:$usage.availability}]') || fail "usage record construction failed"
  attempt_open=false
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
deadline_ok || fail "consultation deadline exceeded"

progress "consultation verified"
consultation_finished=$(python3 - <<'PY'
import datetime as dt
print(dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"))
PY
) || fail "consultation timestamp failed"
consultation_finished_ms=$(python3 - <<'PY'
import time
print(time.monotonic_ns() // 1_000_000)
PY
) || fail "consultation timing failed"
total_duration_ms=$((consultation_finished_ms - consultation_started_ms))
metric_rows=$(usage_totals) || fail "usage total construction failed"
totals=$(printf '%s' "$metric_rows" | jq -c '{input:.input.value,cached_input:.cached_input.value,output:.output.value,reasoning:.reasoning.value}') || fail "usage total construction failed"
availability=$(printf '%s' "$metric_rows" | jq -c '{input:.input.availability,cached_input:.cached_input.availability,output:.output.availability,reasoning:.reasoning.availability}') || fail "usage total construction failed"
if [ "$journal_enabled" = true ]; then
  progress "writing content-free usage journal"
  journal_record=$(jq -cn --arg id "$consultation_id" --arg started "$consultation_started" --arg finished "$consultation_finished" --arg tier "$tier" --arg model "$model" --arg effort "$effort" --argjson duration "$total_duration_ms" --argjson attempts "$attempt_records" --argjson totals "$totals" '{schema_version:1,consultation_id:$id,started_at:$started,finished_at:$finished,tier:$tier,model:$model,effort:$effort,outcome:"accepted",transport_contract_version:"1.4",total_duration_ms:$duration,attempts:[$attempts[] | {number,duration_ms,outcome,usage}],totals:$totals}') || journal_record=''
  if [ -z "$journal_record" ] || ! python3 "$script_dir/advisor_config.py" --json _journal-record "$journal_record" >/dev/null 2>&1; then
    printf '%s\n' 'ADVISOR TRANSPORT: warning (usage journal write unavailable)' >&2
  fi
fi
jq -cn --argjson evidence "$(cat "$evidence")" --rawfile response "$rendered" \
  --arg tier "$tier" --arg model "$model" --arg effort "$effort" \
  --arg source "$selection_source" --argjson revision "$selection_revision" --argjson source_revision "$source_revision" --argjson attempts "$attempt_records" --argjson totals "$totals" --arg id "$consultation_id" \
  --argjson availability "$availability" --argjson duration "$total_duration_ms" \
  '{schema_version:3,status:"completed",outcome:"accepted",consultation_id:$id,selection:{tier:$tier,model:$model,effort:$effort,source:$source,revision:$revision,source_revision:$source_revision,transport_contract_version:"1.4"},attempts:$attempts,usage:{total_duration_ms:$duration,totals:$totals,availability:$availability},runtime:$evidence,response:$response}'
