# Codex Advisor Support and Troubleshooting Guide (Draft)

> **Notice:** This document is a pre-release draft. All publisher-specific entries marked `OWNER-PROVIDED` must be populated by the repository owner prior to formal directory submission.

**Support Contact:** OWNER-PROVIDED support email  
**Issue Tracker:** OWNER-PROVIDED issue tracker URL  
**Support SLA / Hours:** OWNER-PROVIDED response SLA  

---

## 1. Support Channels

For technical assistance, bug reports, or feature questions regarding Codex Advisor:
- **Primary Issue Tracker:** OWNER-PROVIDED issue tracker URL  
- **Email Support:** OWNER-PROVIDED support email  
- **Discussions / Community:** OWNER-PROVIDED community forum URL  

Please note that Codex Advisor is an open-source project maintained on a best-effort basis by OWNER-PROVIDED legal entity name.

## 2. Supported Platforms and Scope

### Supported Platforms
- **Codex CLI:** Supported on Linux and macOS environments.
- **Codex Desktop:** Supported on Linux and macOS environments with persisted sessions.

### Unsupported Platforms & Out-of-Scope Configurations
- **Generic ChatGPT Alone:** Generic ChatGPT with no local Codex runtime is unsupported (preflight emits `route: unavailable`).
- **Remote / Hosted Services:** MCP servers and hosted services are unsupported and out of scope (operates with no MCP server and no hosted service).
- **Subagents as Consultation Transports:** Native Codex subagents are unsupported as a consultation transport because they lack the required read-only isolation guarantees.

## 3. Local Host Prerequisites Checklist

Before opening a support ticket, ensure your local environment satisfies all required local host prerequisites:

1. **Codex CLI or Codex Desktop:** Installed and operational.
2. **`jq` Utility:** Installed and accessible in your `$PATH` (e.g. `which jq`).
3. **POSIX Shell:** `/bin/sh` compliant environment.
4. **Persisted Session Rollout:** Active Codex thread session files present in your local Codex home directory.
5. **Thread Identity:** Environment variable `CODEX_THREAD_ID` set in the active parent execution context.
6. **Launcher Permissions:** Escalated permission enabled for the installed plugin launcher script via `require_escalated`.
7. **Model Availability:** Subscription access to `gpt-5.6-terra` (Standard) and `gpt-5.6-sol` (Specialist).

## 4. Common Troubleshooting Scenarios

### Scenario A: Preflight Returns `route: unavailable`
- **Symptom:** In the root agent log, you observe:
  ```text
  ADVISOR DECISION
  route: unavailable
  ```
- **Cause:** Preflight script (`inspect-parent-runtime.sh`) could not verify the parent environment or prerequisites.
- **Remedies:**
  - Verify that `jq` is installed and reachable in `$PATH`.
  - Ensure you are running within an interactive, persisted Codex session (ephemeral test sessions lack persisted rollouts and correctly emit `route: unavailable`).
  - Check that the installed plugin companion scripts were installed via `install-agents.sh`.

### Scenario B: Model Availability / Authorization Failure
- **Symptom:** Consultation launcher reports failure or unexpected model response.
- **Cause:** Your OpenAI account lacks model availability for `gpt-5.6-terra` or `gpt-5.6-sol`.
- **Remedies:**
  - Verify your OpenAI subscription tier supports GPT-5.6 models with high reasoning effort.
  - Test Codex authentication using `codex auth check` or standard CLI commands.

### Scenario C: Response Classification Retries
- **Symptom:** Stderr logs indicate a single retry attempt during consultation.
- **Behavior:** The plugin allows exactly one fresh retry if the first response is structurally empty or misordered, provided runtime isolation was verified. If the retry also fails, it safely terminates with `decision: blocked`.

## 5. Diagnostic and Verification Commands

You can verify your local plugin installation using the non-networked verification script:

```sh
sh plugins/advisor/scripts/verify.sh --static
```

To review local aggregate consultation activity without disclosing sensitive project data:

```sh
sh plugins/advisor/scripts/advisor-audit.sh --window-hours 24
```

## 6. Submitting a Support Request

When submitting a support ticket to OWNER-PROVIDED support email, please include:
1. Codex host type (Codex CLI or Codex desktop) and version.
2. Operating system and shell version.
3. Output of `sh plugins/advisor/scripts/verify.sh --static`.
4. Relevant `ADVISOR DECISION`, `ADVISOR CALL`, or `ADVISOR RESULT` receipts from the conversation (ensuring all private project secrets are redacted).
