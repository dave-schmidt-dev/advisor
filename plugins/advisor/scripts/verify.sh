#!/bin/sh
# Non-networked repository verification for the consultation-only plugin.

set -eu
pass() { printf '%s\n' "PASS: $*"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }
case "$#" in 0) ;; 1) [ "$1" = --static ] || fail "expected no args or --static" ;; *) fail "expected no args or --static" ;; esac

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
plugin_dir=$(CDPATH= cd "$script_dir/.." && pwd) || exit 1
repo_dir=$(CDPATH= cd "$plugin_dir/../.." && pwd) || exit 1
manifest=$plugin_dir/.codex-plugin/plugin.json
marketplace=$repo_dir/.agents/plugins/marketplace.json
terra_role=$plugin_dir/agents/advisor-terra.toml
sol_role=$plugin_dir/agents/advisor-sol.toml
skill=$plugin_dir/skills/consultation/SKILL.md
ui=$plugin_dir/skills/consultation/agents/openai.yaml
operations=$plugin_dir/skills/consultation/references/operations.md
fixtures=$plugin_dir/evals/trigger-cases.json
installer=$script_dir/install-agents.sh
inspector=$script_dir/inspect-agent-runtime.sh
parent_inspector=$script_dir/inspect-parent-runtime.sh
transport=$script_dir/run-advisor.sh
audit=$script_dir/advisor-audit.sh
evaluator=$script_dir/evaluate-triggers.sh
readme=$repo_dir/README.md
notice=$repo_dir/NOTICE.md
license=$repo_dir/LICENSE

for file in "$manifest" "$marketplace" "$terra_role" "$sol_role" "$skill" "$ui" "$operations" "$fixtures" "$installer" "$inspector" "$parent_inspector" "$transport" "$audit" "$evaluator" "$readme" "$notice" "$license"; do
  [ -f "$file" ] || fail "missing required file: $file"
done
[ "$(find "$plugin_dir/agents" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')" -eq 2 ] || fail "expected exactly two active roles"
[ "$(find "$plugin_dir/skills" -type f -name SKILL.md | wc -l | tr -d ' ')" -eq 1 ] || fail "expected exactly one skill"
pass "required inventory: one skill, two model pins, read-only transport, parent/child inspectors, evaluator, documentation"

python3 - "$manifest" "$marketplace" "$terra_role" "$sol_role" "$fixtures" "$ui" <<'PY'
import json, re, sys, tomllib
from pathlib import Path
manifest=json.loads(Path(sys.argv[1]).read_text())
market=json.loads(Path(sys.argv[2]).read_text())
terra=tomllib.loads(Path(sys.argv[3]).read_text())
sol=tomllib.loads(Path(sys.argv[4]).read_text())
cases=json.loads(Path(sys.argv[5]).read_text())
ui=Path(sys.argv[6]).read_text()
version=manifest.get("version","")
if manifest.get("name")!="advisor" or not re.fullmatch(r"1\.3\.0(?:\+codex\.[0-9A-Za-z.-]+)?",version): raise SystemExit("manifest identity/version")
if "homepage" in manifest or "repository" in manifest: raise SystemExit("unowned upstream metadata remains")
author_name=manifest.get("author",{}).get("name","")
if "David Schmidt / Zero Delta LLC" not in author_name or "Daniel McAteer" not in author_name: raise SystemExit("maintainer/original-author identity")
if manifest.get("skills")!="./skills/" or any(k in manifest for k in ("hooks","apps","mcpServers")): raise SystemExit("unsupported plugin components")
entry=market.get("plugins",[])
if market.get("name")!="advisor" or market.get("interface",{}).get("displayName")!="Codex Advisor": raise SystemExit("marketplace identity")
if len(entry)!=1 or entry[0].get("name")!="advisor" or entry[0].get("source")!={"source":"local","path":"./plugins/advisor"}: raise SystemExit("marketplace source")
if entry[0].get("policy")!={"installation":"AVAILABLE","authentication":"ON_INSTALL"} or not entry[0].get("category"): raise SystemExit("marketplace policy")
pairs=((terra,{"name":"advisor-terra","description":"Standard fresh, read-only advisor for material technical decisions and generic advisor requests.","model":"gpt-5.6-terra","model_reasoning_effort":"high","sandbox_mode":"read-only"}),(sol,{"name":"advisor-sol","description":"Specialist fresh, read-only advisor for narrowly qualified unresolved critical decisions.","model":"gpt-5.6-sol","model_reasoning_effort":"high","sandbox_mode":"read-only"}))
for role,pins in pairs:
    if any(role.get(k)!=v for k,v in pins.items()): raise SystemExit("role pins")
    if not all(isinstance(role.get(k),str) and role[k].strip() for k in ("description","developer_instructions")): raise SystemExit("role text")
    required=("Use zero tools.", "Do not call any tool or function", "inspect files or repositories", "browse, fetch, or search the web", "independent", "FOLLOW-UP AREAS", "research-first", "Do not spawn or route another agent")
    if any(phrase not in role["developer_instructions"] for phrase in required): raise SystemExit("role zero-tool contract")
items=cases.get("cases",[])
if len(items)!=12 or len({c.get("id") for c in items})!=12: raise SystemExit("fixture inventory")
counts={k:sum(c.get("class")==k for c in items) for k in ("consult","skip","boundary")}
if counts!={"consult":4,"skip":4,"boundary":4}: raise SystemExit(f"fixture classes {counts}")
if any(c.get("expected") not in ("consult","skip") or not c.get("prompt") for c in items): raise SystemExit("fixture fields")
risks={k:sum(c.get("risk")==k for c in items) for k in ("standard","specialist")}
if risks!={"standard":10,"specialist":2}: raise SystemExit(f"fixture risk tiers {risks}")
if {c["id"] for c in items if c.get("risk")=="specialist"}!={"consult-security","boundary-high-risk"}: raise SystemExit("specialist fixture scope")
if "allow_implicit_invocation: true" not in ui or "interface:" not in ui or "policy:" not in ui: raise SystemExit("UI YAML contract")
print("structured files valid")
PY
pass "manifest, marketplace, TOML, YAML, and 4/4/4 evaluator fixtures"

for phrase in \
  'material architecture' 'interface' 'data-model' 'compatibility' \
  'cross-module' 'competing diagnoses' 'security' 'privacy' 'authorization' \
  'migration' 'recovery' 'irreversible-state' 'explicit advisor' \
  'factual/status/summarization' 'mechanical edits' 'formatting/renaming/docs synchronization' \
  'settled-plan execution' 'final review owned elsewhere' 'no-delegation' 'borderline case'; do
  grep -Fqi "$phrase" "$skill" || fail "skill description/contract omits: $phrase"
done
for phrase in 'ADVISOR DECISION' 'route: consult | skip | unavailable' 'inspect-parent-runtime.sh' 'CODEX_THREAD_ID' 'CODEX_SESSION_ID' 'run-advisor.sh' \
  '--role advisor-terra' '--role advisor-sol' 'gpt-5.6-terra' 'gpt-5.6-sol' \
  'Standard consultation' 'Specialist consultation' 'generic advisor requests' \
  'unresolved security or trust boundary' 'irreversible migration or data-loss decision' \
  'credible unresolved High-severity disagreement' 'Security adjacency or project importance alone' \
  'borderline role choice' 'model and sandbox are irrelevant' \
  'DECISION' 'CONTEXT' 'OPTIONS' 'BOUNDARIES' 'REQUEST' \
  'ADVISOR RESPONSE' 'RECOMMENDATION:' 'WHY:' 'STRONGEST OBJECTION:' 'CHANGE MY MIND:' \
  'ACCEPTANCE CHECKS:' 'RISKS:' 'FOLLOW-UP AREAS:' 'research-first' 'accept' 'modify' 'reject' 'advisor unavailable' \
  'ADVISOR CALL' 'status: running' 'ADVISOR RESULT' 'status: completed | unavailable' \
  'tier: Standard | Specialist' 'role: advisor-terra | advisor-sol' \
  'model: <verified gpt-5.6-terra | gpt-5.6-sol>' 'effort: high' \
  'isolation: read-only' 'recommendation: <concise recommendation, or unavailable>' \
  'decision: accept | modify | reject | blocked' 'recommendation: unavailable' \
  'decision: blocked' 'distinct Codex consultation thread remains the inspectable detailed record' \
  'Before consultation, the root performs any repository or web research' \
  'relevant evidence and source references' 'enough relevant evidence' \
  'Use zero tools: do not inspect files, call tools, fetch' 'research-first next step' \
  'specific missing evidence' 'FOLLOW-UP AREAS' 'outside this consultation' \
  'unavailable result cannot be rescued' 'accepts the returned technical recommendation or' \
  'research-first plan, never a technical choice' \
  'sandbox_permissions: require_escalated' 'Do not first try' \
  'nested Codex app-server' 'elevation applies only to the fixed launcher' \
  'absolute installed plugin root' 'regular, nonsymlinked files' \
  'Never elevate a repository-relative or' 'workspace-resolved `plugins/advisor` script' \
  "<<'ADVISOR_PACKET'" 'Never use `< packet.txt`' 'unquoted heredoc' \
  '`eval`' 'shell-interpolated' 'workspace-writable file' \
  'post-response inspection proves' 'same-session' 'wrong-model' 'wrong-effort' \
  'non-read-only' 'tool-use evidence'; do
  grep -Fq -- "$phrase" "$skill" || fail "consultation contract omits: $phrase"
done
for document in "$operations" "$readme" "$repo_dir/SPEC.md"; do
  grep -Fqi 'repository or web research' "$document" || fail "root-research contract missing: $document"
  grep -Fqi 'source references' "$document" || fail "source-reference contract missing: $document"
  grep -Fqi 'zero-tool' "$document" || fail "zero-tool contract missing: $document"
  grep -Fqi 'non-read-only' "$document" || fail "non-read-only block contract missing: $document"
  grep -Fqi 'FOLLOW-UP AREAS' "$document" || fail "follow-up contract missing: $document"
  grep -Fqi 'research-first' "$document" || fail "research-first contract missing: $document"
  grep -Fqi 'outside' "$document" || fail "outside-consultation boundary missing: $document"
  grep -Fqi 'unavailable result cannot be rescued' "$document" || fail "unavailable rescue prohibition missing: $document"
  grep -Fqi 'require_escalated' "$document" || fail "escalated launcher boundary missing: $document"
  grep -Fqi 'nested Codex app-server' "$document" || fail "nested app-server boundary missing: $document"
  grep -Eqi 'installed[- ]plugin' "$document" || fail "installed root boundary missing: $document"
  grep -Fqi 'workspace-resolved' "$document" || fail "workspace-script elevation refusal missing: $document"
  grep -Fqi 'single-quoted' "$document" || fail "quoted packet boundary missing: $document"
  grep -Fqi 'workspace-writable' "$document" || fail "workspace packet refusal missing: $document"
  grep -Fqi 'Codex home' "$document" || fail "private transport root missing: $document"
