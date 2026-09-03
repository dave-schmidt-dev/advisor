# Advisor Plugin Specification

## Product decision

Replace the upstream Sol Advisor delivery orchestration with one automatic, read-only
consultation layer for Codex. The plugin advises the root agent on material
technical decisions; it never implements, routes implementation, or performs
final verification.

The distributable plugin identity is `advisor`. Its single skill is `consultation`, and
the current candidate version is `1.3.4`. Release archives use that exact version.

Supported local Codex hosts are **Codex CLI and Codex desktop**. Generic ChatGPT is
out of scope.

## Outcome

When a Codex task contains a material design or diagnostic decision, implicit
skill matching causes the root to consult exactly one fresh advisor selected from
the decision-risk policy
before the decision is finalized. Routine work does not spawn an advisor.

The root owns the task, chooses whether advice is accepted, and records the
disposition. The root supplies enough evidence for the advisor to recommend a path;
when that is not possible, a valid result identifies a concrete research-first next
step, missing evidence, research questions, or bounded brainstorming areas. Any
later implementation continues through the repository's normal workflow, including
Switchyard where applicable.

## Trigger contract

The skill description must front-load both positive and negative matching terms.
`agents/openai.yaml` must explicitly set `policy.allow_implicit_invocation: true`.

Consult once per decision when at least one condition is true:

1. The task requires choosing between viable architectures, interfaces, data
   models, or compatibility behaviors.
2. A feature crosses module, process, persistence, trust, or concurrency
   boundaries.
3. A diagnosis still has competing plausible root causes after initial evidence
   gathering.
4. The task changes security, privacy, authorization, migration, recovery, or
   irreversible-state behavior.
5. The user explicitly asks for an advisor, challenge, second opinion, or
   architecture review.
6. Complex work is about to be declared complete. This completion consultation
   applies when the task already consulted, or when it spans multiple phases,
   files, or sessions. Its decision question is whether the finished work meets
   its stated contract and what evidence would falsify that. It is not the final
   diff review of skip condition 4, which stays with its existing owner.

Skip when every applicable condition is routine:

1. Factual answers, summaries, translations, or read-only status checks.
2. Mechanical edits with a fully determined transformation and acceptance test.
3. Formatting, renaming, dependency-free documentation synchronization, or
   execution of an already settled plan.
4. Final diff review or release verification already owned by another review
   workflow.
5. The user explicitly forbids delegation or asks to use only the root context.

Borderline cases skip. A consultation must have a concrete decision question;
"general quality" is not sufficient.

## Runtime contract

### Root declaration

Before the first implementation write, emit exactly one decision record:

```text
ADVISOR DECISION
route: consult | skip | unavailable
reason: <one task-specific sentence>
question: <bounded decision question, or none>
```

Read-only discovery may precede this declaration so the question can be grounded
in repository evidence. For a consult candidate, first run
`inspect-parent-runtime.sh`. It identifies the current parent only with
`CODEX_THREAD_ID`, resolves exactly one regular, nonsymlinked persisted rollout in a
caller-supplied/default sessions root, and accepts unambiguous recognized sandbox and
permission metadata. It never falls back to `CODEX_SESSION_ID`. A normal
`workspace-write` root remains eligible because the consultation uses a distinct
read-only transport. Missing, duplicate, malformed, or conflicting evidence must emit
one `route: unavailable` decision with no `ADVISOR CALL` and no consultation process;
this does not block root-owned work. An identified parent uses `route: consult`; the
ordinary `route: skip` path remains unchanged.

### Consult route

1. Before the `ADVISOR DECISION`, run the parent-runtime preflight. Continue only
   when it returns `status: available` with a recognized sandbox policy; otherwise
   emit the required unavailable decision and do not invoke the transport.
