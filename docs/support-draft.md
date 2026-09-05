# Codex Advisor Support and Troubleshooting Guide

> The published support page at [`site/support/index.html`](../site/support/index.html)
> is the source of truth. This draft mirrors its current distribution and recovery
> guidance.

**Support Contact:** advisor@zerodelta.dev
**Issue Tracker:** https://github.com/dave-schmidt-dev/advisor/issues
**Support SLA / Hours:** Best effort; no response-time commitment

## 1. Support Channels

For technical assistance, bug reports, or feature questions, use the
[GitHub issue tracker](https://github.com/dave-schmidt-dev/advisor/issues). Email
[advisor@zerodelta.dev](mailto:advisor@zerodelta.dev) for anything that should not
be filed publicly.

## 2. Reinstall or Update Advisor

Codex Advisor v1.3.3 is distributed through the
[official OpenAI Plugins Directory](https://chatgpt.com/plugins/plugins_6a984f37e9c88191a2a777998f7b0521).
If Advisor is missing, outdated, or not responding, reinstall or update it there,
then start a new Codex thread so the installed plugin is available to the session.

The Directory package is skills-only. Consultations execute through the
authenticated local Codex runtime on the user's own machine; there is no hosted
service or MCP server.

## 3. Supported Platforms and Scope

- **Codex CLI:** Supported on Linux and macOS.
- **Codex desktop:** Supported on Linux and macOS with persisted sessions.
- **Generic ChatGPT alone:** Unsupported; without a local Codex runtime, preflight
  emits `route: unavailable`.
- **Remote / hosted services:** Unsupported and out of scope; the plugin operates
  with no MCP server and no hosted service.
- **Native Codex subagents:** Unsupported as a consultation transport because they
  cannot supply the required read-only isolation guarantee.

## 4. Local Host Prerequisites

Before opening a support ticket, ensure that Codex CLI or desktop is installed and
operational, `jq` is on `$PATH`, a POSIX shell is available, an active persisted
Codex session rollout exists, `CODEX_THREAD_ID` is set in the active parent
context, the installed plugin can use its declared `require_escalated` launcher
permission, and the account has access to `gpt-5.6-terra` and `gpt-5.6-sol`.

## 5. Common Troubleshooting Scenarios

### Preflight returns `route: unavailable`

Confirm `jq`, the persisted Codex session, and the current thread identity. If the
problem persists, reinstall or update Advisor from the official Plugins Directory
and start a new Codex thread.

### Model availability or authorization failure

Verify that the authenticated OpenAI account and subscription provide
`gpt-5.6-terra` and `gpt-5.6-sol` at the required reasoning effort, then verify
Codex authentication with the standard CLI commands.

### Response classification retry

A runtime-valid child with an empty or structurally malformed response gets one
fresh retry. If it fails again, the plugin records `recommendation: unavailable` and
`decision: blocked` and stops. Packet, launcher, identity, runtime, wrong-model,
wrong-effort, and tool-use failures are terminal and never retry.

## 6. Check an Installed Copy

From a new Codex thread, ask Advisor for a consultation on a bounded architecture or
technical decision. A working installed copy leaves an `ADVISOR DECISION` receipt
followed, when consultation is selected, by an `ADVISOR CALL` and verified
`ADVISOR RESULT` receipt. For an unavailable or skipped request, the
`ADVISOR DECISION` receipt is still the diagnostic result.

## 7. Submitting a Support Request

Include the Codex host type and version, operating system and shell version, and
relevant `ADVISOR DECISION`, `ADVISOR CALL`, or `ADVISOR RESULT` receipts. Redact
secrets and proprietary context before sending.