done
python3 - "$readme" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md" "$skill" "$operations" <<'PY'
import re
import sys
from pathlib import Path

allowlist = re.compile(r"allowlisted\s+`?codex_exec`?\s+or\s+`?Codex Desktop`?\s+provenance", re.IGNORECASE)
for filename in sys.argv[1:]:
    if not allowlist.search(Path(filename).read_text(encoding="utf-8")):
        raise SystemExit(f"exact runtime provenance allowlist missing: {filename}")
PY
pass "exact codex_exec or Codex Desktop provenance allowlist documented across contracts"
grep -Fqi 'FOLLOW-UP AREAS' "$repo_dir/SPEC.md" || fail "SPEC follow-up placement missing"
if grep -Fq 'specific missing evidence under CHANGE MY MIND' "$repo_dir/SPEC.md"; then fail "SPEC retains stale missing-evidence placement"; fi
for document in "$manifest" "$skill" "$operations" "$readme" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md"; do
  grep -Fqi 'trailing spaces or tabs' "$document" || fail "trailing-whitespace contract missing: $document"
  grep -Fqi 'exactly one fresh retry' "$document" || fail "single-retry contract missing: $document"
  grep -Fqi 'empty-valued' "$document" || fail "empty-valued-field contract missing: $document"
done
grep -Fq 'Missing, duplicate, renamed, misordered, or empty-valued fields remain malformed.' "$readme" || fail "README full malformed-field list missing"
pass "retry, trailing-whitespace, and empty-valued-field documentation parity"
grep -Fqi 'accepting that plan' "$operations" || fail "research-first disposition semantics missing"
grep -Fqi '.retired-v1.3.0-zero-tool' "$operations" || fail "1.3.0 zero-tool retirement documentation missing"
grep -Fq 'never substitute a role other than the policy-selected' "$skill" || fail "no-substitution rule missing"
grep -Fq 'For `skip` or `unavailable`, emit only the existing `ADVISOR DECISION`' "$skill" || fail "skip/unavailable receipt exclusion missing"
call_line=$(grep -n '^ADVISOR CALL$' "$skill" | head -1 | cut -d: -f1)
transport_line=$(grep -n '^5\. Run exactly one selected consultation\.' "$skill" | head -1 | cut -d: -f1)
response_line=$(grep -n '^6\. Receive the required advisor response' "$skill" | head -1 | cut -d: -f1)
inspection_line=$(grep -n 'post-response inspection proves' "$skill" | head -1 | cut -d: -f1)
result_line=$(grep -n '^ADVISOR RESULT$' "$skill" | head -1 | cut -d: -f1)
[ -n "$call_line" ] && [ -n "$transport_line" ] && [ "$call_line" -lt "$transport_line" ] || fail "ADVISOR CALL must precede transport"
[ -n "$response_line" ] && [ -n "$inspection_line" ] && [ -n "$result_line" ] && [ "$inspection_line" -lt "$response_line" ] && [ "$response_line" -lt "$result_line" ] || fail "transport inspection must precede response processing and completed result"
grep -Fq '($b|unique)!=["read-only"]' "$inspector" || fail "inspector does not block non-read-only policy"
grep -Fq '($tool_events|length)!=0' "$inspector" || fail "inspector does not block advisor tool use"
grep -Fq 'parent_thread_id=${CODEX_THREAD_ID-}' "$parent_inspector" || fail "parent inspector does not require CODEX_THREAD_ID"
if grep -Fq 'CODEX_SESSION_ID' "$parent_inspector"; then fail "parent inspector falls back to CODEX_SESSION_ID"; fi
for phrase in 'codex exec --json --ignore-user-config --ignore-rules' '--sandbox read-only --model "$model"' 'model_reasoning_effort="high"' '--skip-git-repo-check' '--output-last-message' 'ADVISOR TRANSPORT:' '--expected-parent "$parent_thread_id"' 'jq -cn' 'consultation reused the parent thread' 'LC_ALL=C sed' 'response normalization failed' 'advisor response was not verified'; do
  grep -Fq -- "$phrase" "$transport" || fail "transport contract omits: $phrase"
done
if grep -Eq 'auth\.json|bws|get secret|CODEX_HOME=' "$transport"; then fail "transport handles authentication or secrets"; fi
pass "implicit boundaries, root research, exact read-only transport, clean output, and mandatory inspection"

for document in "$manifest" "$skill" "$ui" "$operations" "$readme" "$terra_role" "$sol_role"; do
  if grep -Eqi 'SELECTIVE ROUTE|mode: solo|solo \| delegate|sol_advisor_(luna|terra|sol_reviewer)|route selected implementation|fresh final review lane'; then
    fail "retired delivery behavior remains in $document"
  fi <"$document"
done
for forbidden in hooks .mcp.json .app.json; do [ ! -e "$plugin_dir/$forbidden" ] || fail "forbidden component exists: $forbidden"; done
pass "retired routing, implementer, reviewer, hook, MCP, and app behavior absent"

for digest in \
 fba1b42849d93737e83b094a2ab0b1611f87ac37db7438c8bbdf581f0813f8eb \
 5cfaf77f14757074ca5d3cfecd0b8204c91dc14eff8d6119985c64416ddf4853 \
 12fa9180a292876e6731bc325779123bcd931c3caa902fbf90d676a31833be84 \
 4425a8c1f21ce8c6af93f96adc253bbc33ea301f1389b3fa8ce350be08584eca \
 dc329fe87f6f6610c13157ec16432f91c79cf5a541ee3e7448f6afb165dd18ce \
 06c318e5e93f37452635906394e6ea69fb6a65ba9e6ad7172d37b444e0dc871d \
 77ed2f36bb149da5d9032230c3d6f5e5cd56b059b3fa5f59085249bba06e1f3a \
 0333acf0ef562bcfebd06009ac09bd1dd8cbc04c4cf28e08e9e049bd8bf202d2 \
 b0be4d07ef2958ad2dd01a4b11be6edff309063fe45d75e778aeac6dfce80363 \
 95be7e69ee4d5350ea199a66280e180774309371fefcf1a2765f782ec1a670c0 \
 5ab78b10e1abd4b86d8adeb7d71aa6b4d1c79b1a44457d2c717f5a03cd360367 \
 4ad79cb613cc9865cb3d1db02f2e98b3b117524153c075a2de3d6bd249798c5e \
 4c29a9fec188e7c9c1618dacbcf0e26e40781f1ba783f425ece24c5919a16ad4 \
 e939a9c7e96d2a74dde015838802d6a481d36520616464a192daff0412dccaba \
 294b5fe76799200b0ff814decc575a82ddbf4d426a4a680750113608de6516cd; do
  grep -Fq "$digest" "$installer" || fail "missing historical digest: $digest"
done
pass "all historical and Advisor 1.1.0 upgrade fingerprints retained"

