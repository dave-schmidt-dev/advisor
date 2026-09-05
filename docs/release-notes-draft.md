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

## Local candidate

Version `1.4.2` is a local candidate. It ships `advisor.toml` as the live,
in-place-editable configuration for normal Standard and Specialist consultations.
Its defaults are Terra/high and Sol/high; two independent model/effort pairs, Astra
opt-in, future selectors, content-digest revisions, retry freezing, and fail-closed
TOML errors are covered locally. Normal tiers no longer depend on saved selections,
catalog registration, discovery, or synthetic canaries. Plugin updates or reinstalling
can replace edits. It has not been installed from a candidate ZIP, run against a real
model, owner-accepted in a walkthrough, uploaded, published, or verified in a live
marketplace.

Candidate content digest: `5dae43e5d226b95a375d54876e2dec7ff132d8361d8ee6d8905001f45ba01f39`.

The manifest contains supported `websiteURL`, `privacyPolicyURL`, and
`termsOfServiceURL` fields. It contains no supported `supportURL` field; portal URL
autofill is unverified. The live site remains version `1.3.3`; this candidate does not
replace it. Privacy-copy reconciliation remains an owner-approved publication step.

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
