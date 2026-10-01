# shellcheck shell=sh
# Sourced by plugins/advisor/scripts/verify.sh; do not run directly.
jq -e '
  .type == "object" and .additionalProperties == false and
  .required == ["recommendation", "why", "strongest_objection", "change_my_mind", "acceptance_checks", "risks", "follow_up_areas"] and
  (.properties | keys | sort) == (["recommendation", "why", "strongest_objection", "change_my_mind", "acceptance_checks", "risks", "follow_up_areas"] | sort) and
  all(.properties.recommendation, .properties.why, .properties.strongest_objection, .properties.change_my_mind, .properties.risks, .properties.follow_up_areas; .type == "string") and
  .properties.acceptance_checks.type == "array" and .properties.acceptance_checks.minItems == 1 and
  .properties.acceptance_checks.items == {"type":"string"}
' "$response_schema" >/dev/null || fail "response schema contract mismatch"
[ ! -L "$response_schema" ] || fail "response schema must not be a symlink"
pass "strict seven-field response schema"

python3 - "$manifest" "$marketplace" "$terra_role" "$sol_role" "$astra_role" "$fixtures" "$ui" "$models" "$live_config" <<'PY'
import json, re, sys, tomllib
from pathlib import Path
manifest=json.loads(Path(sys.argv[1]).read_text())
market=json.loads(Path(sys.argv[2]).read_text())
terra=tomllib.loads(Path(sys.argv[3]).read_text())
sol=tomllib.loads(Path(sys.argv[4]).read_text())
astra=tomllib.loads(Path(sys.argv[5]).read_text())
cases=json.loads(Path(sys.argv[6]).read_text())
ui=Path(sys.argv[7]).read_text()
models=json.loads(Path(sys.argv[8]).read_text())
live=tomllib.loads(Path(sys.argv[9]).read_text())
version=manifest.get("version","")
if manifest.get("name")!="advisor" or version!="1.4.8": raise SystemExit("manifest identity/version")
if "homepage" in manifest or "repository" in manifest: raise SystemExit("unowned upstream metadata remains")
author_name=manifest.get("author",{}).get("name","")
if author_name!="David Schmidt / Zero Delta LLC": raise SystemExit("plugin developer identity")
if manifest.get("skills")!="./skills/" or any(k in manifest for k in ("hooks","apps","mcpServers")): raise SystemExit("unsupported plugin components")
interface=manifest.get("interface",{})
if {key: interface.get(key) for key in ("websiteURL","supportURL","privacyPolicyURL","termsOfServiceURL")} != {"websiteURL":"https://zerodelta.dev/advisor/","supportURL":"https://zerodelta.dev/advisor/support/","privacyPolicyURL":"https://zerodelta.dev/advisor/privacy/","termsOfServiceURL":"https://zerodelta.dev/advisor/terms/"}: raise SystemExit("manifest URL fields")
if interface.get("category")!="Developer Tools": raise SystemExit("manifest category")
if interface.get("shortDescription")!="Architecture and code advice.": raise SystemExit("manifest short description")
if "Zero Delta receives no packets" not in interface.get("longDescription",""): raise SystemExit("manifest relay disclosure")
if models.get("transport_contract_version")!="1.4" or models.get("tested_codex_cli")!="codex-cli 0.153.2": raise SystemExit("model transport provenance")
if models.get("defaults")!={"standard":{"model":"gpt-5.6-terra","effort":"high"},"specialist":{"model":"gpt-6.1-sol","effort":"high"}}: raise SystemExit("model defaults")
if live != {"standard":{"model":"gpt-5.6-terra","effort":"high"},"specialist":{"model":"gpt-6.1-sol","effort":"high"}}: raise SystemExit("live config defaults")
if any("codex_cli_version_pattern" in (item.get("compatibility_baseline") or {}) for item in models.get("models", [])): raise SystemExit("CLI version eligibility pin")
if {item.get("model") for item in models.get("models",[])} != {"gpt-5.6-terra","gpt-6.1-sol","gpt-6-astra"}: raise SystemExit("model catalog inventory")
entry=market.get("plugins",[])
if market.get("name")!="advisor" or market.get("interface",{}).get("displayName")!="Codex Advisor": raise SystemExit("marketplace identity")
if len(entry)!=1 or entry[0].get("name")!="advisor" or entry[0].get("source")!={"source":"local","path":"./plugins/advisor"}: raise SystemExit("marketplace source")
if entry[0].get("policy")!={"installation":"AVAILABLE","authentication":"ON_INSTALL"} or entry[0].get("category")!="Developer Tools": raise SystemExit("marketplace policy")
pairs=((terra,{"name":"advisor-terra","description":"Standard fresh, read-only advisor for material technical decisions and generic advisor requests.","model":"gpt-5.6-terra","model_reasoning_effort":"high","sandbox_mode":"read-only"}),(sol,{"name":"advisor-sol","description":"Specialist fresh, read-only advisor for narrowly qualified unresolved critical decisions.","model":"gpt-6.1-sol","model_reasoning_effort":"high","sandbox_mode":"read-only"}),(astra,{"name":"advisor-astra","description":"Explicit opt-in, fresh, read-only advisor for higher-usage technical consultations.","model":"gpt-6-astra","model_reasoning_effort":"high","sandbox_mode":"read-only"}))
for role,pins in pairs:
    if any(role.get(k)!=v for k,v in pins.items()): raise SystemExit("role pins")
    if not all(isinstance(role.get(k),str) and role[k].strip() for k in ("description","developer_instructions")): raise SystemExit("role text")
    required=("Use zero tools.", "Do not call any tool or function", "inspect files or repositories", "browse, fetch, or search the web", "independent", "FOLLOW-UP AREAS", "research-first", "Do not spawn or route another agent")
    if any(phrase not in role["developer_instructions"] for phrase in required): raise SystemExit("role zero-tool contract")
