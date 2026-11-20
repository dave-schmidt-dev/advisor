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
publication of 1.4.11 on 17 November 2026, and the website was deployed the
same day; all seven live site files byte-match the current source, and
`public-release/verify-upload-ready.sh` reported UPLOAD READY for
`Codex-Advisor-1.4.11.zip`.

This record documents the site copy and local verification. It does not claim
marketplace publication.

## Post-release candidate: unified Zero Delta shell (2026-11-20, not deployed)

The source now differs from the deployed 1.4.11 pages; the byte-match statement
above describes 17 November only. Copy is unchanged. Presentation changes:

- Every route links `/assets/site-shell.css` before `assets/style.css`. One
  bordered frame with a rounded bottom holds the hero or document header, the
  content and the footer, below the shared header.
- The footer is the shared Zero Delta footer, identical to zerodelta.dev:
  "© 2026 Zero Delta LLC · Virginia" with Home, Advisor, Privacy, Terms and
  Contact (`mailto:dave@zdelta.dev`). Support and Source stay reachable from the
  landing hero and Resources section and from the document text.
- Document eyebrows (Help, Legal) use the shared section label with the cyan
  prompt; document titles use the same heading scale as the landing hero.
  Steps and Compatibility tiles use the shared card surface; Resources links use
  the shared button.
- One 560px breakpoint and one inset: brand, heading, first section heading and
  footer text align at 1280, 561, 560, 520, 481, 480 and 390px (previously the
  header kept a 34px inset between 481 and 560px while content used 18px).
- `npm --prefix web-tests test`: 64 passed (desktop and iPhone 13).
