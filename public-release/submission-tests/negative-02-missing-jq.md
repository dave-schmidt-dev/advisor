## Name

Missing local jq prerequisite

## Host

Codex CLI

## Preconditions

Codex CLI, a POSIX shell, a persisted Codex session rollout, a resolvable `CODEX_THREAD_ID`, and the declared escalated launcher are available, but `jq` is not installed. The required host prerequisites are therefore incomplete.

## Prompt

For the fictional Cinder Registry, ask Advisor whether to preserve the current schema or migrate it.

## Expected outcome

Advisor emits only `ADVISOR DECISION` with `route: unavailable`; it emits no `ADVISOR CALL` or `ADVISOR RESULT` receipt and starts no consultation transport.

## Why this is the expected outcome

`jq` is a required local host prerequisite, and its missing-state recovery is `route: unavailable` with no transport.
