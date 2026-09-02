# Release notes draft

## Candidate identity

The submitted identity is version `1.3.4`, matching `plugin.json` and the public
listing. The release owner will use the `git tag` `v1.3.4` to pin the candidate
commit.

## Candidate contents

This candidate packages the skills-only Codex Advisor consultation skill, its local
runtime references and scripts, and the two read-only advisor profiles. It adds no
networked service component.

## Candidate freeze

The content digest (SHA-256) is `7795648ba5b7f2da284a64808194e42f362c779288e869b8388abec70c6e5974`.
Run `public-release/freeze-candidate.sh --check` to verify it against the candidate
content; use `--write` only after an intentional candidate change.

## Submission test cases

The local submission case pack is available at `public-release/submission-tests/` with five positive and three negative synthetic reviewer scenarios.