2. Verify the installed plugin includes `run-advisor.sh` and both runtime inspectors.
3. Select the role from decision risk. Standard consultation uses
   `advisor-terra`, pinned GPT-5.6 Terra / high, for material architecture,
   interface, data-model, compatibility, cross-boundary, competing-diagnosis,
   and generic advisor requests. Specialist consultation uses `advisor-sol`,
   pinned GPT-5.6 Sol / high, only for an unresolved security or trust boundary,
   an irreversible migration or data-loss decision, or a credible unresolved
   High-severity disagreement. Security adjacency and project importance alone
   do not qualify; a borderline role choice uses Terra. Parent model is irrelevant.
4. Immediately before transport invocation, emit a visible `ADVISOR CALL` receipt containing
   the selected tier and role, task-specific reason, bounded question, and
   `status: running`.
5. Invoke the fixed installed-plugin `run-advisor.sh` exactly once through the shell
   tool's `sandbox_permissions: require_escalated` boundary with the selected exact
   role label and the packet on stdin. Do not first attempt it inside the parent
   sandbox, where nested Codex app-server initialization is blocked. The elevation
   applies only to the fixed launcher; the child remains forced read-only and
   runtime-inspected. Resolve the absolute installed plugin root from the loaded skill
   path, require regular nonsymlinked scripts beneath it, and never elevate a
   repository-relative or workspace-resolved script. Do not call `codex exec`
   directly and do not pass a model or
   effort override. The wrapper maps the role to its pinned Terra/Sol model, forces
   High effort and `--sandbox read-only`, starts a distinct persisted Codex exec
   thread, and uses existing Codex authentication without reading or copying secrets.
   The single wrapper invocation may launch exactly one additional fresh child only
   under the response-retry rule below; the root does not launch a replacement itself.
   Deliver the packet only through a single-quoted heredoc whose delimiter is absent
   from the packet. Never use a workspace-writable packet file, unquoted heredoc,
   `eval`, or shell-interpolated packet text. Store all transport files beneath the
   nonsandbox-writable Codex home, never `$TMPDIR`.
6. Before consultation, the root performs any repository or web research. Send only
   the bounded packet below, with enough relevant root-gathered evidence and source
   references for a decision; do not send secrets, credentials, personal data, or
   irrelevant conversation history. The advisor uses zero tools: it does not inspect
   files, fetch the web, or conduct independent research. If the packet cannot settle
   the question, it identifies the specific missing evidence or research questions
   under `FOLLOW-UP AREAS` instead of researching.
7. For every launched child, before response classification or successful machine
   stdout, the wrapper runs `inspect-agent-runtime.sh` for that child and the parent.
   This inspection is mandatory, not a metadata fallback, and must prove exact
   allowlisted `codex_exec` or `Codex Desktop` provenance, role/model, High effort, a thread distinct from the parent,
   read-only isolation, and zero-tool behavior. The installed JSON Schema is the sole supported wrapper model-output contract. Direct/native role invocation is unsupported and is not schema-validated. Wrapper-owned semantic validation rejects
   invalid JSON and duplicate, missing, extra, wrong-type, noncontiguous-array, or
   blank fields. It deterministically renders an accepted object as the canonical eight-line `ADVISOR RESPONSE` receipt. Exactly one fresh corrective retry is
   allowed only after a runtime-valid response-validation failure; stderr and the retry prompt expose only its redacted failure `class` and
   `field`, never rejected content. A consultation launches at most two children.
   Packet, launcher, event, identity, same-session, runtime, wrong-model, wrong-effort,
   non-read-only, normalization, provenance, or tool-use failure is terminal and never
   retries. A second response-validation failure is unavailable. Every attempt artifact
   stays only in a private mode-0700 consultation directory beneath the private Codex
   transport root, and an unconditional exit trap removes it after every wrapper exit.
   Progress is stderr-only; successful stdout is one verified JSON object containing
   runtime evidence and the canonical receipt.
8. Treat a response that passed runtime inspection as advice, not authority. A valid
   processed response contains either a recommendation grounded in the packet or a
   concrete `FOLLOW-UP AREAS` entry. The root checks its cited source references and
   records `accept`, `modify`, or `reject` with one reason.