tmp_base=${TMPDIR:-/tmp}; case "$tmp_base" in /*) ;; *) tmp_base=/tmp ;; esac
tmp=$(mktemp -d "$tmp_base/advisor-verify.XXXXXX") || fail "cannot create fixture directory"
cleanup() { case "$tmp" in "$tmp_base"/advisor-verify.*) rm -rf "$tmp" ;; esac; }
trap cleanup 0 HUP INT TERM
snapshot() { find "$1" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort | while IFS= read -r f; do if [ -L "$f" ]; then printf 'L %s\n' "$(basename "$f")"; elif [ -f "$f" ]; then shasum -a 256 "$f"; else printf 'O %s\n' "$(basename "$f")"; fi; done; }

clean=$tmp/clean
sh "$installer" --target-dir "$clean" >/dev/null
cmp -s "$terra_role" "$clean/advisor-terra.toml" || fail "clean Terra install differs"
cmp -s "$sol_role" "$clean/advisor-sol.toml" || fail "clean Sol install differs"
sh "$installer" --target-dir "$clean" --check >/dev/null
before=$(snapshot "$clean"); sh "$installer" --target-dir "$clean" >/dev/null; after=$(snapshot "$clean")
[ "$before" = "$after" ] || fail "second install changed exact state"
[ ! -e "$clean/config.toml" ] || fail "installer edited Codex config"
pass "clean install, exact check, idempotency, and no config mutation"

v110=$tmp/advisor-v110; mkdir "$v110"
python3 - "$terra_role" "$sol_role" "$v110" <<'PY'
from pathlib import Path
import sys
terra,sol,target=map(Path,sys.argv[1:])
replacements={
    terra:("Standard fresh, read-only advisor for material technical decisions and generic advisor requests.","Fresh, read-only GPT-5.6 Terra advisor for Luna, Spark, and lower-capability parents."),
    sol:("Specialist fresh, read-only advisor for narrowly qualified unresolved critical decisions.","Fresh, read-only GPT-5.6 Sol advisor for Terra, Sol, and unknown parents."),
}
zero_tool_block='''
Use zero tools. Do not call any tool or function, inspect files or repositories,
browse, fetch, or search the web, access external services, or conduct independent
research. The packet and its cited source references are the complete record. Recommend
a path when the evidence supports a decision. If it does not, identify only a concrete
research-first next step, missing evidence, research questions, or bounded
brainstorming areas under FOLLOW-UP AREAS; do not seek or perform that follow-up
yourself.
'''
follow_up_output='''FOLLOW-UP AREAS: <none, or a concrete research-first next step, missing evidence,
research questions, or bounded brainstorming areas>
'''
for source,(new,old) in replacements.items():
    text=source.read_text(encoding="utf-8")
    if text.count(new)!=1: raise SystemExit(f"current role description fixture mismatch: {source}")
    if text.count(zero_tool_block)!=1: raise SystemExit(f"current role zero-tool fixture mismatch: {source}")
    if text.count(follow_up_output)!=1: raise SystemExit(f"current role follow-up fixture mismatch: {source}")
    prior=text.replace(new,old).replace(zero_tool_block,"").replace(follow_up_output,"")
    prior=prior.replace("Do not spawn or route another agent", "Do not spawn another agent")
    target.joinpath(source.name).write_text(prior,encoding="utf-8")
PY
assert_v110_digest() {
  file=$1 expected=$2
  actual=$(shasum -a 256 "$file" | awk '{print $1}')
  [ "$actual" = "$expected" ] || fail "Advisor 1.1.0 fixture digest mismatch: $file ($actual)"
}
assert_v110_digest "$v110/advisor-terra.toml" 95be7e69ee4d5350ea199a66280e180774309371fefcf1a2765f782ec1a670c0
assert_v110_digest "$v110/advisor-sol.toml" 5ab78b10e1abd4b86d8adeb7d71aa6b4d1c79b1a44457d2c717f5a03cd360367
if sh "$installer" --target-dir "$v110" --check >/dev/null 2>&1; then fail "check accepted active Advisor 1.1.0 roles"; fi
sh "$installer" --target-dir "$v110" >/dev/null
cmp -s "$terra_role" "$v110/advisor-terra.toml" || fail "Advisor 1.1.0 Terra upgrade did not install 1.3.0 exactly"
cmp -s "$sol_role" "$v110/advisor-sol.toml" || fail "Advisor 1.1.0 Sol upgrade did not install 1.3.0 exactly"
assert_v110_digest "$v110/advisor-terra.toml.retired-v1.1.0" 95be7e69ee4d5350ea199a66280e180774309371fefcf1a2765f782ec1a670c0
assert_v110_digest "$v110/advisor-sol.toml.retired-v1.1.0" 5ab78b10e1abd4b86d8adeb7d71aa6b4d1c79b1a44457d2c717f5a03cd360367
sh "$installer" --target-dir "$v110" --check >/dev/null
before=$(snapshot "$v110"); sh "$installer" --target-dir "$v110" >/dev/null; after=$(snapshot "$v110")
[ "$before" = "$after" ] || fail "Advisor 1.1.0 upgraded state is not idempotent"
v110_interrupted=$tmp/advisor-v110-interrupted; mkdir "$v110_interrupted"
cp "$v110/advisor-terra.toml.retired-v1.1.0" "$v110_interrupted/advisor-terra.toml.retired-v1.1.0"
cp "$v110/advisor-sol.toml.retired-v1.1.0" "$v110_interrupted/advisor-sol.toml.retired-v1.1.0"
sh "$installer" --target-dir "$v110_interrupted" >/dev/null
cmp -s "$terra_role" "$v110_interrupted/advisor-terra.toml" || fail "retired-only Terra upgrade did not resume"
cmp -s "$sol_role" "$v110_interrupted/advisor-sol.toml" || fail "retired-only Sol upgrade did not resume"
sh "$installer" --target-dir "$v110_interrupted" --check >/dev/null
pass "exact Advisor 1.1.0 same-path upgrade, recoverable retirement, and idempotency"

v130=$tmp/advisor-v130; mkdir "$v130"
python3 - "$terra_role" "$sol_role" "$v130" <<'PY'
from pathlib import Path
import sys
current_block='''
Use zero tools. Do not call any tool or function, inspect files or repositories,
browse, fetch, or search the web, access external services, or conduct independent
research. The packet and its cited source references are the complete record. Recommend
a path when the evidence supports a decision. If it does not, identify only a concrete
research-first next step, missing evidence, research questions, or bounded
brainstorming areas under FOLLOW-UP AREAS; do not seek or perform that follow-up
yourself.
'''
prior_block='''
Use zero tools. Do not call any tool or function, inspect files or repositories,
browse, fetch, or search the web, access external services, or conduct independent
research. The packet and its cited source references are the complete record. If
evidence is insufficient, name the specific missing evidence under CHANGE MY MIND;
do not seek it yourself.
'''
follow_up_output='''FOLLOW-UP AREAS: <none, or a concrete research-first next step, missing evidence,
research questions, or bounded brainstorming areas>
'''
for source in map(Path,sys.argv[1:3]):
    text=source.read_text(encoding="utf-8")
    if text.count(current_block)!=1: raise SystemExit(f"current role zero-tool fixture mismatch: {source}")
    if text.count(follow_up_output)!=1: raise SystemExit(f"current role follow-up fixture mismatch: {source}")
    prior=text.replace(current_block,prior_block).replace(follow_up_output,"")
    prior=prior.replace("Do not spawn or route another agent", "Do not spawn another agent")
    Path(sys.argv[3],source.name).write_text(prior,encoding="utf-8")
PY
assert_v110_digest "$v130/advisor-terra.toml" e939a9c7e96d2a74dde015838802d6a481d36520616464a192daff0412dccaba
assert_v110_digest "$v130/advisor-sol.toml" 294b5fe76799200b0ff814decc575a82ddbf4d426a4a680750113608de6516cd
cp "$v110/advisor-terra.toml.retired-v1.1.0" "$v130/advisor-terra.toml.retired-v1.1.0"
cp "$v110/advisor-sol.toml.retired-v1.1.0" "$v130/advisor-sol.toml.retired-v1.1.0"
if sh "$installer" --target-dir "$v130" --check >/dev/null 2>&1; then fail "check accepted active prior Advisor 1.3.0 roles"; fi
sh "$installer" --target-dir "$v130" >/dev/null
cmp -s "$terra_role" "$v130/advisor-terra.toml" || fail "Advisor 1.3.0 Terra upgrade did not install current role exactly"
cmp -s "$sol_role" "$v130/advisor-sol.toml" || fail "Advisor 1.3.0 Sol upgrade did not install current role exactly"
assert_v110_digest "$v130/advisor-terra.toml.retired-v1.3.0-zero-tool" e939a9c7e96d2a74dde015838802d6a481d36520616464a192daff0412dccaba
assert_v110_digest "$v130/advisor-sol.toml.retired-v1.3.0-zero-tool" 294b5fe76799200b0ff814decc575a82ddbf4d426a4a680750113608de6516cd
sh "$installer" --target-dir "$v130" --check >/dev/null
before=$(snapshot "$v130"); sh "$installer" --target-dir "$v130" >/dev/null; after=$(snapshot "$v130")
[ "$before" = "$after" ] || fail "Advisor 1.3.0 upgraded state is not idempotent"

v130_early=$tmp/advisor-v130-early; mkdir "$v130_early"
python3 - "$v130/advisor-terra.toml.retired-v1.3.0-zero-tool" "$v130/advisor-sol.toml.retired-v1.3.0-zero-tool" "$v130_early" <<'PY'
from pathlib import Path
import sys
zero_tool_block='''
Use zero tools. Do not call any tool or function, inspect files or repositories,
browse, fetch, or search the web, access external services, or conduct independent
research. The packet and its cited source references are the complete record. If
evidence is insufficient, name the specific missing evidence under CHANGE MY MIND;
do not seek it yourself.
'''
for source in map(Path,sys.argv[1:3]):
    text=source.read_text(encoding="utf-8")
    if text.count(zero_tool_block)!=1: raise SystemExit(f"zero-tool predecessor fixture mismatch: {source}")
    active_name=source.name.removesuffix(".retired-v1.3.0-zero-tool")
    Path(sys.argv[3],active_name).write_text(text.replace(zero_tool_block,""),encoding="utf-8")
PY
assert_v110_digest "$v130_early/advisor-terra.toml" 4ad79cb613cc9865cb3d1db02f2e98b3b117524153c075a2de3d6bd249798c5e
assert_v110_digest "$v130_early/advisor-sol.toml" 4c29a9fec188e7c9c1618dacbcf0e26e40781f1ba783f425ece24c5919a16ad4
cp "$v110/advisor-terra.toml.retired-v1.1.0" "$v130_early/advisor-terra.toml.retired-v1.1.0"
cp "$v110/advisor-sol.toml.retired-v1.1.0" "$v130_early/advisor-sol.toml.retired-v1.1.0"
sh "$installer" --target-dir "$v130_early" >/dev/null
cmp -s "$terra_role" "$v130_early/advisor-terra.toml" || fail "early Advisor 1.3.0 Terra upgrade did not install current role exactly"
cmp -s "$sol_role" "$v130_early/advisor-sol.toml" || fail "early Advisor 1.3.0 Sol upgrade did not install current role exactly"
assert_v110_digest "$v130_early/advisor-terra.toml.retired-v1.3.0" 4ad79cb613cc9865cb3d1db02f2e98b3b117524153c075a2de3d6bd249798c5e
assert_v110_digest "$v130_early/advisor-sol.toml.retired-v1.3.0" 4c29a9fec188e7c9c1618dacbcf0e26e40781f1ba783f425ece24c5919a16ad4
sh "$installer" --target-dir "$v130_early" --check >/dev/null
pass "both prior Advisor 1.3.0 generations upgrade to separate retirement paths"

# Exercise all three v0.6.0 historical role types using their original exact bytes.
historical=$tmp/historical; mkdir "$historical"
sed -n '1,21p' "$repo_dir/plugins/advisor/scripts/verify.sh" >/dev/null
python3 - "$historical" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
files={
"sol-advisor-luna-implementer.toml":'''name = "sol_advisor_luna_implementer"\ndescription = "Sol Advisor's default routine implementation lane for bounded, fully specified work."\nmodel = "gpt-5.6-luna"\nmodel_reasoning_effort = "max"\n\ndeveloper_instructions = """\nYou are Sol Advisor's default routine implementation worker. Execute the supplied\nfive-part implementation specification when the work is bounded and largely\ndetermined by the contract. Preserve every stated interface and constraint, stay\nwithin the owned file set, and document material judgment calls.\n\nYou are not alone in the codebase: preserve concurrent edits and do not revert\nunrelated work. Surface material ambiguity, scope conflicts, or verification failures\nrather than redesigning the architecture. Run the requested checks and report actual\nevidence. If the result itself reveals judgment-heavy, high-risk, or misclassified\nwork, stop and return that signal so the parent can escalate immediately to Terra /\nHigh. If the specification is incomplete or wrong, identify the precise correction\nneeded for one corrected Luna attempt; that retry is not a prerequisite for Terra.\nDo not silently substitute a different role, model, or reasoning level; this installed\ncustom-agent profile is the required routine lane.\n"""\n''',
"sol-advisor-terra-implementer.toml":'''name = "sol_advisor_terra_implementer"\ndescription = "Sol Advisor's explicit high-complexity escalation lane for judgment-heavy or high-risk work."\nmodel = "gpt-5.6-terra"\nmodel_reasoning_effort = "high"\n\ndeveloper_instructions = """\nYou are Sol Advisor's explicit high-complexity escalation worker. Execute the\nsupplied five-part implementation specification within the settled architecture when\nthe parent identifies judgment-heavy, high-risk, or wider-blast-radius work, whether\nthat is known before delegation or revealed by the first Luna result. A corrected\nLuna attempt is reserved for a specification error and is not a prerequisite for\nTerra escalation.\nPreserve every stated interface and constraint, stay within the owned file set, and\ndocument material judgment calls.\n\nYou are not alone in the codebase: preserve concurrent edits and do not revert\nunrelated work. Surface ambiguity, scope conflicts, or verification failures rather\nthan redesigning the architecture without direction. Run the requested checks and\nreport actual evidence. Do not silently substitute a different role, model, or\nreasoning level; this installed custom-agent profile is the required escalation lane.\n"""\n''',
"sol-advisor-sol-reviewer.toml":'''name = "sol_advisor_sol_reviewer"\ndescription = "Sol Advisor's fresh, read-only final review lane for inspected diffs and evidence."\nmodel = "gpt-5.6-sol"\nmodel_reasoning_effort = "high"\nsandbox_mode = "read-only"\n\ndeveloper_instructions = """\nYou are Sol Advisor's fresh final reviewer. Remain strictly read-only: do not create,\nmodify, delete, format, or implement files, and do not broaden the requested scope.\nInspect the actual files, accumulated change set, stated interfaces and constraints,\nand verification evidence in a fresh context.\n\nReturn exactly one verdict: ship, fix-first, or rethink. Base the verdict on concrete,\nevidence-backed findings. Use fix-first only for bounded required corrections and\nrethink when the architecture or scope must change. Do not silently substitute a\ndifferent role, model, or reasoning level; this installed custom-agent profile is the\nrequired read-only review lane.\n"""\n'''}
for name,text in files.items(): (root/name).write_text(text,encoding="utf-8")
PY
python3 - "$historical/sol-advisor.toml" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('''name = "sol_advisor"\ndescription = "Fresh, read-only GPT-5.6 Sol advisor for bounded technical decisions."\nmodel = "gpt-5.6-sol"\nmodel_reasoning_effort = "high"\nsandbox_mode = "read-only"\n\ndeveloper_instructions = """\nYou are Sol Advisor, a consultation-only technical advisor. Remain strictly\nread-only. Do not create, edit, delete, format, route, implement, or review final\nwork. Evaluate only the bounded decision packet supplied by the root agent.\n\nReturn exactly:\nADVISOR RESPONSE\nRECOMMENDATION: <one path>\nWHY: <decisive evidence and reasoning>\nSTRONGEST OBJECTION: <best case against the recommendation>\nCHANGE MY MIND: <specific missing or contrary evidence>\nACCEPTANCE CHECKS: <concrete checks>\nRISKS: <material residual risks, or none>\n\nAdvice is non-authoritative. Do not spawn another agent, request irrelevant history,\nor silently substitute a different role, model, reasoning level, or isolation mode.\n"""\n''',encoding="utf-8")
PY
python3 - "$historical/advisor.toml" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('''name = "advisor"\ndescription = "Fresh, read-only advisor for bounded technical decisions. The parent selects the model from the shipped policy."\nsandbox_mode = "read-only"\n\ndeveloper_instructions = """\nYou are Advisor, a consultation-only technical advisor. Remain strictly\nread-only. Do not create, edit, delete, format, route, implement, or review final\nwork. Evaluate only the bounded decision packet supplied by the root agent.\n\nReturn exactly:\nADVISOR RESPONSE\nRECOMMENDATION: <one path>\nWHY: <decisive evidence and reasoning>\nSTRONGEST OBJECTION: <best case against the recommendation>\nCHANGE MY MIND: <specific missing or contrary evidence>\nACCEPTANCE CHECKS: <concrete checks>\nRISKS: <material residual risks, or none>\n\nAdvice is non-authoritative. Do not spawn another agent, request irrelevant history,\nor silently substitute a different role, model, reasoning level, or isolation mode.\n"""\n''',encoding="utf-8")
PY

v020=$tmp/historical-v020
v050=$tmp/historical-v050
intermediate=$tmp/historical-intermediate
mkdir "$v020" "$v050" "$intermediate"
python3 - "$v020" "$v050" "$intermediate" <<'PY'
from pathlib import Path
import sys
v020,v050,intermediate=map(Path,sys.argv[1:])
v020.joinpath("sol-advisor-luna-implementer.toml").write_text('''name = "sol_advisor_luna_implementer"\ndescription = "Sol Advisor's routine implementation lane for bounded, fully specified work."\nmodel = "gpt-5.6-luna"\nmodel_reasoning_effort = "max"\n\ndeveloper_instructions = """\nYou are Sol Advisor's routine implementation worker. Execute the supplied five-part\nimplementation specification exactly when it is bounded and largely determined by\nthe contract. Preserve stated interfaces and constraints, make only the files you\nown, and adapt to concurrent edits instead of reverting work you do not own.\n\nSurface material ambiguity, missing acceptance criteria, scope conflicts, or failed\nverification rather than redesigning the architecture. Run the requested checks and\nreport actual evidence. Do not silently substitute a different role, model, or\nreasoning level; this installed custom-agent profile is the required routine lane.\n"""\n''',encoding="utf-8")
v020.joinpath("sol-advisor-terra-implementer.toml").write_text('''name = "sol_advisor_terra_implementer"\ndescription = "Sol Advisor's complex implementation lane for context-heavy or higher-risk work."\nmodel = "gpt-5.6-terra"\nmodel_reasoning_effort = "max"\n\ndeveloper_instructions = """\nYou are Sol Advisor's complex implementation worker. Resolve difficult implementation\ndetails within the settled architecture, including context-heavy, higher-risk, or\nwider-blast-radius work. Preserve every stated interface and constraint, stay within\nthe owned file set, and document material judgment calls.\n\nYou are not alone in the codebase: preserve concurrent edits and do not revert\nunrelated work. Surface ambiguity, scope conflicts, or verification failures rather\nthan changing the architecture without direction. Run the requested checks and report\nactual evidence. Do not silently substitute a different role, model, or reasoning\nlevel; this installed custom-agent profile is the required complex lane.\n"""\n''',encoding="utf-8")
v050.joinpath("sol-advisor-luna-implementer.toml").write_text('''name = "sol_advisor_luna_implementer"\ndescription = "Sol Advisor's default routine implementation lane for bounded, fully specified work."\nmodel = "gpt-5.6-luna"\nmodel_reasoning_effort = "max"\n\ndeveloper_instructions = """\nYou are Sol Advisor's default routine implementation worker. Execute the supplied\nfive-part implementation specification when the work is bounded and largely\ndetermined by the contract. Preserve every stated interface and constraint, stay\nwithin the owned file set, and document material judgment calls.\n\nYou are not alone in the codebase: preserve concurrent edits and do not revert\nunrelated work. Surface material ambiguity, scope conflicts, or verification failures\nrather than redesigning the architecture. Run the requested checks and report actual\nevidence. If one corrected attempt shows that the work is judgment-heavy, high-risk,\nor misclassified as routine, stop and return that signal so the parent can escalate\nit to Terra / High. Do not silently substitute a different role, model, or reasoning\nlevel; this installed custom-agent profile is the required routine lane.\n"""\n''',encoding="utf-8")
v050.joinpath("sol-advisor-terra-implementer.toml").write_text('''name = "sol_advisor_terra_implementer"\ndescription = "Sol Advisor's explicit high-complexity escalation lane for judgment-heavy or high-risk work."\nmodel = "gpt-5.6-terra"\nmodel_reasoning_effort = "high"\n\ndeveloper_instructions = """\nYou are Sol Advisor's explicit high-complexity escalation worker. Execute the\nsupplied five-part implementation specification within the settled architecture when\nthe parent identifies judgment-heavy, high-risk, or wider-blast-radius work, or when\none corrected Luna attempt shows that routine routing was a misclassification.\nPreserve every stated interface and constraint, stay within the owned file set, and\ndocument material judgment calls.\n\nYou are not alone in the codebase: preserve concurrent edits and do not revert\nunrelated work. Surface ambiguity, scope conflicts, or verification failures rather\nthan redesigning the architecture without direction. Run the requested checks and\nreport actual evidence. Do not silently substitute a different role, model, or\nreasoning level; this installed custom-agent profile is the required escalation lane.\n"""\n''',encoding="utf-8")
intermediate.joinpath("sol-advisor-terra-implementer.toml").write_text('''name = "sol_advisor_terra_implementer"\ndescription = "Sol Advisor's sole implementation lane for routine and complex work."\nmodel = "gpt-5.6-terra"\nmodel_reasoning_effort = "high"\n\ndeveloper_instructions = """\nYou are Sol Advisor's sole implementation worker for routine, context-heavy,\nhigher-risk, and wider-blast-radius work. Execute the supplied five-part specification\nwithin the settled architecture. Preserve every stated interface and constraint, stay\nwithin the owned file set, and document material judgment calls.\n\nYou are not alone in the codebase: preserve concurrent edits and do not revert\nunrelated work. Surface ambiguity, scope conflicts, or verification failures rather\nthan redesigning the architecture without direction. Run the requested checks and\nreport actual evidence. Do not silently substitute a different role, model, or\nreasoning level; this installed custom-agent profile is the only implementation lane.\n"""\n''',encoding="utf-8")
PY

assert_digest() {
  file=$1 expected=$2
  actual=$(shasum -a 256 "$file" | awk '{print $1}')
  [ "$actual" = "$expected" ] || fail "historical fixture digest mismatch: $file ($actual)"
}
assert_digest "$v020/sol-advisor-luna-implementer.toml" fba1b42849d93737e83b094a2ab0b1611f87ac37db7438c8bbdf581f0813f8eb
assert_digest "$v020/sol-advisor-terra-implementer.toml" 4425a8c1f21ce8c6af93f96adc253bbc33ea301f1389b3fa8ce350be08584eca
assert_digest "$v050/sol-advisor-luna-implementer.toml" 5cfaf77f14757074ca5d3cfecd0b8204c91dc14eff8d6119985c64416ddf4853
assert_digest "$v050/sol-advisor-terra-implementer.toml" dc329fe87f6f6610c13157ec16432f91c79cf5a541ee3e7448f6afb165dd18ce
assert_digest "$intermediate/sol-advisor-terra-implementer.toml" 06c318e5e93f37452635906394e6ea69fb6a65ba9e6ad7172d37b444e0dc871d
assert_digest "$historical/sol-advisor-luna-implementer.toml" 12fa9180a292876e6731bc325779123bcd931c3caa902fbf90d676a31833be84
assert_digest "$historical/sol-advisor-terra-implementer.toml" 77ed2f36bb149da5d9032230c3d6f5e5cd56b059b3fa5f59085249bba06e1f3a
assert_digest "$historical/sol-advisor-sol-reviewer.toml" 0333acf0ef562bcfebd06009ac09bd1dd8cbc04c4cf28e08e9e049bd8bf202d2
assert_digest "$historical/sol-advisor.toml" 20ed49d92068594b251b2cf3fc38207f415a39879e15d07d635b3f7f7127da57
assert_digest "$historical/advisor.toml" b0be4d07ef2958ad2dd01a4b11be6edff309063fe45d75e778aeac6dfce80363

exercise_retirement() {
  label=$1 target=$2
  shift 2
  sh "$installer" --target-dir "$target" >/dev/null
  cmp -s "$terra_role" "$target/advisor-terra.toml" || fail "$label Terra advisor install mismatch"
  cmp -s "$sol_role" "$target/advisor-sol.toml" || fail "$label Sol advisor install mismatch"
  for old in "$@"; do
    suffix=.retired-v0.6.0
    [ "$old" != sol-advisor.toml ] || suffix=.retired-v1.0.0
    [ "$old" != advisor.toml ] || suffix=.retired-v1.0.1
    [ ! -e "$target/$old" ] && [ -f "$target/$old$suffix" ] || fail "$label retirement failed: $old"
  done
  sh "$installer" --target-dir "$target" --check >/dev/null
  before=$(snapshot "$target"); sh "$installer" --target-dir "$target" >/dev/null; after=$(snapshot "$target")
  [ "$before" = "$after" ] || fail "$label retired-only state is not idempotent"
}
exercise_retirement v0.2.0 "$v020" sol-advisor-luna-implementer.toml sol-advisor-terra-implementer.toml
exercise_retirement v0.5.0 "$v050" sol-advisor-luna-implementer.toml sol-advisor-terra-implementer.toml
exercise_retirement intermediate "$intermediate" sol-advisor-terra-implementer.toml
exercise_retirement through-v1.0.1 "$historical" advisor.toml sol-advisor.toml sol-advisor-luna-implementer.toml sol-advisor-terra-implementer.toml sol-advisor-sol-reviewer.toml
pass "all historical digests retire dynamically and every vintage is second-run idempotent"

for kind in modified symlink nonregular dual collision neutral-modified neutral-dual v110-modified v110-dual v110-collision; do
  target=$tmp/refuse-$kind; mkdir "$target"
  case "$kind" in
    modified) printf 'unknown\n' >"$target/sol-advisor-luna-implementer.toml" ;;
    symlink) ln -s "$terra_role" "$target/sol-advisor-luna-implementer.toml" ;;
    nonregular) mkdir "$target/sol-advisor-luna-implementer.toml" ;;
    dual) cp "$historical/sol-advisor-luna-implementer.toml.retired-v0.6.0" "$target/sol-advisor-luna-implementer.toml"; cp "$target/sol-advisor-luna-implementer.toml" "$target/sol-advisor-luna-implementer.toml.retired-v0.6.0" ;;
    collision) printf 'unknown\n' >"$target/sol-advisor-luna-implementer.toml.retired-v0.6.0" ;;
    neutral-modified) printf 'unknown\n' >"$target/advisor.toml" ;;
    neutral-dual) cp "$historical/advisor.toml.retired-v1.0.1" "$target/advisor.toml"; cp "$historical/advisor.toml.retired-v1.0.1" "$target/advisor.toml.retired-v1.0.1" ;;
    v110-modified) printf 'unknown\n' >"$target/advisor-terra.toml" ;;
    v110-dual) cp "$v110/advisor-terra.toml.retired-v1.1.0" "$target/advisor-terra.toml"; cp "$v110/advisor-terra.toml.retired-v1.1.0" "$target/advisor-terra.toml.retired-v1.1.0" ;;
    v110-collision) cp "$v110/advisor-terra.toml.retired-v1.1.0" "$target/advisor-terra.toml"; printf 'unknown\n' >"$target/advisor-terra.toml.retired-v1.1.0" ;;
  esac
  before=$(snapshot "$target")
  if sh "$installer" --target-dir "$target" >/dev/null 2>&1; then fail "installer accepted $kind state"; fi
  after=$(snapshot "$target"); [ "$before" = "$after" ] || fail "$kind refusal mutated target"
done
pass "modified, symlink, nonregular, dual-path, destination-collision, obsolete-neutral, and 1.1.0 upgrade refusal"

sessions=$tmp/sessions/2026/08/27; mkdir -p "$sessions"
id=11111111-1111-7111-8111-111111111111
root_id=00000000-0000-7000-8000-000000000000
rollout=$sessions/rollout-fixture-$id.jsonl
printf '%s\n' \
 '{"type":"response_item","payload":{"text":"DO_NOT_LEAK"}}' \
 "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$id\",\"source\":\"exec\",\"originator\":\"codex_exec\",\"agent_role\":null,\"parent_thread_id\":null}}" \
 '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$rollout"
out=$(TMPDIR=/nonexistent-read-only-path sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$root_id" "$id")
printf '%s\n' "$out" | jq -e '.agent_role=="advisor-sol" and .model=="gpt-5.6-sol" and .effort=="high" and .sandbox_policy_type=="read-only" and .transport=="codex-exec" and (keys|sort)==["agent_role","effort","model","parent_thread_id","permission_profile_type","sandbox_policy_type","thread_id","transport"]' >/dev/null || fail "inspector allowlist/pins"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-terra --expected-model gpt-5.6-terra --expected-parent "$root_id" "$id" >/dev/null 2>&1; then fail "inspector accepted a role/model pair other than the selected pair"; fi
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$id" "$id" >/dev/null 2>&1; then fail "inspector accepted the parent session as the advisor session"; fi
printf '%s\n' "$out" | grep -Fq DO_NOT_LEAK && fail "inspector leaked payload"
desktop_id=22222222-2222-7222-8222-222222222222
printf '%s\n' \
  '{"type":"response_item","payload":{"text":"DO_NOT_LEAK_DESKTOP"}}' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$desktop_id\",\"source\":\"exec\",\"originator\":\"Codex Desktop\",\"agent_role\":null,\"parent_thread_id\":null}}" \
  '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$desktop_id.jsonl"
desktop_out=$(sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$root_id" "$desktop_id")
printf '%s\n' "$desktop_out" | jq -e '.agent_role=="advisor-sol" and .model=="gpt-5.6-sol" and .effort=="high" and .sandbox_policy_type=="read-only" and .permission_profile_type=="managed" and .transport=="codex-exec"' >/dev/null || fail "inspector rejected exact Codex Desktop provenance"
printf '%s\n' "$desktop_out" | grep -Fq DO_NOT_LEAK && fail "desktop inspector leaked payload"
assert_provenance_mismatch() {
  candidate=$1
  error=$tmp/provenance-error-$candidate.txt
  if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$root_id" "$candidate" >"$tmp/provenance-out-$candidate.json" 2>"$error"; then
    fail "inspector accepted mismatched provenance"
  fi
  [ "$(cat "$error")" = 'ERROR: runtime_provenance_mismatch' ] || fail "provenance mismatch category was not fixed and stderr-only"
}
arbitrary_provenance_id=23232323-2323-7232-8232-232323232323
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$arbitrary_provenance_id\",\"source\":\"exec\",\"originator\":\"desktop\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$arbitrary_provenance_id.jsonl"
assert_provenance_mismatch "$arbitrary_provenance_id"
near_provenance_id=24242424-2424-7242-8242-242424242424
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$near_provenance_id\",\"source\":\"exec\",\"originator\":\"Codex desktop\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$near_provenance_id.jsonl"
assert_provenance_mismatch "$near_provenance_id"
nonreadonly_id=33333333-3333-7333-8333-333333333333
nonreadonly=$sessions/rollout-fixture-$nonreadonly_id.jsonl
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$nonreadonly_id\",\"source\":\"exec\",\"originator\":\"codex_exec\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","sandbox_policy":{"type":"workspace-write"},"permission_profile":{"type":"managed"}}}' >"$nonreadonly"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$root_id" "$nonreadonly_id" >/dev/null 2>&1; then fail "inspector accepted non-read-only runtime policy"; fi
tool_id=44444444-4444-7444-8444-444444444444
tool_rollout=$sessions/rollout-fixture-$tool_id.jsonl
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$tool_id\",\"source\":\"exec\",\"originator\":\"codex_exec\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' \
  '{"type":"response_item","payload":{"type":"function_call","name":"repo_inspection"}}' >"$tool_rollout"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$root_id" "$tool_id" >/dev/null 2>&1; then fail "inspector accepted advisor tool use"; fi
printf '%s\n' '{"type":"turn_context","payload":{"model":"gpt-5.6-terra","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >>"$rollout"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$root_id" "$id" >/dev/null 2>&1; then fail "inspector accepted conflicting model"; fi
wrong_effort_id=99999999-9999-7999-8999-999999999999
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$wrong_effort_id\",\"source\":\"exec\",\"originator\":\"codex_exec\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"medium","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$wrong_effort_id.jsonl"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$root_id" "$wrong_effort_id" >/dev/null 2>&1; then fail "inspector accepted wrong effort"; fi
wrong_source_id=aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa
printf '%s\n' \
  "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$wrong_source_id\",\"source\":\"tui\",\"originator\":\"codex-tui\"}}" \
  '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$sessions/rollout-fixture-$wrong_source_id.jsonl"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol --expected-parent "$root_id" "$wrong_source_id" >/dev/null 2>&1; then fail "inspector accepted non-exec provenance"; fi
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

fake_bin=$tmp/fake-bin
fake_home=$tmp/fake-codex-home
mkdir -p "$fake_bin" "$fake_home/sessions/2026/08/30"
python3 - "$fake_bin/codex" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(r'''#!/bin/sh
set -eu
output='' model='' sandbox='' effort='' workdir=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message) output=$2; shift 2 ;;
    --model) model=$2; shift 2 ;;
    --sandbox) sandbox=$2; shift 2 ;;
    -c) effort=$2; shift 2 ;;
    -C) workdir=$2; shift 2 ;;
    exec|--json|--ignore-user-config|--ignore-rules|--skip-git-repo-check|-) shift ;;
    *) exit 90 ;;
  esac
done
[ "$sandbox" = read-only ] && [ "$effort" = 'model_reasoning_effort="high"' ] || exit 91
case "$model" in gpt-5.6-terra|gpt-5.6-sol) ;; *) exit 92 ;; esac
case "$output" in "$CODEX_HOME"/.tmp/advisor-transport/run.*/response.*.txt) ;; *) exit 94 ;; esac
case "$workdir" in "$CODEX_HOME"/.tmp/advisor-transport/run.*/workdir.*) ;; *) exit 95 ;; esac
dd of=/dev/null 2>/dev/null
[ -z "${FAKE_CODEX_MARKER-}" ] || : >"$FAKE_CODEX_MARKER"
if [ "${FAKE_CODEX_CASE-valid}" = heartbeat ]; then sleep 1; fi
attempt=1
if [ -n "${FAKE_CODEX_COUNT_FILE-}" ]; then
  [ ! -f "$FAKE_CODEX_COUNT_FILE" ] || attempt=$(($(cat "$FAKE_CODEX_COUNT_FILE") + 1))
  printf '%s\n' "$attempt" >"$FAKE_CODEX_COUNT_FILE"
