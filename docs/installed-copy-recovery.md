# Installed copy recovery

## Identify the installed candidate

For already-installed copies, use the Codex plugin manager to locate the Advisor
plugin directory, then read its `.codex-plugin/plugin.json`. Its `version` field
identifies the exact build metadata; the published Directory release identity is
`1.3.3`.

## Verify the installed content

If the installed copy is missing or stale, reinstall or update Advisor from the
[official OpenAI Plugins Directory](https://chatgpt.com/plugins/plugins_6a984f37e9c88191a2a777998f7b0521),
then start a new Codex thread. Ask Advisor for a bounded consultation and inspect its
`ADVISOR DECISION`, `ADVISOR CALL`, or `ADVISOR RESULT` receipts. Consultation
continues to run through the local Codex runtime; the published package adds no
hosted service or MCP server.

## Update to a newer candidate

Reinstall or update Advisor through the official Directory, start a new Codex thread,
and repeat the identity and receipt checks above before resuming use.

## Static-gate failure

If the installed copy does not produce the expected receipts, do not edit the
installed files in place. Reinstall the published Directory copy, start a new Codex
thread, and check again. If it still fails, retain the non-sensitive receipt output
and report it with the installed version.