items=cases.get("cases",[])
if len(items)!=14 or len({c.get("id") for c in items})!=14: raise SystemExit("fixture inventory")
counts={k:sum(c.get("class")==k for c in items) for k in ("consult","skip","boundary")}
if counts!={"consult":6,"skip":4,"boundary":4}: raise SystemExit(f"fixture classes {counts}")
if any(c.get("expected") not in ("consult","skip") or not c.get("prompt") for c in items): raise SystemExit("fixture fields")
risks={k:sum(c.get("risk")==k for c in items) for k in ("standard","specialist")}
if risks!={"standard":10,"specialist":4}: raise SystemExit(f"fixture risk tiers {risks}")
if {c["id"] for c in items if c.get("risk")=="specialist"}!={"consult-security","boundary-high-risk","consult-unresolved-compatibility","consult-competing-diagnoses"}: raise SystemExit("specialist fixture scope")
if "allow_implicit_invocation: true" not in ui or "interface:" not in ui or "policy:" not in ui: raise SystemExit("UI YAML contract")
print("structured files valid")
PY
pass "manifest, marketplace, live TOML, YAML, and 6/4/4 evaluator fixtures"

for phrase in \
  'ordinary bounded material architecture' 'interface' 'data-model' 'compatibility' \
  'cross-module' 'competing diagnoses' 'security' 'privacy' 'authorization' \
  'migration' 'recovery' 'irreversible-state' 'explicit advisor' \
  'factual/status/summarization' 'mechanical edits' 'formatting/renaming/docs synchronization' \
  'settled-plan execution' 'final review owned elsewhere' 'no-delegation' 'borderline case'; do
  grep -Fqi "$phrase" "$skill" || fail "skill description/contract omits: $phrase"
done
skill_header=$(sed -n '1,3p' "$skill")
for phrase in 'authorization' 'challenge' 'second-opinion' 'architecture-review'; do
  printf '%s\n' "$skill_header" | grep -Fqi "$phrase" || fail "skill selection vocabulary omits: $phrase"
