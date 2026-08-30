# Consultation operations

Advisor provides pre-decision advice only. It does not implement, route
implementation, perform final review, or replace root authority. The root performs
any repository or web research before consultation and sends enough relevant evidence
and source references in the five-section packet for a decision. If the evidence is
not enough, the advisor may identify only a concrete research-first next step, missing
evidence, research questions, or bounded brainstorming areas. The advisor uses zero
tools: it does not inspect files, fetch the web, or conduct independent research.

## Install and verify the companion roles

From the repository root:

```sh
sh plugins/advisor/scripts/install-agents.sh
sh plugins/advisor/scripts/install-agents.sh --check
```

The installer adds only `advisor-terra.toml` and `advisor-sol.toml`. During an attended upgrade it
recoverably retires byte-exact known historical Luna, Terra, and Sol-reviewer files
to `<role>.toml.retired-v0.6.0`, the old Sol consultation role to
`sol-advisor.toml.retired-v1.0.0`, and the obsolete neutral role to
`advisor.toml.retired-v1.0.1`. It preflights every path before mutation, is
idempotent, refuses symlinks/nonregular files/modified content/collisions/dual paths,
and never edits Codex configuration. An exact Advisor 1.1.0 upgrade recoverably
retires the prior model-pinned roles to `advisor-terra.toml.retired-v1.1.0` and
`advisor-sol.toml.retired-v1.1.0`, then installs the risk-described 1.3.0 roles at
their original active paths. Later exact 1.3.0 generations retire separately to
`.retired-v1.3.0` and `.retired-v1.3.0-zero-tool`, preserving both predecessor
files without collision. Exact retired-only interrupted states resume safely;
modified, dual, or colliding states refuse all mutation.

## Root and advisor records

For a consult candidate, before the first implementation write and before the
decision record, run:

```sh
sh <absolute-installed-plugin-root>/scripts/inspect-parent-runtime.sh
```

This preflight identifies the parent only with `CODEX_THREAD_ID`; it never falls back
to `CODEX_SESSION_ID`. It resolves one regular, nonsymlinked rollout in the
caller-supplied/default sessions root and accepts an unambiguous recognized sandbox
and permission profile. The parent may be `workspace-write`; the separate consultation
transport owns read-only isolation. Missing, malformed, duplicate, or conflicting
evidence is typed unavailable.

Then emit:

```text
ADVISOR DECISION
route: consult | skip | unavailable
reason: <one task-specific sentence>
question: <bounded decision question, or none>
```

An identified parent permits `consult`, including a normal `workspace-write` root.
An unavailable preflight emits `route: unavailable`, with no `ADVISOR CALL`, no
consultation process, and no block on root-owned work. The ordinary `skip` route
remains unchanged.

For a consult, select the exact role label from decision risk:

- Standard: `advisor-terra`, pinned `gpt-5.6-terra`, high. This default covers
  material architecture, interface, data-model, compatibility, cross-boundary,
  competing-diagnosis, and generic advisor requests.
- Specialist: `advisor-sol`, pinned `gpt-5.6-sol`, high, only for an unresolved
  security or trust boundary, an irreversible migration or data-loss decision,
  or a credible unresolved High-severity disagreement.

Security adjacency and project importance alone do not qualify for Specialist.
A borderline role choice uses Standard. The parent model is irrelevant.

Never call `codex exec` directly or pass a model/effort override. Invoke the fixed
installed-plugin wrapper through the shell tool's
`sandbox_permissions: require_escalated` boundary with a narrow justification; do
not first attempt it inside the parent sandbox, where nested Codex app-server
initialization is blocked. This elevation launches only the fixed wrapper. The child
remains forced to `--sandbox read-only` and must pass runtime inspection. The wrapper
maps the selected exact role label to its model pin, forces High effort and a
read-only sandbox, and creates a distinct persisted consultation thread:

```sh
/bin/sh <absolute-installed-plugin-root>/scripts/run-advisor.sh --role advisor-terra <<'ADVISOR_PACKET'
DECISION
<the complete five-section packet continues here>
ADVISOR_PACKET
# or use: --role advisor-sol
```

