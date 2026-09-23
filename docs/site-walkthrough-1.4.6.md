# Codex Advisor 1.4.6 public-site walkthrough — 2026-09-22

Candidate source: `site/` for `https://zerodelta.dev/advisor/`. This is a
pre-deployment review of the 1.4.6 candidate, not evidence of a live deployment,
marketplace update, or owner acceptance. The release owner reviews this walkthrough
before `./deploy-site.sh`; any later visible route, control, state, or copy change
requires a refreshed walkthrough.

## Shared navigation and presentation

- On all four routes, the keyboard “Skip to content” link targets `#content`.
  The ZERO DELTA brand and Home links open `https://zerodelta.dev/`; Advisor
  opens the landing route. Advisor has `aria-current="page"` on the landing
  route only.
- Every footer links to Zero Delta LLC, Support, Privacy, Terms, and the GitHub
  Source. Support, Privacy, and Terms navigate within this four-page site.
- Each page has `advisor-release=1.4.6` metadata, its own canonical URL, the
  shared dark stylesheet, and the logo favicon. Desktop shows the header,
  content, and footer in the shared wrap. Mobile keeps the same routes and
  controls available without horizontal page overflow; code blocks may scroll
  internally. Keyboard focus and link access apply in both layouts.
- The site is static. There are no authenticated roles, forms, toggles,
  disabled controls, loading or error panels, recovery sheets, or system-owned
  sheets. Recovery guidance appears on Support as text and outbound links.

## Landing — `/advisor/`

- The candidate badge says “Open source · Candidate documentation v1.4.6”.
  Model copy shows automatic Standard as `gpt-5.6-terra` / high, automatic
  Specialist as `gpt-6-sol` / high, and the separate explicit-only
  `advisor-astra` as `gpt-6-astra` / high. The live `advisor.toml` example and
  compatibility facts agree. Specialist eligibility remains limited to the
  documented decisions unresolved after targeted evidence; Astra is never
  selected automatically.
- Hero controls: “Install from OpenAI” opens the official Plugins Directory;
  “View source” opens the GitHub repository. The lower “Open in Plugins
  Directory” button opens the same Directory listing. Resource links open
  Support, Privacy, Terms, and GitHub Issues. Header and footer links are
  covered by the shared navigation above.
- The page explains read-only, zero-tool consultation, the terminal deferred
  shell handoff, the exact schema-v3 receipt, and the absence of silent model
  fallback. The install section directs users to start a new Codex thread.

## Support — `/advisor/support/`

- Issue tracker links in the heading and support section open GitHub Issues;
  email links open `mailto:advisor@zerodelta.dev`. The official Plugins
  Directory link is the reinstall/update route. Shared header and footer links
  remain reachable.
- The page explains installed `advisor.toml` editing, automatic GPT-6 Sol/high
  for Specialist, explicit-only Astra, and the lack of a GUI settings screen.
  It covers host prerequisites, `route: unavailable`, model authorization,
  response-only retry, deferred-handoff recovery, receipt checks, and what to
  include in a redacted support request. There is no interactive recovery
  control on this page.

## Privacy — `/advisor/privacy/`

- Contact links open `mailto:advisor@zerodelta.dev`; the website link opens
  Zero Delta. Shared header and footer navigation remains reachable.
- The page states the local no-relay, no-telemetry boundary, bounded packet
  handling through the user's Codex/OpenAI account, opt-in content-free local
  journal, user data controls, and GPT-6 Sol/high Specialist default. The legal
  effective date remains 10 September 2026; the 1.4.6 marker identifies the
  candidate page, not a change to that effective date.

## Terms — `/advisor/terms/`

- Contact links open `mailto:advisor@zerodelta.dev`; shared header and footer
  links remain reachable.
- The page keeps the 10 September 2026 effective date, MIT license, advisory
  decision boundary, model-access and usage responsibility, warranty,
  liability, termination, and Virginia governing-law terms. Its model copy
  names automatic GPT-6 Sol/high Specialist and explicit-only Astra/high.

## Review and deployment gate

The owner reviews all four routes and the desktop/mobile presentation before
deployment. The captain then runs the site behavior/visual checks and the
repository release gates against the frozen candidate, deploys only after owner
approval, and verifies that all seven public files byte-match the reviewed
source. Those later checks are separate evidence from this walkthrough.
