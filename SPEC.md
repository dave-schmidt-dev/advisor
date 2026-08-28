# Advisor Plugin Specification

## Product decision

Replace the upstream Sol Advisor delivery orchestration with one automatic, read-only
consultation layer for Codex. The plugin advises the root agent on material
technical decisions; it never implements, routes implementation, or performs
final verification.

The distributable plugin identity is `advisor`. Its single skill is `consultation`, and
the breaking redesign version is `1.0.0`. Local development installs may add
one `+codex.<cachebuster>` build suffix without changing that release identity.

## Outcome

When a Codex task contains a material design or diagnostic decision, implicit
skill matching causes the root to consult exactly one fresh advisor selected from
the parent-model policy
before the decision is finalized. Routine work does not spawn an advisor.

The root owns the task, chooses whether advice is accepted, and records the
disposition. Any later implementation continues through the repository's normal
workflow, including Switchyard where applicable.

## Trigger contract

The skill description must front-load both positive and negative matching terms.
`agents/openai.yaml` must explicitly set `policy.allow_implicit_invocation: true`.

Consult once when at least one condition is true:

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
route: consult | skip
reason: <one task-specific sentence>
question: <bounded decision question, or none>
```

Read-only discovery may precede this declaration so the question can be grounded
in repository evidence.

### Consult route

1. Verify the installed `advisor` custom role exactly matches the shipped
   profile.
2. Select the child model from the parent: Luna, Spark, or lower uses GPT-5.6
   Terra / high; Terra uses GPT-5.6 Sol / high; Sol uses a fresh GPT-5.6 Sol /
   high; unknown parents fail safe to GPT-5.6 Sol / high.
3. Spawn exactly one fresh subagent with `agent_type: advisor` and explicit selected
   model/high effort. Use the
   fresh-context field exposed by the host schema: `fork_turns: none` for the v2
   schema or `fork_context: false` for the v1 schema. Never send both, inherit
   context, or pass model or effort overrides.
4. Verify the completed spawn event first. Accept only the selected model, high
   reasoning, named role, and distinct receiver thread; invocation and role files
   establish read-only isolation. A local inspector may fill
   only metadata fields omitted by the public record.
5. Send only the bounded packet below. Do not send secrets, credentials, personal
   data, or irrelevant conversation history.
6. Treat the response as advice, not authority. The root checks cited repository
   evidence and records `accept`, `modify`, or `reject` with one reason.
7. Do not spawn a replacement, second advisor, implementer, or final reviewer as
   part of this skill.

If the exact completed spawn evidence is unavailable, report `advisor unavailable`,
block the consult route, and never continue independently or silently substitute
another role or model.

### Advisor input

```text
DECISION
<one question the root must resolve>

CONTEXT
<goal, observed evidence, and current constraints>

OPTIONS
<known viable choices, including the root's tentative choice when one exists>

BOUNDARIES
<owned files, excluded scope, compatibility, security, and authority limits>