9. After runtime evidence and advice processing, always emit a visible
   `ADVISOR RESULT` receipt containing completed/unavailable status, tier, role,
   verified model and high effort, read-only isolation, a concise recommendation
   or unavailable, the accept/modify/reject/blocked disposition, and one-sentence
   reason.
10. After a valid, runtime-inspected completed result, the root may route only the
    identified research or brainstorming follow-up to an appropriate Luna or Terra
    subagent outside this consultation, synthesize the result, and optionally start a
    fresh consultation with fresh `ADVISOR CALL` and `ADVISOR RESULT` receipts. This
    does not rescue or alter the original result; an unavailable result cannot be
    rescued by follow-up work. The advisor may not spawn or conduct that work.
11. Do not independently start a replacement or second advisor, implementer, or final
    reviewer as part of this skill. The only permitted second child is the wrapper-owned
    retry in step 7.

If the exact completed transport evidence is unavailable, report `advisor unavailable`,
block the consult route, and never continue independently or silently substitute
another role or model.

`completed` requires mandatory post-response runtime inspection and a processed
advisor response with either a recommendation or a concrete `FOLLOW-UP AREAS`
entry. Unavailable runtime evidence, a non-read-only runtime policy, tool-use
evidence, or required advice must visibly produce
`status: unavailable`, `recommendation: unavailable`, and `decision: blocked`, and
remain fail-closed. Receipts summarize verified evidence and are not runtime proof;
the distinct Codex consultation thread remains the inspectable detailed record. The skip or
unavailable route emits only the existing `ADVISOR DECISION`, with no call/result
receipt and no transport invocation.

### Main-chat consultation receipts

```text
ADVISOR CALL
tier: Standard | Specialist
role: advisor-terra | advisor-sol
reason: <one task-specific sentence>
question: <bounded decision question>
status: running
```

```text
ADVISOR RESULT
status: completed | unavailable
tier: Standard | Specialist
role: advisor-terra | advisor-sol
model: <verified gpt-5.6-terra | gpt-5.6-sol>
effort: high
isolation: read-only
recommendation: <concise recommendation, or unavailable>
decision: accept | modify | reject | blocked
reason: <one sentence>
```

### Advisor input

```text
DECISION
<one question the root must resolve>

CONTEXT
<goal, relevant root-gathered evidence with source references, and current constraints>

OPTIONS
<known viable choices, including the root's tentative choice when one exists>

BOUNDARIES
<owned files, excluded scope, compatibility, security, and authority limits>

REQUEST
Challenge the tentative choice. Recommend one path when the packet supports a
decision; otherwise recommend a research-first next step and identify the specific
missing evidence, research questions, or bounded brainstorming areas under
FOLLOW-UP AREAS. Identify the strongest counterargument, name evidence that would
change the recommendation, and give specific acceptance checks. Use zero tools: do
not inspect files, call tools, fetch the web, or conduct independent research.
```

### Advisor model output and canonical receipt

The model emits exactly one JSON object matching the installed
`advisor-response.schema.json`, with no prose or code fences. It has six required
nonblank scalar strings (`recommendation`, `why`, `strongest_objection`,
`change_my_mind`, `risks`, `follow_up_areas`) and a required nonempty array of
nonblank strings (`acceptance_checks`). The wrapper, not a direct/native role
invocation, validates it and renders this exact eight-line receipt:

```text
ADVISOR RESPONSE
RECOMMENDATION: <recommendation>
WHY: <why>
STRONGEST OBJECTION: <strongest_objection>
CHANGE MY MIND: <change_my_mind>
ACCEPTANCE CHECKS: <acceptance checks joined by ; >
RISKS: <risks>
FOLLOW-UP AREAS: <follow_up_areas>
```

