# Release record

## Published package

The published identity is version `1.3.3`, pinned by Git tag `v1.3.3` at commit
`2cd47df0fc86931f34a05b982f38232a6b51c2e9`. The release archive is
`Codex-Advisor-1.3.3.zip` with SHA-256
`a0064662cfabd419a120c4e583068bb86905bb17aeb0482005d93f8b5cde505d`.

## Marketplace candidate

Version `1.3.4` hardens response handling with a strict JSON Schema, precise
redacted validation failures, one corrective retry, and deterministic canonical
rendering. The handoff archive is `Codex-Advisor-1.3.4.zip`; its SHA-256 is
`aece3eaab6fa7b3bd33bb170618b025770f853687b954c2a8d614b56a882e933`.
Candidate content digest: `81a2c85d55c5ecfb8cfbf68e618368400f4fea983c004d2bb51c7c9bfaa1815d`.

## Candidate contents

The published archive packages the skills-only Codex Advisor consultation skill, its local
runtime references and scripts, and the two read-only advisor profiles. It adds no
networked service component.

## Candidate preparation

Run `public-release/freeze-candidate.sh --write` only when an intentional new package
release is approved. Root legal or provenance-document changes do not create a new
package release.

## Submission test cases

The local submission case pack is available at `public-release/submission-tests/` with five positive and three negative synthetic reviewer scenarios.
