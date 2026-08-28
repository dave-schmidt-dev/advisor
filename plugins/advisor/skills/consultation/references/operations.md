# Consultation operations

Advisor provides pre-decision advice only. It does not implement, route
implementation, perform final review, or replace root authority.

## Install and verify the companion role

From the repository root:

```sh
sh plugins/advisor/scripts/install-agents.sh
sh plugins/advisor/scripts/install-agents.sh --check
```

The installer adds only `advisor.toml`. During an attended upgrade it
recoverably retires byte-exact known historical Luna, Terra, and Sol-reviewer files
to `<role>.toml.retired-v0.6.0`. It preflights every path before mutation, is
idempotent, refuses symlinks/nonregular files/modified content/collisions/dual paths,
and never edits Codex configuration.

## Root and advisor records

Before the first implementation write, emit:

```text
ADVISOR DECISION
route: consult | skip
reason: <one task-specific sentence>
question: <bounded decision question, or none>
```

For a consult, verify the exact installed role, select the child model from the
parent-model policy, then use one schema only:

- Luna, Spark, or lower parent: `gpt-5.6-terra`, high.
- Terra parent: `gpt-5.6-sol`, high.
- Sol parent: fresh `gpt-5.6-sol`, high.
- Unknown parent: `gpt-5.6-sol`, high fail-safe.

```text
# host schema v2
agent_type: advisor
fork_turns: none
model: <selected model>
reasoning_effort: high

# host schema v1
agent_type: advisor
fork_context: false
model: <selected model>
reasoning_effort: high
```

Never inherit context or omit the selected model/high override. Send the five-section
DECISION/CONTEXT/OPTIONS/BOUNDARIES/REQUEST packet from the skill. Require:

```text
ADVISOR RESPONSE
RECOMMENDATION: <one path>
WHY: <decisive evidence and reasoning>
STRONGEST OBJECTION: <best case against the recommendation>
CHANGE MY MIND: <specific missing or contrary evidence>
ACCEPTANCE CHECKS: <concrete checks>
RISKS: <material residual risks, or none>
```

The root verifies evidence and records `accept`, `modify`, or `reject`. The advisor
is never authoritative.

## Runtime evidence

Public spawn metadata is primary. A completed `spawn_agent` event must establish one
receiver agent and thread, role `advisor`, the policy-selected model, effort `high`,
and a receiver thread distinct from the root `thread.started` identifier. Invocation
flags and the installed role establish the read-only sandbox. For fields omitted by
the public record only:

```sh
sh plugins/advisor/scripts/inspect-agent-runtime.sh --expected-model <selected-model> <thread-id>
```

The inspector emits only thread, parent, role, model, effort, sandbox-policy, and
permission-profile fields. Missing, conflicting, or unexpected evidence is
unavailable, never approval. No substitute role or follow-up agent is allowed.

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
plugin, while the companion installer places and checks the exact role in the child
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