fi
case "$attempt" in
  1) child=dddddddd-dddd-7ddd-8ddd-dddddddddddd ;;
  2) child=abababab-abab-7aba-8aba-abababababab ;;
  *) exit 96 ;;
esac
case "${FAKE_CODEX_CASE-valid}:$attempt" in
  launcher-failure:*) exit 97 ;;
  same-session:*) child=${FAKE_PARENT_ID:?} ;;
  retry-reused-child:2) child=dddddddd-dddd-7ddd-8ddd-dddddddddddd ;;
esac
case "${FAKE_CODEX_CASE-valid}:$attempt" in
  response-misordered:*|malformed-twice:*|malformed-first-valid-second:1|retry-reused-child:1)
    printf '%s\n' 'ADVISOR RESPONSE' 'WHY: reason' 'RECOMMENDATION: path' 'STRONGEST OBJECTION: objection' 'CHANGE MY MIND: evidence' 'ACCEPTANCE CHECKS: checks' 'RISKS: none' 'FOLLOW-UP AREAS: none' >"$output"
    ;;
  response-missing:*)
    printf '%s\n' 'ADVISOR RESPONSE' 'RECOMMENDATION: path' 'WHY: reason' 'STRONGEST OBJECTION: objection' 'CHANGE MY MIND: evidence' 'ACCEPTANCE CHECKS: checks' 'FOLLOW-UP AREAS: none' >"$output"
    ;;
  trailing-whitespace-valid:*)
    {
      printf '%s  \n' 'ADVISOR RESPONSE'
      printf '%s\t\n' 'RECOMMENDATION: path'
      printf '%s  \n' 'WHY: reason'
      printf '%s\t\n' 'STRONGEST OBJECTION: objection'
      printf '%s \n' 'CHANGE MY MIND: evidence'
      printf '%s  \n' 'ACCEPTANCE CHECKS: checks'
      printf '%s\t\n' 'RISKS: none'
      printf '%s \n' 'FOLLOW-UP AREAS: none'
    } >"$output"
    ;;
  indented-continuation:*)
    printf '%s\n' 'ADVISOR RESPONSE' 'RECOMMENDATION: path' 'WHY: reason' '  WHY: indented continuation' 'STRONGEST OBJECTION: objection' 'CHANGE MY MIND: evidence' 'ACCEPTANCE CHECKS: checks' 'RISKS: none' 'FOLLOW-UP AREAS: none' >"$output"
    ;;
  response-duplicate:*)
    printf '%s\n' 'ADVISOR RESPONSE' 'RECOMMENDATION: path' 'WHY: reason' 'WHY: duplicate' 'STRONGEST OBJECTION: objection' 'CHANGE MY MIND: evidence' 'ACCEPTANCE CHECKS: checks' 'RISKS: none' 'FOLLOW-UP AREAS: none' >"$output"
    ;;
  response-renamed:*)
    printf '%s\n' 'ADVISOR RESPONSE' 'RECOMMENDATION: path' 'RATIONALE: reason' 'STRONGEST OBJECTION: objection' 'CHANGE MY MIND: evidence' 'ACCEPTANCE CHECKS: checks' 'RISKS: none' 'FOLLOW-UP AREAS: none' >"$output"
    ;;
  response-empty-valued:*)
    printf '%s\n' 'ADVISOR RESPONSE' 'RECOMMENDATION: path' 'WHY:' 'STRONGEST OBJECTION: objection' 'CHANGE MY MIND: evidence' 'ACCEPTANCE CHECKS: checks' 'RISKS: none' 'FOLLOW-UP AREAS: none' >"$output"
    ;;
  runtime-invalid-malformed:*)
    printf '%s\n' 'ADVISOR RESPONSE' 'WHY: reason' 'RECOMMENDATION: path' 'STRONGEST OBJECTION: objection' 'CHANGE MY MIND: evidence' 'ACCEPTANCE CHECKS: checks' 'RISKS: none' 'FOLLOW-UP AREAS: none' >"$output"
    ;;
  *)
    printf '%s\n' 'ADVISOR RESPONSE' 'RECOMMENDATION: path' 'WHY: reason' 'STRONGEST OBJECTION: objection' 'CHANGE MY MIND: evidence' 'ACCEPTANCE CHECKS: checks' 'RISKS: none' 'FOLLOW-UP AREAS: none' >"$output"
    ;;
