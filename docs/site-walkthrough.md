# Codex Advisor public site walkthrough — 2026-09-10

Candidate walkthrough for version `1.4.3` at `https://zerodelta.dev/advisor/`.

**Evidence boundary:** This walkthrough records candidate-current static source,
browser-assertion coverage, owner approval, website deployment, and live byte-match
verification. Marketplace upload and GitHub release publication are not claimed here.
The exact plugin roles are installed and a successful live `advisor-astra` smoke is
recorded separately in `docs/advisor-1.4-walkthrough.md`.

## Shared controls and states

Candidate-current static source evidence on all four routes:

- Zero Delta brand link goes to the main site; Home goes to `https://zerodelta.dev/`;
  Advisor goes to `/advisor/` and is current only on the landing route.
- The keyboard skip link reaches the `#content` landmark.
- Footer links reach Support, Privacy, Terms, and Source where present.
- The static site has no settings UI, form, authentication flow, role-dependent
  UI, loading state, disabled control, or system-owned sheet.
- All four pages carry `advisor-release` metadata set to `1.4.3`.
- The pages make no GUI settings promise. Host-404 behavior is not a candidate
  website-copy check.

## Landing — `/advisor/`

Candidate-current static source evidence:

- The badge reads `Open source · Documentation v1.4.3`; the page metadata has
  `advisor-release` set to `1.4.3`.
- The hero explains automatic read-only advice, smart defaults, and optional
  models. Install from OpenAI and View source remain visible.
- What it does contains the three static decision, challenge, and disposition
  steps plus the verified read-only/tool-free qualifier.
- Choose your models contains `[standard]` and `[specialist]` TOML with Terra/high
  and Sol/high automatic defaults. It presents `advisor-astra` as a separate
  explicit-only Astra/high role that is never selected automatically, uses more
  Codex allowance, and remains subject to account and runtime availability.
- Install from OpenAI retains the Plugins Directory CTA and new-thread handoff.
- Compatibility explains authenticated Codex/OpenAI transmission and no
  Zero Delta relay; Resources exposes Support, Privacy, Terms, and Issues.

## Support — `/advisor/support/`

Candidate-current static source evidence:

- The route metadata has `advisor-release` set to `1.4.3`.
- Support channels, directory update/reinstall guidance, and the new Codex
  thread handoff are visible.
- Configuration guidance identifies `advisor.toml` two directories above the
  directory containing `skills/consultation/SKILL.md`, directs an in-place edit,
  and forbids copying or repository commands.
- The page documents independent Standard/Specialist settings, configurable
  models, invalid TOML and unsupported-model errors, no silent fallback, and
  update replacement. It does not require a GUI settings screen or canary in
  the normal flow.
- Troubleshooting distinguishes automatic Standard and Specialist routing from
  explicit-only `advisor-astra`, including its account/runtime availability and
  higher Codex allowance use.
- Receipt labels `ADVISOR DECISION`, `ADVISOR CALL`, and `ADVISOR RESULT` remain
  available for diagnostics, along with prerequisites, recovery, and ticket
  submission controls.

## Privacy — `/advisor/privacy/`

Candidate-current static source evidence:

- The route metadata has `advisor-release` set to `1.4.3`; the effective date is
  10 September 2026.
- The page retains authenticated OpenAI transmission and the explicit
  no-Zero-Delta-relay statement.
- It describes live plugin configuration, advanced settings/catalog data under
  Codex home, automatic Terra/Sol defaults, and separate explicit-only
  `advisor-astra`. It does
  not claim offline inference or that all data exists only in session logs.
- The optional content-free usage journal is off by default, stores operational
  metadata and aggregate counters only, stores no packets or responses, prunes
  entries older than 30 days during later writes, enforces a bounded count, and
  has no background deletion service.
- It explains that uninstall may leave user state and session logs, which are
  managed separately.

## Terms — `/advisor/terms/`

Candidate-current static source evidence:

- The route metadata has `advisor-release` set to `1.4.3`; the effective date is
  10 September 2026.
- The prerequisites section assigns responsibility for configured model
  availability and account usage, and says bundled configuration edits may be
  replaced by an update or reinstall.
- It identifies `advisor-astra` as separate and explicit-only, never automatic,
  higher-allowance, and subject to account/runtime availability.
- The MIT license, advisory disclaimer, warranty disclaimer, liability limit,
  governing law, jurisdiction, and contact terms are unchanged and visible.
- Developer and maintainer is David Schmidt / Zero Delta LLC; the public Original
  author and Fork maintainer wording is absent.

