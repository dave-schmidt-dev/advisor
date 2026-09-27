# shellcheck shell=sh
# Sourced by plugins/advisor/scripts/verify.sh; do not run directly.
python3 - "$tmp/result.json" "$tmp/rerun-result.json" "$tmp/unnecessary-rerun-result.json" "$tmp/boundary-three-of-four.json" "$tmp/boundary-two-of-four.json" "$fixtures" <<'PY'
import copy,json,sys
result,rerun_result,unnecessary_result,threshold_pass_result,threshold_fail_result,fixtures=sys.argv[1:]; items=json.load(open(fixtures))["cases"]
schemas=[]; n=0
def trial(route,risk="standard"):
  selected_role="advisor-terra" if risk=="standard" else "advisor-sol"
  selected_model="gpt-5.6-terra" if risk=="standard" else "gpt-6-sol"
  return {"route":route,"advisor_count":1 if route=="consult" else 0,"roles":[selected_role] if route=="consult" else [],"freshness":"distinct_receiver_thread" if route=="consult" else "none","model":selected_model if route=="consult" else "none","effort":"high" if route=="consult" else "none","sandbox":"read-only" if route=="consult" else "none","risk":risk,"selected_role":selected_role,"selected_model":selected_model}
for name,flag in (("v1",False),("v2",True)):
  cases=[]
  for c in items:
    route=c["expected"]; n+=1
    cases.append({"id":c["id"],"final_route":route,"trials":[trial(route,c["risk"])]})
  schemas.append({"name":name,"multi_agent_v2":flag,"cases":cases})
data={"status":"pass","redacted":True,"subscription_only":True,"overage_disabled":True,"session_cap":40,"sessions_run":n,"nonmutation":{"live_home":{"before":"a","after":"a","unchanged":True},"marketplace":{"before":"b","after":"b","unchanged":True}},"schemas":schemas}
json.dump(data,open(result,"w"),indent=2)

# In each schema, force one boundary case to miss on trial 1, then match on trials
# 2 and 3. The evaluator must accept the bounded 2-of-3 majority and account for
# exactly four extra sessions across both schemas.
rerun=copy.deepcopy(data)
for schema in rerun["schemas"]:
  case=next(c for c in schema["cases"] if c["id"]=="boundary-explicit-advisor")
  case["trials"]=[trial("skip","standard"),trial("consult","standard"),trial("consult","standard")]
rerun["sessions_run"] += 4
json.dump(rerun,open(rerun_result,"w"),indent=2)

# Three trials are invalid when the first trial already matched. Preserve the same
# 2-of-3 final route so rejection proves the unnecessary-rerun guard specifically.
unnecessary=copy.deepcopy(rerun)
for schema in unnecessary["schemas"]:
  case=next(c for c in schema["cases"] if c["id"]=="boundary-explicit-advisor")
  case["trials"]=[trial("consult","standard"),trial("skip","standard"),trial("consult","standard")]
json.dump(unnecessary,open(unnecessary_result,"w"),indent=2)

# Hold trial counts, role identity, freshness, pins, and session accounting valid
# while exercising the per-schema boundary_ok threshold itself. Exactly one wrong
# boundary final route leaves 3/4 matches and must pass; two leave 2/4 and must fail.
threshold_pass=copy.deepcopy(data)
for schema in threshold_pass["schemas"]:
  case=next(c for c in schema["cases"] if c["id"]=="boundary-no-delegation")
  case["final_route"]="consult"
  case["trials"]=[trial("consult","standard")]
json.dump(threshold_pass,open(threshold_pass_result,"w"),indent=2)

threshold_fail=copy.deepcopy(threshold_pass)
for schema in threshold_fail["schemas"]:
  case=next(c for c in schema["cases"] if c["id"]=="boundary-explicit-advisor")
  case["final_route"]="skip"
  case["trials"]=[trial("skip","standard")]
json.dump(threshold_fail,open(threshold_fail_result,"w"),indent=2)
PY
sh "$evaluator" --verify-result --result "$tmp/result.json" >/dev/null
sh "$evaluator" --verify-result --result "$tmp/rerun-result.json" >/dev/null
if sh "$evaluator" --verify-result --result "$tmp/unnecessary-rerun-result.json" >/dev/null 2>&1; then
  fail "evaluator accepted an unnecessary three-trial boundary rerun"
fi
sh "$evaluator" --verify-result --result "$tmp/boundary-three-of-four.json" >/dev/null
if sh "$evaluator" --verify-result --result "$tmp/boundary-two-of-four.json" >/dev/null 2>&1; then
  fail "evaluator accepted only two of four matching boundary cases"