esac
rollout=$CODEX_HOME/sessions/2026/08/30/rollout-fake-$child.jsonl
runtime_policy=read-only
case "${FAKE_CODEX_CASE-valid}" in runtime-invalid|runtime-invalid-malformed) runtime_policy=workspace-write ;; esac
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
chmod 700 "$fake_bin/codex"

transport_parent=56565656-5656-7565-8565-565656565656
valid_packet=$tmp/valid-packet.txt
printf '%s\n' DECISION 'question' CONTEXT 'evidence' OPTIONS 'choice' BOUNDARIES 'limits' REQUEST 'challenge' >"$valid_packet"
transport_out=$tmp/transport-out.json
transport_err=$tmp/transport-err.txt
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=valid FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$transport_out" 2>"$transport_err" || {
    sed -n '1,20p' "$transport_err" >&2
    fail "valid fake transport failed"
  }
[ "$(wc -l <"$transport_out" | tr -d ' ')" -eq 1 ] || fail "transport stdout was not one JSON line"
jq -e '.status=="completed" and .runtime.agent_role=="advisor-terra" and .runtime.model=="gpt-5.6-terra" and .runtime.effort=="high" and .runtime.sandbox_policy_type=="read-only" and .runtime.transport=="codex-exec" and (.response|startswith("ADVISOR RESPONSE\n"))' "$transport_out" >/dev/null || fail "valid transport JSON mismatch"
for progress_line in 'launching advisor-terra (gpt-5.6-terra, high, read-only)' 'inspecting persisted runtime evidence' 'consultation verified'; do
  grep -Fq "$progress_line" "$transport_err" || fail "transport stderr progress missing: $progress_line"
