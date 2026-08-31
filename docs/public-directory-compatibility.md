# Public directory compatibility

## Distribution and execution

Advisor is not listed in the OpenAI Plugins Directory and has not been submitted for
review. Today it is installed from its Git repository as a Codex plugin marketplace.
This document records what a listing would mean so that decision can be made against a
written runtime boundary; it is not a description of current distribution.

If listed, the Directory would distribute a skills-only package. Consultation would
still execute only through the **local Codex runtime** on the user's own machine, and
publication would add no hosted or remote execution path.

## Surface matrix

| Surface | Verdict | Runtime behavior |
| --- | --- | --- |
| Codex CLI | Supported | The local Codex runtime may complete preflight and use the fixed local launcher. |
| Codex desktop | Supported | The local Codex runtime may complete preflight when the persisted originator is `Codex Desktop`. |
| Generic ChatGPT with no local Codex runtime | Unsupported | In ChatGPT the skill has no local transport, so it takes `route: unavailable` and emits no `ADVISOR CALL` or `ADVISOR RESULT` receipt. |
| Native Codex subagents | Unsupported as a consultation transport | A native child observed in local testing inherited the parent's `workspace-write` and network access, so it cannot supply the pinned read-only `codex exec` child, Advisor role, High effort, fresh thread, and allowlisted provenance that consultation requires. Subagents remain available for follow-up work outside a consultation. |
| MCP servers and hosted services | Unsupported and out of scope | They are not a workaround and provide no Advisor execution path. |

## Universal-directory consequence

OpenAI describes a universal Plugins Directory shared by ChatGPT and Codex. This
universal plugin directory listing is not a runtime boundary: the boundary is local
preflight. On every non-Codex surface, preflight must produce the documented
unavailable result; non-Codex use is unsupported.

## Local host prerequisites and recovery

Consultation requires all of the following:

| Prerequisite | Missing-state recovery |
| --- | --- |
| Codex CLI or Codex desktop | Return `route: unavailable`; no consultation transport runs. |
| `jq` | Return `route: unavailable`; no consultation transport runs. |
| POSIX shell | Return `route: unavailable`; no consultation transport runs. |
| Persisted Codex session rollout | Return `route: unavailable`; no consultation transport runs. |
| A resolvable current-thread identity from `CODEX_THREAD_ID` | Return `route: unavailable`; `CODEX_SESSION_ID` is never used as a fallback. |
| A narrowly elevated launcher invoked through the escalated-command boundary, the skill's `require_escalated` declaration | Return `route: unavailable`; no consultation transport runs. |

## Directory submission requirements

The submission source is <https://developers.openai.com/plugins/deploy/submission.md>.
Public submission requires a verified developer or business identity; name, short
description, and long description; logo and category; website plus support,
privacy-policy, and terms URLs; at least five positive test cases and three negative
test cases; an availability (country/region) selection; release notes; OpenAI review
approval; and a separate explicit publisher action to publish. Skills-only plugins
with no MCP server are explicitly permitted.

## Owner decision

OWNER DECISION: pending

The owner must replace `pending` with `approved` or `rejected`. Approval authorizes
only local packaging work; it does not authorize submission or publication.