fi
printf '%s\n' '{"status":"unavailable","reason_type":"role_unavailable","redacted":true}' >"$tmp/unavailable.json"
if sh "$evaluator" --verify-result --result "$tmp/unavailable.json" >/dev/null 2>&1; then fail "unavailable accepted without flag"; fi
sh "$evaluator" --verify-result --result "$tmp/unavailable.json" --allow-unavailable >/dev/null
printf '%s\n' '{"status":"unavailable","reason_type":"parent_runtime_unavailable","redacted":true}' >"$tmp/parent-unavailable.json"
sh "$evaluator" --verify-result --result "$tmp/parent-unavailable.json" --allow-unavailable >/dev/null
printf '%s\n' '{"status":"unavailable","reason_type":"runtime_evidence_unavailable","redacted":true,"nonmutation":{"live_home":{"before":"a","after":"a","unchanged":true},"marketplace":{"before":"b","after":"b","unchanged":true}}}' >"$tmp/unavailable-with-pair.json"
sh "$evaluator" --verify-result --result "$tmp/unavailable-with-pair.json" --allow-unavailable >/dev/null
printf '%s\n' '{"status":"unavailable","reason_type":"runtime_evidence_unavailable","redacted":true,"nonmutation":{"live_home":{"before":"a","after":"changed","unchanged":false},"marketplace":{"before":"b","after":"b","unchanged":true}}}' >"$tmp/unavailable-bad-pair.json"
if sh "$evaluator" --verify-result --result "$tmp/unavailable-bad-pair.json" --allow-unavailable >/dev/null 2>&1; then
  fail "evaluator accepted invalid paired nonmutation evidence on unavailable result"
fi
printf '%s\n' '{"status":"unavailable","reason_type":"role_unavailable","redacted":true,"api_key":"forbidden-value"}' >"$tmp/unavailable-secret.json"
if sh "$evaluator" --verify-result --result "$tmp/unavailable-secret.json" --allow-unavailable >/dev/null 2>&1; then
  fail "evaluator accepted a secret-like value in an unavailable result"
fi
for accepted_version in \
  'codex-cli 0.150.1' 'codex 0.150.1' \
  'codex-cli 1.2.3-beta.1' 'codex 1.2.3+build.7'; do
  ADVISOR_VALIDATE_CLI_VERSION=$accepted_version sh "$evaluator" ||
    fail "evaluator rejected supported Codex CLI version: $accepted_version"
done
for rejected_version in \
  'other-cli 0.150.1' 'codex-cli' 'codex-cli 0.150' \
  'codex-cli 0.150.1 unrelated' 'codex-cli 1.2.3-beta..1' \
  'codex-cli 1.2.3+build+other' 'codex-cli 0.150.1
other-cli 9.9.9'; do
  if ADVISOR_VALIDATE_CLI_VERSION=$rejected_version sh "$evaluator" >/dev/null 2>&1; then
    fail "evaluator accepted malformed or unrelated CLI version: $rejected_version"
  fi
done
grep -Fq 'validate_cli_version "$version" || write_unavailable cli_incompatible' "$evaluator" || fail "live CLI version path bypasses the tested validator"
feature_false='other_feature stable true
multi_agent_v2                           stable             false
another_feature experimental false'
feature_true='other_feature stable false
  multi_agent_v2    beta    true  '
ADVISOR_VALIDATE_FEATURE_STATE=$feature_false ADVISOR_EXPECTED_FEATURE_STATE=false sh "$evaluator" ||
  fail "evaluator rejected exact false feature-state evidence"
ADVISOR_VALIDATE_FEATURE_STATE=$feature_true ADVISOR_EXPECTED_FEATURE_STATE=true sh "$evaluator" ||
  fail "evaluator rejected exact true feature-state evidence"
for rejected_feature_fixture in \
  'other_feature stable false' \
  'multi_agent_v2 removed false' \
  'multi_agent_v2 stable true' \
  'multi_agent_v2 stable false
multi_agent_v2 stable false' \
  'multi_agent_v2 stable false
multi_agent_v2 stable true' \
  'multi_agent_v2
stable false' \
  'note multi_agent_v2 stable false' \
  'multi_agent_v2 stable false extra'; do
  if ADVISOR_VALIDATE_FEATURE_STATE=$rejected_feature_fixture ADVISOR_EXPECTED_FEATURE_STATE=false sh "$evaluator" >/dev/null 2>&1; then
    fail "evaluator accepted missing, removed, opposite, duplicate, conflicting, or malformed feature-state evidence"
  fi