done

heartbeat_err=$tmp/heartbeat-err.txt
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=heartbeat FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$tmp/heartbeat-out.json" 2>"$heartbeat_err" || fail "heartbeat transport fixture failed"
[ "$(grep -Fc 'child invocation still running (attempt 1)' "$heartbeat_err")" -eq 1 ] || fail "heartbeat was not emitted once and cleaned up"
[ "$(wc -l <"$tmp/heartbeat-out.json" | tr -d ' ')" -eq 1 ] || fail "heartbeat fixture contaminated stdout"

whitespace_count=$tmp/whitespace-count
whitespace_out=$tmp/whitespace-out.json
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=trailing-whitespace-valid FAKE_CODEX_COUNT_FILE="$whitespace_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$whitespace_out" 2>/dev/null || fail "trailing-whitespace response failed"
[ "$(cat "$whitespace_count")" -eq 1 ] || fail "trailing-whitespace response retried"
whitespace_expected=$tmp/whitespace-expected.txt
{
  printf '%s  \n' 'ADVISOR RESPONSE'
  printf '%s\t\n' 'RECOMMENDATION: path'
  printf '%s  \n' 'WHY: reason'
  printf '%s\t\n' 'STRONGEST OBJECTION: objection'
  printf '%s \n' 'CHANGE MY MIND: evidence'
  printf '%s  \n' 'ACCEPTANCE CHECKS: checks'
  printf '%s\t\n' 'RISKS: none'
  printf '%s \n' 'FOLLOW-UP AREAS: none'
} >"$whitespace_expected"
jq -j '.response' "$whitespace_out" >"$tmp/whitespace-actual.txt"
cmp -s "$whitespace_expected" "$tmp/whitespace-actual.txt" || fail "transport changed raw trailing-whitespace response bytes"

continuation_count=$tmp/continuation-count
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=indented-continuation FAKE_CODEX_COUNT_FILE="$continuation_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$tmp/continuation-out.json" 2>/dev/null || fail "indented field-like continuation was treated as a structural duplicate"
[ "$(cat "$continuation_count")" -eq 1 ] || fail "indented field-like continuation triggered a retry"

retry_count=$tmp/retry-count
retry_err=$tmp/retry-err.txt
PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=malformed-first-valid-second FAKE_CODEX_COUNT_FILE="$retry_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >"$tmp/retry-out.json" 2>"$retry_err" || fail "runtime-valid malformed response did not retry successfully"
[ "$(cat "$retry_count")" -eq 2 ] || fail "malformed-first response did not launch exactly one retry"
jq -e '.status=="completed" and (.response|startswith("ADVISOR RESPONSE\nRECOMMENDATION:"))' "$tmp/retry-out.json" >/dev/null || fail "retry did not return only the valid second response"
grep -Fq 'runtime-valid response was empty or malformed; launching one fresh retry' "$retry_err" || fail "retry progress missing from stderr"

twice_count=$tmp/twice-count
if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=malformed-twice FAKE_CODEX_COUNT_FILE="$twice_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>&1; then fail "transport accepted two malformed responses"; fi
[ "$(cat "$twice_count")" -eq 2 ] || fail "malformed-twice did not stop after one retry"

