# Codex Advisor — Public Directory Listing Draft

## Overview

Codex Advisor is a skills-only plugin that provides disciplined, read-only second opinions for material architecture, interface, data-model, and diagnostic decisions in Codex. Its local integration sends bounded consultation packets through the user's authenticated Codex/OpenAI account. Zero Delta runs no relay or hosted backend, and the plugin provides no MCP server.

## Submission Metadata

| Field | Value |
| --- | --- |
| **Plugin Name** | `advisor` |
| **Display Name** | Codex Advisor |
| **Version** | `1.4.9` |
| **Category** | Developer Tools |
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

**Candidate status:** Version 1.4.9 identifies the current local source candidate.
It is a license-distribution, support/privacy disclosure, and review-remediation
correction with no model-pin change. The plugin ships byte-exact copies of
the root `LICENSE` and `NOTICE.md` at `plugins/advisor/LICENSE` and
`plugins/advisor/NOTICE.md`, so the tracked plugin inventory automatically
includes the required upstream copyright and permission notice, and the
candidate inventory gate enforces exact root/plugin notice parity. The
published privacy page distinguishes no automatic transmission of consultation
packets or responses to Zero Delta from voluntary user sharing of redacted
receipts, and adds the public GitHub issue support disclosure. The manifest and
this listing replace the blanket "Zero Delta receives no packets" claim with
the accurate no-automatic-relay/telemetry wording; optional user-shared support
receipts are covered by the privacy policy. The Developer Tools category, the
`interface.supportURL` at `https://zerodelta.dev/advisor/support/`, and the
short and long descriptions remain synchronized with this listing. This round
also corrects every preventive no-tools/tool-free claim in the manifest, this
listing, the README, and the website to the actual contract: the consultation
child is launched in a read-only sandbox and instructed to use zero tools, and
the launcher validates the recorded runtime after execution and rejects the
result on any observed tool call, which is a post-execution acceptance check
rather than preventive tool isolation. The privacy page states that a
prohibited tool call may read additional locally accessible data before
rejection and that rejection cannot undo information already processed by
OpenAI. Python 3.11 or newer (the standard-library `tomllib` dependency) is
declared in the long description and the prerequisites above, and the
consultation launcher now runs an explicit Python version preflight before
helper imports, packet capture, or any provider launch. Model pins and
consultation runtime behavior are otherwise unchanged. The exact
candidate archive, its hash, the docs deployment, and the marketplace upload
are finalized by the release owner; the upload-readiness gate verifies exact
bytes before handoff. Marketplace upload remains owner-controlled.

**Historical website deployment status (1.4.7 snapshot):** The landing, support,
privacy, and terms pages were deployed on 1 October 2026 for Advisor 1.4.7, and
upload-readiness verification confirmed that all seven live site files
byte-matched the 1.4.7 source. That record applies to the 1.4.7 source snapshot
and does not verify 1.4.8.

**Historical website deployment status (1.4.6 snapshot):** The landing, support,
privacy, and terms pages were deployed on 22 September 2026. The then-current
`Codex-Advisor-1.4.6.zip` passed `public-release/verify-upload-ready.sh`; that
record covered its seven live site files and archive hash
`c262ed96736216e225fdbe63db211fe1651f0b4c3900bee50bf3201b3a7a33bd`. It applies
to the 1.4.6 source snapshot and does not verify 1.4.7.

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
Architecture and code advice.

### Long Description
Codex Advisor helps software developers review architecture, API interfaces, data models, and migration plans in Codex CLI and Codex desktop. Each consultation returns one recommendation with tradeoffs, risks, and acceptance checks.

Advisor sends bounded technical context to OpenAI for inference through your authenticated account and allowance; Zero Delta runs no relay or telemetry backend and does not automatically receive consultation packets or responses. Redacted receipts you voluntarily share through support channels are covered by the privacy policy. The consultation child is launched in a read-only sandbox and instructed to use zero tools; after execution the launcher inspects the recorded runtime and rejects the result if it observes any tool call, which is a post-execution acceptance check, not preventive tool-free isolation. The local launcher writes temporary files and Codex session records. The root agent owns implementation and final decisions; Advisor does not implement, deploy, or perform final review.

Requires Python 3.11+, a local Codex host, jq, a supported POSIX shell, and a persisted session. Standard uses Terra/high, Specialist uses GPT-6.1 Sol/high, and explicit-only Astra/high is available for the most complex uses.

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
| Python Runtime | `python3` 3.11 or newer (standard-library `tomllib` dependency) | The launcher reports `ADVISOR TRANSPORT: unavailable` citing Python 3.11+; no provider launch or packet capture runs. |
| CLI Tools | `jq` command-line JSON processor installed in `$PATH` | Return `route: unavailable`; no consultation transport runs. |
| Shell Environment | Standard POSIX shell (`sh`) | Return `route: unavailable`; no consultation transport runs. |
| Persisted Rollout | Active persisted Codex session rollout | Return `route: unavailable`; no consultation transport runs. |
| Thread Identity | Resolvable `CODEX_THREAD_ID` environment variable | Return `route: unavailable`; `CODEX_SESSION_ID` is never used as a fallback. |
| Launcher Elevation | Escalated launcher boundary permission (`require_escalated`) | Return `route: unavailable`; no consultation transport runs. |

When any prerequisite is absent, the system safely records `route: unavailable` without blocking the root agent's primary work.

## Model Availability and Requirements

Execution uses the user's authenticated Codex account. Normal tier consultations use the models and effort configured in the bundled `advisor.toml`:
- Standard defaults to Terra with high reasoning effort.
- Specialist defaults to GPT-6.1 Sol with high reasoning effort.
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

## Candidate Notes (v1.4.9)

- The plugin ships byte-exact copies of the root `LICENSE` and `NOTICE.md`; the candidate inventory gate rejects a missing or tampered plugin notice copy.
- Automatic read-only advice uses configurable Standard and Specialist sections in the live bundled `advisor.toml` file.
- Terra/high and GPT-6.1 Sol/high remain the automatic defaults.
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
1.4.9 candidate.
