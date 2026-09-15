# Codex Advisor 1.4.5 public-site walkthrough — 2026-09-15

This is the candidate-current walkthrough for `https://zerodelta.dev/advisor/`.
It is not deployment, marketplace, GitHub-release, or owner-acceptance evidence.
Owner review is required before deployment.

## Shared controls and states

- The Zero Delta, Home, Advisor, footer, Support, Privacy, Terms, Source, Issues, and
  Plugins Directory links are present and have automated route/link coverage.
- The keyboard skip link reaches `#content`; Advisor is current only on the landing
  route.
- This static site has no form, authentication, role-specific screen, disabled
  control, loading state, recovery sheet, or system-owned sheet.
- All four pages expose `advisor-release=1.4.5` metadata.

## Landing — `/advisor/`

- The candidate badge reads `Open source · Candidate documentation v1.4.5`.
- Standard is described as Terra/high for ordinary bounded material architecture,
  interface, data-model, and generic-advisor decisions.
- Specialist is described as Sol/high only when targeted evidence still leaves an
  eligible cross-system, compatibility/concurrency, competing-diagnosis,
  security/trust, recovery, irreversible-migration, or data-loss decision unresolved.
- Project importance, security adjacency, and an ordinary architecture question alone
  remain Standard. `advisor-astra` remains explicit-only and never automatic.
- The install CTA and source link remain visible; the deferred-handoff explanation and
  no-fallback promise remain visible.

## Support — `/advisor/support/`

- The page gives Directory update/reinstall guidance and the new-Codex-thread handoff.
- It explains the installed `advisor.toml` location, in-place configuration, no GUI
  settings screen, no silent fallback, and the revised Standard/Specialist routing.
- It exposes prerequisites, unavailable-route recovery, receipt diagnostics, and
  ticket-submission guidance.

## Privacy — `/advisor/privacy/` and Terms — `/advisor/terms/`

- Both pages carry the 1.4.5 release marker and retain the existing legal/effective
  date, owner, and contact information.
- Privacy retains the no-relay statement and content-free, opt-in local journal
  description. Terms retains the model-access, license, warranty, liability,
  governing-law, and advisory-decision terms.

## Automated visual and behavior evidence

`npm test` in `web-tests` completed with **52 passed** on 2026-09-15 across desktop
and mobile profiles. It covers all four routes, rendered headings, console/network
errors, stylesheet loading, internal links, navigation, canonical URLs, horizontal
overflow, revised routing claims, release metadata, support recovery, privacy, and
terms. The test captures are regenerated on each run.

## Owner review boundary

Review this candidate before `./deploy-site.sh`. After approval, deploy and verify all
seven public files match the candidate bytes; that later evidence belongs in the
release record, not this pre-deployment walkthrough.