done
for document in "$skill" "$operations" "$repo_dir/SPEC.md"; do
  for phrase in 'targeted evidence' 'leaves unresolved' 'compatibility or concurrency' 'competing diagnosis'; do
    grep -Fqi "$phrase" "$document" || fail "routing contract omits: $phrase: $document"
  done
done
for phrase in 'ADVISOR DECISION' 'route: consult | skip | unavailable' 'inspect-parent-runtime.sh' 'CODEX_THREAD_ID' 'CODEX_SESSION_ID' 'run-advisor.sh' \
  '--role advisor-terra' '--role advisor-sol' 'actual resolved model and effort metadata' \
  'Standard consultation' 'Specialist consultation' 'generic advisor requests' \
  'unresolved security or trust boundary' 'irreversible migration or data-loss decision' \
  'credible unresolved High-severity disagreement' 'Security adjacency or project importance alone' \
  'borderline choice uses Standard' 'parent model and sandbox are irrelevant' \
  'DECISION' 'CONTEXT' 'OPTIONS' 'BOUNDARIES' 'REQUEST' \
  'ADVISOR RESPONSE' 'RECOMMENDATION:' 'WHY:' 'STRONGEST OBJECTION:' 'CHANGE MY MIND:' \
  'ACCEPTANCE CHECKS:' 'RISKS:' 'FOLLOW-UP AREAS:' 'research-first' 'accept' 'modify' 'reject' 'advisor unavailable' \
  'ADVISOR CALL' 'status: running' 'ADVISOR RESULT' 'status: completed | unavailable' \
  'tier: Standard | Specialist' 'model: <resolved model selector>' \
  'model: <verified resolved model selector>' 'effort: <verified resolved effort>' \
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
for document in "$operations" "$repo_dir/SPEC.md"; do
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
# The skill sentence must stay on one physical line; grep '.*' does not span newlines.
grep -Eq 'non-Codex.*route: unavailable' "$skill" || fail "non-Codex unavailable route missing from skill"
pass "non-Codex surfaces document the unavailable route"

for document in "$skill" "$repo_dir/SPEC.md" "$operations"; do
  grep -Fqi 'completion consultation' "$document" || fail "completion-consultation contract missing: $document"
done
# Gate the rule itself, not the frontmatter restatement of it: the description alone
# must not be able to satisfy this check.
grep -Fq 'Emit a second `ADVISOR DECISION`' "$skill" || fail "skill omits the completion-consultation rule"
grep -Fq 'Complex work is about to be declared complete' "$repo_dir/SPEC.md" || fail "SPEC omits the completion trigger condition"
grep -Fqi 'takes one completion consultation before it is declared complete' "$operations" || fail "operations omits the completion-consultation rule"
if grep -Fqi 'completion consultation is a final diff review' "$skill"; then fail "completion consultation must not claim final review"; fi
pass "complex work takes one completion consultation that never becomes final review"

python3 - "$skill" "$operations" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md" <<'PY'
import sys
from pathlib import Path

skill, operations, spec, invariants = (
    Path(path).read_text(encoding="utf-8") for path in sys.argv[1:]
)
ownership = "The root owns architecture, implementation routing, verification, and acceptance."
legacy_ownership = "The root remains architect, implementer-or-router, verifier, and acceptor."
evidence_workers = (
    "The root may assign bounded evidence gathering to separate research workers before "
    "assembling the decision packet; the consulted advisor still uses zero tools and "
    "never delegates."
)
if ownership not in skill or ownership not in spec:
    raise SystemExit("root ownership sentence missing from skill or SPEC")
if legacy_ownership in skill or legacy_ownership in spec:
    raise SystemExit("legacy root ownership sentence remains")
if (
    "the advisor to recommend a path.\n\n"
    + evidence_workers
    + "\n\nIf that evidence cannot settle the question,"
) not in skill:
    raise SystemExit("skill evidence-worker paragraph placement changed")
if (
    "tools: it does not inspect files, fetch the web, or conduct independent research.\n\n"
    + evidence_workers
) not in operations:
    raise SystemExit("operations evidence-worker paragraph placement changed")
