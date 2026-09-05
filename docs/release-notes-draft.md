# Release record

## Published package

The published identity is version `1.3.3`, pinned by Git tag `v1.3.3` at commit
`2cd47df0fc86931f34a05b982f38232a6b51c2e9`. The release archive is
`Codex-Advisor-1.3.3.zip` with SHA-256
`a0064662cfabd419a120c4e583068bb86905bb17aeb0482005d93f8b5cde505d`.

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

Candidate content digest: `5dae43e5d226b95a375d54876e2dec7ff132d8361d8ee6d8905001f45ba01f39`.

The manifest contains supported `websiteURL`, `privacyPolicyURL`, and
`termsOfServiceURL` fields. It contains no supported `supportURL` field; portal URL
autofill is unverified. The release owner approved the refreshed Terms captures, and
the approved Terms release was deployed and live-byte verified on 5 September 2026.

## Candidate contents

The candidate ZIP packages only `plugins/advisor`: its single consultation skill, local
runtime references and scripts, configuration helper, schemas, catalog, assets, and
the two read-only advisor profiles. Repository-root documentation is not in the ZIP.
It adds no networked service component.

## Candidate preparation

Run `public-release/freeze-candidate.sh --write` only when an intentional new package
release is approved. Root legal or provenance-document changes do not create a new
package release.

## Submission test cases

The local submission case pack is available at `public-release/submission-tests/` with five positive and three negative synthetic reviewer scenarios.
