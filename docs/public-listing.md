# Codex Advisor — Public Directory Listing Draft

## Overview

Codex Advisor is a skills-only plugin that provides disciplined, read-only second opinions for material architecture, interface, data-model, and diagnostic decisions in Codex. The plugin operates as a Codex-only tool running entirely within the local Codex environment on the user's workstation. It does not provide automatic provisioning or guaranteed automatic routing, and it operates with no hosted service and no MCP server.

## Submission Metadata

| Field | Value |
| --- | --- |
| **Plugin Name** | `advisor` |
| **Display Name** | Codex Advisor |
| **Version** | `1.3.0` |
| **Category** | Productivity |
| **Capabilities** | Interactive, Read |
| **Author / Maintainer** | David Schmidt / Zero Delta LLC (maintainer); Daniel McAteer (original author) |
| **Developer / Publisher Entity** | OWNER-PROVIDED legal entity name |
| **Publisher Website** | OWNER-PROVIDED website URL |
| **Support URL** | OWNER-PROVIDED support URL |
| **Support Email** | OWNER-PROVIDED support email |
| **Privacy Policy URL** | OWNER-PROVIDED privacy policy URL |
| **Terms of Service URL** | OWNER-PROVIDED terms URL |
| **Logo Asset** | `assets/public-logo.svg` |
| **Geographic Availability** | OWNER-PROVIDED country and region availability |
| **Pricing Model** | Free / Open Source (MIT); requires user's own Codex model access |

## Descriptions

### Short Description
Read-only second opinions for architecture and technical decisions in Codex.

### Long Description
Codex Advisor adds an automatic, read-only consultation layer for material technical decisions. When a task requires choosing between viable architectures, evaluating cross-boundary designs, comparing competing root-cause diagnoses, or deciding irreversible state changes, the root agent consults a fresh, read-only advisor before finalizing the decision.

Consultation is strictly non-authoritative: the root agent owns the decision, evaluates advice against repository evidence, and explicitly records whether the recommendation was accepted, modified, or rejected. Routine work (such as factual summaries, mechanical edits, documentation formatting, or settled-plan execution) skips consultation.

Codex Advisor selects between two risk-calibrated roles: Standard consultation (`advisor-terra` on GPT-5.6 Terra) for general architecture and technical trade-offs, and Specialist consultation (`advisor-sol` on GPT-5.6 Sol) for unresolved security boundaries, irreversible data migration, or high-severity disagreements. Every consultation runs in an isolated read-only sandbox with zero tools and receives mandatory runtime inspection. The plugin operates locally with no hosted service, no MCP server, and no telemetry.

## Surface and Host Compatibility

Codex Advisor is a Codex-only plugin designed strictly for local execution.

| Surface | Compatibility | Details |
| --- | --- | --- |
| Codex CLI | Supported | Runs locally through the user's local Codex CLI runtime. |
| Codex desktop | Supported | Runs locally through the user's local Codex desktop runtime. |
| Generic ChatGPT alone | Unsupported | ChatGPT alone is unsupported; preflight returns `route: unavailable` with no transport invocation. |
| Native Codex subagents | Unsupported as transport | Native subagents inherit parent permissions and cannot supply the required read-only isolation contract. |
| MCP servers and hosted services | Unsupported and out of scope | The plugin operates with no MCP server and no hosted service. |

Consultation processing is strictly local: there is no public service processing and no external server execution.

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

Execution of consultations depends on user model availability through their authenticated Codex account:
- Standard consultation requires model availability for `gpt-5.6-terra` with high reasoning effort.
- Specialist consultation requires model availability for `gpt-5.6-sol` with high reasoning effort.
- If required models are unavailable or unentitled in the user's subscription, preflight or transport inspection will fail closed and record `advisor unavailable`.

## Directory Test Cases

### Positive Test Cases
1. **Architecture Decision:** "Should we implement event sourcing with PostgreSQL JSONB or an append-only log table in DynamoDB for our billing audit trail?" (Triggers Standard consultation with `advisor-terra`).
2. **Cross-Boundary Service Interface:** "Design the synchronization boundary between our local SQLite cache and remote GraphQL API handling offline conflicts." (Triggers Standard consultation with `advisor-terra`).
3. **Competing Diagnoses:** "Investigate intermittent HTTP 504 gateway timeouts: evidence is split between connection pool exhaustion and downstream lock contention." (Triggers Standard consultation with `advisor-terra`).
4. **Critical Security Boundary:** "Review cryptographic key rotation design and trust-boundary transition for zero-downtime database encryption." (Triggers Specialist consultation with `advisor-sol`).
5. **Explicit Advisor Request:** "Use $advisor:consultation to review this caching strategy trade-off." (Triggers explicit consultation with `advisor-terra`).

### Negative Test Cases
1. **Routine Factual Query:** "What is the return type of `inspect_parent_runtime` in the operations script?" (Skips consultation; factual lookup).
2. **Mechanical Implementation:** "Rename variable `old_path` to `source_path` across all helper functions in `utils.py`." (Skips consultation; deterministic mechanical edit).
3. **Diff Review / No Delegation:** "Review the committed git diff for typos and formatting errors, and do not delegate to an advisor." (Skips consultation; owned by review workflow and explicit no-delegation).

## Release Notes (v1.3.0)

- Initial public listing candidate for Codex Advisor (v1.3.0).
- Dual-tier risk-calibrated consultation: Standard (`advisor-terra`) and Specialist (`advisor-sol`).
- Mandatory parent preflight and post-response runtime inspection verifying read-only sandbox and zero-tool isolation.
- Structured receipts (`ADVISOR CALL` and `ADVISOR RESULT`) for transparent execution visibility.
- Fail-closed error handling and deterministic aggregate audit schema v2.