For a research-first response, `RECOMMENDATION` is the concise research-first plan
and `FOLLOW-UP AREAS` contains its concrete inquiries. In `ADVISOR RESULT`, `accept`
means the root accepts the returned technical recommendation or research-first plan;
it never implies that a technical choice was accepted when no technical choice was made.

## Boundaries

- The root remains architect, implementer-or-router, verifier, and acceptor.
- The root performs all repository and web research before consultation and supplies
  enough relevant evidence and source references for a decision; the advisor receives
  no secrets and makes no tool call, file inspection, web fetch, or independent
  research attempt. If a decision cannot yet be made, it may only identify a concrete
  research-first next step, missing evidence, research questions, or bounded
  brainstorming areas.
- After a valid runtime-inspected result, the root may use Luna or Terra subagents
  outside the consultation for the identified research or brainstorming, synthesize
  it, and optionally start a fresh separately receipted consultation. Unavailable
  runtime evidence cannot be rescued this way. An unavailable result cannot be rescued by follow-up work.
- Every wrapper-launched advisor response receives mandatory runtime inspection before
  a completed result; direct/native role invocation is unsupported and has no
  schema-validation claim. Missing, conflicting, non-read-only, provenance, or
  tool-use evidence blocks.
- Every consult candidate receives parent-runtime preflight before its decision
  receipt. It uses only `CODEX_THREAD_ID`, never `CODEX_SESSION_ID`, and fails closed
  on missing identity or rollout, symlinks/nonregular files, malformed, ambiguous, or
  conflicting metadata, and every non-read-only sandbox. Its typed unavailable result
  prevents a call or child spawn but does not block root-owned work.
- Switchyard remains the implementation router; the plugin must not contain an
  implementation role or bypass repository routing policy.
- The advisor is pre-decision consultation, not post-implementation review.
- No hooks, MCP server, connector, API key, network service, telemetry, or
  scheduled task is introduced.
- `advisor-audit.sh` is a local read-only, aggregate-only inspection command. It
  supports a caller-selected time window and an optional session directory for
  synthetic tests, writes progress to stderr before enumeration and parsing, and
  emits stable redacted JSON only. It may parse only allowlisted metadata, fixed
  receipt enums, event kinds, timestamps, and usage counters; it must not emit
  content, identifiers, paths, filenames, contact data, secret-shaped values, or
  cost estimates. Schema v2 must derive exact current `advisor-terra` and
  `advisor-sol` child-session identity from full-file `session_meta` before applying
  the half-open window to session activity. It must parse only allowlisted
  `ADVISOR DECISION` routes (`consult`, `skip`, and `unavailable`) in an exact
  top-level `decisions` object with separate availability, deduplicate repeated
  records, and report child sessions separately from parent `spawn_agent` completion
  evidence. Parent completion evidence has explicit `evidenced`/`unavailable`
  availability and JSON `null` counts unless a completed role-bearing spawn event
  exists. Current parent `response_item` `function_call` spawn requests and role-free
  `event_msg` `SubAgentActivity` kinds (`started`, `interacted`, `completed`, and
  `interrupted`) are separate corroborating aggregate coverage. Requests may not
  establish selected role or completion; activity may be counted only by correlation
  to an exact current child ID.
  Unknown runtime evidence is unavailable, never inferred.
- Installation may add only the exact `advisor-terra` and `advisor-sol` custom-agent TOMLs through a
  fail-closed, idempotent companion installer. An attended upgrade must also
  deactivate byte-exact known historical Sol Advisor role files by recoverably renaming
  implementation/review roles to `<role>.toml.retired-v0.6.0` and the historical
  consultation role to `sol-advisor.toml.retired-v1.0.0` and the obsolete neutral
  `advisor.toml` to `advisor.toml.retired-v1.0.1`, outside the `.toml` discovery
  pattern. An exact 1.1.0 same-path upgrade must retire `advisor-terra.toml` and
  `advisor-sol.toml` to their respective `.retired-v1.1.0` paths before installing
  the risk-described 1.3.0 roles. A later run resumes an exact retired-only 1.1.0
  state by installing the current role and accepts the exact current-plus-retired
  state as already migrated. An old active role plus its retirement path, a
  mismatched retired file, or a modified, unsafe, or conflicting active role stops
  migration. Historical retired-only roles remain already migrated. The installer
  must not edit Codex config.
