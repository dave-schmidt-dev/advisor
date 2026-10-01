# Codex Advisor 1.4.7 website review record — 2026-10-01

Candidate source: `site/` for `https://zerodelta.dev/advisor/`. This is the
current post-deployment review record for the 1.4.7 version and model-copy change.
The previous [1.4.6 walkthrough](site-walkthrough-1.4.6.md) retains the detailed
shared navigation and desktop/mobile presentation review.

## Copy and version reviewed

- All four routes identify `advisor-release=1.4.7` and retain their canonical URL,
  shared stylesheet, favicon, and shared navigation.
- The landing page badge reads “Open source · Candidate documentation v1.4.7”.
  Its configuration example and model summary identify Specialist as GPT-6.1
  Sol / `gpt-6.1-sol` / high. Standard remains GPT-5.6 Terra / high, and
  `advisor-astra` remains a separate explicit-only GPT-6 Astra / high role.
- Support, Privacy, and Terms retain their reviewed 1.4.6 copy and structure;
  their release metadata advances to 1.4.7.

## Verification and deployment

The existing Playwright suite passed all 52 tests for the candidate. The landing
copy and all four route metadata values are covered by the current source checks.
The website was deployed on 1 October 2026; upload-readiness verification
confirmed that all seven live site files byte-match the current source.

This record documents the deployed site copy and local verification. It does not
claim marketplace publication.
