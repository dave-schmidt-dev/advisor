# Codex Advisor 1.4.11 website review record — 2026-11-17

Candidate source: `site/` for `https://zerodelta.dev/advisor/`. This is the
current review record for the 1.4.11 version and Specialist/Astra model change.
The 1.4.10 record (`git show f4d8165:docs/site-walkthrough-1.4.10.md`), the 1.4.7
walkthrough and the 1.4.6 walkthrough they cite retain the detailed navigation and
desktop/mobile presentation review; layout and styles are unchanged since then.

## Copy and version reviewed

- All four routes identify `advisor-release=1.4.11` and retain their canonical URL,
  shared stylesheet, favicon, and shared navigation.
- The landing page badge reads “Open source · Candidate documentation v1.4.11”.
  Its configuration example sets `[specialist] model = "gpt-6.2-sol"`, and the
  Compatibility summary reads Specialist: GPT-6.2 Sol / `gpt-6.2-sol` / high and
  Explicit-only: `advisor-astra` / `gpt-6.2-astra` / high. Standard remains
  GPT-6.1 Terra / `gpt-6.1-terra` / high.
- Support, Privacy, and Terms describe automatic Specialist as GPT-6.2 Sol/high;
  their release metadata advances to 1.4.11.

## Verification and deployment

The Playwright suite passes for the candidate, covering the landing copy, the
model pins, and all four route metadata values. The owner approved release and
publication of 1.4.11 on 17 November 2026. Deployment status is recorded below
after the deploy.

This record documents the site copy and local verification. It does not claim
marketplace publication.
