# shellcheck shell=sh
# Sourced by plugins/advisor/scripts/verify.sh; do not run directly.
fake_bin=$tmp/fake-bin
fake_home=$tmp/fake-codex-home
mkdir -p "$fake_bin" "$fake_home/sessions/2026/08/30"
real_jq=$(command -v jq)
python3 - "$fake_bin/codex" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(r'''#!/bin/sh
set -eu
output='' model='' sandbox='' effort='' workdir='' schema=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message) output=$2; shift 2 ;;
    --output-schema) schema=$2; shift 2 ;;
    --model) model=$2; shift 2 ;;
    --sandbox) sandbox=$2; shift 2 ;;
    -c) effort=$2; shift 2 ;;
    -C) workdir=$2; shift 2 ;;
    exec|--json|--ignore-user-config|--ignore-rules|--skip-git-repo-check|-) shift ;;
    *) exit 90 ;;
  esac
done
[ "$sandbox" = read-only ] && [ "$effort" = "model_reasoning_effort=\"${FAKE_EXPECTED_EFFORT:-high}\"" ] || exit 91
[ "$model" = "${FAKE_EXPECTED_MODEL:-gpt-5.6-terra}" ] || exit 92
case "$schema" in */plugins/advisor/advisor-response.schema.json) ;; *) exit 93 ;; esac
case "$output" in "$CODEX_HOME"/.tmp/advisor-transport/run.*/response.*.json) ;; *) exit 94 ;; esac
case "$workdir" in "$CODEX_HOME"/.tmp/advisor-transport/run.*/workdir.*) ;; *) exit 95 ;; esac
[ "$(stat -f '%Lp' "$(dirname "$output")" 2>/dev/null || stat -c '%a' "$(dirname "$output")")" = 700 ] || exit 96

attempt=1
if [ -n "${FAKE_CODEX_COUNT_FILE-}" ]; then
  [ ! -f "$FAKE_CODEX_COUNT_FILE" ] || attempt=$(($(cat "$FAKE_CODEX_COUNT_FILE") + 1))
  printf '%s\n' "$attempt" >"$FAKE_CODEX_COUNT_FILE"
fi
if [ -n "${FAKE_CODEX_PROMPT_DIR-}" ]; then
  dd of="$FAKE_CODEX_PROMPT_DIR/attempt.$attempt.txt" 2>/dev/null
else
  dd of=/dev/null 2>/dev/null
fi
[ -z "${FAKE_CODEX_MARKER-}" ] || : >"$FAKE_CODEX_MARKER"
if [ "${FAKE_CODEX_CASE-valid}" = heartbeat ]; then sleep 11; fi
case "$attempt" in
  1) child=dddddddd-dddd-7ddd-8ddd-dddddddddddd ;;
  2) child=abababab-abab-7aba-8aba-abababababab ;;
  *) exit 97 ;;
esac
case "${FAKE_CODEX_CASE-valid}:$attempt" in
  launcher-failure:*) exit 98 ;;
  same-session:*) child=${FAKE_PARENT_ID:?} ;;
  retry-reused-child:2) child=dddddddd-dddd-7ddd-8ddd-dddddddddddd ;;
esac

valid_response() {
  printf '%s\n' '{"recommendation":"  neutral   path  ","why":"reason with\nspacing","strongest_objection":"objection","change_my_mind":"contrary evidence","acceptance_checks":["first check"," second   check "],"risks":"none","follow_up_areas":"none"}' >"$output"
}
neutral_22_response() {
  printf '%s\n' \
    'ADVISOR RESPONSE' \
    'RECOMMENDATION: neutral path' \
    '' \
    'WHY: neutral reason' \
    '' \
    'STRONGEST OBJECTION: neutral objection' \
    '' \
    'CHANGE MY MIND: neutral evidence' \
    '' \
    'ACCEPTANCE CHECKS:' \
    '- neutral check 1' \
    '- neutral check 2' \
    '- neutral check 3' \
    '- neutral check 4' \
    '- neutral check 5' \
    '- neutral check 6' \
    '- neutral check 7' \
    '- neutral check 8' \
    '' \
    'RISKS: none' \
    '' \
    'FOLLOW-UP AREAS: none' >"$output"
}

case "${FAKE_CODEX_CASE-valid}:$attempt" in
  neutral-22-first-valid-second:1|retry-reused-child:1|runtime-invalid-second:1) neutral_22_response ;;
  legacy-text:*) neutral_22_response ;;
  empty-output:*) : >"$output" ;;
  invalid-twice:*) printf '%s\n' '{"recommendation":"path"' >"$output" ;;
  concatenated:*)
    printf '%s\n' \
      '{"recommendation":"path","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"risks":"none","follow_up_areas":"none"}' \
      '{"recommendation":"path","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"risks":"none","follow_up_areas":"none"}' >"$output"
    ;;
  truncated:*) printf '%s\n' '{"recommendation":"DO_NOT_LEAK_REJECTED"' >"$output" ;;
  non-object:*) printf '%s\n' '["not","an","object"]' >"$output" ;;
  duplicate-scalar:*) printf '%s\n' '{"recommendation":"path","why":"first","why":"DO_NOT_LEAK_REJECTED","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"risks":"none","follow_up_areas":"none"}' >"$output" ;;
  duplicate-array:*) printf '%s\n' '{"recommendation":"path","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["first"],"acceptance_checks":["second"],"risks":"none","follow_up_areas":"none"}' >"$output" ;;
  container-scalar-overwrite:*) printf '%s\n' '{"recommendation":"path","why":{"nested":"DO_NOT_LEAK_REJECTED"},"why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"risks":"none","follow_up_areas":"none"}' >"$output" ;;
  missing:*) printf '%s\n' '{"recommendation":"path","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"follow_up_areas":"none"}' >"$output" ;;
  extra:*) printf '%s\n' '{"recommendation":"path","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"risks":"none","follow_up_areas":"none","extra":"DO_NOT_LEAK_REJECTED"}' >"$output" ;;
  wrong-type:*) printf '%s\n' '{"recommendation":7,"why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"risks":"none","follow_up_areas":"none"}' >"$output" ;;
  noncontiguous-array:*) printf '%s\n' '{"recommendation":"path","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["first",{"nested":"DO_NOT_LEAK_REJECTED"},"third"],"risks":"none","follow_up_areas":"none"}' >"$output" ;;
  blank-scalar:*) printf '%s\n' '{"recommendation":"path","why":"  \n ","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"risks":"none","follow_up_areas":"none"}' >"$output" ;;
  blank-array-item:*) printf '%s\n' '{"recommendation":"path","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"," \t "],"risks":"none","follow_up_areas":"none"}' >"$output" ;;
  empty-array:*) printf '%s\n' '{"recommendation":"path","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":[],"risks":"none","follow_up_areas":"none"}' >"$output" ;;
  *) valid_response ;;
esac

if [ -n "${FAKE_CODEX_RESPONSE_CAPTURE_DIR-}" ]; then
  cp "$output" "$FAKE_CODEX_RESPONSE_CAPTURE_DIR/attempt.$attempt.txt"
fi

if [ "${FAKE_CODEX_CASE-valid}" = concurrent ]; then
  consultation_dir=$(dirname "$output")
  slot=${FAKE_CODEX_CONCURRENT_SLOT:?}
  printf '%s\n' "$consultation_dir" >"$FAKE_CODEX_SYNC_DIR/dir.$slot"
  : >"$FAKE_CODEX_SYNC_DIR/ready.$slot"
  cycles=0
  while [ ! -e "$FAKE_CODEX_SYNC_DIR/ready.1" ] || [ ! -e "$FAKE_CODEX_SYNC_DIR/ready.2" ]; do
    cycles=$((cycles + 1)); [ "$cycles" -le 200 ] || exit 99; sleep 0.05
  done
  if [ "$slot" -eq 2 ]; then
    cycles=0
    while [ ! -e "$FAKE_CODEX_SYNC_DIR/release.2" ]; do
      cycles=$((cycles + 1)); [ "$cycles" -le 200 ] || exit 100; sleep 0.05
    done
    [ -d "$consultation_dir" ] || exit 101
    child=cdcdcdcd-cdcd-7dcd-8dcd-cdcdcdcdcdcd
  fi
fi

rollout=$CODEX_HOME/sessions/2026/08/30/rollout-fake-$child.jsonl
runtime_policy=read-only
case "${FAKE_CODEX_CASE-valid}:$attempt" in runtime-invalid-first:*|runtime-invalid-second:2) runtime_policy=workspace-write ;; esac
runtime_originator=codex_exec
case "${FAKE_CODEX_CASE-valid}" in desktop-valid) runtime_originator='Codex Desktop' ;; provenance-mismatch) runtime_originator='Codex desktop' ;; esac
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$child\",\"source\":\"exec\",\"originator\":\"$runtime_originator\"}}" \
  "{\"type\":\"turn_context\",\"payload\":{\"model\":\"$model\",\"effort\":\"high\",\"sandbox_policy\":{\"type\":\"$runtime_policy\"},\"permission_profile\":{\"type\":\"managed\"}}}" >"$rollout"
printf '%s\n' "{\"type\":\"thread.started\",\"thread_id\":\"$child\"}"
if [ "${FAKE_CODEX_CASE-valid}" = duplicate-thread ]; then
  printf '%s\n' '{"type":"thread.started","thread_id":"34343434-3434-7343-8343-343434343434"}'
fi
''', encoding='utf-8')
PY
python3 - "$fake_bin/jq" "$real_jq" <<'PY'
from pathlib import Path
import sys
target, real_jq = sys.argv[1:]
Path(target).write_text(f'''#!/bin/sh
set -eu
if [ "${{FAKE_JQ_RENDER_FAILURE-}}" = 1 ] && [ "${{1-}}" = -r ]; then
  case "${{2-}}" in *'"ADVISOR RESPONSE"'*) exit 70 ;; esac
fi
exec {real_jq!r} "$@"
''', encoding='utf-8')
PY
chmod 700 "$fake_bin/codex" "$fake_bin/jq"