done
if ADVISOR_VALIDATE_FEATURE_STATE='multi_agent_v2 stable false' ADVISOR_EXPECTED_FEATURE_STATE=maybe sh "$evaluator" >/dev/null 2>&1; then
  fail "evaluator accepted an invalid requested feature state"
fi
grep -Fq 'validate_feature_state "$feature_output" "$feature" || write_unavailable feature_state_unavailable' "$evaluator" || fail "live feature-state path bypasses the tested validator"
ADVISOR_VALIDATE_EPHEMERAL_ROUTE=unavailable sh "$evaluator" ||
  fail "evaluator rejected the required ephemeral unavailable route"
for rejected_ephemeral_route in consult skip invalid ''; do
  if ADVISOR_VALIDATE_EPHEMERAL_ROUTE=$rejected_ephemeral_route sh "$evaluator" >/dev/null 2>&1; then
    fail "evaluator accepted a non-unavailable ephemeral route"
  fi
done
grep -Fq 'require_ephemeral_unavailable_route "$(jq -r '\''.route'\'' "$evidence")" || fail "ephemeral trial bypassed unavailable parent preflight"' "$evaluator" ||
  fail "live ephemeral route bypasses the tested fail-closed validator"

python3 - "$tmp/runtime-events" <<'PY'
import copy, json, sys
from pathlib import Path

root=Path(sys.argv[1]); root.mkdir()
root_id="11111111-1111-7111-8111-111111111111"
child_id="22222222-2222-7222-8222-222222222222"
def message(route, extra=""):
    return {"type":"item.completed","item":{"type":"agent_message","text":extra+f"ADVISOR_EVAL route={route}"}}
def spawn(role="advisor-sol",model="gpt-6-sol",**changes):
    item={"id":"spawn-1","type":"collab_tool_call","tool":"spawn_agent","receiver_thread_ids":[child_id],"receiver_agents":[{"agent_role":role,"thread_id":child_id}],"model":model,"reasoning_effort":"high","status":"completed"}
    item.update(changes)
    return {"type":"item.completed","item":item}
def write(name, events):
    (root/f"{name}.jsonl").write_text("".join(json.dumps(e)+"\n" for e in events),encoding="utf-8")
base=[{"type":"thread.started","thread_id":root_id},spawn(),message("consult","PRIVATE PROMPT MUST NOT SURVIVE\n")]
write("valid-consult",base)
started=copy.deepcopy(base[1]); started["type"]="item.started"; started["item"]["status"]="in_progress"
write("valid-lifecycle",[base[0],started,base[1],base[2]])
write("valid-terra",[{"type":"thread.started","thread_id":root_id},spawn("advisor-terra","gpt-5.6-terra"),message("consult")])
write("valid-skip",[{"type":"thread.started","thread_id":root_id},message("skip")])
write("valid-unavailable",[{"type":"thread.started","thread_id":root_id},message("unavailable","ADVISOR DECISION\nroute: unavailable\n")])
write("unavailable-call",[{"type":"thread.started","thread_id":root_id},message("unavailable","ADVISOR DECISION\nroute: unavailable\nADVISOR CALL\n")])
write("unavailable-spawn",[{"type":"thread.started","thread_id":root_id},message("unavailable","ADVISOR DECISION\nroute: unavailable\n"),spawn(),message("unavailable")])
write("fabricated-no-spawn",[{"type":"thread.started","thread_id":root_id},message("consult","advisor_count=1 role=advisor-sol model=gpt-6-sol\n")])
write("empty-wait",[{"type":"thread.started","thread_id":root_id},{"type":"item.completed","item":{"type":"collab_tool_call","tool":"wait","receiver_thread_ids":[]}},message("consult")])
write("duplicate-spawn",base[:2]+[copy.deepcopy(base[1]),base[2]])
write("duplicate-started",[base[0],started,copy.deepcopy(started),base[1],base[2]])
extra_spawn=copy.deepcopy(base[1]); extra_spawn["type"]="item.started"; extra_spawn["item"]["id"]="spawn-2"
write("extra-uncompleted-spawn",[base[0],extra_spawn,base[1],base[2]])
for name,changes in (
    ("wrong-role",{"receiver_agents":[{"agent_role":"advisor-terra","thread_id":child_id}]}),
    ("wrong-model",{"model":"gpt-5.6-terra"}),
    ("wrong-effort",{"reasoning_effort":"medium"}),
    ("root-equals-child",{"receiver_thread_ids":[root_id],"receiver_agents":[{"agent_role":"advisor-sol","thread_id":root_id}]}),
    ("noncompleted",{"status":"failed"}),
):
    write(name,[{"type":"thread.started","thread_id":root_id},spawn(**changes),message("consult")])