- Existing modified or unsafe agent destinations are never overwritten.
- The byte-exact v0.6.0 retirement identities are:
  - Luna: `12fa9180a292876e6731bc325779123bcd931c3caa902fbf90d676a31833be84`
  - Terra: `77ed2f36bb149da5d9032230c3d6f5e5cd56b059b3fa5f59085249bba06e1f3a`
  - Sol reviewer: `0333acf0ef562bcfebd06009ac09bd1dd8cbc04c4cf28e08e9e049bd8bf202d2`
- Preserve and retire the existing byte-exact v0.2.0 and v0.5.0 Luna/Terra
  fingerprints already documented in `install-agents.sh`; direct upgrades from
  those releases must not require manual deletion.
- Also retire Terra fingerprint
  `06c318e5e93f37452635906394e6ea69fb6a65ba9e6ad7172d37b444e0dc871d`,
  used by the intermediate v0.3.0/v0.4.0/pre-revert v0.5.0 history. Unknown blobs
  still fail closed.
- Plugin installation identity is `advisor`. Set version `1.3.4` and make
  the manifest author identify David Schmidt / Zero Delta LLC. Preserve Daniel
  McAteer's MIT copyright in `LICENSE` and keep upstream provenance in root
  `NOTICE.md`; do not add upstream attribution to the marketplace listing,
  public site, README, or package. Use the owner-authorized project URLs.

## Implementation shape

```text
plugins/advisor/
  .codex-plugin/plugin.json
  agents/advisor-terra.toml
  agents/advisor-sol.toml
  scripts/install-agents.sh
  scripts/inspect-parent-runtime.sh
  scripts/inspect-agent-runtime.sh
  scripts/evaluate-triggers.sh
  scripts/verify.sh
  evals/trigger-cases.json
  skills/consultation/SKILL.md
  skills/consultation/agents/openai.yaml
  skills/consultation/references/operations.md
NOTICE.md
```

Remove the Luna and Terra implementation roles, the final-review role, selective
route modes, and their documentation. Do not leave compatibility aliases that can
trigger retired behavior.

## Acceptance

### Static verification

The repository verifier must prove:

1. Manifest JSON, marketplace JSON, TOML, YAML, and shell syntax are valid.
2. The plugin exposes exactly one skill and ships exactly two model-pinned custom-agent roles.
3. Implicit invocation is enabled and the skill description contains explicit
   consult and skip boundaries.
4. Retired `solo`, `delegate`, `audit`, `full`, Luna, Terra, and final-review
   contracts are absent from active plugin content.
5. The advisor roles pin the exact Terra/high and Sol/high pairs, request read-only
   sandboxing, and forbid tools, file inspection, web fetches, and independent
   research; static fixtures prove decision-risk role selection and exact spawn evidence.
6. The installer is fail-closed, idempotent, supports an isolated target, and
   refuses modified, symlinked, nonregular, unknown, or unsafe destinations.
7. Upgrade fixtures prove byte-exact retired roles become recoverable inactive
   files, a second run is idempotent, and modified, unsafe, or conflicting
   historical roles stop migration.
8. Parent preflight and mandatory post-response runtime inspection emit only
   allowlisted identity/isolation fields and fail closed on missing, conflicting,
   malformed, non-read-only, or tool-use evidence.
9. README, manifest UI text, skill metadata, operations reference, and examples
   describe the same workflow.
10. Every consult emits visible `ADVISOR CALL` and `ADVISOR RESULT` receipts; a
    skip emits neither, and unavailable evidence is visibly blocked fail-closed.
