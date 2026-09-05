# Codex Advisor public site walkthrough — 2026-09-05

Prior-candidate walkthrough for `https://zerodelta.dev/advisor/`.

**Observation status:** Prior-candidate static evidence and visual review are
preserved for the unchanged Landing, Support, and Privacy routes. Refreshed Terms
static and browser evidence is recorded below; the release owner approved those Terms
captures and the deployed site was live-byte verified on 5 September 2026.

## Shared controls and states

Prior-candidate observed static evidence on all four routes:

- Zero Delta brand link goes to the main site; Home goes to `https://zerodelta.dev/`;
  Advisor goes to `/advisor/` and is current only on the landing route.
- The keyboard skip link reaches the `#content` landmark.
- Footer links reach Support, Privacy, Terms, and Source where present.
- The static site has no settings UI, form, authentication flow, role-dependent
  UI, loading state, disabled control, or system-owned sheet.
- The pages make no GUI settings promise. Host-404 behavior is not an observed
  website-copy check.

## Landing — `/advisor/`

Prior-candidate observed static evidence:

- The badge reads `Open source · Documentation v1.4.2`; the page metadata has
  `advisor-release` set to `1.4.2`.
- The hero explains automatic read-only advice, smart defaults, and optional
  models. Install from OpenAI and View source remain visible.
- What it does contains the three static decision, challenge, and disposition
  steps plus the verified read-only/tool-free qualifier.
- Choose your models contains `[standard]` and `[specialist]` TOML with model and
  effort values, Terra/high and Sol/high defaults, and the optional Astra usage
  comment. It explains in-place edits to the bundled `advisor.toml`, next-
  consultation effect, independent effort settings, future selector support,
  no setup conversation or separate canary, and update replacement.
- Install from OpenAI retains the Plugins Directory CTA and new-thread handoff.
- Compatibility explains authenticated Codex/OpenAI transmission and no
  Zero Delta relay; Resources exposes Support, Privacy, Terms, and Issues.

## Support — `/advisor/support/`

Prior-candidate observed static evidence:

- The route metadata has `advisor-release` set to `1.4.2`.
- Support channels, directory update/reinstall guidance, and the new Codex
  thread handoff are visible.
- Configuration guidance identifies `advisor.toml` two directories above the
  directory containing `skills/consultation/SKILL.md`, directs an in-place edit,
  and forbids copying or repository commands.
- The page documents independent Standard/Specialist settings, configurable
  models, invalid TOML and unsupported-model errors, no silent fallback, and
  update replacement. It does not require a GUI settings screen or canary in
  the normal flow.
- Receipt labels `ADVISOR DECISION`, `ADVISOR CALL`, and `ADVISOR RESULT` remain
  available for diagnostics, along with prerequisites, recovery, and ticket
  submission controls.

## Privacy — `/advisor/privacy/`

Prior-candidate observed static evidence:

- The route metadata has `advisor-release` set to `1.4.2`; the effective date is
  5 September 2026.
- The page retains authenticated OpenAI transmission and the explicit
  no-Zero-Delta-relay statement.
- It describes live plugin configuration, advanced settings/catalog data under
  Codex home, and configurable Terra/Sol defaults with optional Astra. It does
  not claim offline inference or that all data exists only in session logs.
- The optional content-free usage journal is off by default, stores operational
  metadata and aggregate counters only, stores no packets or responses, prunes
  entries older than 30 days during later writes, enforces a bounded count, and
  has no background deletion service.
- It explains that uninstall may leave user state and session logs, which are
  managed separately.

## Terms — `/advisor/terms/`

Refreshed static and browser evidence:

- The route metadata has `advisor-release` set to `1.4.2`; the effective date is
  5 September 2026.
- The prerequisites section assigns responsibility for configured model
  availability and account usage, and says bundled configuration edits may be
  replaced by an update or reinstall.
- The MIT license, advisory disclaimer, warranty disclaimer, liability limit,
  governing law, jurisdiction, and contact terms are unchanged and visible.
- Developer and maintainer is David Schmidt / Zero Delta LLC; the public Original
  author and Fork maintainer wording is absent.

Refreshed Terms visual evidence:

- The root reviewed the refreshed desktop and mobile captures. Both show the
  Developer and maintainer wording with the expected layout.
- The release owner approved the refreshed Terms captures. The approved Terms page
  was deployed and live-byte verified on 5 September 2026.

## Install handoff and recovery review

Both landing-page Plugins Directory CTAs use the published Directory URL, and
the support page exposes update/reinstall and configuration-error guidance. The
website copy contains no settings control that implies GUI model configuration.
This static review did not install the plugin, start a live consultation, or
check Astra availability.

## Automated evidence

The complete local Playwright suite passed: 52 tests across desktop and mobile
profiles in 3.8 seconds. It covers route rendering, console and network errors,
internal links, navigation, canonical URLs, horizontal overflow, release metadata,
public claims, support recovery, privacy, and terms, including current developer and
maintainer identity.

The root reviewed the refreshed Terms desktop and mobile captures; their layout is
correct. The other three routes are unchanged and retain their prior-candidate visual
review. The approved Terms release was deployed; the upload-readiness gate verified
the exact marketplace ZIP and all 7 live site files.

## Current browser capture evidence

| Route | Desktop | Mobile |
| --- | --- | --- |
| Landing | [capture](../web-tests/test-results/site--renders-without-errors-desktop/page.png) | [capture](../web-tests/test-results/site--renders-without-errors-mobile/page.png) |
| Support | [capture](../web-tests/test-results/site--support-renders-without-errors-desktop/page.png) | [capture](../web-tests/test-results/site--support-renders-without-errors-mobile/page.png) |
| Privacy | [capture](../web-tests/test-results/site--privacy-renders-without-errors-desktop/page.png) | [capture](../web-tests/test-results/site--privacy-renders-without-errors-mobile/page.png) |
| Terms | [capture](../web-tests/test-results/site--terms-renders-without-errors-desktop/page.png) | [capture](../web-tests/test-results/site--terms-renders-without-errors-mobile/page.png) |

All eight captures were regenerated by the current browser run. Current visual review
is recorded only for Terms; the unchanged Landing, Support, and Privacy routes retain
their prior-candidate visual review.

## Candidate-current file snapshot

These SHA-256 hashes bind the current static candidate:

| File | SHA-256 |
| --- | --- |
| `site/index.html` | `694a167979024dbb2c95c0cee2df31a75dc284eaf75f804b04ae570aaf0f87b5` |
| `site/support/index.html` | `748b0ce0d72982f9bcb6fc6941505436b3d8b30ee0082abd3fb60dce51846204` |
| `site/privacy/index.html` | `e7f3e36c1561df999c0973291957d4c7893482519b5556b00292b1dd641bc2ba` |
| `site/terms/index.html` | `86ae9942456f6d2fe54e4896777f86d1696ddacd3ecf163b4149bb0ab2b75a2e` |
| `site/assets/style.css` | `8a5e30c6d1c331a667577ae30b49c90d0db3fe40048b9bfe8c05c9a237d8df3a` |
| `site/assets/logo.svg` | `5cdf5277721efc07305ef9129410a2aefbc1fdd61e46c3d8946caa888210f0e2` |
| `site/sitemap.xml` | `a6baf34abddca5c09f2659d226c605771a25b65089e0dd66874856b32141b792` |

Plugin installation, live model calls, and Astra availability were not tested by this
website evidence.