PY
events=$tmp/runtime-events
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-consult.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-consult.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-6-sol sh "$evaluator"
jq -e '.route=="consult" and .advisor_count==1 and .roles==["advisor-sol"] and .freshness=="distinct_receiver_thread" and .model=="gpt-6-sol" and .effort=="high" and .sandbox=="read-only"' "$tmp/valid-consult.json" >/dev/null || fail "valid Sol consult spawn evidence was not derived exactly"
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-lifecycle.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-lifecycle.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-6-sol sh "$evaluator"
jq -e '.route=="consult" and .advisor_count==1 and .roles==["advisor-sol"]' "$tmp/valid-lifecycle.json" >/dev/null || fail "one logical spawn lifecycle was not accepted"
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-terra.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-terra.json" ADVISOR_EXPECTED_ROLE=advisor-terra ADVISOR_EXPECTED_MODEL=gpt-5.6-terra sh "$evaluator"
jq -e '.role==null and .roles==["advisor-terra"] and .model=="gpt-5.6-terra" and .effort=="high"' "$tmp/valid-terra.json" >/dev/null || fail "valid Terra consult spawn evidence was not derived exactly"
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-skip.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-skip.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-6-sol sh "$evaluator"
jq -e '.route=="skip" and .advisor_count==0 and .roles==[]' "$tmp/valid-skip.json" >/dev/null || fail "valid skip/no-spawn evidence was not derived exactly"
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-unavailable.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-unavailable.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-6-sol sh "$evaluator"
jq -e '.route=="unavailable" and .advisor_count==0 and .roles==[] and .freshness=="none"' "$tmp/valid-unavailable.json" >/dev/null || fail "valid unavailable/no-spawn preflight evidence was not derived exactly"
for rejected_events in unavailable-call unavailable-spawn fabricated-no-spawn empty-wait duplicate-spawn duplicate-started extra-uncompleted-spawn wrong-role wrong-model wrong-effort root-equals-child noncompleted; do
  if ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/$rejected_events.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/rejected.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-6-sol sh "$evaluator" >/dev/null 2>&1; then
    fail "runtime evidence parser accepted: $rejected_events"
  fi
done
if grep -Eq '11111111|22222222|PRIVATE PROMPT' "$tmp/valid-consult.json"; then fail "runtime evidence output leaked raw prompt or thread identifiers"; fi
grep -Fq 'parse_runtime_evidence "$raw" "$evidence" "$selected_role" "$selected_model" || write_unavailable runtime_evidence_unavailable' "$evaluator" || fail "live path bypasses the tested runtime evidence parser"
grep -Fq 'route=unavailable' "$evaluator" || fail "ephemeral evaluator does not expect unavailable preflight"
grep -Fq 'do not emit ADVISOR CALL, and do not spawn a child' "$evaluator" || fail "ephemeral evaluator permits a call or child spawn"

