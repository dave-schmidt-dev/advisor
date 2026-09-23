# Release record

## Advisor 1.4.6 candidate

Version `1.4.6` changes the automatic Specialist default and fixed legacy
`advisor-sol` alias to `gpt-6-sol` / high. Standard remains `gpt-5.6-terra` /
high, and explicit-only `advisor-astra` remains `gpt-6-astra` / high. The
1.4.5 Specialist eligibility, read-only zero-tool runtime checks, exact
inspection, frozen retry selection, output schema, and no-fallback behavior
remain in place. The public site and support copy reflect the new Specialist
model. The landing, support, privacy, and terms pages were deployed on
22 September 2026 after the walkthrough was provided and the owner authorized
the site update. The upload-readiness
verification exited 0 and confirmed that all seven live site files byte-match
the local source for the 1.4.6 candidate archive.
The packaged installer recognizes the byte-exact 1.4.0–1.4.5 Sol role and
retains it at `.retired-v1.4.5` during upgrade; edited role files still fail
closed.

This is a local packaged candidate only. `Codex-Advisor-1.4.6.zip` contains 28
files and has SHA-256
`c262ed96736216e225fdbe63db211fe1651f0b4c3900bee50bf3201b3a7a33bd`.
Candidate content digest: `085170475891ee207f50a9ae3c624d0dac0ab01de6bbccae0385cf0fd231c1f6`.
The site update was authorized after the dated walkthrough was provided. This
site-deployment record does not establish a later 1.4.6 commit, GitHub release,
or marketplace publication; each requires separate evidence. Marketplace upload
remains owner-controlled.

## Advisor 1.4.5 candidate record

Version `1.4.5` expanded Specialist eligibility to evidence-unresolved complex
decisions while keeping the then-current models unchanged: Standard was
Terra/high for ordinary bounded material architecture, interface, data-model,
and generic-advisor decisions. Specialist was GPT-5.6 Sol/high when targeted
evidence still left a cross-module/system design, compatibility or concurrency
boundary, competing diagnosis, security/trust boundary, recovery, irreversible
migration, or data-loss decision unresolved. Project importance, security
adjacency, or an ordinary architecture question alone remained Standard.
Explicit-only Astra was unchanged. The optional content-free journal remained
disabled by default, with no schema or retention change. This paragraph records
the prior candidate and does not claim marketplace publication.

## Advisor 1.4.4 publication record

Version `1.4.4` repairs the deferred shell handoff that could leave the enclosing
caller without the result it had launched. The caller treats a nonterminal
`session_id` as progress, drains it with `write_stdin`, requires terminal exit,
validates exactly one schema-v3 envelope, and explicitly returns that receipt.
This is a delivery-contract repair only: Standard remains Terra/high, Specialist
remains Sol/high, and explicit-only Astra remains unchanged with no model fallback.

