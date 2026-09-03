# Public site walkthrough — 2026-09-03

Candidate-current review record for `https://zerodelta.dev/advisor/`.

## Shared controls

Every public route has the same global navigation: Zero Delta brand, Home,
and Advisor. Advisor is marked current on the landing page. Every route also
has a keyboard skip link.

## Landing — `/advisor/`

- Hero: version 1.3.3, one-sentence purpose, an Install from OpenAI link to the official OpenAI Plugins Directory, and Source link. It starts at the shared content edge with no standalone product icon or cursor animation.
- What it does: three static steps covering selection, read-only challenge, and disposition, followed by the verified-child and unsupported-direct-profile qualifier.
- Install from OpenAI: states that Codex Advisor is available in the official OpenAI Plugins Directory, provides an Open in Plugins Directory button to the same directory URL, and directs users to start a new Codex thread after installation.
- Compatibility: the user's Codex/OpenAI account and no-intermediary boundary,
  plus four facts covering supported Codex surfaces, absent services, and the
  Standard and Specialist roles.
- Resources: Support, Privacy, Terms, and Issues.
- Footer: Zero Delta and source links.

## Documentation routes

- `/advisor/support/`: support channels, prerequisites, troubleshooting, diagnostics, and report format.
- `/advisor/privacy/`: controller, local integration, the read-only zero-tool child, local data handling, third parties, retention, website logs, and contact.
- `/advisor/terms/`: license, advisory boundary, responsibilities, warranty, liability, governing law, and contact.

There is no onboarding, authentication, role-dependent UI, form, disabled
control, loading state, or system-owned sheet. Unknown paths use the host 404.
Reduced-motion mode disables hover motion; the prior blinking cursor was removed.

## Candidate verification

- `npm --prefix web-tests test`: 44 Playwright checks passed in desktop Chromium and iPhone 13 WebKit profiles.
- All four routes loaded without console or network errors.
- Every internal link resolved; every page had no horizontal overflow.
- The global navigation labels and destinations matched on all four routes.
- Static Advisor verification passed with the validated version, role, model,
  read-only, no-MCP, and no-hosted-service claims intact.
- The shared `> ZERO DELTA` brand prompt has an explicit 0.45em right margin; browser coverage asserts at least 4px computed spacing.
- Standalone screenshot capture was unavailable because macOS denied the
  Playwright browser rendezvous outside the passing suite; no visual defect was
  inferred from that unavailable evidence.
