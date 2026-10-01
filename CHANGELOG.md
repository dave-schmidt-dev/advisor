# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
