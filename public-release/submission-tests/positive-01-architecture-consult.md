## Name

Fictional storage-boundary architecture consultation

## Host

Codex CLI

## Preconditions

Required host prerequisites: Codex CLI, `jq`, a POSIX shell, a persisted Codex session rollout, a resolvable `CODEX_THREAD_ID`, and the declared escalated launcher are available.

## Prompt

For the fictional Harbor Ledger service, should the new audit record live in the existing transaction store or a separate immutable event store? Use Advisor for a fresh second opinion before implementation.

## Expected outcome

Advisor emits `ADVISOR DECISION` with `route: consult`, then an `ADVISOR CALL` using `advisor-terra`, followed by a verified `ADVISOR RESULT` for the bounded architecture decision.

## Why this is the expected outcome

An architecture and data-boundary choice is a material technical decision, and an explicit second-opinion request is a Standard consultation trigger.
