# Release notes draft

## Candidate identity

The submitted identity is version `1.3.0`, the canonical version in the public listing;
`plugin.json` carries the additional build-metadata suffix `+codex.20260831221407`.
The release owner will use the `git tag` `advisor-v1.3.0` to pin the candidate commit.

## Candidate contents

This candidate packages the skills-only Codex Advisor consultation skill, its local
runtime references and scripts, and the two read-only advisor profiles. It adds no
networked service component.

## Candidate freeze

The content digest (SHA-256) is `767bbf4c5bb13406ed92fabdc24ac1c89508dc0742d1990de3c8dfed6242406b`.
Run `public-release/freeze-candidate.sh --check` to verify it against the candidate
content; use `--write` only after an intentional candidate change.

## Submission test cases

The local submission case pack is available at `public-release/submission-tests/` with five positive and three negative synthetic reviewer scenarios.
