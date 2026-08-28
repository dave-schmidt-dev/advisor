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
evaluator=$script_dir/evaluate-triggers.sh
readme=$repo_dir/README.md
notice=$repo_dir/NOTICE.md
license=$repo_dir/LICENSE

for file in "$manifest" "$marketplace" "$terra_role" "$sol_role" "$skill" "$ui" "$operations" "$fixtures" "$installer" "$inspector" "$evaluator" "$readme" "$notice" "$license"; do
  [ -f "$file" ] || fail "missing required file: $file"
done
[ "$(find "$plugin_dir/agents" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')" -eq 2 ] || fail "expected exactly two active roles"
[ "$(find "$plugin_dir/skills" -type f -name SKILL.md | wc -l | tr -d ' ')" -eq 1 ] || fail "expected exactly one skill"
pass "required inventory: one skill, two model-pinned roles, evaluator, documentation"

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
if market.get("name")!="advisor" or market.get("interface",{}).get("displayName")!="Advisor": raise SystemExit("marketplace identity")
if len(entry)!=1 or entry[0].get("name")!="advisor" or entry[0].get("source")!={"source":"local","path":"./plugins/advisor"}: raise SystemExit("marketplace source")
if entry[0].get("policy")!={"installation":"AVAILABLE","authentication":"ON_INSTALL"} or not entry[0].get("category"): raise SystemExit("marketplace policy")
pairs=((terra,{"name":"advisor-terra","description":"Standard fresh, read-only advisor for material technical decisions and generic advisor requests.","model":"gpt-5.6-terra","model_reasoning_effort":"high","sandbox_mode":"read-only"}),(sol,{"name":"advisor-sol","description":"Specialist fresh, read-only advisor for narrowly qualified unresolved critical decisions.","model":"gpt-5.6-sol","model_reasoning_effort":"high","sandbox_mode":"read-only"}))
for role,pins in pairs:
    if any(role.get(k)!=v for k,v in pins.items()): raise SystemExit("role pins")
    if not all(isinstance(role.get(k),str) and role[k].strip() for k in ("description","developer_instructions")): raise SystemExit("role text")
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
for phrase in 'ADVISOR DECISION' 'route: consult | skip' 'fork_turns: none' 'fork_context: false' \
  'agent_type: advisor-terra' 'agent_type: advisor-sol' 'gpt-5.6-terra' 'gpt-5.6-sol' \
  'Standard consultation' 'Specialist consultation' 'generic advisor requests' \
  'unresolved security or trust boundary' 'irreversible migration or data-loss decision' \
  'credible unresolved High-severity disagreement' 'Security adjacency or project importance alone' \
  'borderline role choice' 'model is irrelevant' \
  'DECISION' 'CONTEXT' 'OPTIONS' 'BOUNDARIES' 'REQUEST' \
  'ADVISOR RESPONSE' 'RECOMMENDATION:' 'WHY:' 'STRONGEST OBJECTION:' 'CHANGE MY MIND:' \
  'ACCEPTANCE CHECKS:' 'RISKS:' 'accept' 'modify' 'reject' 'advisor unavailable' \
  'ADVISOR CALL' 'status: running' 'ADVISOR RESULT' 'status: completed | unavailable' \
  'tier: Standard | Specialist' 'role: advisor-terra | advisor-sol' \
  'model: <verified gpt-5.6-terra | gpt-5.6-sol>' 'effort: high' \
  'isolation: read-only' 'recommendation: <concise recommendation, or unavailable>' \
  'decision: accept | modify | reject | blocked' 'recommendation: unavailable' \
  'decision: blocked' 'native child thread remains the inspectable detailed record'; do
  grep -Fq "$phrase" "$skill" || fail "consultation contract omits: $phrase"
done
grep -Fq 'Never send both or inherit' "$skill" || fail "fresh-context exclusion missing"
grep -Fq 'never substitute a role other than the policy-selected' "$skill" || fail "no-substitution rule missing"
grep -Fq 'For `skip`, emit only the existing `ADVISOR DECISION`' "$skill" || fail "skip receipt exclusion missing"
call_line=$(grep -n '^ADVISOR CALL$' "$skill" | head -1 | cut -d: -f1)
spawn_line=$(grep -n '^4\. Spawn exactly one selected role\.' "$skill" | head -1 | cut -d: -f1)
response_line=$(grep -n '^Treat the response as evidence' "$skill" | head -1 | cut -d: -f1)
result_line=$(grep -n '^ADVISOR RESULT$' "$skill" | head -1 | cut -d: -f1)
[ -n "$call_line" ] && [ -n "$spawn_line" ] && [ "$call_line" -lt "$spawn_line" ] || fail "ADVISOR CALL must precede spawn"
[ -n "$response_line" ] && [ -n "$result_line" ] && [ "$response_line" -lt "$result_line" ] || fail "ADVISOR RESULT must follow response processing"
pass "implicit consult/skip boundaries and exact request/response contract"

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
 5ab78b10e1abd4b86d8adeb7d71aa6b4d1c79b1a44457d2c717f5a03cd360367; do
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
for source,(new,old) in replacements.items():
    text=source.read_text(encoding="utf-8")
    if text.count(new)!=1: raise SystemExit(f"current role description fixture mismatch: {source}")
    target.joinpath(source.name).write_text(text.replace(new,old),encoding="utf-8")
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
rollout=$sessions/rollout-fixture-$id.jsonl
printf '%s\n' \
 '{"type":"response_item","payload":{"text":"DO_NOT_LEAK"}}' \
 "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$id\",\"parent_thread_id\":\"00000000-0000-7000-8000-000000000000\",\"agent_role\":\"advisor-sol\"}}" \
 '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >"$rollout"