transport_parent=56565656-5656-7565-8565-565656565656
valid_packet=$tmp/valid-packet.txt
printf '%s\n' DECISION 'question' CONTEXT 'evidence' OPTIONS 'choice' BOUNDARIES 'limits' REQUEST 'challenge' >"$valid_packet"
transport_out=$tmp/transport-out.json
transport_err=$tmp/transport-err.txt
assert_transport_clean() {
  [ -d "$fake_home/.tmp/advisor-transport" ] || return 0
  [ "$(find "$fake_home/.tmp/advisor-transport" -mindepth 1 -maxdepth 1 -type d -name 'run.*' | wc -l | tr -d ' ')" -eq 0 ] || fail "private consultation directory survived wrapper exit"
}
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=valid FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$transport_out" 2>"$transport_err" || {
    sed -n '1,20p' "$transport_err" >&2
    fail "valid fake transport failed"
  }
[ "$(wc -l <"$transport_out" | tr -d ' ')" -eq 1 ] || fail "transport stdout was not one JSON line"
jq -e '.status=="completed" and .runtime.agent_role=="advisor-terra" and .runtime.model=="gpt-5.6-terra" and .runtime.effort=="high" and .runtime.sandbox_policy_type=="read-only" and .runtime.transport=="codex-exec" and .response=="ADVISOR RESPONSE\nRECOMMENDATION: neutral path\nWHY: reason with spacing\nSTRONGEST OBJECTION: objection\nCHANGE MY MIND: contrary evidence\nACCEPTANCE CHECKS: first check; second check\nRISKS: none\nFOLLOW-UP AREAS: none\n"' "$transport_out" >/dev/null || fail "valid transport JSON or canonical render mismatch"
assert_transport_clean
for progress_line in 'launching advisor-terra (gpt-5.6-terra, high, read-only)' 'inspecting persisted runtime evidence' 'consultation verified'; do
  grep -Fq "$progress_line" "$transport_err" || fail "transport stderr progress missing: $progress_line"
