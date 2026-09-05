# Codex Advisor — Public Directory Listing Draft

## Overview

Codex Advisor is a skills-only plugin that provides disciplined, read-only second opinions for material architecture, interface, data-model, and diagnostic decisions in Codex. Its local integration sends bounded consultation packets through the user's authenticated Codex/OpenAI account. Zero Delta runs no relay or hosted backend, and the plugin provides no MCP server.

## Submission Metadata

| Field | Value |
| --- | --- |
| **Plugin Name** | `advisor` |
| **Display Name** | Codex Advisor |
| **Version** | `1.4.2` |
| **Category** | Productivity |
| **Capabilities** | Interactive, Read |
| **Author / Maintainer** | David Schmidt / Zero Delta LLC |
| **Developer / Publisher Entity** | Zero Delta LLC (Commonwealth of Virginia, United States) |
| **Publisher Website** | `https://zerodelta.dev/advisor/` |
| **Support URL** | `https://zerodelta.dev/advisor/support/` |
| **Support Email** | `advisor@zerodelta.dev` |
| **Privacy Policy URL** | `https://zerodelta.dev/advisor/privacy/` |
| **Terms of Service URL** | `https://zerodelta.dev/advisor/terms/` |
| **Logo Asset** | `assets/public-logo.svg` |
| **Geographic Availability** | United States |
| **Pricing Model** | Free / Open Source (MIT); requires user's own Codex model access |

**Candidate status:** This document contains proposed 1.4.2 submission copy.
Directory publication and the matching live website have not been verified here.

## Descriptions

### Short Description
Automatic second opinions with your choice of models

### Long Description
Codex Advisor automatically adds a fresh, read-only second opinion for important technical decisions in Codex CLI and Codex desktop. Smart defaults work immediately: Standard uses Terra and Specialist uses Sol. To choose another model or reasoning effort, edit the commented advisor.toml file included with the plugin. Astra is optional and uses more of your Codex allowance. Future model selectors can be entered directly, subject to your account access and runtime support. No configuration conversation or separate compatibility test is required. Each consultation is tool-free, and your main agent retains control of implementation and final decisions. Plugin updates may replace edits to the bundled configuration file. Consultations use your own authenticated Codex/OpenAI account; Zero Delta operates no relay or hosted backend.

## Surface and Host Compatibility

Codex Advisor is a Codex-only plugin integrated with the user's authenticated local Codex runtime.

| Surface | Compatibility | Details |
| --- | --- | --- |
| Codex CLI | Supported | Runs locally through the user's local Codex CLI runtime. |
| Codex desktop | Supported | Runs locally through the user's local Codex desktop runtime. |
| Generic ChatGPT alone | Unsupported | ChatGPT alone is unsupported; preflight returns `route: unavailable` with no transport invocation. |
| Native Codex subagents | Unsupported as transport | Native subagents inherit parent permissions and cannot supply the required read-only isolation contract. |
| MCP servers and hosted services | Unsupported and out of scope | The plugin operates with no MCP server and no hosted service. |

Consultation packets are sent through the user's authenticated Codex/OpenAI account. Zero Delta runs no relay, proxy, or hosted backend.

## Local Host Prerequisites and Recovery

The plugin requires specific local host prerequisites to execute consultations:

| Prerequisite | Description | Missing-State Recovery |
| --- | --- | --- |
| Supported Host | Codex CLI or Codex desktop | Return `route: unavailable`; no consultation transport runs. |
| CLI Tools | `jq` command-line JSON processor installed in `$PATH` | Return `route: unavailable`; no consultation transport runs. |
| Shell Environment | Standard POSIX shell (`sh`) | Return `route: unavailable`; no consultation transport runs. |
| Persisted Rollout | Active persisted Codex session rollout | Return `route: unavailable`; no consultation transport runs. |
| Thread Identity | Resolvable `CODEX_THREAD_ID` environment variable | Return `route: unavailable`; `CODEX_SESSION_ID` is never used as a fallback. |
| Launcher Elevation | Escalated launcher boundary permission (`require_escalated`) | Return `route: unavailable`; no consultation transport runs. |

When any prerequisite is absent, the system safely records `route: unavailable` without blocking the root agent's primary work.

## Model Availability and Requirements

Execution of consultations depends on the models and effort configured in the bundled `advisor.toml` through the user's authenticated Codex account:
- Standard defaults to Terra with high reasoning effort.
- Specialist defaults to Sol with high reasoning effort.
- Optional Astra uses more of the user's Codex allowance.
- Future model selectors are subject to account access and runtime support. Invalid TOML or an unsupported model reports an error; there is no silent fallback.

## Directory Test Cases

### Positive Test Cases
1. **Architecture Decision:** "Should we implement event sourcing with PostgreSQL JSONB or an append-only log table in DynamoDB for our billing audit trail?" (Triggers Standard consultation).
2. **Cross-Boundary Service Interface:** "Design the synchronization boundary between our local SQLite cache and remote GraphQL API handling offline conflicts." (Triggers Standard consultation).
3. **Competing Diagnoses:** "Investigate intermittent HTTP 504 gateway timeouts: evidence is split between connection pool exhaustion and downstream lock contention." (Triggers Standard consultation).
4. **Critical Security Boundary:** "Review cryptographic key rotation design and trust-boundary transition for zero-downtime database encryption." (Triggers Specialist consultation).
5. **Explicit Advisor Request:** "Use $advisor:consultation to review this caching strategy trade-off." (Triggers Standard consultation).

### Negative Test Cases
1. **Routine Factual Query:** "What is the return type of `inspect_parent_runtime` in the operations script?" (Skips consultation; factual lookup).
2. **Mechanical Implementation:** "Rename variable `old_path` to `source_path` across all helper functions in `utils.py`." (Skips consultation; deterministic mechanical edit).
3. **Diff Review / No Delegation:** "Review the committed git diff for typos and formatting errors, and do not delegate to an advisor." (Skips consultation; owned by review workflow and explicit no-delegation).

## Candidate Notes (v1.4.2)

- Automatic read-only advice uses configurable Standard and Specialist sections in the live bundled `advisor.toml` file.
- Terra/high and Sol/high are the defaults; optional Astra uses more of the user's Codex allowance.
- Editing the installed file applies to the next consultation, with independent effort settings. Invalid TOML and unsupported models report errors without silent fallback.
- No setup conversation or separate compatibility test is required, and plugin updates may replace bundled configuration edits.
- Consultations send bounded packets through the user's authenticated Codex/OpenAI account; Zero Delta operates no relay or hosted backend.
- The optional content-free usage journal is off by default, stores operational metadata and aggregate counters only, prunes entries older than 30 days during later writes, and enforces a bounded count without a background deletion service.
