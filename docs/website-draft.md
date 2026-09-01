# Codex Advisor — Official Website Copy (Draft)

> **Draft Copy:** Content draft for the official Codex Advisor project landing page and documentation site.

---

## Hero Section

**Headline:** Second Opinions Before You Ship.  
**Subhead:** Automatic, read-only architectural and technical consultations for Codex CLI and Codex desktop.  

**Primary CTA:** Get Started with Codex Advisor  
**Secondary CTA:** View Documentation & Source  

---

## What is Codex Advisor?

Codex Advisor is an open-source, skills-only plugin that provides disciplined second opinions for material technical decisions. When your root agent faces complex architectural trade-offs, interface designs, data-model migrations, or competing bug diagnoses, Codex Advisor consults a fresh, read-only advisor before writing code.

Advice is non-authoritative: your root agent reviews the advice against repository evidence and explicitly records whether to accept, modify, or reject the recommendation.

---

## Key Features

### 1. Disciplined Triggering
Codex Advisor triggers only on material technical decisions:
- Architecture, interface, and compatibility design choices.
- Features spanning module, trust, process, or persistence boundaries.
- Competing root-cause diagnoses for difficult bugs.
- Irreversible state transitions, migrations, security, and privacy boundaries.

Routine work (such as factual lookups, mechanical edits, documentation formatting, and settled plans) automatically skips consultation.

### 2. Dual-Tier Risk-Calibrated Roles
- **Standard Consultation (`advisor-terra`):** Powered by `gpt-5.6-terra` / High effort for general architecture, interface design, data modeling, and generic advisor requests.
- **Specialist Consultation (`advisor-sol`):** Powered by `gpt-5.6-sol` / High effort, reserved specifically for unresolved security or trust boundaries, irreversible data migration, or critical high-severity disagreements.

### 3. Local Isolation & Zero Tools
- Advisor processes run in a forced read-only sandbox with zero tools enabled.
- The advisor does not inspect unprovided files, call external tools, or browse the web.
- The plugin operates locally with no hosted service, no MCP server, and no cloud telemetry.

### 4. Transparent Chat Lifecycle
Every consultation is surfaced directly in your chat stream with verifiable receipts:
- `ADVISOR CALL` before launch (displaying tier, role, reason, question, and status).
- `ADVISOR RESULT` after completion (displaying verified model, high effort, read-only isolation, recommendation, decision disposition, and rationale).

### 5. Research-First Fallback
When evidence in the context packet is insufficient to make a definitive choice, the advisor does not guess; it recommends a concrete research-first next step and identifies specific missing evidence under `FOLLOW-UP AREAS`.

---

## Host and Surface Compatibility

Codex Advisor is a Codex-only plugin built for local development workflows:

- **Supported Hosts:** Codex CLI and Codex desktop on macOS and Linux.
- **Generic ChatGPT Alone:** Generic ChatGPT alone is unsupported; preflight checks return `route: unavailable` with no transport invocation.
- **Local Execution:** Consultation processing is strictly local: there is no public service processing and no external server execution.
- **No MCP / Hosted Services:** The plugin operates with no MCP server and no hosted service.

---

## Local Host Prerequisites

To run Codex Advisor consultations, your local environment needs:
- Codex CLI or Codex desktop.
- `jq` installed in your `$PATH`.
- POSIX shell (`sh`).
- Persisted Codex session rollout and valid `CODEX_THREAD_ID`.
- Active OpenAI subscription with model availability for `gpt-5.6-terra` and `gpt-5.6-sol`.

---

## Quick Start / Installation

Add the plugin from the marketplace and run the companion agent installer:

```sh
# Add the marketplace repository
codex plugin marketplace add dave-schmidt-dev/advisor --ref main

# Install the advisor plugin
codex plugin add advisor@advisor

# Run the companion installer
plugin_dir="$(codex plugin list --json | jq -r '.installed[] | select(.pluginId == "advisor@advisor") | .source.path')" && test -n "$plugin_dir" && test "$plugin_dir" != null && test -d "$plugin_dir" && test -f "$plugin_dir/scripts/install-agents.sh" && sh "$plugin_dir/scripts/install-agents.sh"
```

---

## Local Privacy and Redacted Audit

Codex Advisor respects your code privacy:
- Consultation data stays inside your local Codex session and your direct connection to OpenAI.
- Transcripts reside in your local persisted Codex session logs.
- The local audit tool (`advisor-audit.sh`) provides aggregated token and decision counts while strictly redacting all code, prompts, filenames, paths, and identifiers.

---

## Project Links and Resources

- **Terms of Service:** [Terms Draft](terms-draft.md) / `OWNER-PROVIDED terms URL`
- **Privacy Policy:** [Privacy Policy Draft](privacy-policy-draft.md) / `OWNER-PROVIDED privacy policy URL`
- **Support & Troubleshooting:** [Support Guide](support-draft.md) / `OWNER-PROVIDED support URL`
- **Source Repository:** `OWNER-PROVIDED repository URL`
- **License:** MIT License (Original author Daniel McAteer; Maintainer David Schmidt / Zero Delta LLC)