REQUEST
Challenge the tentative choice. Recommend one path, identify the strongest
counterargument, name evidence that would change the recommendation, and give
specific acceptance checks. Remain read-only.
```

### Advisor output

```text
ADVISOR RESPONSE
RECOMMENDATION: <one path>
WHY: <decisive evidence and reasoning>
STRONGEST OBJECTION: <best case against the recommendation>
CHANGE MY MIND: <specific missing or contrary evidence>
ACCEPTANCE CHECKS: <concrete checks>
RISKS: <material residual risks, or none>
```

## Boundaries

- The root remains architect, implementer-or-router, verifier, and acceptor.
- Switchyard remains the implementation router; the plugin must not contain an
  implementation role or bypass repository routing policy.
- The advisor is pre-decision consultation, not post-implementation review.
- No hooks, MCP server, connector, API key, network service, telemetry, or
  scheduled task is introduced.
- Installation may add only the exact `advisor` custom-agent TOML through a
  fail-closed, idempotent companion installer. An attended upgrade must also
  deactivate byte-exact known historical Sol Advisor role files by recoverably renaming
  implementation/review roles to `<role>.toml.retired-v0.6.0` and the historical
  consultation role to `sol-advisor.toml.retired-v1.0.0`, outside the `.toml` discovery
  pattern. A later run treats an absent active role plus an exact retired file as
  already migrated. Both paths existing, a mismatched retired file, or a modified,
  unsafe, or conflicting active role stops migration. The installer must not edit
  Codex config.
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
- Plugin installation identity is `advisor`. Set version `1.0.0` and make
  the manifest author identify David Schmidt / Zero Delta LLC as the fork
  maintainer while crediting original author Daniel McAteer. Preserve Daniel
  McAteer's MIT copyright in `LICENSE`, add `NOTICE.md` with the upstream URL and
  audited base commit, and credit the origin in README. Remove the upstream
  Substack promotion, homepage, and repository values; omit homepage/repository
  fields until an owner-authorized project remote exists.

## Implementation shape

```text
plugins/advisor/
  .codex-plugin/plugin.json
  agents/advisor.toml
  scripts/install-agents.sh
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
2. The plugin exposes exactly one skill and ships exactly one custom-agent role.
3. Implicit invocation is enabled and the skill description contains explicit
   consult and skip boundaries.
4. Retired `solo`, `delegate`, `audit`, `full`, Luna, Terra, and final-review
   contracts are absent from active plugin content.
5. The advisor role is model-neutral and requests read-only sandboxing; static
   fixtures prove the parent-model selection policy and exact spawn evidence.
6. The installer is fail-closed, idempotent, supports an isolated target, and
   refuses modified, symlinked, nonregular, unknown, or unsafe destinations.
7. Upgrade fixtures prove byte-exact retired roles become recoverable inactive
   files, a second run is idempotent, and modified, unsafe, or conflicting
   historical roles stop migration.
8. Runtime inspection emits only allowlisted routing fields and fails on missing
   or conflicting evidence.
9. README, manifest UI text, skill metadata, operations reference, and examples
   describe the same workflow.

`verify.sh` with no arguments is exactly equivalent to `verify.sh --static` and
never starts Codex, performs network work, or requires a runtime result. Live
evaluation is owned only by `evaluate-triggers.sh`; its result verifier accepts a
typed unavailable artifact only when `--allow-unavailable` is explicit.

### Trigger evaluation

Run fresh Codex sessions against a checked-in table of at least twelve prompts:

- four clear consult cases;
- four clear skip cases;
- four adversarial boundary cases, including explicit no-delegation, an explicit
  advisor request, a routine implementation, and a high-risk decision.

Pass criteria:

- all clear cases choose the expected route;
- in each schema independently, each boundary case runs once; a mismatch receives
  exactly two more trials and its majority route becomes that schema's case result;
- at least three of four boundary cases choose the expected route after that
  bounded majority rule;
- every consult case spawns exactly one `advisor` role with fresh context and the
  model selected for its parent;
- both `multi_agent_v2` feature states are covered without ever accepting a
  self-reported or inherited-context consultation as runtime evidence;
- every skip case spawns none;
- no case spawns an implementation worker or final reviewer through the plugin;
- unavailable or unverified advisor evidence is reported as unavailable, never
  counted as a successful consultation.

The live evaluation is a native host-runtime step because it uses the installed
subscription-authenticated Codex CLI. It records the exact version. The parent
keeps its authenticated Codex home; the evaluator neither copies nor links auth
material. Each feature state uses an isolated temporary project and child runtime,
with `--ignore-user-config`, `--ignore-rules`, `--ephemeral`, and a read-only
sandbox. The project links only the repository-local consultation skill and plugin,
and `install-agents.sh --target-dir` installs and checks the exact role in the child
runtime. The evaluator applies `--disable multi_agent_v2` and `--enable
multi_agent_v2` in separate runs and confirms each effective state with `codex
features list`. A completed `spawn_agent` event, not model-authored output, must
prove the exact receiver role, model, effort, and a thread distinct from the root.
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
