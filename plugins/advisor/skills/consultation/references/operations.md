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

Before the first implementation write, emit:

```text
ADVISOR DECISION
route: consult | skip
reason: <one task-specific sentence>
question: <bounded decision question, or none>
```

For a consult, verify both exact installed roles, select the role from decision
risk, then use one schema only:

- Standard: `advisor-terra`, pinned `gpt-5.6-terra`, high. This default covers
  material architecture, interface, data-model, compatibility, cross-boundary,
  competing-diagnosis, and generic advisor requests.
- Specialist: `advisor-sol`, pinned `gpt-5.6-sol`, high, only for an unresolved
  security or trust boundary, an irreversible migration or data-loss decision,
  or a credible unresolved High-severity disagreement.

Security adjacency and project importance alone do not qualify for Specialist.
A borderline role choice uses Standard. The parent model is irrelevant.

```text
# host schema v2
agent_type: advisor-terra | advisor-sol
fork_turns: none

# host schema v1
agent_type: advisor-terra | advisor-sol
fork_context: false
```

Never inherit context or pass a model/effort override. The selected installed role
enforces the pair. Send the five-section
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

Immediately after every native advisor response, before a completed result, the root
must run `inspect-agent-runtime.sh` for the selected thread and expected role/model.
This mandatory inspection verifies the runtime is read-only and zero-tool; it is not
a metadata fallback. Missing, conflicting, non-read-only, or tool-use evidence makes
the advisor unavailable and blocks the consult route. If packet evidence is
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

Immediately before the spawn, the root emits:

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
summarize verified evidence but are not runtime proof. The native child thread remains
the inspectable detailed record. A skip emits only `ADVISOR DECISION`, with no
call/result receipt and no spawn.

## Runtime evidence

Public spawn metadata is primary. A completed `spawn_agent` event must establish one
receiver agent and thread, the exact decision-risk-selected `advisor-terra`/`gpt-5.6-terra`
or `advisor-sol`/`gpt-5.6-sol` pair, effort `high`,
and a receiver thread distinct from the root `thread.started` identifier. After every
native advisor response, the root must run:

```sh
sh plugins/advisor/scripts/inspect-agent-runtime.sh --expected-role <selected-role> --expected-model <selected-model> <thread-id>
```

The inspector emits only thread, parent, role, model, effort, sandbox-policy, and
permission-profile fields, while rejecting any tool-use event. It must confirm a
read-only runtime policy; a role TOML requesting read-only is not proof of actual
isolation. Missing, conflicting, unexpected, non-read-only, or tool-use evidence is
unavailable, never approval. No substitute advisor role or replacement consultation
is allowed; any root-routed follow-up remains outside this consultation.

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
attempts separately from completed `spawn_agent` advisor child calls, Standard and
Specialist selections, evidenced dispositions, stale `sol_advisor`/`sol-advisor`
attempts, sandbox counts, advisor tool-call counts, duration aggregates, and token
totals. It never changes sessions or Codex configuration.

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

The two schemas confirm `multi_agent_v2=false/true`, but feature-state coverage is not
freshness evidence: both require a completed `spawn_agent` event whose sole receiver
thread differs from the root. A route marker classifies consult/skip only; claimed
advisor metadata, an empty wait, or consultation without that event is typed
`runtime_evidence_unavailable` and blocks the consult route. The evaluator runs the 24-session base matrix and
permits only boundary mismatches to receive two additional trials per schema, with a
pooled cap of 40 root sessions. Progress goes to stderr; the result is redacted JSON
without prompts, raw events, or thread identifiers. Each run records paired
before/after digests for contract-owned live state (`config.toml`, `agents/`,
`skills/`, and `plugins/`) and marketplace state, including unavailable exits.
Auth, session, log, and cache files are excluded from the read set. Validate with:

```sh
sh plugins/advisor/scripts/evaluate-triggers.sh --verify-result --result PATH
```

Use `--allow-unavailable` only to accept a typed unavailable artifact as evidence of
an unavailable evaluation, never as a passing consultation result.
