#!/bin/sh
# Attended native trigger evaluator. Progress is stderr; result JSON is file-only.

set -eu
fail() { printf '%s\n' "ERROR: $*" >&2; exit 1; }
progress() { printf '%s\n' "EVAL: $*" >&2; }

validate_cli_version() {
  cli_version=$1
  case "$cli_version" in
    *'
'*) return 1 ;;
  esac
  printf '%s\n' "$cli_version" | LC_ALL=C grep -Eq '^(codex|codex-cli)[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
}

validate_feature_state() {
  feature_output=$1
  expected_state=$2
  case "$expected_state" in true|false) ;; *) return 1 ;; esac
  printf '%s\n' "$feature_output" | LC_ALL=C awk -v expected="$expected_state" '
    index($0, "multi_agent_v2") {
      mentions += 1
      if ($1 != "multi_agent_v2" || NF != 3 ||
          $2 !~ /^[[:alnum:]_-]+$/ || $2 == "removed" ||
          ($3 != "true" && $3 != "false") || $3 != expected) {
        valid = 0
      } else {
        valid += 1
      }
    }
    END { exit !(mentions == 1 && valid == 1) }
  '
}

select_advisor_role() {
  normalized=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$normalized" in
    *luna*|*spark*) printf '%s\n' advisor-terra ;;
    *) printf '%s\n' advisor-sol ;;
  esac
}

model_for_role() {
  case "$1" in advisor-terra) printf '%s\n' gpt-5.6-terra ;; advisor-sol) printf '%s\n' gpt-5.6-sol ;; *) return 1 ;; esac
}

parse_runtime_evidence() {
  raw_path=$1
  evidence_path=$2
  expected_role=$3
  expected_model=$4
  python3 - "$raw_path" "$evidence_path" "$expected_role" "$expected_model" <<'PY'
import json, re, sys
from pathlib import Path

raw_path, evidence_path = map(Path, sys.argv[1:3])
expected_role, expected_model = sys.argv[3:]
valid_pairs = {"advisor-terra":"gpt-5.6-terra", "advisor-sol":"gpt-5.6-sol"}
if valid_pairs.get(expected_role) != expected_model:
    raise SystemExit("unsupported expected role/model pair")
events = []
for line in raw_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if line.strip():
        event = json.loads(line)
        if not isinstance(event, dict):
            raise SystemExit("non-object event")
        events.append(event)

roots = [e.get("thread_id") for e in events if e.get("type") == "thread.started"]
if len(roots) != 1 or not isinstance(roots[0], str) or not roots[0]:
    raise SystemExit("missing or ambiguous root thread")
root = roots[0]

markers = []
for event in events:
    item = event.get("item")
    if event.get("type") == "item.completed" and isinstance(item, dict) and item.get("type") == "agent_message":
        text = item.get("text")
        if isinstance(text, str):
            markers.extend(re.findall(r"(?m)^ADVISOR_EVAL route=(consult|skip)[ \t]*$", text))
if len(markers) != 1:
    raise SystemExit("missing or ambiguous route marker")
route = markers[0]

collab = []
for event in events:
    item = event.get("item")
    if isinstance(item, dict) and item.get("type") == "collab_tool_call":
        collab.append((event.get("type"), item))
for _, item in collab:
    if item.get("tool") == "wait" and item.get("receiver_thread_ids") == []:
        raise SystemExit("empty wait is not runtime evidence")

spawn_events = [(outer,item) for outer,item in collab if item.get("tool") == "spawn_agent"]
completed = [item for outer, item in spawn_events if outer == "item.completed"]
all_spawns = [item for _, item in spawn_events]
if route == "skip":
    if all_spawns:
        raise SystemExit("skip spawned an advisor")
    evidence = {"route":"skip","advisor_count":0,"roles":[],"freshness":"none","model":"none","effort":"none","sandbox":"none"}
else:
    if len(completed) != 1:
        raise SystemExit("consult requires exactly one completed spawn")
    item = completed[0]
    completed_id = item.get("id")
    if isinstance(completed_id, str) and completed_id:
        if any(spawn.get("id") != completed_id for spawn in all_spawns):
            raise SystemExit("consult contains more than one logical spawn")
        lifecycle = [outer for outer, _ in spawn_events]
        if any(outer not in {"item.started","item.completed"} for outer in lifecycle) or lifecycle.count("item.started") > 1 or lifecycle.count("item.completed") != 1:
            raise SystemExit("duplicate or malformed spawn lifecycle")
    elif len(all_spawns) != 1:
        raise SystemExit("spawn lifecycle events lack a stable call identity")
    tids = item.get("receiver_thread_ids")
    agents = item.get("receiver_agents")
    if item.get("status") != "completed" or not isinstance(tids, list) or len(tids) != 1 or not isinstance(tids[0], str) or not tids[0]:
        raise SystemExit("invalid completed spawn")
    if not isinstance(agents, list) or len(agents) != 1 or not isinstance(agents[0], dict):
        raise SystemExit("invalid receiver agent evidence")
    agent = agents[0]
    if agent.get("agent_role") != expected_role or agent.get("thread_id") != tids[0]:
        raise SystemExit("wrong receiver identity")
    if item.get("model") != expected_model or item.get("reasoning_effort") != "high":
        raise SystemExit("wrong receiver model or effort")
    if tids[0] == root:
        raise SystemExit("receiver reused root thread")
    evidence = {"route":"consult","advisor_count":1,"roles":[expected_role],"freshness":"distinct_receiver_thread","model":expected_model,"effort":"high","sandbox":"read-only"}

text = json.dumps(evidence, separators=(",", ":"))
if root in text or any(tid in text for item in all_spawns for tid in item.get("receiver_thread_ids", []) if isinstance(tid, str)):
    raise SystemExit("thread identifier escaped redaction")
evidence_path.write_text(text + "\n", encoding="utf-8")
PY
}