Candidate archive: `Codex-Advisor-1.4.4.zip`; SHA-256
`36876ac573b5c752259b687295a34d2cd70c51c9a72a07b2a808f776f710b6ba`.
Marketplace publication was owner-confirmed on 13 September 2026. GitHub release
[`v1.4.4`](https://github.com/dave-schmidt-dev/advisor/releases/tag/v1.4.4) was
published at commit `a2f84e65bc551ea6c826baf29d8b792252ae04b0`; its downloaded
asset matches this SHA-256. The 1.4.4 public site is deployed, and its seven
deployable files byte-match the release source. Independent authenticated live-listing
inspection is not claimed by this draft. The 1.4.3 publication record below remains
historical.

## Advisor 1.4.3 publication record

The 1.4.3 GitHub identity is pinned by Git tag `v1.4.3` at
commit `554376fd3e1da8e4d98e4c29183406510814bf56`. The release archive is
`Codex-Advisor-1.4.3.zip` with SHA-256
`85c86f5a1c582c43a99bc274f9f54a60445cae316683892668b608e8054b54c2`.
The downloaded GitHub asset was verified byte-identical to the marketplace handoff
archive. Marketplace publication remains owner-controlled and is not claimed.

## Marketplace candidate

Version `1.3.4` hardens response handling with a strict JSON Schema, precise
redacted validation failures, one corrective retry, and deterministic canonical
rendering. The handoff archive is `Codex-Advisor-1.3.4.zip`; its historical archive fingerprint is `aece3eaab6fa7b3bd33bb170618b025770f853687b954c2a8d614b56a882e933`.
The release owner has confirmed that this archive was uploaded to the marketplace.
Live marketplace directory state has not been independently verified.

## Advisor 1.4.2 release notes

Version `1.4.2` ships the live, commented `advisor.toml` with two roles: Standard
Terra/high and Specialist Sol/high. Optional Astra and future model selectors remain
subject to account and runtime support. Editing the live file affects the next
consultation; plugin updates or reinstalling may replace those edits. The defaults
require no setup conversation or separate canary. The local opt-in usage journal is
off by default.

Release evidence recorded for this version:

- The marketplace owner confirmed publication on 5 September 2026.
- Website verification covered 7 files.
- The marketplace ZIP SHA-256 is
  `21324cf22eee2424859ab8825ea76eb2046fd2cd772190ad7ab822ab794df6c6`.
- GitHub release `v1.4.2` is published from commit
  `57dad72989c175ae08d7e7c7ee1a981b1d177fb4`. Its tag and downloaded ZIP asset
  were verified against that source and the marketplace ZIP SHA-256 above.
- No hosted CI is configured.
- Installed model inference was not tested or claimed. No full static green is
  claimed: 62 of 63 behavior tests passed; the existing cancellation test failed.
  The release suite passed 30 tests and the browser suite passed 50 tests.

The local-candidate record remains relevant to the published archive: it provided
in-place-editable configuration for normal Standard and Specialist consultations;
the two independent model/effort pairs, Astra opt-in, future selectors,
content-digest revisions, retry freezing, and fail-closed TOML errors were covered
locally. Normal tiers no longer depend on saved selections, catalog registration,
discovery, or synthetic canaries.

The manifest contains supported `websiteURL`, `privacyPolicyURL`, and
`termsOfServiceURL` fields. It contains no supported `supportURL` field; portal URL
autofill is unverified. The release owner approved the refreshed Terms captures, and
the approved Terms release was deployed and live-byte verified on 5 September 2026.

## Advisor 1.4.3 candidate release notes

Version `1.4.3` adds `advisor-astra`, a separate explicit-only consultation role
pinned to Astra/high for the most complex uses. It is never selected automatically:
automatic Standard remains Terra/high and automatic Specialist remains Sol/high.
Astra uses more Codex allowance and remains subject to account and runtime
availability.

The exact three role files are installed, and one explicit Astra/high consultation
completed with verified read-only, zero-tool runtime evidence. The owner approved the
website walkthrough; all seven public files are deployed and live-byte verified.
GitHub release `v1.4.3` is published from commit
`554376fd3e1da8e4d98e4c29183406510814bf56`; its downloaded asset is byte-identical
to the marketplace handoff archive. Marketplace upload is not claimed yet.
The deterministic handoff archive is `Codex-Advisor-1.4.3.zip` with SHA-256
`85c86f5a1c582c43a99bc274f9f54a60445cae316683892668b608e8054b54c2`.

## Candidate contents

The candidate ZIP packages only `plugins/advisor`: its single consultation skill, local
runtime references and scripts, configuration helper, schemas, catalog, assets, and
the three read-only advisor profiles. Repository-root documentation is not in the ZIP.
It adds no networked service component.

## Candidate preparation

Run `public-release/freeze-candidate.sh --write` only when an intentional new package
release is approved. Root legal or provenance-document changes do not create a new
package release.

## Submission test cases

The local submission case pack is available at `public-release/submission-tests/` with five positive and three negative synthetic reviewer scenarios.
