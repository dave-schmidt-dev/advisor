## Name

Generic fictional second-opinion request

## Host

Codex CLI

## Preconditions

Required host prerequisites: Codex CLI, `jq`, a POSIX shell, a persisted Codex session rollout, a resolvable `CODEX_THREAD_ID`, and the declared escalated launcher are available.

## Prompt

Use Advisor for a fresh, read-only second opinion on whether the fictional Atlas Queue should expose retries as a command option or as a configuration field.

## Expected outcome

Advisor emits `ADVISOR DECISION` with `route: consult`, followed by `ADVISOR CALL` and a verified `ADVISOR RESULT` from `advisor-terra`.

## Why this is the expected outcome

An explicit generic advisor or second-opinion request is a Standard consultation trigger when supported-host preflight succeeds.