# Private deterministic test path for the static verifier. It invokes the same
# fail-closed parser used by --run without starting Codex or touching live state.
if [ "${ADVISOR_SELECT_FOR_PARENT+x}" = x ]; then
  [ "$#" -eq 0 ] || fail "model-selection fixture accepts no arguments"
  selected_role=$(select_advisor_role "$ADVISOR_SELECT_FOR_PARENT")
  printf '%s %s\n' "$selected_role" "$(model_for_role "$selected_role")"
  exit
fi
if [ "${ADVISOR_VALIDATE_CLI_VERSION+x}" = x ]; then
  [ "$#" -eq 0 ] || fail "version-validation fixture accepts no arguments"
  validate_cli_version "$ADVISOR_VALIDATE_CLI_VERSION"
  exit
fi
if [ "${ADVISOR_VALIDATE_FEATURE_STATE+x}" = x ]; then
  [ "$#" -eq 0 ] || fail "feature-state fixture accepts no arguments"
  [ "${ADVISOR_EXPECTED_FEATURE_STATE+x}" = x ] || fail "feature-state fixture requires an expected boolean"
  validate_feature_state "$ADVISOR_VALIDATE_FEATURE_STATE" "$ADVISOR_EXPECTED_FEATURE_STATE"
  exit
fi
if [ "${ADVISOR_PARSE_RUNTIME_EVIDENCE+x}" = x ]; then
  [ "$#" -eq 0 ] || fail "runtime-evidence fixture accepts no arguments"
  [ "${ADVISOR_RUNTIME_EVIDENCE_OUT+x}" = x ] || fail "runtime-evidence fixture requires an output path"
  [ "${ADVISOR_EXPECTED_MODEL+x}" = x ] || fail "runtime-evidence fixture requires an expected model"
  [ "${ADVISOR_EXPECTED_ROLE+x}" = x ] || fail "runtime-evidence fixture requires an expected role"
  parse_runtime_evidence "$ADVISOR_PARSE_RUNTIME_EVIDENCE" "$ADVISOR_RUNTIME_EVIDENCE_OUT" "$ADVISOR_EXPECTED_ROLE" "$ADVISOR_EXPECTED_MODEL"
  exit
fi

mode='' result='' allow_unavailable=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run|--verify-result) [ -z "$mode" ] || fail "choose one mode"; mode=$1; shift ;;
    --result) [ "$#" -ge 2 ] && [ -n "$2" ] || fail "--result requires PATH"; result=$2; shift 2 ;;
    --allow-unavailable) allow_unavailable=1; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[ -n "$mode" ] && [ -n "$result" ] || fail "usage: evaluate-triggers.sh --run --result PATH | --verify-result --result PATH [--allow-unavailable]"