11. Audit schema v2 fixtures cover current and legacy session shapes, full-file
    child metadata followed by windowed activity, all allowlisted decision routes,
    unavailable parent completion evidence, current spawn-request and role-free
    activity corroboration, duplicate records, and adversarial redaction.

`verify.sh` with no arguments is exactly equivalent to `verify.sh --static` and
never starts Codex, performs network work, or requires a runtime result. Live
evaluation is owned only by `evaluate-triggers.sh`; its result verifier accepts a
typed unavailable artifact only when `--allow-unavailable` is explicit.

### Trigger evaluation

Static fixtures exercise the checked-in table of at least twelve prompts:

- four clear consult cases;
- four clear skip cases;
- four adversarial boundary cases, including explicit no-delegation, an explicit
  advisor request, a routine implementation, and a high-risk decision.

Persisted-fixture pass criteria:

- all clear cases choose the expected route;
- in each schema independently, each boundary case runs once; a mismatch receives
  exactly two more trials and its majority route becomes that schema's case result;
- at least three of four boundary cases choose the expected route after that
  bounded majority rule;
- every consult case spawns exactly one selected `advisor-terra` or `advisor-sol`
  role with fresh context and its pinned model;
- both `multi_agent_v2` feature states are covered without ever accepting a
  self-reported or inherited-context consultation as runtime evidence;
- every skip case spawns none;
- no case spawns an implementation worker or final reviewer through the plugin;
- unavailable or unverified advisor evidence is reported as unavailable, never
  counted as a successful consultation.
- ephemeral evaluation expects parent preflight unavailable because it has no
  persisted rollout; deterministic persisted fixtures separately prove the read-only
  consult path.

The live evaluation is a native host-runtime step because it uses an installed
subscription-authenticated Codex host, either Codex CLI or Codex desktop. It records
the exact version and surface. The parent
keeps its authenticated Codex home; the evaluator neither copies nor links auth
material. Each feature state uses an isolated temporary project and child runtime,
with `--ignore-user-config`, `--ignore-rules`, `--ephemeral`, and a read-only
sandbox. The project links only the repository-local consultation skill and plugin,
and `install-agents.sh --target-dir` installs and checks both exact roles in the child
runtime. The evaluator applies `--disable multi_agent_v2` and `--enable
multi_agent_v2` in separate runs when a persisted-runtime evaluation is available.
Its current ephemeral preflight must instead emit `route: unavailable`, with no
`ADVISOR CALL` or child spawn, because no parent rollout persists. Deterministic
persisted fixtures, not the ephemeral CLI run, prove a completed `spawn_agent` event,
the exact receiver role/model/effort, and a thread distinct from the root.
An unrecognized flag, unavailable custom role, absent or malformed spawn event, or
mismatched effective state is typed unavailable, not a test failure or pass.
The evaluator must stream progress and preserve one redacted machine-readable
result artifact covering both configurations.

The evaluator writes its local redacted result to
`.logs/advisor-trigger-evaluation.json`. The run command captures paired digests
for contract-owned live state (`config.toml`, `agents/`, `skills/`, and `plugins/`)
and marketplace state, including on an unavailable exit. Auth, session, log, and
cache files are explicitly excluded. Standalone nonmutation checks without this
paired snapshot are invalid.

Evaluation may use only the already-enabled subscription-backed Codex route with
overage disabled. The initial matrix is 24 root sessions across both schemas;
boundary-only reruns cap the total at 40. Any API-key-billed route, enabled
overage, added provider, or expansion beyond 40 root sessions is Red and parked.

## Release boundary

Overnight work may redesign, test, document, and locally checkpoint the plugin.
Unattended work may not install into the user's live Codex home, push, publish,
change the marketplace source, or claim live trigger acceptance without current
evidence. Publication and live installation remain attended, owner-authorized
actions; a missing external review or runtime spawn evidence is unavailable, not
approval to continue.
