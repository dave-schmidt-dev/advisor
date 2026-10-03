# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Reject missing or symlinked installed configuration helpers before running configuration commands.
- Honor custom exception files in staged file-size checks, using their staged contents.
- Remove stale test counts from the verification summary and an extra trailing blank line from the diagnostics module.
- Fix early startup cancellation cleanup without deleting preexisting directories; cancellation waits for local directory setup to finish.

### Removed
- Unused `save_catalog` writer and `MAX_EVENTS` constant, plus their `advisor_config` facade exports and Vulture whitelist lines. No caller existed in the plugin, tests, or other projects.
- Unenforced `plugins/advisor/settings.schema.json` (nothing loaded it; `validate_settings` is the contract). The next package contains one fewer file.
- 46 unreferenced re-exports from the `advisor_config.py` facade (constants, validators, and internal helpers with no consumer); the config CLI and every name used by tests are unchanged.

## [1.4.9] - 2026-10-01

### Changed
- The plugin now ships byte-exact copies of the root `LICENSE` and `NOTICE.md`
  at `plugins/advisor/LICENSE` and `plugins/advisor/NOTICE.md`, so the tracked
  plugin inventory automatically includes the required upstream copyright and
  permission notice.
- The manifest and public listing long descriptions replace the blanket
  "Zero Delta receives no packets" claim with the accurate no-automatic-relay
  and no-telemetry wording; voluntarily shared support receipts are covered by
  the privacy policy.
- The published privacy page distinguishes no automatic transmission of
  consultation packets or responses to Zero Delta from voluntary user sharing
  of redacted receipts, and adds the public GitHub issue support disclosure
  (identity, content, purpose, recipients, retention, and deletion). The
  support page keeps minimal redacted diagnostics user-initiated only. The
  terms effective date is unchanged.
- The manifest, public listing, README, and website no longer claim preventive
  tool-free isolation. They now state the actual contract: the consultation
  child is launched in a read-only sandbox and instructed to use zero tools,
  and the launcher validates the recorded runtime after execution and rejects
  the result on any observed tool call, which is a post-execution acceptance
  check. The privacy page states that a prohibited tool call may read
  additional locally accessible data before rejection and that rejection
  cannot undo information already processed by OpenAI.
- Python 3.11 or newer (the standard-library `tomllib` requirement) is now
  declared in the manifest long description, the public listing prerequisites,
  the README, and the support and terms pages.

### Added
- The candidate inventory gate now enforces exact root/plugin notice parity,
  with candidate tests covering a missing or tampered plugin notice copy, and
  repository verification requires the same byte-exact parity.
- The consultation launcher now runs an explicit Python version preflight
  immediately after the `python3` presence check and before helper imports,
  packet capture, or any provider launch. An older Python returns the existing
  `ADVISOR TRANSPORT: unavailable` diagnostic mentioning Python 3.11+ with no
  traceback, and black-box regression coverage uses a synthetic old-version
  Python to assert the failure, the diagnostic, and the absence of any
  provider launch or packet capture.

## [1.4.8] - 2026-10-01

### Changed
- The plugin manifest and marketplace listing now use the Developer Tools
  category (previously Productivity), and the manifest adds
  `interface.supportURL` at `https://zerodelta.dev/advisor/support/`. The
  display name remains Codex Advisor; the reported name check was incomplete
  and did not identify a naming violation.
- The short and long directory descriptions are simplified and now match
  `docs/public-listing.md` exactly.
- The published privacy page explicitly discloses data categories, purposes,
  recipients, retention, and controls, effective 1 October 2026. The terms
  effective date is unchanged.
- The support page adds a concise private-support and privacy contact section.

### Added
- The upload-readiness gate now requires the real manifest interface to carry
  the public support URL, the Developer Tools category, and short/long
  description parity with the public listing, with tests covering a missing
  support URL, URL mismatch, and description drift.

## [1.4.7] - 2026-10-01

### Changed
- The automatic Specialist default and fixed legacy `advisor-sol` alias now use
  `gpt-6.1-sol` / high (previously `gpt-6-sol` / high). Standard remains
  `gpt-5.6-terra` / high, and explicit-only `advisor-astra` remains
  `gpt-6-astra` / high.

### Added
- The installer safely upgrades the byte-exact Advisor 1.4.6 Sol role, preserving
  it at `advisor-sol.toml.retired-v1.4.6`. Edited and conflicting role files fail
  closed without mutation.

[1.4.7]: https://github.com/dave-schmidt-dev/advisor/releases/tag/v1.4.7

[1.4.8]: https://github.com/dave-schmidt-dev/advisor/releases/tag/v1.4.8

[1.4.9]: https://github.com/dave-schmidt-dev/advisor/releases/tag/v1.4.9