done

astra_transport_out=$tmp/astra-transport-out.json
astra_transport_err=$tmp/astra-transport-err.txt
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=valid FAKE_EXPECTED_MODEL=gpt-6-astra FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-astra --parent-thread "$transport_parent" <"$valid_packet" >"$astra_transport_out" 2>"$astra_transport_err" || {
    sed -n '1,20p' "$astra_transport_err" >&2
    fail "valid fake Astra transport failed"
  }
jq -e '.status=="completed" and .selection.tier=="opt-in" and .selection.model=="gpt-6-astra" and .selection.effort=="high" and .selection.source=="explicit-fixed" and .runtime.model=="gpt-6-astra" and .runtime.effort=="high" and .runtime.sandbox_policy_type=="read-only"' "$astra_transport_out" >/dev/null || fail "explicit Astra alias did not remain fixed and isolated"
if grep -Eq 'tier=(standard|specialist); model=gpt-6-astra|role=advisor-tier-(standard|specialist).*gpt-6-astra' "$transport"; then fail "Astra leaked into a normal tier route"; fi
pass "explicit Astra/high fixed alias is isolated from Standard/Specialist defaults"

heartbeat_err=$tmp/heartbeat-err.txt
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=heartbeat FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$tmp/heartbeat-out.json" 2>"$heartbeat_err" || fail "heartbeat transport fixture failed"
[ "$(grep -Fc 'owned child invocation still running' "$heartbeat_err")" -eq 1 ] || fail "heartbeat was not emitted once and cleaned up"
[ "$(wc -l <"$tmp/heartbeat-out.json" | tr -d ' ')" -eq 1 ] || fail "heartbeat fixture contaminated stdout"
assert_transport_clean

