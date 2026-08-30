# Invariants — Advisor

> System contract. `plugins/advisor/scripts/verify.sh --static` is the
> canonical local gate for every invariant below.

## Standing invariants

### INV-1 — No silent blocking waits
area: ["plugins/advisor/scripts/**/*.sh"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: Live evaluation and stall-prone operations must emit progress to stderr without contaminating machine-readable output.

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
rationale: Eligible tasks consult exactly once, while routine and borderline tasks spawn no advisor.

### INV-5 — Exact runtime identity and isolation
area: ["plugins/advisor/agents/**", "plugins/advisor/scripts/evaluate-triggers.sh", "plugins/advisor/scripts/inspect-agent-runtime.sh", "plugins/advisor/scripts/inspect-parent-runtime.sh"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: A successful consultation requires an identified parent plus a regular nonsymlinked launcher resolved from the absolute installed-skill root and invoked through the escalated-command boundary, never a workspace-resolved script; packet input uses a non-interpolating quoted heredoc, transport files remain beneath nonsandbox-writable Codex home, and a distinct Codex exec child proves the decision-risk-selected role/model pair, High effort, read-only runtime policy, fresh thread, codex_exec provenance, well-formed response, and zero tool use. Normal workspace-write roots remain eligible, while missing, conflicting, same-session, malformed, wrong-model, wrong-effort, non-read-only, or tool-use evidence is unavailable.

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