for policy_case in \
  'standard:advisor-terra gpt-5.6-terra' 'STANDARD:advisor-terra gpt-5.6-terra' \
  'specialist:advisor-sol gpt-6-sol' 'SPECIALIST:advisor-sol gpt-6-sol'; do
  risk=${policy_case%%:*}; wanted=${policy_case#*:}
  actual=$(ADVISOR_SELECT_FOR_RISK=$risk sh "$evaluator")
  [ "$actual" = "$wanted" ] || fail "wrong advisor role/model selection for $risk"
done
for invalid_risk in unknown security-adjacent important; do
  if ADVISOR_SELECT_FOR_RISK=$invalid_risk sh "$evaluator" >/dev/null 2>&1; then
    fail "advisor selection accepted unsupported risk: $invalid_risk"
  fi
done

for exact_flag in \
  'codex exec --json --ignore-user-config --ignore-rules --ephemeral "$feature_switch" multi_agent_v2' \
  '-C "$project" --sandbox read-only --skip-git-repo-check "$eval_prompt" </dev/null' \
  '-c "agents.advisor-terra.config_file=\"$runtime_home/agents/advisor-terra.toml\""' \
  '-c "agents.advisor-sol.config_file=\"$runtime_home/agents/advisor-sol.toml\""' \
  '-c "shell_environment_policy.set={CODEX_HOME=\"$runtime_home\"}"'; do
  grep -Fq -- "$exact_flag" "$evaluator" || fail "live isolation invocation omits: $exact_flag"
done
for fixture_link in \
  'ln -s "$plugin_dir/skills/consultation" "$project/.codex/skills/consultation"' \
  'ln -s "$plugin_dir" "$project/plugins/advisor"'; do
  grep -Fq "$fixture_link" "$evaluator" || fail "isolated project fixture omits: $fixture_link"
done
if grep -Eq 'CODEX_HOME=.*codex exec|auth\.json|codex plugin (add|marketplace)' "$evaluator"; then
  fail "live evaluator overrides parent auth, handles auth files, or mutates plugin state"
fi
grep -Fq 'codex features "$feature_switch" multi_agent_v2 list' "$evaluator" || fail "feature override confirmation omits the explicit boolean override"
grep -Fq "progress() { printf '%s\\n' \"EVAL: \$*\" >&2; }" "$evaluator" || fail "evaluator progress is not pinned to stderr"
grep -Fq "session_cap\":40" "$evaluator" || fail "evaluator does not write the pooled cap"
grep -Fq 'live_before=$(snapshot_live_state live-state-before)' "$evaluator" || fail "evaluator lacks scoped live-state before snapshot"
grep -Fq 'live_after=$(snapshot_live_state live-state-after)' "$evaluator" || fail "evaluator lacks scoped live-state after snapshot"
snapshot_before_line=$(grep -nF 'live_before=$(snapshot_live_state live-state-before)' "$evaluator" | awk -F: 'NR==1 {print $1}')
for dependency in codex jq; do
  dependency_line=$(grep -nF "command -v $dependency" "$evaluator" | awk -F: 'NR==1 {print $1}')
  [ "$snapshot_before_line" -lt "$dependency_line" ] || fail "$dependency absence bypasses paired nonmutation evidence"
done
for scoped_path in 'config.toml' 'agents skills plugins' 'auth/session/cache excluded'; do
  grep -Fq "$scoped_path" "$evaluator" || fail "live-state snapshot scope omits: $scoped_path"
done
if grep -Fq 'snapshot "$live_home"' "$evaluator"; then fail "evaluator hashes the entire authenticated Codex home"; fi
grep -Fq 'progress "$label snapshot started"' "$evaluator" || fail "snapshot start progress is missing"
grep -Fq 'progress "$label snapshot hashing: $count files"' "$evaluator" || fail "snapshot periodic file-count progress is missing"
grep -Fq 'if [ $((count % 100)) -eq 0 ]' "$evaluator" || fail "snapshot progress interval is not pinned to 100 files"
grep -Fq 'progress "$label snapshot complete ($count contract files; auth/session/cache excluded)"' "$evaluator" || fail "scoped snapshot completion progress is missing"
grep -Fq 'shasum -a 256 "$file" >>"$digest_lines"' "$evaluator" || fail "snapshot per-file digests are not isolated from stdout"
grep -Fq 'printf '\''%s\n'\'' "$digest"' "$evaluator" || fail "snapshot final digest stdout emission is missing"
snapshot_start_line=$(grep -nF 'progress "$label snapshot started"' "$evaluator" | awk -F: 'NR==1 {print $1}')
snapshot_find_line=$(grep -nF 'find "$live_home/$name" -type f -print' "$evaluator" | awk -F: 'NR==1 {print $1}')
[ "$snapshot_start_line" -lt "$snapshot_find_line" ] || fail "snapshot traversal can start before visible progress"
for phrase in \
  'marketplace before snapshot started' 'marketplace before snapshot complete (1 file)' \
  'marketplace after snapshot started' 'marketplace after snapshot complete (1 file)'; do
  grep -Fq "$phrase" "$evaluator" || fail "marketplace snapshot progress omits: $phrase"
done
for phrase in 'multi_agent_v2' 'ephemeral' 'route: unavailable' 'no `ADVISOR CALL`' 'persisted fixtures' 'subscription-only' 'overage' 'Progress goes' 'before/after digests'; do grep -Fqi "$phrase" "$operations" || fail "operations omits evaluator parity: $phrase"; done
pass "deterministic evaluator parsing, parent-unavailable ephemeral path, persisted read-only fixtures, exact pinned-role/model spawn evidence, lifecycle duplicate and extra-logical-spawn refusal, redaction, authenticated-parent isolation flags, mismatch reruns, Codex CLI and feature-state compatibility/refusal, typed unavailable, progress-visible snapshots, and nonmutation"