reused_count=$tmp/reused-count
reused_err=$tmp/reused-err.txt
if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE=retry-reused-child FAKE_CODEX_COUNT_FILE="$reused_count" FAKE_PARENT_ID="$transport_parent" \
  sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>"$reused_err"; then fail "transport accepted a retry that reused the first child"; fi
[ "$(cat "$reused_count")" -eq 2 ] || fail "reused-child retry did not stop after exactly two launches"
grep -Fq 'retry reused the first child thread' "$reused_err" || fail "reused-child retry was not classified as terminal identity failure"

for terminal_case in launcher-failure duplicate-thread same-session runtime-invalid runtime-invalid-malformed; do
  terminal_count=$tmp/terminal-count-$terminal_case
  if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE="$terminal_case" FAKE_CODEX_COUNT_FILE="$terminal_count" FAKE_PARENT_ID="$transport_parent" \
    sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>&1; then fail "transport accepted terminal case: $terminal_case"; fi
  [ "$(cat "$terminal_count")" -eq 1 ] || fail "transport retried terminal case: $terminal_case"
done

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

for rejected_case in response-misordered response-missing response-duplicate response-renamed response-empty-valued; do
  rejected_count=$tmp/rejected-count-$rejected_case
  if PATH="$fake_bin:$PATH" CODEX_HOME="$fake_home" FAKE_CODEX_CASE="$rejected_case" FAKE_CODEX_COUNT_FILE="$rejected_count" FAKE_PARENT_ID="$transport_parent" \
    sh "$transport" --role advisor-terra --parent-thread "$transport_parent" <"$valid_packet" >/dev/null 2>&1; then
    fail "transport accepted fake case: $rejected_case"
  fi
  [ "$(cat "$rejected_count")" -eq 2 ] || fail "malformed response case did not exercise exactly one fresh retry: $rejected_case"
done
pass "run-advisor behavioral transport: raw trailing-whitespace preservation, indented continuation, exact field grammar, one runtime-gated malformed retry, fresh retry identity, second-malformed refusal, terminal no-retry, pinned read-only exec, stderr progress, and single JSON stdout"

audit_sessions=$tmp/audit-sessions; mkdir -p "$audit_sessions/2026/01/01"
python3 - "$audit_sessions/2026/01/01" <<'PY'
import json,sys
from pathlib import Path

root=Path(sys.argv[1])
def write(name, entries):
    root.joinpath(name).write_text("".join(json.dumps(entry)+"\n" for entry in entries),encoding="utf-8")
def stamp(second):
    return f"2026-01-01T00:00:{second:02d}Z"
def receipt(heading, **fields):
    return heading+"\n"+"\n".join(f"{key}: {value}" for key,value in fields.items())+"\nDO_NOT_LEAK_SECRET_PROMPT api_key=sk-forbidden contact@example.test"
def message(text, second):
    return {"timestamp":stamp(second),"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":text}]}}
def spawn(role, second):
    return {"timestamp":stamp(second),"type":"event_msg","payload":{"type":"item_completed","item":{"id":f"spawn-{role}-{second}","type":"CollabAgentToolCall","tool":"spawn_agent","status":"completed","receiver_agents":[{"agent_role":role,"thread_id":f"receiver-{role}-{second}"}]}}}
def legacy_spawn(role, second):
    return {"timestamp":stamp(second),"type":"response_item","payload":{"id":f"legacy-{role}-{second}","type":"collab_tool_call","tool":"spawn_agent","status":"completed","receiver_agents":[{"agent_role":role,"thread_id":f"legacy-receiver-{role}-{second}"}]}}
def request(role, second, call_id):
    arguments=json.dumps({"agent_type":role,"fork_turns":"none","message":"DO_NOT_LEAK_REQUEST_PROMPT api_key=sk-request-secret","task_name":"private-task"})
    return {"timestamp":stamp(second),"type":"response_item","payload":{"type":"function_call","name":"spawn_agent","namespace":"functions","call_id":call_id,"arguments":arguments}}
def activity(thread_id, kind, second, item_id):
    return {"timestamp":stamp(second),"type":"event_msg","payload":{"type":"item_completed","item":{"type":"SubAgentActivity","id":item_id,"agent_thread_id":thread_id,"agent_path":"DO_NOT_LEAK_AGENT_PATH","kind":kind}}}
root_meta={"timestamp":"2025-12-31T23:59:00Z","type":"session_meta","payload":{"id":"root-private-id","agent_role":"root","source":{"private":"DO_NOT_LEAK_SOURCE"}}}
duplicate_call=message(receipt("ADVISOR CALL",tier="Standard",role="advisor-terra",status="running"),2)
write("root.jsonl",[
    root_meta,
    message(receipt("ADVISOR DECISION",route="consult"),1),
    duplicate_call, duplicate_call,
    spawn("advisor-terra",3), spawn("advisor-terra",3),
    message(receipt("ADVISOR RESULT",status="completed",decision="accept"),4),
    message(receipt("ADVISOR DECISION",route="skip"),5),
    message(receipt("ADVISOR DECISION",route="unavailable"),6),
    message(receipt("ADVISOR DECISION",route="forbidden"),7),
    message("ADVISOR DECISION\nroute: consult\nroute: skip\nDO_NOT_LEAK_DUPLICATE_ROUTE",7),
    message(receipt("ADVISOR CALL",tier="Specialist",role="advisor-sol",status="running"),8),
    legacy_spawn("advisor-sol",9),
    message(receipt("ADVISOR RESULT",status="unavailable",decision="blocked"),10),
    spawn("sol_advisor",11), spawn("sol-advisor",12),
    request("advisor-terra",13,"request-terra"), request("advisor-terra",13,"request-terra"),
    request("advisor-sol",14,"request-sol"),
    activity("terra-private-id","started",15,"activity-terra-started"),
    activity("terra-private-id","interacted",15,"activity-terra-interacted"),
    activity("terra-private-id","completed",16,"activity-terra-completed"),
    activity("sol-private-id","started",17,"activity-sol-started"),
    activity("sol-private-id","interrupted",17,"activity-sol-interrupted"),
    activity("sol-private-id","completed",18,"activity-sol-completed"),
    activity("sol-private-id","completed",18,"activity-sol-completed"),
])
terra_entries=[
    {"timestamp":"2025-12-31T23:59:59Z","type":"session_meta","payload":{"agent_role":"advisor-terra","id":"terra-private-id","source":{"subagent":{"thread_spawn":{"agent_role":"advisor-terra"}}},"prompt":"DO_NOT_LEAK_TERRA_META"}},
    {"timestamp":stamp(11),"type":"turn_context","payload":{"sandbox_policy":{"type":"read-only"}}},
    message(receipt("ADVISOR DECISION",route="unavailable"),12),
    {"timestamp":stamp(12),"type":"response_item","payload":{"type":"custom_tool_call","text":"DO_NOT_LEAK_TOOL"}},
    {"timestamp":stamp(13),"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":4}}}},
]
write("terra.jsonl",terra_entries)
write("terra-duplicate-session.jsonl",terra_entries)
write("sol.jsonl",[
    {"timestamp":stamp(20),"type":"session_meta","payload":{"agent_role":"advisor-sol","id":"sol-private-id","source":{"subagent":{"thread_spawn":{"agent_role":"advisor-sol"}}}}},
    {"timestamp":stamp(22),"type":"turn_context","payload":{"sandbox_policy":{"type":"workspace-write"}}},
    {"timestamp":stamp(23),"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"DO_NOT_LEAK_RESPONSE"}]}},
    {"timestamp":stamp(24),"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":5,"output_tokens":6,"reasoning_output_tokens":7}}}},
])
# A legacy nested role mention is parent metadata, not exact current child metadata.
write("legacy-nested-role.jsonl",[
    {"timestamp":stamp(30),"type":"session_meta","payload":{"id":"legacy-private-id","source":{"subagent":{"thread_spawn":{"agent_role":"advisor-sol"}}}}},
    {"timestamp":stamp(31),"type":"turn_context","payload":{"sandbox_policy":{"type":"read-only"}}},
])
# Exact child metadata with no activity in the selected window must not count.
write("outside-window.jsonl",[
    {"timestamp":"2026-01-02T00:00:00Z","type":"session_meta","payload":{"agent_role":"advisor-terra","id":"outside-private-id"}},
    {"timestamp":"2026-01-02T00:00:01Z","type":"turn_context","payload":{"sandbox_policy":{"type":"read-only"}}},
])
PY
audit_out=$tmp/advisor-audit.json
audit_err=$tmp/advisor-audit.stderr
audit_before=$(snapshot "$audit_sessions/2026/01/01")
sh "$audit" --sessions-dir "$audit_sessions" --since 2026-01-01T00:00:00Z --until 2026-01-02T00:00:00Z >"$audit_out" 2>"$audit_err"
audit_after=$(snapshot "$audit_sessions/2026/01/01")
[ "$audit_before" = "$audit_after" ] || fail "advisor audit modified session fixtures"
jq -e '
  .schema_version==2 and .redacted==true and
  .decisions=={"consult":1,"skip":1,"unavailable":1} and
  .availability.decisions=="evidenced" and
  .consultations.attempted==2 and
  .consultations.advisor_child_sessions=={"total":2,"by_role":{"advisor-terra":1,"advisor-sol":1}} and
  .consultations.parent_spawn_completions=={"total":2,"by_role":{"advisor-terra":1,"advisor-sol":1},"availability":"evidenced"} and
  .consultations.parent_spawn_requests=={"count":2,"availability":"evidenced"} and
  .consultations.parent_subagent_activity=={"count":6,"by_kind":{"started":2,"interacted":1,"completed":2,"interrupted":1},"availability":"evidenced"} and
  .consultations.selected_roles=={"standard":1,"specialist":1} and
  .consultations.dispositions=={"completed":1,"unavailable":1,"blocked":1,"accept":1,"modify":0,"reject":0} and
  .runtime.sandbox_counts=={"read_only":1,"workspace_write":1,"other":0} and
  .runtime.advisor_tool_calls==1 and
  .runtime.child_durations=={"count":2,"total_ms":6000,"minimum_ms":2000,"maximum_ms":4000,"average_ms":3000,"availability":"evidenced"} and
  .runtime.tokens=={"input":30,"cached_input":7,"output":9,"reasoning":11} and
  .runtime.availability=={"sandbox_counts":"evidenced","advisor_tool_calls":"evidenced","tokens":"evidenced"} and
  .stale_role_attempts=={"sol_advisor":1,"sol-advisor":1}