out=$(TMPDIR=/nonexistent-read-only-path sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol "$id")
printf '%s\n' "$out" | jq -e '.agent_role=="advisor-sol" and .model=="gpt-5.6-sol" and .effort=="high" and .sandbox_policy_type=="read-only" and (keys|sort)==["agent_role","effort","model","parent_thread_id","permission_profile_type","sandbox_policy_type","thread_id"]' >/dev/null || fail "inspector allowlist/pins"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-terra --expected-model gpt-5.6-terra "$id" >/dev/null 2>&1; then fail "inspector accepted a role/model pair other than the selected pair"; fi
printf '%s\n' "$out" | grep -Fq DO_NOT_LEAK && fail "inspector leaked payload"
printf '%s\n' '{"type":"turn_context","payload":{"model":"gpt-5.6-terra","effort":"high","sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}' >>"$rollout"
if sh "$inspector" --sessions-dir "$tmp/sessions" --expected-role advisor-sol --expected-model gpt-5.6-sol "$id" >/dev/null 2>&1; then fail "inspector accepted conflicting model"; fi
pass "runtime inspector exact allowlist, pin validation, redaction, and conflict refusal"

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
for rejected_events in fabricated-no-spawn empty-wait duplicate-spawn duplicate-started extra-uncompleted-spawn wrong-role wrong-model wrong-effort root-equals-child noncompleted; do
  if ADVISOR_PARSE_RUNTIME_EVIDENCE="$events/$rejected_events.jsonl" ADVISOR_RUNTIME_EVIDENCE_OUT="$tmp/rejected.json" ADVISOR_EXPECTED_ROLE=advisor-sol ADVISOR_EXPECTED_MODEL=gpt-5.6-sol sh "$evaluator" >/dev/null 2>&1; then
    fail "runtime evidence parser accepted: $rejected_events"
  fi
done
if grep -Eq '11111111|22222222|PRIVATE PROMPT' "$tmp/valid-consult.json"; then fail "runtime evidence output leaked raw prompt or thread identifiers"; fi
grep -Fq 'parse_runtime_evidence "$raw" "$evidence" "$selected_role" "$selected_model" || write_unavailable runtime_evidence_unavailable' "$evaluator" || fail "live path bypasses the tested runtime evidence parser"

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
for phrase in 'multi_agent_v2=false/true' 'pooled cap of 40' 'subscription-only' 'overage' 'Progress goes' 'before/after digests'; do grep -Fqi "$phrase" "$operations" || fail "operations omits evaluator parity: $phrase"; done
pass "deterministic evaluator base path, exact pinned-role/model spawn evidence, lifecycle duplicate and extra-logical-spawn refusal, redaction, authenticated-parent isolation flags, mismatch reruns, 2-of-3 majority, unnecessary-rerun refusal, exact 3-of-4 boundary threshold, 2-of-4 rejection, Codex CLI and feature-state compatibility/refusal, typed unavailable, schemas, cap, progress-visible snapshots, and nonmutation"

grep -Fq 'https://github.com/DannyMac180/sol-advisor' "$notice" || fail "NOTICE upstream URL"
grep -Fq '37b75cad535abdd46531f0227483a8842d045ab8' "$notice" || fail "NOTICE base"
grep -Fq 'David Schmidt / Zero Delta LLC' "$notice" || fail "NOTICE maintainer"
grep -Fq 'Daniel McAteer' "$notice" || fail "NOTICE original author"
grep -Fq 'Copyright (c) 2026 Daniel McAteer' "$license" || fail "LICENSE copyright"
if grep -Eqi 'substack|attentionheads' "$readme"; then fail "README retains Substack promotion"; fi
for phrase in 'consultation' 'read-only' 'ADVISOR DECISION' 'ADVISOR CALL' 'ADVISOR RESULT' 'status: running' 'decision: blocked' 'native child thread' 'advisor' 'gpt-5.6-terra' 'gpt-5.6-sol' 'unavailable' 'NOTICE.md'; do grep -Fqi "$phrase" "$readme" || fail "README parity omits: $phrase"; done
for document in "$operations" "$readme" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md"; do
  for phrase in 'ADVISOR CALL' 'ADVISOR RESULT' 'unavailable' 'blocked' 'native child thread'; do
    grep -Fqi "$phrase" "$document" || fail "lifecycle documentation omits $phrase: $document"
  done
done
pass "README, NOTICE, LICENSE, UI, and operations parity"

sh -n "$script_dir"/*.sh
pass "all shell syntax and stderr-progress contract"
printf '%s\n' "VERIFY PASSED: Advisor 1.3.0 consultation-only static contract"