Candidate-current visual review completed on 10 September 2026 for all eight
desktop and mobile captures. No page-content clipping, broken layout, or page-level
horizontal overflow was observed. The landing-page TOML sample retains intentional
horizontal scrolling inside its code box on mobile; the explanatory Astra copy
below it remains fully visible.

## Install handoff and recovery review

Both landing-page Plugins Directory CTAs use the published Directory URL, and
the support page exposes update/reinstall and configuration-error guidance. The
website copy contains no settings control that implies GUI model configuration.
This static review did not install the plugin, start a live consultation, upload a
marketplace build, publish a GitHub release, deploy the website, or check Astra
availability.

## Automated evidence

`web-tests/tests/site.spec.js` expects version `1.4.3` on all four routes and checks
the explicit-only `advisor-astra` wording, non-automatic selection, higher allowance
use, and account/runtime availability. It also covers route rendering, console and
network errors, internal links, navigation, canonical URLs, horizontal overflow,
support recovery, privacy, and terms. The candidate-current run completed on
10 September 2026 with `52 passed (3.7s)` across desktop and mobile profiles.

## Browser capture paths

| Route | Desktop | Mobile |
| --- | --- | --- |
| Landing | [capture](../web-tests/test-results/site--renders-without-errors-desktop/page.png) | [capture](../web-tests/test-results/site--renders-without-errors-mobile/page.png) |
| Support | [capture](../web-tests/test-results/site--support-renders-without-errors-desktop/page.png) | [capture](../web-tests/test-results/site--support-renders-without-errors-mobile/page.png) |
| Privacy | [capture](../web-tests/test-results/site--privacy-renders-without-errors-desktop/page.png) | [capture](../web-tests/test-results/site--privacy-renders-without-errors-mobile/page.png) |
| Terms | [capture](../web-tests/test-results/site--terms-renders-without-errors-desktop/page.png) | [capture](../web-tests/test-results/site--terms-renders-without-errors-mobile/page.png) |

These captures were regenerated by the successful candidate-current browser run,
reviewed screen by screen, and approved by the owner on 10 September 2026 before
deployment.

## Candidate file snapshot

| File | SHA-256 |
| --- | --- |
| `site/index.html` | `84c341dba7c2242ec4768279e9a01765c4b4f6fd44e175363e879fcd40f2d02e` |
| `site/support/index.html` | `d4c93fcebc13803b0f9719ad63fcedb9c17008d64713bea3a2252e841062bf2a` |
| `site/privacy/index.html` | `6fc19a0ac1e9a47554ab4fff4feef16873778d56f0c216377681b7886c762fe6` |
| `site/terms/index.html` | `58d73329a682a5e337d42f7da04f313d28b82b58b339855a3d3ab6c0001191ea` |
| `site/assets/style.css` | `8a5e30c6d1c331a667577ae30b49c90d0db3fe40048b9bfe8c05c9a237d8df3a` |
| `site/assets/logo.svg` | `5cdf5277721efc07305ef9129410a2aefbc1fdd61e46c3d8946caa888210f0e2` |
| `site/sitemap.xml` | `a6baf34abddca5c09f2659d226c605771a25b65089e0dd66874856b32141b792` |

## Prior file snapshot

These hashes bind the prior deployed candidate only; they are preserved as history
and do not identify the 1.4.3 candidate:

| File | SHA-256 |
| --- | --- |
| `site/index.html` | `694a167979024dbb2c95c0cee2df31a75dc284eaf75f804b04ae570aaf0f87b5` |
| `site/support/index.html` | `748b0ce0d72982f9bcb6fc6941505436b3d8b30ee0082abd3fb60dce51846204` |
| `site/privacy/index.html` | `e7f3e36c1561df999c0973291957d4c7893482519b5556b00292b1dd641bc2ba` |
| `site/terms/index.html` | `86ae9942456f6d2fe54e4896777f86d1696ddacd3ecf163b4149bb0ab2b75a2e` |
| `site/assets/style.css` | `8a5e30c6d1c331a667577ae30b49c90d0db3fe40048b9bfe8c05c9a237d8df3a` |
| `site/assets/logo.svg` | `5cdf5277721efc07305ef9129410a2aefbc1fdd61e46c3d8946caa888210f0e2` |
| `site/sitemap.xml` | `a6baf34abddca5c09f2659d226c605771a25b65089e0dd66874856b32141b792` |

The approved website was deployed on 10 September 2026. The repository upload gate
then verified all seven public files byte-for-byte against this snapshot. Marketplace
upload and GitHub release publication remain separate gates.
