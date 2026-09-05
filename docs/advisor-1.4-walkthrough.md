# Advisor 1.4.2 candidate walkthrough

Date: 2026-09-04. This is a local candidate walkthrough, not publication, installation,
real-model-canary, or owner acceptance evidence.

The installed helper keeps its state under Codex home, outside the plugin cache.

| Surface | Expected behavior | Evidence and remaining gate |
| --- | --- | --- |
| Live configuration | The installed `advisor.toml` has only Standard and Specialist model/effort sections. Editing either pair applies to the next tier consultation; comments list efforts, future-selector limits, Astra usage, and upgrade replacement risk. | Mocked configuration tests cover defaults, future selectors, malformed/missing/unsafe input, and content-digest revision. No user file was edited. |
| Tier consultation | `run-advisor.sh --tier standard` resolves the live Standard pair; Specialist independently resolves its pair. Saved stale selections do not win. Retries reuse the frozen pair, source revision, and total deadline. | Mocked wrapper tests cover Astra, independent effort, future selectors without catalog/canary/state, stale-state precedence, retry, and exact runtime mismatch rejection. Actual Terra, Sol, or Astra inference has not run. |
| Legacy aliases | `--role advisor-terra` and `--role advisor-sol` remain fixed Terra/high and Sol/high. They cannot be mixed with tier or preset. | Static and transport tests cover the pins. |
| Current and legacy tools | `show` and `doctor` report actual live pairs, config path, and digest. Catalogs/presets/canaries are advanced-only; `set` and `reset` reject and `restore` labels legacy-only state recovery. | Mocked CLI diagnostics cover live values and stale saved-state precedence. |
| Deadline | `deadline` displays the total deadline; `deadline SECONDS` accepts 30–900 seconds and defaults to 300. Frozen launch and retry share that budget. | CLI tests cover valid and rejected values. |
| Discovery unavailable | `models refresh` checks isolation support before starting discovery. Tested CLI provenance `0.153.2` lacks the flags, so it reports unavailable and leaves saved catalog state intact; discovery never blocks built-in defaults. | Unit coverage simulates the rejection. A manual selector is the recovery path. |
| Consent canary | `models test MODEL --effort EFFORT --authorize-usage --parent-thread THREAD_ID` refuses without the consent flag, runs only after explicit authorization, and does not select the pair. | Mocked synthetic canary coverage passed. Real canaries remain pending owner authorization. |
| Journal | Disabled by default; status, enable, disable, and clear are explicit. A subsequent journal write performs the 30-day prune; there is no background task. | Usage tests cover retention, null/partial accounting, and clear behavior. |
| Errors and recovery | Missing, malformed, duplicate, unknown-key/table, symlinked, nonregular, oversized, unsafe selector, or invalid effort live config fails before child launch with a redacted `advisor.toml` error. Runtime model/effort errors remain terminal. | Mocked error paths prove no model launch on invalid TOML. |
| Transport terminal paths | A runtime-valid response error gets one frozen-pair retry. Launch, identity, isolation, tool, timeout, or cancellation failures are terminal/unavailable; cancellation reaps only the wrapper-owned group. | Mocked transport tests cover retry, timeout, cancellation, and fail-closed cases. |

The canonical command `sh plugins/advisor/scripts/verify.sh --static` runs Advisor
tests plus 17 candidate packaging tests in this checkout;
`sh public-release/validate-public-artifacts.sh --candidate` checks manifest and
marketplace identity plus the skills-only contract; it does not scan all public claims.
`git diff --check` checks whitespace. The captain records actual final command output in the ignored local
verification record after the phase gate.

The package ships only `plugins/advisor`; this walkthrough and other repository-root
docs are not inside the ZIP. A future owner walkthrough must inspect an installed copy,
exercise config editing, malformed-file recovery, supported host states, and separately
accept any real model canary before publication. Live website, privacy, terms, portal URL autofill, directory listing,
marketplace state, and release publication are unverified.
