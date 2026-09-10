# Codex Advisor — Public Directory Listing Draft

## Overview

Codex Advisor is a skills-only plugin that provides disciplined, read-only second opinions for material architecture, interface, data-model, and diagnostic decisions in Codex. Its local integration sends bounded consultation packets through the user's authenticated Codex/OpenAI account. Zero Delta runs no relay or hosted backend, and the plugin provides no MCP server.

## Submission Metadata

| Field | Value |
| --- | --- |
| **Plugin Name** | `advisor` |
| **Display Name** | Codex Advisor |
| **Version** | `1.4.3` |
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

**Candidate status:** This document contains the approved 1.4.3 submission copy. The
exact role files are installed, one explicit Astra/high smoke completed successfully,
and the approved website is deployed with a verified live byte match. GitHub release
`v1.4.3` is published with the byte-identical handoff ZIP. Marketplace upload remains
owner-controlled and is not claimed.

## Descriptions

### Short Description
Automatic second opinions with your choice of models

### Long Description
Codex Advisor automatically adds a fresh, read-only second opinion for important technical decisions in Codex CLI and Codex desktop. Smart defaults work immediately: Standard uses Terra/high and Specialist uses Sol/high. Version 1.4.3 adds `advisor-astra`, a separate explicit-only Astra/high role reserved for the most complex uses. It is never selected automatically, uses more of your Codex allowance, and remains subject to account and runtime availability. Each consultation is tool-free, and your main agent retains control of implementation and final decisions. Consultations use your own authenticated Codex/OpenAI account; Zero Delta operates no relay or hosted backend.

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

Execution uses the user's authenticated Codex account. Normal tier consultations use the models and effort configured in the bundled `advisor.toml`:
- Standard defaults to Terra with high reasoning effort.
- Specialist defaults to Sol with high reasoning effort.
- `advisor-astra` is a separate explicit-only Astra/high role; automatic selection never invokes it.
- Astra uses more of the user's Codex allowance and remains subject to account and runtime availability.
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

## Candidate Notes (v1.4.3)

- Automatic read-only advice uses configurable Standard and Specialist sections in the live bundled `advisor.toml` file.
- Terra/high and Sol/high remain the automatic defaults.
- The separate `advisor-astra` role is explicit-only, pinned to Astra/high, and never selected automatically.
- Astra uses more of the user's Codex allowance and remains subject to account and runtime availability.
- Editing the installed file applies to the next consultation, with independent effort settings. Invalid TOML and unsupported models report errors without silent fallback.
- No setup conversation or separate compatibility test is required, and plugin updates may replace bundled configuration edits.
- Consultations send bounded packets through the user's authenticated Codex/OpenAI account; Zero Delta operates no relay or hosted backend.
- The optional content-free usage journal is off by default, stores operational metadata and aggregate counters only, prunes entries older than 30 days during later writes, and enforces a bounded count without a background deletion service.