if f"{evidence_workers}\n\n### INV-12 — Redacted deferred audit" not in invariants:
    raise SystemExit("INVARIANTS evidence-worker paragraph placement changed")
print("ownership and bounded evidence-worker documentation exactness valid")
PY
pass "root ownership and bounded evidence-worker documentation parity"

[ -s "$compat_doc" ] || fail "public directory compatibility document missing or empty: $compat_doc"
python3 - "$compat_doc" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if not re.search(r"^OWNER DECISION:\s*(pending|approved|rejected)\s*$", text, re.MULTILINE):
    raise SystemExit("owner decision line missing or not one of pending/approved/rejected")
supported = ("Codex CLI", "Codex desktop")
unsupported = ("Generic ChatGPT with no local Codex runtime", "Native Codex subagents", "MCP servers and hosted services")
for surface in supported:
    if not re.search(r"\|\s*" + re.escape(surface) + r"\s*\|\s*Supported\s*\|", text):
        raise SystemExit(f"compatibility matrix does not mark supported: {surface}")
for surface in unsupported:
    if not re.search(r"\|\s*" + re.escape(surface) + r"\s*\|\s*Unsupported\b", text):
        raise SystemExit(f"compatibility matrix does not mark unsupported: {surface}")
PY
pass "public directory compatibility document: owner decision recorded and Codex CLI/desktop vs. non-Codex/subagent/MCP verdicts intact"
python3 - "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md" "$skill" "$operations" <<'PY'
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
for document in "$skill" "$operations" "$readme" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md"; do
  grep -Fqi 'sole supported wrapper model-output' "$document" || fail "JSON-only wrapper contract missing: $document"
  grep -Fqi 'wrapper-owned semantic validation' "$document" || fail "wrapper semantic-validation contract missing: $document"
  grep -Fqi 'canonical eight-line' "$document" || fail "canonical renderer contract missing: $document"
  grep -Fqi 'redacted failure' "$document" || fail "redacted failure diagnostic contract missing: $document"
  grep -Fqi 'at most two children' "$document" || fail "two-child retry bound missing: $document"
  grep -Fqi 'direct/native role invocation is unsupported' "$document" || fail "unsupported direct/native invocation contract missing: $document"
done
for document in "$skill" "$operations" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md"; do
  grep -Fqi 'runtime-valid response-validation failure' "$document" || fail "runtime-gated retry contract missing: $document"
  grep -Fqi 'terminal' "$document" || fail "terminal runtime failure contract missing: $document"
  grep -Fqi 'rejected content' "$document" || fail "rejected-content redaction contract missing: $document"
  grep -Fqi 'mode-0700 consultation directory' "$document" || fail "private consultation directory contract missing: $document"
  grep -Fqi 'unconditional exit trap' "$document" || fail "consultation cleanup contract missing: $document"
done
for document in "$skill" "$operations" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md"; do
  if grep -Eqi 'trailing spaces or tabs|raw response bytes|byte-preserved successful response|Structural recognition' "$document"; then
    fail "retired text-parser or raw-byte contract remains: $document"
  fi
