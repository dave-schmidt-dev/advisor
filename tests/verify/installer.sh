# shellcheck shell=sh
# Sourced by plugins/advisor/scripts/verify.sh; do not run directly.
clean=$tmp/clean
sh "$installer" --target-dir "$clean" >/dev/null
cmp -s "$terra_role" "$clean/advisor-terra.toml" || fail "clean Terra install differs"
cmp -s "$sol_role" "$clean/advisor-sol.toml" || fail "clean Sol install differs"
cmp -s "$astra_role" "$clean/advisor-astra.toml" || fail "clean Astra install differs"
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
    if source==sol:
        current_pin='model = "gpt-6-sol"'
        if prior.count(current_pin)!=1: raise SystemExit("current Sol model fixture mismatch")
        prior=prior.replace(current_pin,'model = "gpt-5.6-sol"')
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
cmp -s "$astra_role" "$v110/advisor-astra.toml" || fail "Advisor 1.1.0 upgrade did not install Astra exactly"
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
cmp -s "$astra_role" "$v110_interrupted/advisor-astra.toml" || fail "retired-only upgrade did not install Astra exactly"
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
    if source.name=="advisor-sol.toml":
        current_pin='model = "gpt-6-sol"'
        if prior.count(current_pin)!=1: raise SystemExit("current Sol model fixture mismatch")
        prior=prior.replace(current_pin,'model = "gpt-5.6-sol"')
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
cmp -s "$astra_role" "$v130/advisor-astra.toml" || fail "Advisor 1.3.0 upgrade did not install Astra exactly"
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
cmp -s "$astra_role" "$v130_early/advisor-astra.toml" || fail "early Advisor 1.3.0 upgrade did not install Astra exactly"
assert_v110_digest "$v130_early/advisor-terra.toml.retired-v1.3.0" 4ad79cb613cc9865cb3d1db02f2e98b3b117524153c075a2de3d6bd249798c5e
assert_v110_digest "$v130_early/advisor-sol.toml.retired-v1.3.0" 4c29a9fec188e7c9c1618dacbcf0e26e40781f1ba783f425ece24c5919a16ad4
sh "$installer" --target-dir "$v130_early" --check >/dev/null
pass "both prior Advisor 1.3.0 generations upgrade to separate retirement paths"

# Upgrade the exact v1.4.5 Sol role, preserving it at a versioned recovery path.
v145=$tmp/advisor-v145; mkdir "$v145"
python3 - "$sol_role" "$v145/advisor-sol.toml" <<'PY'
from pathlib import Path
import sys
source,target=map(Path,sys.argv[1:])
text=source.read_text(encoding="utf-8")
current='model = "gpt-6-sol"'
if text.count(current)!=1: raise SystemExit("current Sol model fixture mismatch")
target.write_text(text.replace(current,'model = "gpt-5.6-sol"'),encoding="utf-8")
PY
actual=$(shasum -a 256 "$v145/advisor-sol.toml" | awk '{print $1}')
[ "$actual" = 8923bc56c5cd43db004bf1f2bfdabf3cee56dbcbe13434bb0b01cd5cdb523a7c ] || fail "Advisor 1.4.5 Sol fixture digest mismatch: $actual"
before=$(snapshot "$v145")
if sh "$installer" --target-dir "$v145" --check >/dev/null 2>&1; then fail "check accepted active Advisor 1.4.5 Sol role"; fi
after=$(snapshot "$v145"); [ "$before" = "$after" ] || fail "check mutated active Advisor 1.4.5 Sol role"
sh "$installer" --target-dir "$v145" >/dev/null
cmp -s "$sol_role" "$v145/advisor-sol.toml" || fail "Advisor 1.4.5 Sol upgrade did not install current role exactly"
actual=$(shasum -a 256 "$v145/advisor-sol.toml.retired-v1.4.5" | awk '{print $1}')
[ "$actual" = 8923bc56c5cd43db004bf1f2bfdabf3cee56dbcbe13434bb0b01cd5cdb523a7c ] || fail "Advisor 1.4.5 Sol retirement digest mismatch: $actual"
sh "$installer" --target-dir "$v145" --check >/dev/null
before=$(snapshot "$v145"); sh "$installer" --target-dir "$v145" >/dev/null; after=$(snapshot "$v145")
[ "$before" = "$after" ] || fail "Advisor 1.4.5 Sol upgrade is not idempotent"

v145_interrupted=$tmp/advisor-v145-interrupted; mkdir "$v145_interrupted"
cp "$v145/advisor-sol.toml.retired-v1.4.5" "$v145_interrupted/advisor-sol.toml.retired-v1.4.5"
sh "$installer" --target-dir "$v145_interrupted" >/dev/null
cmp -s "$sol_role" "$v145_interrupted/advisor-sol.toml" || fail "retired-only Advisor 1.4.5 upgrade did not resume"
sh "$installer" --target-dir "$v145_interrupted" --check >/dev/null
before=$(snapshot "$v145_interrupted"); sh "$installer" --target-dir "$v145_interrupted" >/dev/null; after=$(snapshot "$v145_interrupted")
[ "$before" = "$after" ] || fail "retired-only Advisor 1.4.5 state is not idempotent"

for kind in v145-edited v145-collision; do
  target=$tmp/refuse-$kind; mkdir "$target"
  cp "$v145/advisor-sol.toml.retired-v1.4.5" "$target/advisor-sol.toml"
  case "$kind" in
    v145-edited) printf '\n# owner edit\n' >>"$target/advisor-sol.toml" ;;
    v145-collision) printf 'unknown retirement collision\n' >"$target/advisor-sol.toml.retired-v1.4.5" ;;
  esac
  before=$(snapshot "$target")
  if sh "$installer" --target-dir "$target" >/dev/null 2>&1; then fail "installer accepted $kind Sol state"; fi
  after=$(snapshot "$target"); [ "$before" = "$after" ] || fail "$kind refusal mutated target"
done
pass "exact Advisor 1.4.5 Sol upgrade, retirement recovery, idempotency, and edited/collision refusal"

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
  cmp -s "$astra_role" "$target/advisor-astra.toml" || fail "$label Astra advisor install mismatch"
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

for kind in modified symlink nonregular astra-modified astra-symlink astra-nonregular dual collision neutral-modified neutral-dual v110-modified v110-dual v110-collision; do
  target=$tmp/refuse-$kind; mkdir "$target"
  case "$kind" in
    modified) printf 'unknown\n' >"$target/sol-advisor-luna-implementer.toml" ;;
    symlink) ln -s "$terra_role" "$target/sol-advisor-luna-implementer.toml" ;;
    nonregular) mkdir "$target/sol-advisor-luna-implementer.toml" ;;
    astra-modified) printf 'unknown\n' >"$target/advisor-astra.toml" ;;
    astra-symlink) ln -s "$astra_role" "$target/advisor-astra.toml" ;;
    astra-nonregular) mkdir "$target/advisor-astra.toml" ;;
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
pass "modified, symlink, nonregular, Astra destination, dual-path, destination-collision, obsolete-neutral, and 1.1.0 upgrade refusal"