neutral_capture=$tmp/neutral-capture; neutral_prompts=$tmp/neutral-prompts
mkdir "$neutral_capture" "$neutral_prompts"
retry_count=$tmp/retry-count
retry_err=$tmp/retry-err.txt
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=neutral-22-first-valid-second FAKE_CODEX_COUNT_FILE="$retry_count" FAKE_CODEX_RESPONSE_CAPTURE_DIR="$neutral_capture" FAKE_CODEX_PROMPT_DIR="$neutral_prompts" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$tmp/retry-out.json" 2>"$retry_err" || fail "neutral 22-line response did not retry successfully"
[ "$(cat "$retry_count")" -eq 2 ] || fail "neutral 22-line response did not launch exactly one retry"
[ "$(wc -l <"$neutral_capture/attempt.1.txt" | tr -d ' ')" -eq 22 ] || fail "neutral regression was not exactly 22 lines"
awk 'NR==1&&$0=="ADVISOR RESPONSE"{a++} NR==2&&$0~/^RECOMMENDATION:/{a++} NR==4&&$0~/^WHY:/{a++} NR==6&&$0~/^STRONGEST OBJECTION:/{a++} NR==8&&$0~/^CHANGE MY MIND:/{a++} NR==10&&$0=="ACCEPTANCE CHECKS:"{a++} NR==20&&$0~/^RISKS:/{a++} NR==22&&$0~/^FOLLOW-UP AREAS:/{a++} (NR==3||NR==5||NR==7||NR==9||NR==19||NR==21)&&$0==""{b++} NR>=11&&NR<=18&&$0~/^- neutral check [1-8]$/{c++} END{exit !(a==8&&b==6&&c==8)}' "$neutral_capture/attempt.1.txt" || fail "neutral 22-line structure mismatch"
grep -Fq 'class=legacy-text field=response' "$neutral_prompts/attempt.2.txt" || fail "corrective retry omitted redacted legacy-text class"
if grep -Fq 'neutral check 1' "$neutral_prompts/attempt.2.txt"; then fail "corrective retry leaked rejected response"; fi
jq -e '.status=="completed" and (.response|startswith("ADVISOR RESPONSE\nRECOMMENDATION:"))' "$tmp/retry-out.json" >/dev/null || fail "retry did not return only the valid second response"
grep -Fq 'runtime-valid response failed validation; launching one fresh corrective retry (class=legacy-text field=response)' "$retry_err" || fail "corrective retry progress missing from stderr"
assert_transport_clean

