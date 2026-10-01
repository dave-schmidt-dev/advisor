# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
