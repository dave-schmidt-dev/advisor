# Consultation operations

Advisor provides pre-decision advice only. It does not implement, route
implementation, perform final review, or replace root authority.

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
`advisor-sol.toml.retired-v1.1.0`, then installs the risk-described 1.2.0 roles at
their original active paths. Exact retired-only interrupted states resume safely;
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
receiver agent and thread, the exact decision-risk-selected `advisor-terra`/`gpt-5.6-terra`
or `advisor-sol`/`gpt-5.6-sol` pair, effort `high`,
and a receiver thread distinct from the root `thread.started` identifier. Invocation
flags and the installed role establish the read-only sandbox. For fields omitted by
the public record only:

```sh
sh plugins/advisor/scripts/inspect-agent-runtime.sh --expected-role <selected-role> --expected-model <selected-model> <thread-id>
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