twice_count=$tmp/twice-count
twice_err=$tmp/twice-error
if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=invalid-twice FAKE_CODEX_COUNT_FILE="$twice_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>"$twice_err"; then fail "transport accepted two invalid responses"; fi
[ "$(cat "$twice_count")" -eq 2 ] || fail "invalid-twice did not stop after one retry"
grep -Fq 'class=invalid-json field=response' "$twice_err" || fail "invalid JSON diagnostic mismatch"
assert_transport_clean

reused_count=$tmp/reused-count
reused_err=$tmp/reused-err.txt
if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=retry-reused-child FAKE_CODEX_COUNT_FILE="$reused_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>"$reused_err"; then fail "transport accepted a retry that reused the first child"; fi
[ "$(cat "$reused_count")" -eq 2 ] || fail "reused-child retry did not stop after exactly two launches"
grep -Fq 'retry reused the first child thread' "$reused_err" || fail "reused-child retry was not classified as terminal identity failure"

for terminal_case in launcher-failure duplicate-thread same-session runtime-invalid-first; do
  terminal_count=$tmp/terminal-count-$terminal_case
  if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE="$terminal_case" FAKE_CODEX_COUNT_FILE="$terminal_count" FAKE_PARENT_ID="$transport_parent" \
    sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>&1; then fail "transport accepted terminal case: $terminal_case"; fi
  [ "$(cat "$terminal_count")" -eq 1 ] || fail "transport retried terminal case: $terminal_case"
done

second_runtime_count=$tmp/terminal-count-runtime-invalid-second
if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=runtime-invalid-second FAKE_CODEX_COUNT_FILE="$second_runtime_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>&1; then fail "transport accepted runtime-invalid retry child"; fi
[ "$(cat "$second_runtime_count")" -eq 2 ] || fail "runtime-invalid second child launched other than two total children"
assert_transport_clean

PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=desktop-valid FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$tmp/desktop-transport-out.json" 2>"$tmp/desktop-transport-err.txt" || fail "transport rejected exact Codex Desktop provenance"
jq -e '.status=="completed" and .runtime.transport=="codex-exec" and .runtime.sandbox_policy_type=="read-only"' "$tmp/desktop-transport-out.json" >/dev/null || fail "desktop transport result mismatch"
if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=provenance-mismatch FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>"$tmp/provenance-transport-err.txt"; then fail "transport accepted near-match provenance"; fi
grep -Fq 'runtime_provenance_mismatch' "$tmp/provenance-transport-err.txt" || fail "transport did not preserve provenance mismatch category"

misordered_packet=$tmp/misordered-packet.txt
printf '%s\n' CONTEXT 'evidence' DECISION 'question' OPTIONS 'choice' BOUNDARIES 'limits' REQUEST 'challenge' >"$misordered_packet"
marker=$tmp/fake-codex-called
if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_MARKER="$marker" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$misordered_packet" >/dev/null 2>&1; then fail "transport accepted misordered packet headings"; fi
[ ! -e "$marker" ] || fail "transport invoked codex before rejecting packet order"

