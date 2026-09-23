# Codex Advisor — Public Directory Listing Draft

## Overview

Codex Advisor is a skills-only plugin that provides disciplined, read-only second opinions for material architecture, interface, data-model, and diagnostic decisions in Codex. Its local integration sends bounded consultation packets through the user's authenticated Codex/OpenAI account. Zero Delta runs no relay or hosted backend, and the plugin provides no MCP server.

## Submission Metadata

| Field | Value |
| --- | --- |
| **Plugin Name** | `advisor` |
| **Display Name** | Codex Advisor |
| **Version** | `1.4.6` |
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

**Candidate status:** Advisor 1.4.6 is a local packaged release candidate. The
28-file `Codex-Advisor-1.4.6.zip` has SHA-256
`c262ed96736216e225fdbe63db211fe1651f0b4c3900bee50bf3201b3a7a33bd`.
The 1.4.6 public website deployment is complete and independently verified
below. This site-deployment record does not establish a later 1.4.6 commit, tag,
GitHub release, or marketplace publication; each requires separate evidence.
Marketplace upload remains owner-controlled.

**Website deployment status (1.4.6):** The landing, support, privacy, and terms
pages were deployed on 22 September 2026. `public-release/verify-upload-ready.sh
--json Codex-Advisor-1.4.6.zip` exited 0; all seven live site files byte-match
the local source, and the archive SHA-256 is
`c262ed96736216e225fdbe63db211fe1651f0b4c3900bee50bf3201b3a7a33bd`.

**Historical publication status (1.4.4):** Advisor 1.4.4 is published in the OpenAI Plugins Directory,
based on owner confirmation. The published 1.4.4 archive is
`Codex-Advisor-1.4.4.zip` with SHA-256
`36876ac573b5c752259b687295a34d2cd70c51c9a72a07b2a808f776f710b6ba`.
GitHub release [`v1.4.4`](https://github.com/dave-schmidt-dev/advisor/releases/tag/v1.4.4)
is published at commit `a2f84e65bc551ea6c826baf29d8b792252ae04b0`; its downloaded
asset matches this SHA-256. The 1.4.4 public site is deployed, and its seven
deployable files byte-match the release source. Independent authenticated live-listing
inspection is not claimed here.

## Descriptions

### Short Description
Automatic second opinions with your choice of models

### Long Description
Codex Advisor automatically adds a fresh, read-only second opinion for important technical decisions in Codex CLI and Codex desktop. Standard uses Terra/high for ordinary bounded architecture, interface, data-model, and generic-advisor decisions. Specialist uses GPT-6 Sol/high only when targeted evidence still leaves a cross-module/system design, compatibility or concurrency boundary, competing diagnosis, security/trust boundary, recovery, irreversible migration, or data-loss decision unresolved. Project importance, security adjacency, or an ordinary architecture question alone does not select Specialist. Version 1.4.4's deferred result-delivery repair remains in place: callers drain nonterminal shell sessions, require terminal exit, and validate exactly one schema-v3 envelope. `advisor-astra` remains a separate explicit-only Astra/high role and is never selected automatically. Each consultation is tool-free, and your main agent retains control of implementation and final decisions. Consultations use your own authenticated Codex/OpenAI account; Zero Delta operates no relay or hosted backend.

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
- Specialist defaults to GPT-6 Sol with high reasoning effort.
- `advisor-astra` is a separate explicit-only Astra/high role; automatic selection never invokes it.
- Astra uses more of the user's Codex allowance and remains subject to account and runtime availability.
- Future model selectors are subject to account access and runtime support. Invalid TOML or an unsupported model reports an error; there is no silent fallback.

## Directory Test Cases

### Positive Test Cases
1. **Architecture Decision:** "Should we implement event sourcing with PostgreSQL JSONB or an append-only log table in DynamoDB for our billing audit trail?" (Triggers Standard consultation).
2. **Settled Cross-Boundary Interface:** "Targeted evidence has settled offline-conflict compatibility for our local cache and remote API; choose the bounded interface." (Triggers Standard consultation).
3. **Unresolved Cross-System Boundary:** "Targeted evidence still leaves the cache/API concurrency and compatibility boundary unresolved." (Triggers Specialist consultation).
4. **Unresolved Competing Diagnoses:** "Targeted evidence still supports a cache race and producer staleness across modules; choose the next diagnostic path." (Triggers Specialist consultation).
5. **Critical Security Boundary:** "Targeted evidence still leaves the trust-boundary recovery design for an irreversible migration unresolved." (Triggers Specialist consultation).
6. **Explicit Advisor Request:** "Use $advisor:consultation to review this caching strategy trade-off." (Triggers Standard consultation).

### Negative Test Cases
1. **Routine Factual Query:** "What is the return type of `inspect_parent_runtime` in the operations script?" (Skips consultation; factual lookup).
2. **Mechanical Implementation:** "Rename variable `old_path` to `source_path` across all helper functions in `utils.py`." (Skips consultation; deterministic mechanical edit).
3. **Diff Review / No Delegation:** "Review the committed git diff for typos and formatting errors, and do not delegate to an advisor." (Skips consultation; owned by review workflow and explicit no-delegation).

## Candidate Notes (v1.4.6)

- Automatic read-only advice uses configurable Standard and Specialist sections in the live bundled `advisor.toml` file.
- Terra/high and GPT-6 Sol/high remain the automatic defaults.
- Standard covers ordinary bounded material architecture, interface, data-model, and generic-advisor decisions.
- Specialist applies only after targeted evidence leaves an eligible cross-system, compatibility/concurrency, competing-diagnosis, security/trust, recovery, irreversible-migration, or data-loss decision unresolved.
- Project importance, security adjacency, and an ordinary architecture question alone remain Standard.
- The separate `advisor-astra` role is explicit-only, pinned to Astra/high, and never selected automatically.
- Astra uses more of the user's Codex allowance and remains subject to account and runtime availability.
- Editing the installed file applies to the next consultation, with independent effort settings. Invalid TOML and unsupported models report errors without silent fallback.
- No setup conversation or separate compatibility test is required, and plugin updates may replace bundled configuration edits.
- Deferred shell handoffs remain drained to terminal exit; exactly one schema-v3 envelope is required before the enclosing call returns a receipt. There is no model fallback.
- Consultations send bounded packets through the user's authenticated Codex/OpenAI account; Zero Delta operates no relay or hosted backend.
- The optional content-free usage journal is off by default, stores operational metadata and aggregate counters only, prunes entries older than 30 days during later writes, and enforces a bounded count without a background deletion service.

The 1.4.4 publication record above remains historical and is not replaced by this
1.4.6 candidate.
