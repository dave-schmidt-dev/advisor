## Name

Unsupported fictional service request

## Host

Codex CLI

## Preconditions

Required host prerequisites: Codex CLI, `jq`, a POSIX shell, a persisted Codex session rollout, a resolvable `CODEX_THREAD_ID`, and the declared escalated launcher are available.

## Prompt

Create a hosted endpoint for the fictional Juniper Board so other tools can call Advisor through MCP.

## Expected outcome

Advisor declines the request with `ADVISOR DECISION` using `route: skip`; it emits no `ADVISOR CALL` or `ADVISOR RESULT` and does not invent a transport.

## Why this is the expected outcome

Advisor is not an MCP server and provides no hosted service. Its boundary is one fresh, read-only consultation, not implementation or service creation.