Resolve `<absolute-installed-plugin-root>` from the loaded `SKILL.md` path, two
directories above its containing directory. Require regular, nonsymlinked scripts
beneath that root. Never elevate a repository-relative or workspace-resolved
`plugins/advisor` script.
Use only the shown single-quoted heredoc after confirming its delimiter is absent from
the packet. Never use `< packet.txt`, an unquoted heredoc, `eval`, or shell-interpolated
packet text at the elevated boundary, and never stage the packet in a
workspace-writable file.

The wrapper uses existing Codex authentication in place; it does not read, copy,
print, or relink authentication material. Send the five-section
DECISION/CONTEXT/OPTIONS/BOUNDARIES/REQUEST packet from the skill, with only
root-gathered relevant evidence and source references. Require:

```text
ADVISOR RESPONSE
RECOMMENDATION: <one path>
WHY: <decisive evidence and reasoning>
STRONGEST OBJECTION: <best case against the recommendation>
CHANGE MY MIND: <specific missing or contrary evidence>
ACCEPTANCE CHECKS: <concrete checks>
RISKS: <material residual risks, or none>
FOLLOW-UP AREAS: <none, or a concrete research-first next step, missing evidence,
research questions, or bounded brainstorming areas>
```

Immediately after every launched child, before response classification or machine
output, the wrapper runs `inspect-agent-runtime.sh` for that thread, expected
role/model, and parent thread. This mandatory inspection verifies `codex_exec`
provenance, a thread distinct from the parent, High effort, read-only isolation, and
zero tool use; it is not a metadata fallback. Structural recognition trims only
trailing spaces or tabs from a separate validation copy and preserves the successful
response bytes. Leading indentation, a nonliteral-space separator, and missing,
duplicate, renamed, misordered, or empty-valued fields remain
malformed. A runtime-valid empty or malformed first response receives exactly one fresh retry
with stderr progress. Packet, launcher, event, identity, same-session,
runtime, wrong-model, wrong-effort, non-read-only, normalization, or tool-use failure is terminal and
never retries. A second empty or malformed response is unavailable; the rejected first
response is never accepted or merged. If packet evidence is
insufficient, the advisor names the specific missing evidence or research questions
under `FOLLOW-UP AREAS` instead of researching. A valid processed response contains
either a recommendation grounded in the packet or a concrete `FOLLOW-UP AREAS`
entry. Only then does the root verify the response's cited source references and
record `accept`, `modify`, or `reject`. For a research-first response, the concise
research-first plan is the recommendation and `accept` means accepting that plan,
not a technical choice the advisor did not make. The advisor is never authoritative.

After a valid, runtime-inspected completed result, the root may route only its
research or brainstorming follow-up to an appropriate Luna or Terra subagent outside
this consultation, synthesize the result, and optionally begin a fresh consultation
with fresh `ADVISOR CALL` and `ADVISOR RESULT` receipts. An unavailable result cannot be rescued by follow-up work, and the advisor may not spawn or conduct that work.

Immediately before invoking the consultation transport, the root emits:

```text
ADVISOR CALL
tier: Standard | Specialist
role: advisor-terra | advisor-sol
reason: <one task-specific sentence>
question: <bounded decision question>
status: running
```

After runtime evidence and advice processing, it always emits:

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

Only mandatory post-response runtime inspection plus a processed response can produce
`completed`. Missing, conflicting, non-read-only, tool-use, or required-advice
evidence produces `status: unavailable`, `recommendation: unavailable`, and
`decision: blocked`; the consult route remains fail-closed. These main-chat receipts
summarize verified evidence but are not runtime proof. The distinct Codex consultation
thread remains the inspectable detailed record. A skip emits only `ADVISOR DECISION`,
with no call/result receipt and no transport invocation.

## Runtime evidence

Persisted `codex exec` runtime metadata is primary. The transport must establish one
fresh thread, the exact decision-risk-selected `advisor-terra`/`gpt-5.6-terra` or
`advisor-sol`/`gpt-5.6-sol` pair, effort `high`, a read-only sandbox, `codex_exec`
provenance, and a thread distinct from the parent. The wrapper runs:

```sh
sh <absolute-installed-plugin-root>/scripts/inspect-agent-runtime.sh --expected-role <selected-role> --expected-model <selected-model> --expected-parent <parent-thread-id> <thread-id>
```