done
grep -Fqi 'read-only' "$manifest" || fail "listing omits read-only boundary"
grep -Fqi 'tool-free' "$manifest" || fail "listing omits tool-free boundary"
grep -Fqi 'does not implement' "$manifest" || fail "listing omits implementation boundary"
pass "JSON schema, semantic validation, renderer, retry, privacy, cleanup, and unsupported-native documentation parity"
grep -Fqi 'accepting that plan' "$operations" || fail "research-first disposition semantics missing"
grep -Fqi '.retired-v1.3.0-zero-tool' "$operations" || fail "1.3.0 zero-tool retirement documentation missing"
grep -Fq 'substitute another model' "$skill" || fail "no-substitution rule missing"
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
for document in "$skill" "$operations"; do
  grep -Fq 'nonempty `session_id`' "$document" || fail "deferred handoff contract omits nonterminal session_id: $document"
  grep -Fq 'await tools.write_stdin' "$document" || fail "deferred handoff contract omits write_stdin polling: $document"
  grep -Fq 'while (process.session_id)' "$document" || fail "deferred handoff contract omits session polling loop: $document"
  grep -Fq 'combinedOutput += process.output ?? ""' "$document" || fail "deferred handoff contract does not preserve tool-output chunks: $document"
  grep -Fq 'const candidates = combinedOutput.split(/\r?\n/).flatMap' "$document" || fail "deferred handoff contract omits mixed-output extraction: $document"
  grep -Fq 'value.schema_version === 3' "$document" || fail "deferred handoff contract omits schema-v3 envelope check: $document"
  grep -Fq 'const verifiedEnvelope = candidates[0];' "$document" || fail "deferred handoff contract omits post-drain envelope handoff: $document"
  grep -Fq 'text(JSON.stringify(verifiedEnvelope));' "$document" || fail "deferred handoff contract omits final envelope delivery: $document"
  grep -Fq 'outer `functions.wait`' "$document" || fail "deferred handoff contract omits outer wait rule: $document"
done
for document in "$readme" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md"; do
  grep -Fq 'session_id' "$document" || fail "deferred handoff lifecycle documentation omits session handle: $document"
  grep -Fqi 'nonterminal' "$document" || fail "deferred handoff lifecycle documentation omits terminality rule: $document"
  grep -Fq 'exactly one schema-v3 envelope' "$document" || fail "deferred handoff lifecycle documentation omits final-envelope rule: $document"
done
python3 - "$skill" "$operations" <<'PY'
import sys
from pathlib import Path

for filename in sys.argv[1:]:
    lines = Path(filename).read_text(encoding="utf-8").splitlines()
    poll = next(i for i, line in enumerate(lines) if "while (process.session_id)" in line)
    parse = next(i for i, line in enumerate(lines) if "JSON.parse(line)" in line)
    emit = next(i for i, line in enumerate(lines) if "text(JSON.stringify(verifiedEnvelope));" in line)
    if parse <= poll:
        raise SystemExit(f"deferred handoff parses before draining session: {filename}")
    if emit <= parse:
        raise SystemExit(f"deferred handoff emits before envelope validation: {filename}")
    if not any("initial yielded result" in line and "nonterminal" in line for line in lines):
        raise SystemExit(f"initial yielded result terminality rule missing: {filename}")
    if not any("functions.wait" in line and "nonterminal" in line for line in lines):
        raise SystemExit(f"outer functions.wait terminality rule missing: {filename}")
print("deferred handoff contract ordering valid")
PY
pass "deferred exec results are drained with write_stdin and one final envelope is parsed after terminal exit"
for phrase in 'codex exec --json --ignore-user-config --ignore-rules' '--sandbox read-only --model "$model"' 'model_reasoning_effort="high"' '--skip-git-repo-check' '--output-schema "$response_schema"' '--output-last-message' 'ADVISOR TRANSPORT:' '--expected-parent "$parent_thread_id"' 'jq --stream' 'consultation reused the parent thread' 'response validation failed' 'advisor response was not verified'; do
  grep -Fq -- "$phrase" "$transport" || fail "transport contract omits: $phrase"
done
if grep -Eq 'response_is_well_formed|Normalize only trailing ASCII|original candidate remains untouched' "$transport"; then fail "retired line response parser remains"; fi
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
 294b5fe76799200b0ff814decc575a82ddbf4d426a4a680750113608de6516cd \
  517f670937b2174dcd6467e39381b55d3ba133bd97c697c988bf77082dd1531d; do
  grep -Fq "$digest" "$installer" || fail "missing historical digest: $digest"
done
grep -Fq 'sol_v146_retired=$sol_current.retired-v1.4.6' "$installer" || fail "installer omits the Advisor 1.4.6 Sol retired path"
grep -Fq 'active-known-v146' "$installer" || fail "installer omits the Advisor 1.4.6 Sol upgrade state"
pass "all historical and Advisor 1.1.0 through 1.4.6 upgrade fingerprints retained"
