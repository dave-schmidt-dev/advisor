# Public site walkthrough — 2026-09-01

Screen-by-screen review record for the Codex Advisor public site, taken against
the deployed candidate at `https://zerodelta.dev/advisor/`. Refresh this document
whenever a user-visible route, control, state, or copy string changes.

## Scope and hosting

The site is four static pages with no application logic, no forms, no
authentication, and no client-side JavaScript. There are therefore no roles, no
permission differences, no onboarding flow, and no system-owned sheets. Every
reachable screen and every interactive control is enumerated below.

It is served from the `advisor/` subdirectory of the Opalstack static app
`zerodelta` on `opal18.opalstack.com`, under the same certificate and site as
`zerodelta.dev`. Source of truth is `site/` in this repository; publish with
`./deploy-site.sh`.

## Routes

| Route | Page | Purpose |
|---|---|---|
| `/advisor/` | Landing | Positioning, mechanism, install, compatibility, prerequisites, project metadata |
| `/advisor/support/` | Support | Channels, scope, prerequisites checklist, troubleshooting, report template |
| `/advisor/privacy/` | Privacy policy | Directory-submission privacy disclosure |
| `/advisor/terms/` | Terms of service | Directory-submission legal terms |
| `/advisor/sitemap.xml` | Sitemap | Covers the four routes above |

`/robots.txt` lives at the domain root in the `zero-delta-dev` repository, because
a robots file is only honoured there.

## Landing — `/advisor/`

- **Header.** Sticky. Brand lockup (logo + "Codex Advisor") links to `/advisor/`.
  Nav: Install (same-page anchor `#install`), Support, Privacy, Terms, Source
  (external, GitHub).
- **Skip link.** Hidden until focused, then jumps to `#content`. Keyboard only.
- **Hero.** Status pill reading "Version 1.3.0 · MIT". Headline with an animated
  cursor, suppressed under `prefers-reduced-motion`. Two buttons: "Get started"
  (anchors to `#install`) and "Documentation & source" (external, GitHub).
- **What it is.** Positioning copy plus a callout stating the no-hosted-service,
  no-MCP-server, no-telemetry boundary.
- **How it works.** Six cards: triggering, role selection, isolation, receipts,
  research-first fallback, fail-closed behaviour. Static, no interaction.
- **Install.** Three code blocks. Long lines scroll horizontally inside the block
  rather than overflowing the page.
- **Compatibility.** Five-row table. Supported rows are green, unsupported and
  out-of-scope rows amber. Scrolls horizontally on narrow viewports.
- **Local prerequisites.** Six-item list.
- **Privacy in one paragraph.** Summary with an inline link to `/advisor/privacy/`.
- **Project.** Metadata table with links to source, issues, the support mailbox
  (`mailto:`), and the troubleshooting guide.
- **Footer.** Link to `zerodelta.dev`, plus Support / Privacy / Terms / Source.

## Support — `/advisor/support/`

Header nav marks Support as the current page. Six sections: channels, supported
platforms and out-of-scope surfaces, a seven-item prerequisites checklist, three
troubleshooting scenarios (`route: unavailable`, model availability, retry
behaviour), two diagnostic commands, and a four-item report template closing with
a redaction callout. Interactive controls: nav, two `mailto:` links, two external
GitHub links, footer.

## Privacy — `/advisor/privacy/`

Header nav marks Privacy as current. Document header carries the effective date
(1 September 2026), controller (Zero Delta LLC, Commonwealth of Virginia),
contact mailbox, and publisher website. Nine numbered sections. Section 7 covers
this website specifically: no cookies, no third-party scripts or fonts, no
analytics, and standard server access logs. Section 9 states email as the contact
channel with a postal address available on request.

## Terms — `/advisor/terms/`

Header nav marks Terms as current. Document header carries the effective date,
publisher, contact mailbox, and governing law (Commonwealth of Virginia). Nine
numbered sections covering acceptance, MIT licensing and dual authorship,
advisory disclaimers, user responsibilities, warranty disclaimer, liability
limitation, modification, governing law, and contact.

## States

There is no empty state, loading state, error state, or disabled control on any
page: every route is a static document that is either served or not. The only
recovery path is the host's own 404, which Opalstack serves for an unknown path
under this app.

Motion is limited to the hero cursor blink and card and button hover
transitions. All of it is disabled under `prefers-reduced-motion: reduce`.

## Verification, 2026-09-01

Automated, `web-tests/` (38 assertions, Chromium desktop + WebKit iPhone 13):
every page renders with no console error and no failed request; the stylesheet
resolves; no horizontal overflow; every internal link and same-page anchor
resolves; no root-absolute reference, so the tree stays relocatable; canonical
URLs match the deployed path; the claim surface still names version 1.3.0 and the
two entitled models; no mention of an MCP server or a hosted service appears
without its negation; and
no draft `OWNER-PROVIDED` placeholder survives on a legal page.

Live checks against the deployed site returned HTTP 200 for `/advisor/`,
`/advisor/privacy/`, `/advisor/terms/`, `/advisor/support/`,
`/advisor/assets/style.css`, and `/advisor/sitemap.xml`, with no console error,
no failed request, and zero horizontal overflow at iPhone 13 width.

All four pages were reviewed as full-page renders at desktop width, not only as
route checks: heading hierarchy, the doc-head metadata block, code blocks, the
compatibility and metadata tables, list numbering, the callout, and the footer
all render as intended, with no clipped or overlapping content. Automated checks
catch overflow and broken links; they do not catch visual defects, which is why
this pass is recorded separately.

`public-release/validate-public-artifacts.sh` now treats `site/*.html` as a
public document, so the deployed pages are held to the same model-entitlement
rule as the drafts, and to the same rule that no mention of an MCP server or a
hosted service may appear without its negation. Both rules were falsified against
the real files before being trusted.

## Known gaps

- Reviewed by the implementing agent, not yet by the release owner.
- No screen-reader pass and no automated accessibility audit; the pages use
  landmarks, a skip link, labelled sections, and visible focus, but that is an
  assertion about the markup rather than a tested result.