The inspector emits only thread, parent, role, transport, model, effort,
sandbox-policy, and permission-profile fields, while rejecting any tool-use event. It must confirm a
read-only runtime policy; a role TOML requesting read-only is not proof of actual
isolation. Missing, conflicting, unexpected, non-read-only, or tool-use evidence is
unavailable, never approval. No substitute advisor role or replacement consultation
is allowed; any root-routed follow-up remains outside this consultation. Progress is
stderr-only and successful stdout is one verified JSON object containing the allowlisted
runtime evidence and the byte-preserved successful response. Every launched child is
inspected before retry eligibility is decided. Exactly one retry is permitted only for
a runtime-valid empty or structurally malformed first response; terminal transport or
runtime failures never retry.

## Local advisor audit

Use the read-only local audit to inspect aggregate consultation drift without exposing
session content. It writes progress to stderr before enumeration and parsing, then
emits one redacted JSON report on stdout. The report never includes session names,
paths, identifiers, receipt prose, prompts, responses, or cost estimates.

```sh
sh plugins/advisor/scripts/advisor-audit.sh --window-hours 24
```

`--since RFC3339` and `--until RFC3339` select an explicit half-open time window;
`--sessions-dir DIR` is available for isolated synthetic tests. The audit reads only
allowlisted runtime metadata, fixed receipt enums, tool-event kinds, timestamps, and
usage counters. Missing sandbox, tool, token, or duration evidence is JSON `null`
with an `unavailable` availability value, never an inferred value. It reports receipt
attempts and allowlisted `ADVISOR DECISION` routes (`consult`, `skip`, and
`unavailable`) in an exact top-level `decisions` object; decision availability is a
separate field. Schema v2 identifies exact current `advisor-terra` and `advisor-sol`
child sessions from full-file `session_meta` before applying the half-open window to
their activity. It reports those child sessions separately from deduplicated parent
`spawn_agent` completion evidence; parent completion counts are JSON `null` with
explicit `unavailable` availability unless a completed role-bearing spawn event
exists. Current parent `function_call` spawn requests and role-free
`SubAgentActivity` lifecycle events (`started`, `interacted`, `completed`, and
`interrupted`) are separate corroborating counts. A request never establishes a
selected role or completion, and activity is counted only by correlation to an exact
current child ID. Standard
and Specialist selections, evidenced dispositions, stale `sol_advisor`/`sol-advisor`
attempts, sandbox counts, advisor tool-call counts, duration aggregates, and token
totals remain aggregate-only. It never changes sessions or Codex configuration.

## Trigger evaluation

Static verification is non-networked:

```sh
sh plugins/advisor/scripts/verify.sh --static
```

Live evaluation is a separate attended step. `evaluate-triggers.sh --run --result
PATH` requires subscription-only routing and disabled overage. The parent process keeps
the live authenticated Codex home and runs with ignored user configuration/rules,
ephemeral state, and a read-only sandbox. Each feature state gets an isolated temporary
project and child runtime: the project links the consultation skill and repository-local
plugin, while the companion installer places and checks both exact roles in the child
runtime. The evaluator does not copy or link authentication and does not add a plugin
or marketplace during live evaluation.

The two `multi_agent_v2` schemas remain configured, but ephemeral feature-state coverage is not
freshness evidence. A route marker classifies `consult`, `skip`, or `unavailable`;
claimed advisor metadata, an empty wait, or consultation without a completed
`spawn_agent` event is typed `runtime_evidence_unavailable` and blocks the consult
route. Because the evaluator uses `--ephemeral`, its first trial has no persisted
parent rollout and expects the preflight's `route: unavailable`, with no `ADVISOR
CALL` or child spawn; it writes a typed unavailable artifact instead of continuing the
matrix. Deterministic persisted fixtures in `verify.sh` separately prove the read-only
consult path. Progress goes to stderr; the result is redacted JSON
without prompts, raw events, or thread identifiers. Each run records paired
before/after digests for contract-owned live state (`config.toml`, `agents/`,
`skills/`, and `plugins/`) and marketplace state, including unavailable exits.
Auth, session, log, and cache files are excluded from the read set. Validate with:

```sh
sh plugins/advisor/scripts/evaluate-triggers.sh --verify-result --result PATH
```

Use `--allow-unavailable` only to accept a typed unavailable artifact as evidence of
an unavailable evaluation, never as a passing consultation result.
