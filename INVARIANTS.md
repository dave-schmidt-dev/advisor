# Invariants — Advisor

> System contract. `plugins/advisor/scripts/verify.sh --static` is the
> canonical local gate for every invariant below.

## Standing invariants

### INV-1 — No silent blocking waits
area: ["plugins/advisor/scripts/**/*.sh"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Live evaluation and stall-prone operations must emit progress to stderr without contaminating machine-readable output. Reaching the history-mapping threshold requires review, but verified remediation or area-touch history is not itself a defect when this canonical gate passes; unresolved recurrence or missing gate evidence remains an escalation.

## Project-specific invariants

### INV-2 — Root authority
area: ["plugins/advisor/skills/consultation/**", "README.md", "SPEC.md"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: The root owns architecture, routing, verification, and acceptance; advisor output is evidence, never authority.

### INV-3 — Consultation only
area: ["plugins/advisor/agents/**", "plugins/advisor/skills/consultation/**"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: The plugin may spawn one fresh read-only advisor but may not implement, route implementation, or perform final review.

### INV-4 — Selective activation
area: ["plugins/advisor/evals/**", "plugins/advisor/skills/consultation/**"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Eligible tasks consult once per decision and complex work adds one completion consultation before it is declared complete, while routine and borderline tasks spawn no advisor.

### INV-5 — Exact runtime identity and isolation
area: ["plugins/advisor/agents/**", "plugins/advisor/scripts/evaluate-triggers.sh", "plugins/advisor/scripts/inspect-agent-runtime.sh", "plugins/advisor/scripts/inspect-parent-runtime.sh", "plugins/advisor/scripts/run-advisor.sh", "docs/public-directory-compatibility.md"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: A successful consultation requires an identified parent plus a regular nonsymlinked launcher resolved from the absolute installed-skill root and invoked through the escalated-command boundary, never a workspace-resolved script; packet input uses a non-interpolating quoted heredoc, transport files remain beneath nonsandbox-writable Codex home, and every distinct Codex exec child proves the exact model and effort frozen from the selected tier or legacy route, read-only runtime policy, fresh thread, allowlisted codex_exec or Codex Desktop provenance, no model reroute or migration, and zero tool use before response validation. The installed JSON Schema is the sole supported wrapper model-output contract; wrapper-owned semantic validation renders only an accepted object as the canonical eight-line receipt, while direct/native role invocation is unsupported and not schema-validated. Exactly one fresh corrective retry is allowed only after a runtime-valid response-validation failure and exposes only its redacted failure class and field; a consultation launches at most two children and the total monotonic deadline covers packet capture, both attempts, inspection, and response verification. Packet, launcher, event, identity, same-session, runtime, wrong-model, wrong-effort, non-read-only, normalization, provenance, reroute, and tool-use failures are terminal and never retry. Cancellation terminates and reaps only the wrapper-owned process group. Rejected content never leaves its private mode-0700 consultation directory or enters a retry prompt, and an unconditional exit trap cleanup removes that directory after every wrapper exit. Reaching the history-mapping threshold requires review, but verified remediation or area-touch history is not itself a defect when this canonical gate passes; unresolved recurrence or missing gate evidence remains an escalation.

### INV-6 — Switchyard separation
area: ["plugins/advisor/skills/consultation/**", "README.md", "SPEC.md"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Implementation routing remains outside this plugin and follows the repository's normal Switchyard policy.

### INV-7 — Safe installation and evaluation
area: ["plugins/advisor/scripts/install-agents.sh", "plugins/advisor/scripts/evaluate-triggers.sh"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Installation and evaluation are idempotent, fail closed, exclude auth handling, and do not mutate contract-owned live state.

### INV-8 — Provenance preservation
area: ["LICENSE", "NOTICE.md", "README.md", "plugins/advisor/.codex-plugin/plugin.json"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: The fork preserves upstream license credit and identifies its audited base and current maintainer.

### INV-9 — No unattended publication
area: ["README.md", "SPEC.md", ".agents/plugins/marketplace.json"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Overnight work stops at a validated local checkpoint without live installation, push, marketplace mutation, or publication.

### INV-10 — Visible consultation lifecycle
area: ["plugins/advisor/skills/consultation/**", "README.md", "SPEC.md"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Every consult emits a visible running `ADVISOR CALL` receipt and a completed or unavailable `ADVISOR RESULT` receipt; unavailable evidence records `decision: blocked` and remains fail-closed, receipts do not replace runtime proof, the distinct Codex consultation thread remains inspectable, and skips emit neither receipt nor transport invocation.

### INV-11 — Bounded zero-tool consultation
area: ["plugins/advisor/agents/**", "plugins/advisor/skills/consultation/**", "README.md", "SPEC.md"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: The root completes repository and web research before consultation and supplies enough relevant evidence and source references for a decision; advisors make no tool call, file inspection, web fetch, or independent research attempt, and may only identify missing evidence, research questions, or bounded brainstorming areas for a root-routed follow-up.

The root may assign bounded evidence gathering to separate research workers before assembling the decision packet; the consulted advisor still uses zero tools and never delegates.

### INV-12 — Redacted deferred audit
area: ["plugins/advisor/scripts/advisor-audit.sh", "plugins/advisor/scripts/verify.sh", "plugins/advisor/skills/consultation/references/operations.md", "README.md", "SPEC.md"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Audit schema v2 is read-only, progress-visible, window-bounded, and aggregate-only; it resolves exact current child identity from full-file metadata before windowing activity, keeps exact top-level decision counts, child sessions, completed role-bearing parent spawns, request coverage, and role-free child-correlated activity separate, never infers completion or selected role from corroboration, reports unavailable completion evidence explicitly, and never emits session content, identifiers, filenames, paths, contact data, secret-shaped values, or costs.

### INV-13 — Inspected-result follow-up boundary
area: ["plugins/advisor/skills/consultation/**", "README.md", "SPEC.md"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: A valid follow-up requires a processed recommendation or concrete research-first next step plus mandatory read-only, zero-tool runtime inspection; only then may the root route research or brainstorming to Luna or Terra outside consultation and optionally start a fresh separately receipted consultation. An unavailable result remains blocked and cannot be rescued.

### INV-14 — Live tier configuration and bounded discovery
area: ["plugins/advisor/advisor.toml", "plugins/advisor/scripts/advisor_config.py", "plugins/advisor/scripts/advisor_process.py", "plugins/advisor/scripts/run-advisor.sh", "plugins/advisor/scripts/inspect-agent-runtime.sh"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Normal tiers load only the installed regular, nonsymlinked, bounded
`advisor.toml`, with exactly Standard and Specialist model/effort pairs and a frozen
content digest through retry. No state, catalog, canary, or version-eligibility pin
overrides it; future syntactically valid selectors are allowed and real children still
prove exact runtime identity, effort, read-only isolation, zero tools, and schema.
Legacy roles remain pinned and advanced state tools cannot claim to alter live tiers.
Model discovery remains an owned, bounded app-server process with inherited Codex
provider context, actual JSON-RPC validation, safe state files, and no inference or
credential handling.

### INV-15 — Current public release evidence
area: ["docs/public-listing.md", "site/**", "public-release/upload_readiness.py", "public-release/verify-upload-ready.sh", "public-release/test_upload_readiness.py", "public-release/test_candidate_package.py", "public-release/package-candidate.sh", "docs/release-process.md"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: The canonical static gate covers the offline release-checker tests. Separately, marketplace upload readiness requires running `public-release/verify-upload-ready.sh [--json] ARCHIVE.zip` immediately before every upload for fresh, fail-closed evidence of the exact current Git-bound candidate ZIP, complete marketplace descriptions, version-marked local pages, and byte-identical public site pages/assets. No candidate receipt, built ZIP, offline mode, or prior release evidence authorizes upload.
# INV-1.4 Usage privacy and accounting

Usage accounting is structured, bounded, and honest: unavailable components are null, aggregate coverage is partial when any component is absent, and zero remains a valid counter. The content-free journal is opt-in, owner-only, atomic, bounded, and eligible for pruning after 30 days; pruning occurs only during a later journal write, never as a background deletion service. A write error never changes accepted advice. State belongs under Codex home, outside the plugin cache, and an explicit restore retains one prior settings revision.