for diagnostic_spec in \
  'empty-output:empty-output:response' \
  'legacy-text:legacy-text:response' \
  'concatenated:duplicate-or-overwritten-field:recommendation' \
  'truncated:invalid-json:response' \
  'non-object:wrong-type:response' \
  'duplicate-scalar:duplicate-or-overwritten-field:why' \
  'duplicate-array:duplicate-or-overwritten-field:acceptance_checks' \
  'container-scalar-overwrite:duplicate-or-overwritten-field:why' \
  'missing:missing-field:risks' \
  'extra:extra-field:response' \
  'wrong-type:wrong-type:recommendation' \
  'noncontiguous-array:invalid-acceptance-checks:acceptance_checks' \
  'blank-scalar:blank-field:why' \
  'blank-array-item:blank-field:acceptance_checks' \
  'empty-array:invalid-acceptance-checks:acceptance_checks'; do
  rejected_case=${diagnostic_spec%%:*}
  diagnostic_remainder=${diagnostic_spec#*:}
  expected_class=${diagnostic_remainder%%:*}
  expected_field=${diagnostic_remainder#*:}
  rejected_count=$tmp/rejected-count-$rejected_case
  rejected_out=$tmp/rejected-out-$rejected_case.txt
  rejected_err=$tmp/rejected-err-$rejected_case.txt
  if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE="$rejected_case" FAKE_CODEX_COUNT_FILE="$rejected_count" FAKE_PARENT_ID="$transport_parent" \
    sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$rejected_out" 2>"$rejected_err"; then
    fail "transport accepted fake case: $rejected_case"
  fi
  [ "$(cat "$rejected_count")" -eq 2 ] || fail "response validation case did not exercise exactly one fresh retry: $rejected_case"
  grep -Fq "class=$expected_class field=$expected_field" "$rejected_err" || fail "response validation diagnostic mismatch: $rejected_case"
  if grep -Fq 'DO_NOT_LEAK_REJECTED' "$rejected_out" "$rejected_err"; then fail "response validation leaked rejected content: $rejected_case"; fi
  assert_transport_clean
done

render_count=$tmp/render-count
render_err=$tmp/render-err
if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=valid FAKE_JQ_RENDER_FAILURE=1 FAKE_CODEX_COUNT_FILE="$render_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>"$render_err"; then fail "transport accepted render failure"; fi
[ "$(cat "$render_count")" -eq 2 ] || fail "render failure did not stop after one corrective retry"
grep -Fq 'class=render-failure field=response' "$render_err" || fail "render failure diagnostic mismatch"
assert_transport_clean

truncated_fixture=$tmp/truncated-parser.json
printf '%s\n' '{"recommendation":"path"' >"$truncated_fixture"
streaming_status=0
jq --stream -c 'select(length == 2)' "$truncated_fixture" >"$tmp/truncated-parser-stream.jsonl" 2>/dev/null || streaming_status=$?
[ "$streaming_status" -ne 0 ] || fail "streaming parser status did not reject truncated JSON"

concurrent_sync=$tmp/concurrent-sync; mkdir "$concurrent_sync"
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=concurrent FAKE_CODEX_CONCURRENT_SLOT=1 FAKE_CODEX_SYNC_DIR="$concurrent_sync" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$tmp/concurrent-1.json" 2>"$tmp/concurrent-1.err" &
concurrent_pid_1=$!
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=concurrent FAKE_CODEX_CONCURRENT_SLOT=2 FAKE_CODEX_SYNC_DIR="$concurrent_sync" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$tmp/concurrent-2.json" 2>"$tmp/concurrent-2.err" &
concurrent_pid_2=$!
wait "$concurrent_pid_1" || fail "first concurrent transport failed"
: >"$concurrent_sync/release.2"
wait "$concurrent_pid_2" || fail "second concurrent transport lost its private directory"
[ "$(cat "$concurrent_sync/dir.1")" != "$(cat "$concurrent_sync/dir.2")" ] || fail "concurrent transports reused a consultation directory"
jq -e '.status=="completed"' "$tmp/concurrent-1.json" "$tmp/concurrent-2.json" >/dev/null || fail "concurrent transport result mismatch"
assert_transport_clean
pass "run-advisor behavioral transport: strict streamed JSON, duplicate/overwrite defense, nonblank semantics, exact eight-line renderer, neutral 22-line corrective retry, redacted diagnostics, two-child ceiling, terminal runtime failures, mode-0700 cleanup, concurrency isolation, stderr progress, and single JSON stdout"
