# Codex Advisor 1.4.10 website review record — 2026-10-27

Candidate source: `site/` for `https://zerodelta.dev/advisor/`. This is the
current post-deployment review record for the 1.4.10 version and Standard model
change.
The 1.4.7 walkthrough (`git show 9191346:docs/site-walkthrough-1.4.7.md`) and the
1.4.6 walkthrough it cites retain the detailed navigation and desktop/mobile
presentation review; layout and styles are unchanged since then.

## Copy and version reviewed

- All four routes identify `advisor-release=1.4.10` and retain their canonical URL,
  shared stylesheet, favicon, and shared navigation.
- The landing page badge reads “Open source · Candidate documentation v1.4.10”.
  Its configuration example sets `[standard] model = "gpt-6.1-terra"`, and the
  Compatibility summary reads Standard: GPT-6.1 Terra / `gpt-6.1-terra` / high.
  Specialist remains GPT-6.1 Sol / `gpt-6.1-sol` / high, and `advisor-astra`
  remains a separate explicit-only `gpt-6-astra` / high role.
- Support, Privacy, and Terms keep their 1.4.9 copy (they describe Standard as
  Terra/high without a version); only their release metadata advances to 1.4.10.

## Verification and deployment

The Playwright suite passes for the candidate, covering the landing copy, the
`gpt-6.1-terra` pin, and all four route metadata values. The owner reviewed
this record on 27 October 2026, and the website was deployed the same day; all
seven live site files byte-match the current source.

This record documents the deployed site copy and local verification. It does not
claim marketplace publication.