[ "$mode" = --verify-result ] || [ "$allow_unavailable" -eq 0 ] || fail "--allow-unavailable is verifier-only"

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
plugin_dir=$(CDPATH= cd "$script_dir/.." && pwd) || exit 1
repo_dir=$(CDPATH= cd "$plugin_dir/../.." && pwd) || exit 1
fixtures=$plugin_dir/evals/trigger-cases.json
installer=$script_dir/install-agents.sh

verify_result() {
  python3 - "$result" "$allow_unavailable" "$fixtures" <<'PY'
import json, re, sys
from pathlib import Path

path, allow, fixture_path = Path(sys.argv[1]), bool(int(sys.argv[2])), Path(sys.argv[3])
data = json.loads(path.read_text(encoding="utf-8"))
text = path.read_text(encoding="utf-8")
if re.search(r'(?i)(api[_-]?key|authorization|bearer|password|token)["\s:]+[^"\s]{6,}', text):
    raise SystemExit("result contains a secret-like field or value")
fixtures = json.loads(fixture_path.read_text(encoding="utf-8"))["cases"]
expected = {c["id"]: c for c in fixtures}
def selected_pair(parent):
    value = str(parent).lower()
    if "luna" in value or "spark" in value:
        return "advisor-terra", "gpt-5.6-terra"
    return "advisor-sol", "gpt-5.6-sol"
if data.get("status") == "unavailable":
    if not allow:
        raise SystemExit("typed unavailable result requires --allow-unavailable")
    if data.get("reason_type") not in {"cli_incompatible","feature_state_unavailable","role_unavailable","runtime_evidence_unavailable"}:
        raise SystemExit("invalid unavailable reason_type")
    if data.get("redacted") is not True:
        raise SystemExit("unavailable artifact is not marked redacted")
    nm = data.get("nonmutation")
    if nm is not None:
        for name in ("live_home", "marketplace"):
            item = nm.get(name, {})
            if item.get("before") != item.get("after") or item.get("unchanged") is not True:
                raise SystemExit(f"unavailable artifact has invalid paired nonmutation evidence for {name}")
    print("RESULT VERIFIED: typed unavailable evidence accepted")
    raise SystemExit(0)
if data.get("status") != "pass":
    raise SystemExit("evaluation result did not pass")
if data.get("redacted") is not True or data.get("subscription_only") is not True or data.get("overage_disabled") is not True:
    raise SystemExit("routing/redaction enforcement missing")
if data.get("session_cap") != 40 or not isinstance(data.get("sessions_run"), int) or data["sessions_run"] > 40:
    raise SystemExit("invalid pooled session cap")
nm = data.get("nonmutation", {})
for name in ("live_home", "marketplace"):
    item = nm.get(name, {})
    if item.get("before") != item.get("after") or item.get("unchanged") is not True:
        raise SystemExit(f"paired nonmutation failed for {name}")
schemas = data.get("schemas")
if not isinstance(schemas, list) or len(schemas) != 2 or {s.get("multi_agent_v2") for s in schemas} != {False, True}:
    raise SystemExit("both isolated feature schemas are required")
count = 0
for schema in schemas:
    cases = schema.get("cases", [])
    if {c.get("id") for c in cases} != set(expected):
        raise SystemExit("schema case inventory mismatch")
    boundary_ok = 0
    for case in cases:
        fixture = expected[case["id"]]
        trials = case.get("trials", [])
        if len(trials) not in ({1,3} if fixture["class"] == "boundary" else {1}):
            raise SystemExit(f"invalid trial count: {case['id']}")
        if fixture["class"] == "boundary" and len(trials)==3 and trials[0].get("route")==fixture["expected"]:
            raise SystemExit(f"unnecessary boundary rerun: {case['id']}")
        count += len(trials)
        routes = [t.get("route") for t in trials]
        final = max(("consult","skip"), key=routes.count) if all(r in {"consult","skip"} for r in routes) else "unavailable"
        if final != case.get("final_route"):
            raise SystemExit(f"wrong majority route: {case['id']}")
        if fixture["class"] != "boundary" and final != fixture["expected"]:
            raise SystemExit(f"clear case mismatch: {case['id']}")
        if fixture["class"] == "boundary" and final == fixture["expected"]:
            boundary_ok += 1
        for trial in trials:
            route = trial.get("route")
            roles = trial.get("roles")
            expected_role, expected_model = selected_pair(trial.get("parent_model", "unknown"))
            if trial.get("selected_role") != expected_role or trial.get("selected_model") != expected_model:
                raise SystemExit(f"invalid parent-role/model selection: {case['id']}")
            if route == "consult":
                if trial.get("advisor_count") != 1 or roles != [expected_role] or trial.get("freshness") != "distinct_receiver_thread":
                    raise SystemExit(f"invalid consultation identity/freshness: {case['id']}")
                if trial.get("model") != expected_model or trial.get("effort") != "high" or trial.get("sandbox") != "read-only":
                    raise SystemExit(f"invalid consultation pin/isolation: {case['id']}")
            elif route == "skip":
                if trial.get("advisor_count") != 0 or roles != []:
                    raise SystemExit(f"skip spawned a role: {case['id']}")
            else:
                raise SystemExit(f"unavailable trial cannot count as success: {case['id']}")
    if boundary_ok < 3:
        raise SystemExit("fewer than three boundary cases matched")
if count != data["sessions_run"] or count > 40:
    raise SystemExit("session accounting mismatch")
print(f"RESULT VERIFIED: {data['status']} artifact; {count} root sessions")
PY
}