' "$audit_out" >/dev/null || fail "advisor audit aggregate report mismatch"
grep -Fq 'ADVISOR AUDIT: session enumeration started' "$audit_err" || fail "advisor audit lacks enumeration progress"
grep -Fq 'ADVISOR AUDIT: session parsing started' "$audit_err" || fail "advisor audit lacks parsing progress"
if grep -Eqi 'DO_NOT_LEAK|private-id|receiver-|request-|activity-|root\.jsonl|secret_prompt|api_key|contact@example|sk-forbidden|private-task' "$audit_out" "$audit_err"; then fail "advisor audit leaked fixture content or identifiers"; fi
empty_sessions=$tmp/empty-audit-sessions; mkdir "$empty_sessions"
empty_audit=$tmp/empty-advisor-audit.json
sh "$audit" --sessions-dir "$empty_sessions" --since 2026-01-01T00:00:00Z --until 2026-01-02T00:00:00Z >"$empty_audit" 2>/dev/null
jq -e '
  .decisions=={"consult":0,"skip":0,"unavailable":0} and .availability.decisions=="unavailable" and
  .consultations.advisor_child_sessions=={"total":0,"by_role":{"advisor-terra":0,"advisor-sol":0}} and
  .consultations.parent_spawn_completions=={"total":null,"by_role":null,"availability":"unavailable"} and
  .consultations.parent_spawn_requests=={"count":null,"availability":"unavailable"} and
  .consultations.parent_subagent_activity=={"count":null,"by_kind":null,"availability":"unavailable"} and
  .runtime.sandbox_counts==null and .runtime.advisor_tool_calls==null and
  .runtime.tokens==null and .runtime.child_durations.availability=="unavailable" and
  .runtime.availability=={"sandbox_counts":"unavailable","advisor_tool_calls":"unavailable","tokens":"unavailable"}
' "$empty_audit" >/dev/null || fail "advisor audit guessed unavailable evidence"

corroboration_sessions=$tmp/corroboration-audit-sessions; mkdir -p "$corroboration_sessions/2026/01/01"
python3 - "$corroboration_sessions/2026/01/01" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
def write(name,entries): root.joinpath(name).write_text("".join(json.dumps(entry)+"\n" for entry in entries),encoding="utf-8")
def entry(second,type_,payload): return {"timestamp":f"2026-01-01T00:00:{second:02d}Z","type":type_,"payload":payload}
child_id="corroborated-child-private-id"
write("child.jsonl",[
  entry(1,"session_meta",{"id":child_id,"agent_role":"advisor-terra"}),
  entry(2,"turn_context",{"sandbox_policy":{"type":"read-only"}}),
])
arguments=json.dumps({"agent_type":"advisor-sol","fork_turns":"none","message":"DO_NOT_LEAK_REQUEST_ONLY","task_name":"private-request"})
write("parent.jsonl",[
  entry(1,"session_meta",{"id":"corroboration-parent-private-id","agent_role":"root"}),
  entry(2,"response_item",{"type":"function_call","name":"spawn_agent","call_id":"request-only-private-id","arguments":arguments}),
  entry(3,"event_msg",{"type":"item_completed","item":{"type":"SubAgentActivity","id":"started-private-id","agent_thread_id":child_id,"agent_path":"DO_NOT_LEAK_PATH","kind":"started"}}),
  entry(4,"event_msg",{"type":"item_completed","item":{"type":"SubAgentActivity","id":"completed-private-id","agent_thread_id":child_id,"agent_path":"DO_NOT_LEAK_PATH","kind":"completed"}}),
])
PY
corroboration_audit=$tmp/corroboration-audit.json
sh "$audit" --sessions-dir "$corroboration_sessions" --since 2026-01-01T00:00:00Z --until 2026-01-02T00:00:00Z >"$corroboration_audit" 2>/dev/null
jq -e '
  .consultations.advisor_child_sessions.total==1 and
  .consultations.parent_spawn_completions=={"total":null,"by_role":null,"availability":"unavailable"} and
  .consultations.parent_spawn_requests=={"count":1,"availability":"evidenced"} and
  .consultations.parent_subagent_activity=={"count":2,"by_kind":{"started":1,"interacted":0,"completed":1,"interrupted":0},"availability":"evidenced"}
' "$corroboration_audit" >/dev/null || fail "advisor audit inferred completion or role counts from current parent corroboration"
if grep -Eqi 'DO_NOT_LEAK|private-id|private-request' "$corroboration_audit"; then fail "advisor audit leaked corroboration fixture content"; fi
pass "advisor audit schema v2 current/legacy fixtures, exact decisions, current parent corroboration, fail-closed completion availability, window ordering, deduplication, redaction, unavailable evidence, and stderr progress"

python3 - "$tmp/result.json" "$tmp/rerun-result.json" "$tmp/unnecessary-rerun-result.json" "$tmp/boundary-three-of-four.json" "$tmp/boundary-two-of-four.json" "$fixtures" <<'PY'
import copy,json,sys
result,rerun_result,unnecessary_result,threshold_pass_result,threshold_fail_result,fixtures=sys.argv[1:]; items=json.load(open(fixtures))["cases"]
schemas=[]; n=0
def trial(route,risk="standard"):
  selected_role="advisor-terra" if risk=="standard" else "advisor-sol"
  selected_model="gpt-5.6-terra" if risk=="standard" else "gpt-5.6-sol"
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
def spawn(role="advisor-sol",model="gpt-5.6-sol",**changes):
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
write("fabricated-no-spawn",[{"type":"thread.started","thread_id":root_id},message("consult","advisor_count=1 role=advisor-sol model=gpt-5.6-sol\n")])
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
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-consult.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-consult.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-5.6-sol sh "$evaluator"
jq -e '.route=="consult" and .advisor_count==1 and .roles==["advisor-sol"] and .freshness=="distinct_receiver_thread" and .model=="gpt-5.6-sol" and .effort=="high" and .sandbox=="read-only"' "$tmp/valid-consult.json" >/dev/null || fail "valid Sol consult spawn evidence was not derived exactly"
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-lifecycle.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-lifecycle.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-5.6-sol sh "$evaluator"
jq -e '.route=="consult" and .advisor_count==1 and .roles==["advisor-sol"]' "$tmp/valid-lifecycle.json" >/dev/null || fail "one logical spawn lifecycle was not accepted"
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-terra.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-terra.json" ADVISOR_EXPECTED_ROLE=advisor-terra ADVISOR_EXPECTED_MODEL=gpt-5.6-terra sh "$evaluator"
jq -e '.role==null and .roles==["advisor-terra"] and .model=="gpt-5.6-terra" and .effort=="high"' "$tmp/valid-terra.json" >/dev/null || fail "valid Terra consult spawn evidence was not derived exactly"
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-skip.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-skip.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-5.6-sol sh "$evaluator"
jq -e '.route=="skip" and .advisor_count==0 and .roles==[]' "$tmp/valid-skip.json" >/dev/null || fail "valid skip/no-spawn evidence was not derived exactly"
ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/valid-unavailable.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/valid-unavailable.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-5.6-sol sh "$evaluator"
jq -e '.route=="unavailable" and .advisor_count==0 and .roles==[] and .freshness=="none"' "$tmp/valid-unavailable.json" >/dev/null || fail "valid unavailable/no-spawn preflight evidence was not derived exactly"
for rejected_events in unavailable-call unavailable-spawn fabricated-no-spawn empty-wait duplicate-spawn duplicate-started extra-uncompleted-spawn wrong-role wrong-model wrong-effort root-equals-child noncompleted; do
  if ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/$rejected_events.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/rejected.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-5.6-sol sh "$evaluator" >/dev/null 2>&1; then
    fail "runtime evidence parser accepted: $rejected_events"
  fi
done
if grep -Eq '11111111|22222222|PRIVATE PROMPT' "$tmp/valid-consult.json"; then fail "runtime evidence output leaked raw prompt or thread identifiers"; fi
grep -Fq 'parse_runtime_evidence "$raw" "$evidence" "$selected_role" "$selected_model" || write_unavailable runtime_evidence_unavailable' "$evaluator" || fail "live path bypasses the tested runtime evidence parser"
grep -Fq 'route=unavailable' "$evaluator" || fail "ephemeral evaluator does not expect unavailable preflight"
grep -Fq 'do not emit ADVISOR CALL, and do not spawn a child' "$evaluator" || fail "ephemeral evaluator permits a call or child spawn"

for policy_case in \
  'standard:advisor-terra gpt-5.6-terra' 'STANDARD:advisor-terra gpt-5.6-terra' \
  'specialist:advisor-sol gpt-5.6-sol' 'SPECIALIST:advisor-sol gpt-5.6-sol'; do
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

grep -Fq 'https://github.com/DannyMac180/sol-advisor' "$notice" || fail "NOTICE upstream URL"
grep -Fq '37b75cad535abdd46531f0227483a8842d045ab8' "$notice" || fail "NOTICE base"
grep -Fq 'David Schmidt / Zero Delta LLC' "$notice" || fail "NOTICE maintainer"
grep -Fq 'Daniel McAteer' "$notice" || fail "NOTICE original author"
grep -Fq 'Copyright (c) 2026 Daniel McAteer' "$license" || fail "LICENSE copyright"
if grep -Eqi 'substack|attentionheads' "$readme"; then fail "README retains Substack promotion"; fi
for phrase in 'consultation' 'read-only' 'workspace-write' 'run-advisor.sh' 'ADVISOR DECISION' 'ADVISOR CALL' 'ADVISOR RESULT' 'status: running' 'decision: blocked' 'distinct Codex consultation thread' 'advisor' 'gpt-5.6-terra' 'gpt-5.6-sol' 'unavailable' 'NOTICE.md'; do grep -Fqi "$phrase" "$readme" || fail "README parity omits: $phrase"; done
for document in "$operations" "$readme" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md"; do
  for phrase in 'ADVISOR CALL' 'ADVISOR RESULT' 'unavailable' 'blocked' 'distinct Codex consultation'; do
    grep -Fqi "$phrase" "$document" || fail "lifecycle documentation omits $phrase: $document"
  done
done
pass "README, NOTICE, LICENSE, UI, and operations parity"

sh -n "$script_dir"/*.sh
[ "$(stat -f '%Lp' "$parent_inspector" 2>/dev/null || stat -c '%a' "$parent_inspector")" = 644 ] || fail "parent inspector must remain mode 100644"
pass "all shell syntax and stderr-progress contract"
printf '%s\n' "VERIFY PASSED: Advisor 1.3.0 consultation-only static contract"
