# Public site walkthrough — 2026-09-02

Candidate-current review record for `https://zerodelta.dev/advisor/`.

## Shared controls

Every public route has the same global navigation: Zero Delta brand, Home,
Advisor (current), and GitHub. Every route also has a keyboard skip link.

## Landing — `/advisor/`

- Hero: product mark, version 1.3.0, one-sentence purpose, Install anchor, and Source link. No cursor animation.
- What it does: three static steps covering selection, read-only challenge, and disposition, followed by the verified-child and unsupported-direct-profile qualifier.
- Install: three commands in one horizontally scrollable code block; the companion step is labelled “Advisor support.”
- Compatibility: the user's Codex/OpenAI account and no-intermediary boundary,
  plus four facts covering supported Codex surfaces, absent services, and the
  Standard and Specialist roles.
- Resources: Support, Privacy, Terms, and Issues.
- Footer: Zero Delta and source links.

## Documentation routes

- `/advisor/support/`: support channels, prerequisites, troubleshooting, diagnostics, and report format.
- `/advisor/privacy/`: controller, local data handling, third parties, retention, website logs, and contact.
- `/advisor/terms/`: license, advisory boundary, responsibilities, warranty, liability, governing law, and contact.

There is no onboarding, authentication, role-dependent UI, form, disabled
control, loading state, or system-owned sheet. Unknown paths use the host 404.
Reduced-motion mode disables hover motion; the prior blinking cursor was removed.

## Candidate verification

- `npm test`: 42 Playwright checks passed in desktop Chromium and iPhone 13 WebKit profiles.
- All four routes loaded without console or network errors.
- Every internal link resolved; every page had no horizontal overflow.
- The global navigation labels and destinations matched on all four routes.
- Static Advisor verification passed with the validated version, role, model,
  read-only, no-MCP, and no-hosted-service claims intact.
- Standalone screenshot capture was unavailable because macOS denied the
  Playwright browser rendezvous outside the passing suite; no visual defect was
  inferred from that unavailable evidence.