[ "$mode" = --run ] || { verify_result; exit; }

write_unavailable() {
  reason_type=$1
  live_after=''; market_after=''
  if [ -n "${live_before-}" ] && [ -n "${market_before-}" ]; then
    live_after=$(snapshot_live_state live-state-after)
    progress "marketplace after snapshot started"
    market_after=$(shasum -a 256 "$marketplace" | awk '{print $1}')
    progress "marketplace after snapshot complete (1 file)"
    [ "$live_before" = "$live_after" ] && [ "$market_before" = "$market_after" ] ||
      fail "paired live-state nonmutation check failed while recording unavailable result"
  fi
  umask 077
  python3 - "$result" "$reason_type" "${live_before-}" "$live_after" "${market_before-}" "$market_after" <<'PY'
import json, os, sys
path, reason, live_before, live_after, market_before, market_after = sys.argv[1:]
tmp = path + ".tmp"
os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
data = {"status":"unavailable","reason_type":reason,"redacted":True}
if live_before:
    data["nonmutation"] = {
        "live_home":{"before":live_before,"after":live_after,"unchanged":live_before==live_after},
        "marketplace":{"before":market_before,"after":market_after,"unchanged":market_before==market_after},
    }
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
  progress "typed unavailable artifact written ($reason_type)"
  exit 2
}

