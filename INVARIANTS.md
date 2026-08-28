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

### INV-5 — Exact runtime identity
area: ["plugins/advisor/agents/**", "plugins/advisor/scripts/evaluate-triggers.sh", "plugins/advisor/scripts/inspect-agent-runtime.sh"]
gate_test: plugins/advisor/scripts/verify.sh
threshold: 3
rationale: A successful consultation requires the event-proven policy-selected model-pinned role/model pair, effort, freshness, and read-only isolation; missing evidence is unavailable.

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
