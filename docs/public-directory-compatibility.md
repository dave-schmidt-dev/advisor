# Public directory compatibility

## Distribution and execution

Advisor v1.3.3 is published in the official OpenAI Plugins Directory as a skills-only
package. Marketplace users should reinstall or update Advisor from the Directory and
start a new Codex thread so the installed copy is available to the session.
Consultation still executes only through the **local Codex runtime** on the user's own
machine; publication adds no hosted or remote execution path.

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

## Published-directory recovery

The official recovery path is the published Directory entry:
<https://chatgpt.com/plugins/plugins_6a984f37e9c88191a2a777998f7b0521>. Reinstall or
update Advisor there, then start a new Codex thread. To check the installed copy, ask
Advisor for a bounded consultation and inspect the resulting `ADVISOR DECISION`,
`ADVISOR CALL`, or `ADVISOR RESULT` receipts.

## Owner decision

OWNER DECISION: approved