[ "${ADVISOR_SUBSCRIPTION_ONLY-}" = 1 ] || fail "set ADVISOR_SUBSCRIPTION_ONLY=1 after confirming subscription-only routing"
[ "${CODEX_OVERAGE_DISABLED-}" = 1 ] || fail "set CODEX_OVERAGE_DISABLED=1 after confirming overage is disabled"
for key in OPENAI_API_KEY CODEX_API_KEY; do eval "present=\${$key+x}"; [ -z "$present" ] || fail "$key must be unset for subscription-only evaluation"; done
tmp_base=${TMPDIR:-/tmp}; case "$tmp_base" in /*) ;; *) tmp_base=/tmp ;; esac
work=$(mktemp -d "$tmp_base/advisor-eval.XXXXXX") || fail "cannot create isolated evaluator directory"
cleanup() { case "$work" in "$tmp_base"/advisor-eval.*) rm -rf "$work" ;; esac; }
trap cleanup 0 HUP INT TERM

snapshot_live_state() {
  label=$1
  file_list=$work/snapshot-$label-files
  digest_lines=$work/snapshot-$label-digests
  progress "$label snapshot started"
  : >"$file_list"
  [ ! -f "$live_home/config.toml" ] || printf '%s\n' "$live_home/config.toml" >>"$file_list"
  for name in agents skills plugins; do
    [ ! -d "$live_home/$name" ] || find "$live_home/$name" -type f -print >>"$file_list"
  done
  LC_ALL=C sort -u "$file_list" -o "$file_list"
  : >"$digest_lines"
  count=0
  while IFS= read -r file; do
    shasum -a 256 "$file" >>"$digest_lines"
    count=$((count + 1))
    if [ $((count % 100)) -eq 0 ]; then progress "$label snapshot hashing: $count files"; fi
  done <"$file_list"
  digest=$(shasum -a 256 "$digest_lines" | awk '{print $1}')
  progress "$label snapshot complete ($count contract files; auth/session/cache excluded)"
  printf '%s\n' "$digest"
}
live_home=${CODEX_HOME:-${HOME:?HOME is required}/.codex}
marketplace=$repo_dir/.agents/plugins/marketplace.json
live_before=$(snapshot_live_state live-state-before)
progress "marketplace before snapshot started"
market_before=$(shasum -a 256 "$marketplace" | awk '{print $1}')
progress "marketplace before snapshot complete (1 file)"
command -v codex >/dev/null 2>&1 || write_unavailable cli_incompatible
command -v jq >/dev/null 2>&1 || write_unavailable cli_incompatible
version=$(codex --version 2>/dev/null) || write_unavailable cli_incompatible
validate_cli_version "$version" || write_unavailable cli_incompatible

trials=$work/trials.jsonl
: >"$trials"
sessions_run=0

setup_schema() {
  schema=$1
  feature=$2
  project=$work/project-$schema
  runtime_home=$work/runtime-$schema
  mkdir -p "$project/.codex/skills" "$project/plugins" "$runtime_home/agents"
  ln -s "$plugin_dir/skills/consultation" "$project/.codex/skills/consultation"
  ln -s "$plugin_dir" "$project/plugins/advisor"
  sh "$installer" --target-dir "$runtime_home/agents" >/dev/null || write_unavailable role_unavailable
  sh "$installer" --target-dir "$runtime_home/agents" --check >/dev/null || write_unavailable role_unavailable
  case "$feature" in true) feature_switch=--enable ;; false) feature_switch=--disable ;; esac
  progress "$schema: confirming feature state"
  codex features "$feature_switch" multi_agent_v2 list >"$work/features-$schema" 2>/dev/null || write_unavailable feature_state_unavailable
  feature_output=$(cat "$work/features-$schema")
  validate_feature_state "$feature_output" "$feature" || write_unavailable feature_state_unavailable
  progress "$schema: isolated project, skill, plugin link, and exact child roles ready"
}

run_trial() {
  schema=$1 feature=$2 id=$3 expected=$4 attempt=$5 prompt_text=$6
  [ "$sessions_run" -lt 40 ] || fail "pooled 40-session cap reached"
  sessions_run=$((sessions_run + 1))
  project=$work/project-$schema
  runtime_home=$work/runtime-$schema
  parent_model=${ADVISOR_EVAL_PARENT_MODEL-unknown}
  selected_role=$(select_advisor_role "$parent_model")
  selected_model=$(model_for_role "$selected_role")
  case "$feature" in true) feature_switch=--enable ;; false) feature_switch=--disable ;; esac
  raw=$work/raw-$schema-$id-$attempt.jsonl
  evidence=$work/evidence-$schema-$id-$attempt.json
  progress "$schema: session $sessions_run/40, case $id, trial $attempt"
  eval_prompt="Classify this task under the installed Advisor consultation contract. Emit the required ADVISOR DECISION before any implementation. Do not implement. Parent model is $parent_model; apply the shipped role-selection policy. If consulting, spawn exactly one $selected_role in a new thread; its installed profile pins $selected_model and high effort. Do not pass a model override. Finish with exactly one line: ADVISOR_EVAL route=consult|skip. TASK: $prompt_text"
  codex exec --json --ignore-user-config --ignore-rules --ephemeral "$feature_switch" multi_agent_v2 \
    -c "agents.advisor-terra.description=Advisor Terra read-only consultation" \
    -c "agents.advisor-terra.config_file=\"$runtime_home/agents/advisor-terra.toml\"" \
    -c "agents.advisor-sol.description=Advisor Sol read-only consultation" \
    -c "agents.advisor-sol.config_file=\"$runtime_home/agents/advisor-sol.toml\"" \
    -c "shell_environment_policy.set={CODEX_HOME=\"$runtime_home\"}" \
    -C "$project" --sandbox read-only --skip-git-repo-check "$eval_prompt" </dev/null >"$raw" 2>/dev/null || write_unavailable runtime_evidence_unavailable
  parse_runtime_evidence "$raw" "$evidence" "$selected_role" "$selected_model" || write_unavailable runtime_evidence_unavailable
  python3 - "$evidence" "$trials" "$schema" "$feature" "$id" "$expected" "$attempt" "$parent_model" "$selected_role" "$selected_model" <<'PY' || write_unavailable runtime_evidence_unavailable
import json, sys
evidence, out, schema, feature, cid, expected, attempt, parent_model, selected_role, selected_model = sys.argv[1:]
record = json.load(open(evidence, encoding="utf-8"))
record.update({"schema":schema,"multi_agent_v2":feature=="true","id":cid,"expected":expected,"attempt":int(attempt),"parent_model":parent_model,"selected_role":selected_role,"selected_model":selected_model})
with open(out,"a",encoding="utf-8") as f: f.write(json.dumps(record,separators=(",",":"))+"\n")
PY
}

for spec in 'v1 false' 'v2 true'; do
  set -- $spec; schema=$1; feature=$2
  setup_schema "$schema" "$feature"
  base_cases=$work/base-$schema.tsv
  jq -r '.cases[] | [.id,.class,.expected,.prompt] | @tsv' "$fixtures" >"$base_cases"
  while IFS="$(printf '\t')" read -r id class expected prompt_text; do
    run_trial "$schema" "$feature" "$id" "$expected" 1 "$prompt_text"
  done <"$base_cases"
  # Boundary mismatches alone receive exactly two reruns in this schema.
  reruns=$work/reruns-$schema.tsv
  jq -rs --arg s "$schema" --slurpfile f "$fixtures" '
    . as $trials | $f[0].cases[] | select(.class=="boundary") as $c |
    ($trials | map(select(.schema==$s and .id==$c.id))[0]) as $t |
    select($t.route != $c.expected) | [$c.id,$c.expected,$c.prompt] | @tsv
  ' "$trials" >"$reruns"
  while IFS="$(printf '\t')" read -r id expected prompt_text; do
    run_trial "$schema" "$feature" "$id" "$expected" 2 "$prompt_text"
    run_trial "$schema" "$feature" "$id" "$expected" 3 "$prompt_text"
  done <"$reruns"
done

live_after=$(snapshot_live_state live-state-after)
progress "marketplace after snapshot started"
market_after=$(shasum -a 256 "$marketplace" | awk '{print $1}')
progress "marketplace after snapshot complete (1 file)"
[ "$live_before" = "$live_after" ] && [ "$market_before" = "$market_after" ] || fail "paired live-state nonmutation check failed"

python3 - "$trials" "$fixtures" "$result" "$version" "$sessions_run" "$live_before" "$live_after" "$market_before" "$market_after" <<'PY'
import json, os, sys
trials_path, fixtures_path, result, version, count, lb, la, mb, ma = sys.argv[1:]
trials=[json.loads(x) for x in open(trials_path,encoding="utf-8") if x.strip()]
fixtures=json.load(open(fixtures_path,encoding="utf-8"))["cases"]
schemas=[]; overall=True
for name, feature in (("v1",False),("v2",True)):
    cases=[]; boundary_ok=0
    for fixture in fixtures:
        ts=[t for t in trials if t["schema"]==name and t["id"]==fixture["id"]]
        routes=[t["route"] for t in ts]
        final=max(("consult","skip"),key=routes.count)
        if fixture["class"]=="boundary": boundary_ok += final==fixture["expected"]
        else: overall &= final==fixture["expected"]
        cases.append({"id":fixture["id"],"final_route":final,"trials":[{k:t[k] for k in ("route","advisor_count","roles","freshness","model","effort","sandbox","parent_model","selected_role","selected_model")} for t in ts]})
    overall &= boundary_ok>=3
    schemas.append({"name":name,"multi_agent_v2":feature,"cases":cases})
data={"status":"pass" if overall else "fail","redacted":True,"codex_version":version,"subscription_only":True,"overage_disabled":True,"session_cap":40,"sessions_run":int(count),"nonmutation":{"live_home":{"before":lb,"after":la,"unchanged":lb==la},"marketplace":{"before":mb,"after":ma,"unchanged":mb==ma}},"schemas":schemas}
tmp=result+".tmp"; os.makedirs(os.path.dirname(os.path.abspath(result)),exist_ok=True)
with open(tmp,"w",encoding="utf-8") as f: json.dump(data,f,indent=2); f.write("\n")
os.replace(tmp,result)
PY
progress "redacted result written; verifying deterministic contract"
verify_result
